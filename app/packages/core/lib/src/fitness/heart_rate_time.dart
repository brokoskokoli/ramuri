import '../preprocessing/heart_rate_beat.dart';
import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/movement_time_processor.dart';
import 'fitness_parameters.dart';

/// Puls und Zeit in Mikrosekunden (Entwurf „Puls zu Zeit“). Gemeinsame Hilfe
/// für Zonenzeiten und TRIMP.
class HeartRateTime {
  HeartRateTime({
    required this.movingMicros,
    required this.coveredMicros,
    required Map<int, int> microsByBpm,
  }) : microsByBpm = Map.unmodifiable(microsByBpm);

  /// Bewegungszeit (Überschneidungen nur einmal gezählt).
  final int movingMicros;

  /// Bewegungszeit ohne Lücken (> PAR-010) mit gehaltenem Puls.
  final int coveredMicros;

  /// Zeit je Pulswert, aufsteigend nach bpm. Summe = [coveredMicros].
  final Map<int, int> microsByBpm;
}

typedef _Span = ({int start, int end});

List<_Span> _merge(Iterable<_Span> spans) {
  final sorted = spans.where((s) => s.end > s.start).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final out = <_Span>[];
  for (final s in sorted) {
    if (out.isNotEmpty && s.start <= out.last.end) {
      if (s.end > out.last.end) {
        out[out.length - 1] = (start: out.last.start, end: s.end);
      }
    } else {
      out.add(s);
    }
  }
  return out;
}

/// [ArgumentError], wenn Puls, Bewegungszeit und Parametersatz nicht zur
/// selben Parameterversion gehören (NFR-0001, wie `SectionQuality.assess`).
void requireSameParameterVersion({
  required HeartRateResult heartRate,
  required MovementResult movement,
  required FitnessParameters p,
}) {
  final version = p.parameterVersion;
  if (heartRate.parameterVersion != version ||
      movement.parameterVersion != version) {
    throw ArgumentError(
      'Parameterversionen weichen ab: Puls ${heartRate.parameterVersion}, '
      'Bewegungszeit ${movement.parameterVersion}, Parametersatz $version',
    );
  }
}

typedef _Hold = ({int start, int end, int bpm});

/// Zeit je Puls. Abgedeckt ist die Bewegungszeit minus Lücken (> PAR-010);
/// darin gilt jeder akzeptierte Wert ab seiner Zeit höchstens einen
/// Median-Takt lang, bis zum nächsten Wert; der Rest fehlt (dasselbe Maß wie
/// die fehlende Zeit in `SectionQuality`, PAR-010). Beginnt eine abgedeckte
/// Spanne (Laufanfang, nach Pause oder Lücke) ohne gehaltenen Wert, zählt der
/// nächste Wert rückwirkend, wenn er höchstens einen Takt entfernt ist. Ist
/// kein Takt bekannt (weniger als zwei akzeptierte oder eingegangene Werte),
/// ist nichts abgedeckt. Bei gleicher Zeit gilt der spätere Wert. Wirft
/// [ArgumentError] bei abweichender Parameterversion.
HeartRateTime heartRateTimeByBpm({
  required HeartRateResult heartRate,
  required MovementResult movement,
  required FitnessParameters p,
}) {
  requireSameParameterVersion(heartRate: heartRate, movement: movement, p: p);
  final moving = _merge([
    for (final i in movement.movingIntervals)
      (
        start: i.start.microsecondsSinceEpoch,
        end: i.end.microsecondsSinceEpoch,
      ),
  ]);
  final movingMicros = moving.fold<int>(0, (a, s) => a + s.end - s.start);
  final empty = HeartRateTime(
    movingMicros: movingMicros,
    coveredMicros: 0,
    microsByBpm: const {},
  );
  final accepted = heartRate.acceptedValues;
  final beat = medianBeatMicros(receivedHeartRateTimes(heartRate));
  if (accepted.length < 2 || beat == null) return empty;

  final holes = _merge([
    for (final g in heartRate.gaps)
      (
        start: g.start.microsecondsSinceEpoch,
        end: g.end.microsecondsSinceEpoch,
      ),
  ]);
  // Bewegungszeit minus Lücken.
  final covered = <_Span>[];
  for (final m in moving) {
    var from = m.start;
    for (final h in holes) {
      if (h.end <= from) continue;
      if (h.start >= m.end) break;
      if (h.start > from) covered.add((start: from, end: h.start));
      if (h.end > from) from = h.end;
    }
    if (from < m.end) covered.add((start: from, end: m.end));
  }

  final order = List<int>.generate(accepted.length, (i) => i)
    ..sort((a, b) {
      final c = accepted[a].time.compareTo(accepted[b].time);
      return c != 0 ? c : a.compareTo(b);
    });
  final times = [
    for (final i in order) accepted[i].time.microsecondsSinceEpoch,
  ];
  // Haltezeit je Wert: bis zum nächsten Wert, höchstens ein Takt. Bei gleicher
  // Zeit bleibt für den früheren Eintrag eine leere Spanne.
  final holds = <_Hold>[];
  for (var k = 0; k < order.length; k++) {
    final limit = times[k] + beat;
    final end = k + 1 < times.length && times[k + 1] < limit
        ? times[k + 1]
        : limit;
    if (end > times[k]) {
      holds.add((start: times[k], end: end, bpm: accepted[order[k]].bpm));
    }
  }

  final byBpm = <int, int>{};
  var coveredMicros = 0;
  void add(int bpm, int from, int to) {
    if (to <= from) return;
    byBpm[bpm] = (byBpm[bpm] ?? 0) + to - from;
    coveredMicros += to - from;
  }

  var h = 0; // erster Halt, der nach Beginn der Spanne noch gilt
  for (final c in covered) {
    while (h < holds.length && holds[h].end <= c.start) {
      h++;
    }
    // Kein gehaltener Wert am Spannenanfang: der nächste zählt rückwirkend.
    if (h < holds.length &&
        holds[h].start > c.start &&
        holds[h].start - c.start <= beat) {
      final to = holds[h].start < c.end ? holds[h].start : c.end;
      add(holds[h].bpm, c.start, to);
    }
    for (var i = h; i < holds.length && holds[i].start < c.end; i++) {
      final from = holds[i].start > c.start ? holds[i].start : c.start;
      final to = holds[i].end < c.end ? holds[i].end : c.end;
      add(holds[i].bpm, from, to);
    }
  }
  final keys = byBpm.keys.toList()..sort();
  return HeartRateTime(
    movingMicros: movingMicros,
    coveredMicros: coveredMicros,
    microsByBpm: {for (final k in keys) k: byBpm[k]!},
  );
}
