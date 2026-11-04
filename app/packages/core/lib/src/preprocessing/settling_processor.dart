import 'motion_segments.dart';
import 'movement_time_processor.dart';
import 'preprocessing_parameters.dart';

/// Kennung und Version der Einschwingzeit (ADR-0004 P.3).
const String settlingMethod = 'settling';
const int settlingMethodVersion = 1;

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
/// erkannt) und ab jedem Zeitpunkt, an dem das Tempo-Mittel der letzten 2 min
/// um mindestens 0,25 m/s vom vorherigen 2-min-Mittel abweicht. Jedes
/// Auslösen verlängert die Zeit.
///
/// Schrittform: [add] je Segment; die Pausenenden kommen mit [result].
class SettlingProcessor {
  SettlingProcessor(this.parameters, {required this.start});

  final PreprocessingParameters parameters;
  final DateTime start;

  /// Segmente ohne Lücken (Lückenzeit und -strecke bleiben heraus).
  final List<_Leg> _legs = [];
  final List<DateTime> _triggers = [];

  void add(MotionSegment s) {
    if (s.isGap) return;
    _legs.add(_Leg(s.start, s.end, s.meters));
    final now = s.end;
    final w = parameters.settlingPaceWindow;
    final recent = _mean(now.subtract(w), now);
    final before = _mean(now.subtract(w * 2), now.subtract(w));
    // Beide Fenster müssen vollständig sein: Daten reichen bis zum Beginn des
    // früheren Fensters zurück und jedes Fenster hat zählende Zeit.
    if (recent == null || before == null) return;
    if (_legs.first.start.isAfter(now.subtract(w * 2))) return;
    if ((recent - before).abs() >= parameters.settlingPaceChange) {
      _triggers.add(now);
    }
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
