import 'movement_time_processor.dart';
import 'run_preprocessor.dart';

/// Bewegungszeit, die in Positionslücken (PAR-004) liegt. Sie hat keine
/// gemessene Strecke und gehört nicht in die Durchschnittspace (K20).
///
/// Die eine Rechnung für Live-Stand und Historie: Die Lücken sind die der
/// Positionsverarbeitung (Punktzeit, PAR-004, K18), dieselben, die die Strecke
/// nicht zählen. Eine offene Lücke zählt bis zum Ende des Ergebnisses.
Duration movingTimeInPositionGaps(RunPreprocessing r) {
  var sum = Duration.zero;
  for (final TimeSpan m in r.movement.movingIntervals) {
    for (final g in r.position.gaps) {
      final from = m.start.isAfter(g.start) ? m.start : g.start;
      final to = m.end.isBefore(g.end) ? m.end : g.end;
      if (to.isAfter(from)) sum += to.difference(from);
    }
  }
  return sum;
}
