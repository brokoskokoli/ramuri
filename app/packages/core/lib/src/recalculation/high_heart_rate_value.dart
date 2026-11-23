import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/fitness_result.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/high_heart_rate_time.dart';
import '../preprocessing/run_preprocessor.dart';
import 'run_analysis.dart' show snapshotOf;

/// Wertschlüssel der Zeit bei mindestens 80 % HFmax (PAR-058). Ein Laufwert
/// wie der TRIMP: er hängt an HFmax und wird mit der Neuberechnung getauscht
/// (FR-0006, ADR-0004); Läufe ohne ihn bekommen ihn dort nachträglich.
const String highHeartRateTimeValueKey = 'high_hr_time';

const String minutesUnit = 'min';

/// Der Laufwert „Zeit bei mindestens 80 % HFmax“ in Minuten. Ohne Ergebnis
/// (Basis oder Daten) steht er ohne Zahl mit Grund, nie 0. [pre] ist `null`
/// bei einem Lauf ohne Dauer; [basis] wird als Schnappschuss am Wert
/// gespeichert. Reicht die Pulsabdeckung nicht für die volle Bewegungszeit,
/// ist er vorläufig (eine Untergrenze).
ComputedValue buildHighHeartRateTimeValue({
  required StoredRun run,
  required RunPreprocessing? pre,
  required HeartRateBasis basis,
  required FitnessParameters fitness,
  required Set<String> sources,
  required DateTime computedAt,
  HighHeartRateTimeModel model = const HighHeartRateTime(),
}) {
  final FitnessResult<HighHeartRateTimeResult> result = pre == null
      ? FitnessUnavailable(
          reason: UnavailableReason.noMovingTime,
          method: model.method,
          methodVersion: model.methodVersion,
          parameterVersion: fitness.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        )
      : model.compute(
          basis: basis,
          heartRate: pre.heartRate,
          movement: pre.movement,
          p: fitness,
        );
  final reason = result is FitnessUnavailable<HighHeartRateTimeResult>
      ? result.reason
      : null;
  final v = result is FitnessAvailable<HighHeartRateTimeResult>
      ? result.value
      : null;
  return ComputedValue(
    key: highHeartRateTimeValueKey,
    value: v?.minutes,
    unavailableReason: reason,
    heartRateBasis: snapshotOf(basis),
    unit: minutesUnit,
    computedAt: computedAt,
    dataFrom: run.startedAt,
    dataTo: run.endedAt,
    measurementCount: pre?.heartRate.acceptedValues.length ?? 0,
    sources: sources.toList()..sort(),
    method: result.method,
    methodVersion: result.methodVersion,
    parameterVersion: result.parameterVersion,
    quality: reason != null
        ? ValueQuality.undeterminable
        : (v!.incomplete ? ValueQuality.provisional : ValueQuality.good),
  );
}
