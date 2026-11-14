import '../preprocessing/preprocessing_parameters.dart';

/// Zahlen der Aufbereitung von Health-Connect-Daten (docs/phase-2-3-rules.md
/// Version 4: PAR-160, PAR-164, PAR-166; docs/model-parameters.md: PAR-017).
///
/// Keine dieser Zahlen steht außerhalb dieser Klasse. Alle Werte sind
/// vorläufige Startwerte (FR-0054).
class HealthParameters {
  const HealthParameters({
    required this.parameterVersion,
    this.mainSleepMaxAge = const Duration(hours: 16),
    this.mainSleepMinDuration = const Duration(hours: 3),
    this.sleepCoverageMinShare = 0.9,
    this.rmssdMinMs = 1,
    this.rmssdMaxMs = 200,
    this.hrvFallbackWindow = const Duration(minutes: 60),
    this.restingHeartRateMinBpm = 30,
    this.restingHeartRateMaxBpm = 120,
    this.efficiencyLowerKnee = 85,
    this.efficiencyUpperKnee = 95,
    this.efficiencyScoreAtLowerKnee = 70,
    this.efficiencyScoreCap = 80,
    this.efficiencySlopeBelow = 5,
  });

  /// Die Startwerte aus Version 4.
  const HealthParameters.v4() : this(parameterVersion: currentParameterVersion);

  final int parameterVersion;

  /// PAR-164: Die Sitzung muss in den letzten 16 h geendet haben.
  final Duration mainSleepMaxAge;

  /// PAR-164: Mindestdauer der Hauptschlafphase (kürzer ist ein Nickerchen).
  final Duration mainSleepMinDuration;

  /// PAR-166: Decken Phasen weniger als diesen Anteil der Sitzung ab, gilt
  /// die Sitzungsdauer als Schätzung.
  final double sleepCoverageMinShare;

  /// PAR-160: gültiger RMSSD-Bereich in ms (einschließlich der Grenzen).
  final double rmssdMinMs;
  final double rmssdMaxMs;

  /// PAR-160: Zeit nach dem Ende der Hauptschlafphase für den Rückfall.
  final Duration hrvFallbackWindow;

  /// PAR-017: Ruhepuls außerhalb 30–120 bpm wird abgelehnt (einschließlich
  /// der Grenzen gültig). Der Hinweisbereich 40–110 ist hier ohne Belang.
  final double restingHeartRateMinBpm;
  final double restingHeartRateMaxBpm;

  /// PAR-166: Teilskala der Effizienz E in Prozent.
  final double efficiencyLowerKnee;
  final double efficiencyUpperKnee;
  final double efficiencyScoreAtLowerKnee;
  final double efficiencyScoreCap;
  final double efficiencySlopeBelow;
}
