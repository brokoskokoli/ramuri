import '../../ports/storage_profile.dart';
import '../fitness/fitness_parameters.dart';
import '../fitness/fitness_result.dart';
import '../fitness/edwards_trimp.dart';
import '../fitness/heart_rate_basis.dart';
import '../fitness/heart_rate_reserve.dart';
import 'profile_validation.dart';

/// Herkunft der verwendeten HFmax.
enum MaxHeartRateSource {
  /// Eingabe des Nutzers (FR-0003), hat Vorrang.
  entered,

  /// Altersnäherung nach FR-0004, eine Schätzung (CON-0009).
  estimated,

  /// Weder Eingabe noch Alter: Bitte um Eingabe (OQ-0012).
  missing,
}

/// Aufgelöste Herzfrequenzbasis des Profils und Verfügbarkeit der
/// abhängigen Werte.
class ResolvedHeartRate {
  const ResolvedHeartRate({
    required this.basis,
    required this.maxSource,
    required this.reserveBasedReason,
    required this.trimpReason,
    required this.conflictAcrossSources,
  });

  /// Basis für die Fitnessverfahren; `maxIsEstimated` ist bei der Näherung
  /// gesetzt.
  final HeartRateBasis basis;

  final MaxHeartRateSource maxSource;

  /// `null`, wenn `r`, Reservezonen, VO₂max und aerobe Effizienz berechenbar
  /// sind, sonst der Grund (fehlender Wert, PAR-018, PAR-019).
  final UnavailableReason? reserveBasedReason;

  /// `null`, wenn der TRIMP berechenbar ist. Er braucht nur HFmax; bei
  /// PAR-019 läuft er weiter, bei PAR-018 nicht.
  final UnavailableReason? trimpReason;

  /// PAR-018 Satz 2: HFmax ist nicht größer als der Ruhepuls, aber nicht
  /// beide stammen aus Eingaben im Profil (Näherung oder fremde Quelle).
  final bool conflictAcrossSources;

  /// Die Oberfläche bittet um Eingabe der HFmax (kein Wert, kein Alter).
  bool get askForMaxInput => maxSource == MaxHeartRateSource.missing;

  /// Die Oberfläche bittet um Eingabe oder Prüfung der Werte, weil etwas
  /// fehlt oder in Konflikt steht (PAR-018, PAR-019, OQ-0012).
  bool get askForInputOrCheck =>
      reserveBasedReason != null || trimpReason != null;
}

/// Löst HFmax und Ruhepuls des Profils auf: Eingabe vor Näherung (FR-0003,
/// FR-0004). [externalRestingBpm] ist ein Ruhepuls aus anderer Quelle; er
/// gilt nur, wenn im Profil keiner steht, und zählt als „andere Quelle“
/// (PAR-018).
ResolvedHeartRate resolveHeartRate(
  ProfileRecord profile, {
  required int currentYear,
  int? externalRestingBpm,
  FitnessParameters fitness = const FitnessParameters.v4(),
}) {
  final enteredMax = profile.maxHeartRateBpm;
  final approx = approximateMaxHeartRate(
    ageFromBirthYear(profile.birthYear, currentYear),
  );
  final int? max;
  final MaxHeartRateSource source;
  if (enteredMax != null && enteredMax > 0) {
    max = enteredMax;
    source = MaxHeartRateSource.entered;
  } else if (approx != null) {
    max = approx;
    source = MaxHeartRateSource.estimated;
  } else {
    max = null;
    source = MaxHeartRateSource.missing;
  }
  final profileRest = profile.restingHeartRateBpm;
  final rest = profileRest ?? externalRestingBpm;
  final basis = HeartRateBasis(
    maxBpm: max,
    restingBpm: rest,
    maxIsEstimated: source == MaxHeartRateSource.estimated,
  );

  final reason = const HeartRateReserve().check(basis, fitness);
  final trimp = EdwardsTrimp.basisUnavailableReason(basis);
  final conflict =
      reason == UnavailableReason.maxNotAboveResting &&
      !(source == MaxHeartRateSource.entered && profileRest != null);
  return ResolvedHeartRate(
    basis: basis,
    maxSource: source,
    reserveBasedReason: reason,
    trimpReason: trimp,
    conflictAcrossSources: conflict,
  );
}
