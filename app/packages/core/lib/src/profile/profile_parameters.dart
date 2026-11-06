import '../preprocessing/preprocessing_parameters.dart';

/// Grenzen der Profileingaben (docs/model-parameters.md, Version 3, PAR-016,
/// PAR-017) und Konstanten der Näherung (FR-0004).
///
/// Keine dieser Zahlen steht außerhalb dieser Klasse. Die Mindestreserve
/// (PAR-019) steht in `FitnessParameters`.
class ProfileParameters {
  const ProfileParameters({
    required this.parameterVersion,
    this.maxHrRejectBelowBpm = 100,
    this.maxHrRejectAboveBpm = 230,
    this.maxHrHintDeviationBpm = 25,
    this.restHrRejectBelowBpm = 30,
    this.restHrRejectAboveBpm = 120,
    this.restHrHintBelowBpm = 40,
    this.restHrHintAboveBpm = 110,
  });

  /// Die Startwerte aus Version 3 von docs/model-parameters.md.
  const ProfileParameters.v3()
    : this(parameterVersion: currentParameterVersion);

  final int parameterVersion;

  /// PAR-016: HFmax unter diesem Wert wird abgelehnt (100 selbst gilt).
  final int maxHrRejectBelowBpm;

  /// PAR-016: HFmax über diesem Wert wird abgelehnt (230 selbst gilt).
  final int maxHrRejectAboveBpm;

  /// PAR-016: Hinweis, wenn HFmax um mehr als dies von der Näherung abweicht
  /// (genau 25 bpm Abstand gibt keinen Hinweis).
  final int maxHrHintDeviationBpm;

  /// PAR-017: Ruhepuls unter diesem Wert wird abgelehnt (30 selbst gilt).
  final int restHrRejectBelowBpm;

  /// PAR-017: Ruhepuls über diesem Wert wird abgelehnt (120 selbst gilt).
  final int restHrRejectAboveBpm;

  /// PAR-017: Hinweis unter diesem Wert (40 selbst ohne Hinweis).
  final int restHrHintBelowBpm;

  /// PAR-017: Hinweis über diesem Wert (110 selbst ohne Hinweis).
  final int restHrHintAboveBpm;

  /// FR-0004: `HFmax = 208 − 0,7 · Alter`, als Zehntel gerechnet, damit
  /// keine Gleitkommafehler entstehen (Konstante 208 → 2080, Faktor 0,7 → 7).
  static const int approxBaseTenths = 2080;
  static const int approxPerYearTenths = 7;
}
