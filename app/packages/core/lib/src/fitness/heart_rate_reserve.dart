import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';

/// Familie Herzfrequenzreserve (FR-0060): `r` aus Basis und Puls. Andere
/// Verfahren kommen als weitere Varianten (NFR-0005).
abstract class HeartRateReserveModel extends AlgorithmVariant {
  const HeartRateReserveModel();

  /// `null`, wenn `r` definiert ist, sonst der Grund.
  UnavailableReason? check(HeartRateBasis basis, FitnessParameters p);

  FitnessResult<double> relativeLoad(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  );
}

/// Herzfrequenzreserve und relative Auslastung `r` (FR-0060), Kategorie A.
class HeartRateReserve extends HeartRateReserveModel {
  const HeartRateReserve();

  static const methodId = 'heart-rate-reserve';

  @override
  String get method => methodId;
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.established;

  /// Prüft die Basis in der Reihenfolge fehlender Wert, PAR-018, PAR-019.
  /// `null`, wenn `r` definiert ist.
  @override
  UnavailableReason? check(HeartRateBasis basis, FitnessParameters p) {
    final max = basis.usableMaxBpm;
    final rest = basis.usableRestingBpm;
    if (max == null) return UnavailableReason.missingMaxHeartRate;
    if (rest == null) return UnavailableReason.missingRestingHeartRate;
    if (max <= rest) return UnavailableReason.maxNotAboveResting;
    if (max - rest < p.minHeartRateReserveBpm) {
      return UnavailableReason.reserveTooSmall;
    }
    return null;
  }

  /// `r = (hf - HFRuhe) / (HFmax - HFRuhe)`, eine Division, nicht geklemmt.
  @override
  FitnessResult<double> relativeLoad(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  ) {
    // Ein Puls <= 0 ist kein Messwert (FR-0056); der Vorverarbeiter filtert
    // ihn, ein direkter Aufruf (etwa Live-Zone) nicht.
    if (bpm <= 0) {
      return FitnessUnavailable(
        reason: UnavailableReason.noHeartRate,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        maxIsEstimated: basis.maxIsEstimated,
      );
    }
    final reason = check(basis, p);
    if (reason != null) {
      return FitnessUnavailable(
        reason: reason,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        maxIsEstimated: basis.maxIsEstimated,
      );
    }
    return FitnessAvailable(
      value:
          (bpm - basis.usableRestingBpm!) /
          (basis.usableMaxBpm! - basis.usableRestingBpm!),
      method: method,
      methodVersion: methodVersion,
      parameterVersion: p.parameterVersion,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}

const heartRateReserveFamily = AlgorithmFamily<HeartRateReserveModel>(
  'heart-rate-reserve',
);
