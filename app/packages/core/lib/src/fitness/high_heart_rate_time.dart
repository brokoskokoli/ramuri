import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/movement_time_processor.dart';
import 'algorithm_variant.dart';
import 'edwards_trimp.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_time.dart';

/// Zeit eines Laufs bei mindestens
/// [FitnessParameters.highHeartRateMinSharePercent] % HFmax (PAR-058, Pulskriterium für absolvierte intensive Einheiten).
class HighHeartRateTimeResult {
  const HighHeartRateTimeResult({
    required this.micros,
    required this.coveredMicros,
    required this.movingMicros,
    required this.incomplete,
  });

  /// Bewegungszeit mit bekanntem Puls bei mindestens dem Anteil an HFmax.
  final int micros;

  /// Bewegungszeit mit bekanntem Puls (ohne Lücken nach PAR-010).
  final int coveredMicros;
  final int movingMicros;

  /// Der Puls deckt nicht die volle Bewegungszeit ab (PAR-010): die Zeit ist
  /// dann eine Untergrenze.
  final bool incomplete;

  double get minutes => micros / Duration.microsecondsPerMinute;
}

/// Familie „Zeit bei hohem Puls“ (PAR-058).
abstract class HighHeartRateTimeModel extends AlgorithmVariant {
  const HighHeartRateTimeModel();

  FitnessResult<HighHeartRateTimeResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  });
}

const highHeartRateTimeFamily = AlgorithmFamily<HighHeartRateTimeModel>(
  'high-heart-rate-time',
);

/// Zeit bei mindestens 80 % HFmax je Lauf (PAR-058, Auslegung OQ-0079),
/// Kategorie B. Gezählt wird nur Bewegungszeit mit bekanntem Puls nach
/// [heartRateTimeByBpm]: Pausen und Pulslücken (PAR-010) zählen nicht, es wird
/// nichts aufgefüllt. Ohne HFmax oder bei HFmax ≤ HFRuhe (PAR-018) ist der Wert
/// nicht verfügbar, ebenso ohne Puls; zu wenig Abdeckung macht ihn nur
/// vorläufig ([HighHeartRateTimeResult.incomplete]), weil gemessene Zeit über
/// der Grenze nie zu viel gezählt ist.
class HighHeartRateTime extends HighHeartRateTimeModel {
  const HighHeartRateTime();

  static const methodId = 'high-hr-time';

  @override
  String get method => methodId;
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  @override
  FitnessResult<HighHeartRateTimeResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) {
    requireSameParameterVersion(heartRate: heartRate, movement: movement, p: p);
    FitnessUnavailable<HighHeartRateTimeResult> no(UnavailableReason r) =>
        FitnessUnavailable(
          reason: r,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );

    final basisReason = EdwardsTrimp.basisUnavailableReason(basis);
    if (basisReason != null) return no(basisReason);
    final max = basis.usableMaxBpm!;
    final time = heartRateTimeByBpm(
      heartRate: heartRate,
      movement: movement,
      p: p,
    );
    if (time.movingMicros == 0) return no(UnavailableReason.noMovingTime);
    if (time.coveredMicros == 0) {
      return no(
        heartRate.acceptedValues.isEmpty
            ? UnavailableReason.noHeartRate
            : UnavailableReason.insufficientCoverage,
      );
    }
    var above = 0;
    for (final e in time.microsByBpm.entries) {
      // Ganzzahlig: bpm / max >= Anteil, ohne Rundung an der Grenze.
      if (e.key * FitnessParameters.percent >=
          p.highHeartRateMinSharePercent * max) {
        above += e.value;
      }
    }
    return FitnessAvailable(
      value: HighHeartRateTimeResult(
        micros: above,
        coveredMicros: time.coveredMicros,
        movingMicros: time.movingMicros,
        incomplete:
            time.coveredMicros * FitnessParameters.percent <
            time.movingMicros * p.fullCoveragePercent,
      ),
      method: method,
      methodVersion: methodVersion,
      parameterVersion: p.parameterVersion,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}
