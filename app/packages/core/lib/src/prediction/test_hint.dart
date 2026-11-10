import 'performance_prediction.dart';
import 'prediction_level.dart';
import 'prediction_parameters.dart';
import 'prediction_run.dart';
import 'reference_performance.dart';

/// Ob bei „nicht bestimmbar“ ein Hinweis auf einen 5-km-Test erscheint
/// (PAR-117, PAR-143, FR-0129). Nur wenn der Plan ihn enthalten dürfte:
/// mindestens 3 Läufe je Woche und 30 min am Stück. Solange es keinen Plan
/// gibt (WP21), gilt die Ersatzregel: mindestens
/// [PredictionParameters.testHintMinimumRuns] Läufe in den letzten
/// [PredictionParameters.testHintWindowDays] Tagen und ein Lauf von
/// mindestens 30 min darin (Annahme WP20). Ohne Hinweis bleibt nur der Grund.
/// Eine selbst eingetragene Zeit bleibt immer möglich.
bool showFiveKilometerTestHint({
  required PerformancePrediction prediction,
  required DateTime now,
  required Iterable<PredictionRun> runs,
  PredictionParameters parameters = const PredictionParameters(),
}) {
  final p = parameters;
  if (prediction.of(PredictionDistance.fiveKilometers).level !=
      PredictionLevel.notDeterminable) {
    return false;
  }
  var count = 0;
  var longest = 0.0;
  for (final r in runs) {
    final age = daysBetween(r.date, now);
    if (age < 0 || age >= p.testHintWindowDays) continue;
    count++;
    if (r.movingSeconds > longest) longest = r.movingSeconds;
  }
  return count >= p.testHintMinimumRuns &&
      longest >= p.testHintMinimumContinuousMinutes * 60;
}
