import '../algorithm_category.dart';
import 'motion_segments.dart';
import 'movement_time_processor.dart';
import 'pace.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version der Einschwingzeit (ADR-0004 P.3).
const String settlingMethod = 'settling';
const int settlingMethodVersion = 1;

/// Kategorie des Verfahrens (NFR-0002, docs/architecture/algorithm-categories.md): B.
const AlgorithmCategory settlingCategory = AlgorithmCategory.heuristic;

class SettlingResult {
  SettlingResult({
    required this.parameterVersion,
    required List<TimeSpan> intervals,
  }) : intervals = List.unmodifiable(intervals);

  String get method => settlingMethod;
  int get methodVersion => settlingMethodVersion;
  final int parameterVersion;

  /// Zeiträume, die nicht zum Abschnitt zählen (PAR-011), zusammengefasst und
  /// aufsteigend. Das Ende kann nach dem Stand der Abfrage liegen. Die
  /// Pulswerte selbst werden nicht verschoben.
  final List<TimeSpan> intervals;
}

class _Leg {
  const _Leg(this.start, this.end, this.meters);
  final DateTime start;
  final DateTime end;
  final double meters;
}

/// Einschwingzeit der Herzfrequenz (PAR-011): [PreprocessingParameters
/// .settlingDuration] ab Start, ab jedem Ende einer Pause (manuell wie
/// erkannt) und ab der Flanke eines Tempowechsels: Das Tempo-Mittel der
/// letzten 2 min weicht um mindestens 0,25 m/s vom vorherigen 2-min-Mittel ab,
/// vorher lag die Abweichung darunter. Solange sie darüber bleibt, löst nichts
/// erneut aus. Segmente unter der Stillstandsschwelle (PAR-014) gehen nicht
/// ins Mittel ein.
///
/// Schrittform: [add] je Segment; die Pausenenden kommen mit [result].
class SettlingProcessor {
  SettlingProcessor(this.parameters, {required this.start});

  final PreprocessingParameters parameters;
  final DateTime start;

  /// Segmente ohne Lücken (Lückenzeit und -strecke bleiben heraus).
  final List<_Leg> _legs = [];
  final List<DateTime> _triggers = [];

  /// Abweichung der 2-min-Mittel beim letzten auswertbaren Segment über der
  /// Schwelle. Nicht auswertbare Zeitpunkte lassen den Zustand unverändert;
  /// eine Lücke setzt ihn zurück (über die Lücke ist nichts gemessen).
  bool _above = false;

  void add(MotionSegment s) {
    if (s.isGap) {
      _above = false;
      return;
    }
    final v = speedMetersPerSecond(s.meters, s.seconds);
    if (v == null || v < parameters.standstillBelow) return;
    _legs.add(_Leg(s.start, s.end, s.meters));
    final now = s.end;
    final w = parameters.settlingPaceWindow;
    final recent = _mean(now.subtract(w), now);
    final before = _mean(now.subtract(w * 2), now.subtract(w));
    // Vollständig heißt nur am Laufanfang: Die Daten reichen bis zum Beginn
    // des früheren Fensters zurück. Danach genügt zählende Zeit in jedem
    // Fenster; nach einer Lücke wird also auch gegen ein kurzes Fenster
    // verglichen (mehr Ausschluss, nicht weniger).
    if (recent == null || before == null) return;
    if (_legs.first.start.isAfter(now.subtract(w * 2))) return;
    final above = (recent - before).abs() >= parameters.settlingPaceChange;
    if (above && !_above) _triggers.add(now);
    _above = above;
  }

  /// Strecke / Zeit der Segmente mit Ende in `(from, to]`.
  double? _mean(DateTime from, DateTime to) {
    var meters = 0.0;
    var micros = 0;
    for (var i = _legs.length - 1; i >= 0; i--) {
      final l = _legs[i];
      if (!l.end.isAfter(from)) break;
      if (l.end.isAfter(to)) continue;
      meters += l.meters;
      micros += l.end.difference(l.start).inMicroseconds;
    }
    return micros == 0 ? null : meters / (micros / 1e6);
  }

  /// [restarts]: Zeitpunkte, an denen nach einer Pause wieder Bewegung
  /// beginnt (`MovementResult.resumedAt`).
  SettlingResult result({required Iterable<DateTime> restarts}) {
    final starts = [start, ...restarts, ..._triggers]..sort();
    final merged = <TimeSpan>[];
    for (final s in starts) {
      final end = s.add(parameters.settlingDuration);
      if (merged.isNotEmpty && !s.isAfter(merged.last.end)) {
        if (end.isAfter(merged.last.end)) {
          merged[merged.length - 1] = TimeSpan(
            start: merged.last.start,
            end: end,
          );
        }
      } else {
        merged.add(TimeSpan(start: s, end: end));
      }
    }
    return SettlingResult(
      parameterVersion: parameters.parameterVersion,
      intervals: merged,
    );
  }
}
