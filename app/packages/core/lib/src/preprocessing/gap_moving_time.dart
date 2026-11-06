import 'movement_time_processor.dart';
import 'run_preprocessor.dart';

/// Bewegungszeit, die in Positionslücken (PAR-004) liegt. Sie hat keine
/// gemessene Strecke und gehört nicht in die Durchschnittspace (K20).
///
/// Die eine Rechnung für Live-Stand und Historie: Die Lücken sind die der
/// Positionsverarbeitung (Punktzeit, PAR-004, K18), dieselben, die die Strecke
/// nicht zählen. Eine offene Lücke zählt bis zum Ende des Ergebnisses.
Duration movingTimeInPositionGaps(RunPreprocessing r) => overlapDuration(
  r.movement.movingIntervals,
  [for (final g in r.position.gaps) TimeSpan(start: g.start, end: g.end)],
);

/// Bewegungszeit mit bekanntem Puls: die Bewegungszeit ohne die Pulslücken
/// (`HeartRateGap`, länger als PAR-010). `null`, wenn der Lauf keinen
/// akzeptierten Puls hat (nie 0). Das Gewicht des Durchschnittspulses im Mittel
/// über mehrere Läufe: Ein Lauf mit Pulslücken zählt nur mit der Zeit, in der
/// der Puls bekannt war.
Duration? movingTimeWithHeartRate(RunPreprocessing r) {
  if (r.heartRate.averageBpm == null) return null;
  var moving = Duration.zero;
  for (final m in r.movement.movingIntervals) {
    moving += m.end.difference(m.start);
  }
  final lost = overlapDuration(r.movement.movingIntervals, [
    for (final g in r.heartRate.gaps) TimeSpan(start: g.start, end: g.end),
  ]);
  final t = moving - lost;
  return t > Duration.zero ? t : null;
}

/// Summe der Überlappungen jeder Spanne aus [a] mit jeder aus [b]. Die eine
/// Rechnung für Live/Historie ([movingTimeInPositionGaps]) und die gespeicherte
/// Kurzfassung (Spannen `moving` und `positionGap`).
Duration overlapDuration(Iterable<TimeSpan> a, Iterable<TimeSpan> b) {
  var sum = Duration.zero;
  for (final m in a) {
    for (final g in b) {
      final from = m.start.isAfter(g.start) ? m.start : g.start;
      final to = m.end.isBefore(g.end) ? m.end : g.end;
      if (to.isAfter(from)) sum += to.difference(from);
    }
  }
  return sum;
}
