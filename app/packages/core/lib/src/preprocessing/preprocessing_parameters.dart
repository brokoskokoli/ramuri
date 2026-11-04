/// Alle Schwellen der Vorverarbeitung (docs/model-parameters.md, Version 2).
///
/// Keine Schwelle steht außerhalb dieser Klasse. Prozessoren bekommen sie als
/// Argument, so sind abweichende Werte testbar.
class PreprocessingParameters {
  const PreprocessingParameters({
    required this.parameterVersion,
    this.positionMaxAccuracyMeters = 25,
    this.hardJumpMaxSpeed = 12.5,
    this.softJumpSpeed = 8,
    this.gapMaxDuration = const Duration(seconds: 10),
    this.liveSmoothingWindow = const Duration(seconds: 20),
    this.liveMinData = const Duration(seconds: 5),
    this.selectionMedianWindow = const Duration(seconds: 30),
    this.heartRateMin = 30,
    this.heartRateMax = 240,
    this.heartRateDiscardPoorContact = true,
    this.heartRateOutlierDeviation = 25,
    this.heartRateOutlierRate = 5,
    this.heartRateOutlierWindow = const Duration(seconds: 30),
    this.heartRateMaxMissingShare = 0.05,
    this.heartRateMaxSingleGap = const Duration(seconds: 10),
    this.settlingDuration = const Duration(minutes: 3),
    this.settlingPaceWindow = const Duration(minutes: 2),
    this.settlingPaceChange = 0.25,
    this.ascentThresholdMeters = 3,
    this.altitudeMedianWindow = const Duration(seconds: 30),
    this.altitudeMaxVerticalAccuracyMeters = 15,
    this.standstillBelow = 0.5,
    this.movementFrom = 0.8,
    this.standstillMinDuration = const Duration(seconds: 10),
    this.resumeMinDuration = const Duration(seconds: 3),
  });

  /// Die Startwerte aus Version 2 von docs/model-parameters.md. Nur hier ist
  /// die Version fest; jeder andere Parametersatz nennt seine Version selbst.
  const PreprocessingParameters.v2() : this(parameterVersion: 2);

  /// Version des Parametersatzes (ADR-0004 P.3).
  final int parameterVersion;

  /// PAR-001: größte erlaubte Horizontalgenauigkeit (m); genau der Wert zählt.
  final double positionMaxAccuracyMeters;

  /// PAR-002: Geschwindigkeit (m/s) zum letzten akzeptierten Punkt, darüber
  /// wird verworfen.
  final double hardJumpMaxSpeed;

  /// PAR-003: Geschwindigkeit (m/s), über der zusätzlich die Distanz gegen die
  /// Summe beider Genauigkeiten geprüft wird.
  final double softJumpSpeed;

  /// PAR-004: längere Zeit zwischen akzeptierten Punkten ist eine Lücke.
  final Duration gapMaxDuration;

  /// PAR-005: Fenster des Live-Tempos.
  final Duration liveSmoothingWindow;

  /// PAR-005: Live-Tempo erst ab so viel zählender Zeit im Fenster.
  final Duration liveMinData;

  /// PAR-006: Median-Fenster für Tempo und Herzfrequenz der Abschnittsauswahl.
  final Duration selectionMedianWindow;

  /// PAR-007: kleinster gültiger Puls (bpm), inklusive.
  final int heartRateMin;

  /// PAR-007: größter gültiger Puls (bpm), inklusive.
  final int heartRateMax;

  /// PAR-008: schlechten Hautkontakt verwerfen.
  final bool heartRateDiscardPoorContact;

  /// PAR-009: Abweichung vom Median (bpm), darüber Ausreißer.
  final double heartRateOutlierDeviation;

  /// PAR-009: Änderungsrate (bpm/s), darüber Ausreißer.
  final double heartRateOutlierRate;

  /// PAR-009: Fenster des Medians.
  final Duration heartRateOutlierWindow;

  /// PAR-010: größter Anteil fehlender Zeit im Abschnitt.
  final double heartRateMaxMissingShare;

  /// PAR-010: größte Einzellücke im Abschnitt.
  final Duration heartRateMaxSingleGap;

  /// PAR-011: Einschwingzeit nach Start, Pause und Tempowechsel.
  final Duration settlingDuration;

  /// PAR-011: Fensterlänge der Tempo-Mittel für den Tempowechsel.
  final Duration settlingPaceWindow;

  /// PAR-011: Tempowechsel ab dieser Abweichung der Mittel (m/s).
  final double settlingPaceChange;

  /// PAR-012: Höhenänderungen darunter zählen nicht zum Aufstieg (m).
  final double ascentThresholdMeters;

  /// PAR-013: Median-Fenster der Höhe.
  final Duration altitudeMedianWindow;

  /// PAR-013: größte erlaubte Vertikalgenauigkeit (m); genau der Wert zählt.
  final double altitudeMaxVerticalAccuracyMeters;

  /// PAR-014: Stillstand unter dieser Geschwindigkeit (m/s).
  final double standstillBelow;

  /// PAR-014: Bewegung wieder ab dieser Geschwindigkeit (m/s).
  final double movementFrom;

  /// PAR-015: Stillstand zählt ab dieser Dauer als Pause.
  final Duration standstillMinDuration;

  /// PAR-015: Fortsetzen nach dieser Dauer über der oberen Schwelle.
  final Duration resumeMinDuration;
}
