import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';

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

/// Zeit je Puls. Abgedeckt ist die Bewegungszeit minus [gaps]; darin gilt je
/// Moment der letzte akzeptierte Wert (Halten), vor dem ersten Wert der
/// erste. Ohne [acceptedValues] ist nichts abgedeckt. Reihenfolge und
/// Überschneidung der Eingaben sind beliebig; bei gleicher Zeit gilt der
/// spätere Eintrag.
HeartRateTime heartRateTimeByBpm({
  required List<TimeSpan> movingIntervals,
  required List<RawHeartRate> acceptedValues,
  required List<HeartRateGap> gaps,
}) {
  final moving = _merge([
    for (final i in movingIntervals)
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
  if (acceptedValues.isEmpty) return empty;

  final holes = _merge([
    for (final g in gaps)
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

  final order = List<int>.generate(acceptedValues.length, (i) => i)
    ..sort((a, b) {
      final c = acceptedValues[a].time.compareTo(acceptedValues[b].time);
      return c != 0 ? c : a.compareTo(b);
    });
  final times = [
    for (final i in order) acceptedValues[i].time.microsecondsSinceEpoch,
  ];
  final bpms = [for (final i in order) acceptedValues[i].bpm];

  final byBpm = <int, int>{};
  var coveredMicros = 0;
  var idx = 0; // Index des letzten Werts mit time <= Position
  for (final c in covered) {
    // Vor dem ersten Zeitpunkt gilt der Wert, der dort gewinnt.
    final lookup = c.start < times.first ? times.first : c.start;
    while (idx + 1 < times.length && times[idx + 1] <= lookup) {
      idx++;
    }
    var pos = c.start;
    var cur = idx;
    while (pos < c.end) {
      final next = cur + 1 < times.length && times[cur + 1] < c.end
          ? times[cur + 1]
          : c.end;
      byBpm[bpms[cur]] = (byBpm[bpms[cur]] ?? 0) + next - pos;
      coveredMicros += next - pos;
      pos = next;
      while (cur + 1 < times.length && times[cur + 1] <= pos) {
        cur++;
      }
    }
  }
  final keys = byBpm.keys.toList()..sort();
  return HeartRateTime(
    movingMicros: movingMicros,
    coveredMicros: coveredMicros,
    microsByBpm: {for (final k in keys) k: byBpm[k]!},
  );
}
