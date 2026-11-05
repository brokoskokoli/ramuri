import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/movement_time_processor.dart';
import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_time.dart';

/// Belastung eines Laufs nach TRIMP-Art (FR-0091). [points] sind relative
/// Trainingsbelastungspunkte.
class TrimpResult {
  const TrimpResult({
    required this.points,
    required this.incomplete,
    required this.coveredMicros,
    required this.movingMicros,
    required this.aboveHint,
  });

  /// `Σ t[i] · i` mit t in Minuten.
  final double points;

  /// Puls deckte weniger als die volle Bewegungszeit ab (OQ-0051); der Wert
  /// zählt nur die vorhandene Zeit.
  final bool incomplete;

  /// Bewegungszeit mit bekanntem Puls.
  final int coveredMicros;
  final int movingMicros;

  /// Mindestens ein Puls lag über 100 % HFmax (OQ-0014): HFmax zu niedrig
  /// oder Messfehler.
  final bool aboveHint;

  /// Anteil der Bewegungszeit mit Puls, 0 bis 1.
  double get coverage => coveredMicros / movingMicros;
}

/// Familie Belastungsmodell (FR-0091): reine Funktion aus Eingabe und
/// Parametersatz. Weitere Modelle kommen als weitere Varianten; ein Modell
/// mit anderer Eingabe (etwa subjektive Anstrengung) klärt Phase 2.
abstract class LoadModel extends AlgorithmVariant {
  const LoadModel();

  FitnessResult<TrimpResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  });
}

const loadModelFamily = AlgorithmFamily<LoadModel>('load-model');

/// Edwards-TRIMP (FR-0092, FR-0093), Kategorie A. Braucht nur HFmax; der
/// Ruhepuls wirkt nur über PAR-018 (HFmax <= HFRuhe: nicht verfügbar).
/// Reservezonen und PAR-019 gehen nie ein.
class EdwardsTrimp extends LoadModel {
  const EdwardsTrimp();

  static const methodId = 'edwards-trimp';

  @override
  String get method => methodId;
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.established;

  /// Gewicht zu einem Anteil von HFmax: Untergrenze inklusiv, darunter 0,
  /// über der obersten Grenze das höchste Gewicht (OQ-0014).
  int weightFor(double share, FitnessParameters p) {
    var weight = 0;
    for (var i = 0; i < p.trimpZoneLowerBounds.length; i++) {
      if (share >= p.trimpZoneLowerBounds[i]) weight = p.trimpWeights[i];
    }
    return weight;
  }

  /// [ArgumentError] bei unterschiedlich langen, nicht endlichen, negativen
  /// oder nicht streng aufsteigenden TRIMP-Grenzen oder bei Gewichten, die
  /// nicht zu den Grenzen passen.
  static void validateBounds(FitnessParameters p) {
    final b = p.trimpZoneLowerBounds;
    if (b.isEmpty || p.trimpWeights.length != b.length) {
      throw ArgumentError.value(
        p.trimpWeights,
        'trimpWeights',
        'Anzahl passt nicht zu den Grenzen',
      );
    }
    for (var i = 0; i < b.length; i++) {
      if (!b[i].isFinite || b[i] < 0) {
        throw ArgumentError.value(b[i], 'trimpZoneLowerBounds', 'ungültig');
      }
      if (i > 0 && b[i] <= b[i - 1]) {
        throw ArgumentError.value(
          b,
          'trimpZoneLowerBounds',
          'nicht aufsteigend',
        );
      }
    }
  }

  @override
  FitnessResult<TrimpResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) {
    requireSameParameterVersion(heartRate: heartRate, movement: movement, p: p);
    validateBounds(p);
    FitnessUnavailable<TrimpResult> no(UnavailableReason reason) =>
        FitnessUnavailable(
          reason: reason,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );

    final max = basis.usableMaxBpm;
    final rest = basis.usableRestingBpm;
    if (max == null) return no(UnavailableReason.missingMaxHeartRate);
    if (rest != null && max <= rest) {
      return no(UnavailableReason.maxNotAboveResting);
    }
    final time = heartRateTimeByBpm(
      heartRate: heartRate,
      movement: movement,
      p: p,
    );
    if (time.movingMicros == 0) return no(UnavailableReason.noMovingTime);
    if (time.coveredMicros == 0) return no(UnavailableReason.noHeartRate);
    if (time.coveredMicros * FitnessParameters.percent <
        time.movingMicros * p.minCoveragePercent) {
      return no(UnavailableReason.insufficientCoverage);
    }

    var weighted = 0;
    var hint = false;
    for (final e in time.microsByBpm.entries) {
      final share = e.key / max;
      weighted += e.value * weightFor(share, p);
      hint = hint || share > p.hintAboveShare;
    }
    return FitnessAvailable(
      value: TrimpResult(
        points: weighted / Duration.microsecondsPerMinute,
        incomplete:
            time.coveredMicros * FitnessParameters.percent <
            time.movingMicros * p.fullCoveragePercent,
        coveredMicros: time.coveredMicros,
        movingMicros: time.movingMicros,
        aboveHint: hint,
      ),
      method: method,
      methodVersion: methodVersion,
      parameterVersion: p.parameterVersion,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}
