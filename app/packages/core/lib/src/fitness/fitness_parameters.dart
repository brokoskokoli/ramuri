import '../preprocessing/preprocessing_parameters.dart';

/// Schwellen der Fitness- und Belastungsverfahren (docs/model-parameters.md,
/// Version 3, PAR-018, PAR-019, FR-0062, FR-0092, OQ-0014, OQ-0051).
///
/// Keine dieser Zahlen steht außerhalb dieser Klasse. Verfahren bekommen den
/// Satz als Argument; seine Version ist [currentParameterVersion].
class FitnessParameters {
  const FitnessParameters({
    required this.parameterVersion,
    this.minHeartRateReserveBpm = 50,
    this.reserveZoneCount = 5,
    this.reserveZoneBounds = const [0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
    this.trimpZoneLowerBounds = const [0.5, 0.6, 0.7, 0.8, 0.9],
    this.trimpWeights = const [1, 2, 3, 4, 5],
    this.hintAboveShare = 1.0,
    this.minCoveragePercent = 80,
    this.fullCoveragePercent = 100,
    this.sectionSelection = const SectionSelectionParameters(),
  });

  /// Die Startwerte aus Version 3 von docs/model-parameters.md.
  const FitnessParameters.v3()
    : this(parameterVersion: currentParameterVersion);

  /// Kopie mit ersetzten Zonengrenzen; alles andere bleibt wie in diesem Satz.
  FitnessParameters copyWith({
    List<double>? reserveZoneBounds,
    SectionSelectionParameters? sectionSelection,
  }) => FitnessParameters(
    parameterVersion: parameterVersion,
    minHeartRateReserveBpm: minHeartRateReserveBpm,
    reserveZoneCount: reserveZoneCount,
    reserveZoneBounds: reserveZoneBounds ?? this.reserveZoneBounds,
    trimpZoneLowerBounds: trimpZoneLowerBounds,
    trimpWeights: trimpWeights,
    hintAboveShare: hintAboveShare,
    minCoveragePercent: minCoveragePercent,
    fullCoveragePercent: fullCoveragePercent,
    sectionSelection: sectionSelection ?? this.sectionSelection,
  );

  /// Prozent je Ganzes; Umrechnung der ganzzahligen Abdeckung.
  static const percent = 100;

  /// Version des Parametersatzes (ADR-0004 P.3).
  final int parameterVersion;

  /// PAR-019: kleinste Herzfrequenzreserve (bpm); genau dieser Wert zählt
  /// noch als verfügbar.
  final int minHeartRateReserveBpm;

  /// FR-0061: Anzahl der Reservezonen; Grenzen haben einen Eintrag mehr.
  final int reserveZoneCount;

  /// FR-0062: Standardgrenzen der Reservezonen als Anteil der Reserve,
  /// aufsteigend; die erste ist die Untergrenze von Zone 1.
  final List<double> reserveZoneBounds;

  /// FR-0092: Untergrenzen der TRIMP-Zonen als Anteil von HFmax (inklusiv,
  /// OQ-0014). Darunter gilt Gewicht 0.
  final List<double> trimpZoneLowerBounds;

  /// FR-0092: Gewicht je TRIMP-Zone, gleiche Reihenfolge wie die Grenzen.
  final List<int> trimpWeights;

  /// OQ-0014: Anteil, ab dem darüber ein Hinweis erscheint (exklusiv: genau
  /// dieser Wert liegt noch ohne Hinweis in der obersten Zone).
  final double hintAboveShare;

  /// OQ-0051: Mindestabdeckung der Bewegungszeit mit Puls in ganzen Prozent;
  /// genau dieser Wert ist noch unvollständig bewertet, darunter nicht.
  final int minCoveragePercent;

  /// OQ-0051: Abdeckung in Prozent, ab der ein Ergebnis vollständig ist.
  final int fullCoveragePercent;

  /// PAR-020 bis PAR-031: Grenzen der Abschnittsauswahl für die VO₂max.
  final SectionSelectionParameters sectionSelection;
}

/// Grenzen der Abschnittsauswahl (FR-0073, FR-0074, FR-0075;
/// docs/model-parameters.md PAR-020 bis PAR-031, Version 3). PAR-006, PAR-010,
/// PAR-011 und PAR-025-Lücke (PAR-004) stehen in [PreprocessingParameters].
///
/// Jede Grenze ist inklusiv („höchstens“, „mindestens“, „zwischen“), außer
/// wo vermerkt.
class SectionSelectionParameters {
  const SectionSelectionParameters({
    this.minDuration = const Duration(minutes: 5),
    this.splitLength = const Duration(minutes: 10),
    this.paceMaxVariation = 0.05,
    this.paceMaxHalfDifference = 0.03,
    this.heartRateMaxHalfDifferenceBpm = 5,
    this.lateHalfWeightFrom = const Duration(minutes: 30),
    this.lateExcludeFrom = const Duration(minutes: 60),
    this.fullWeight = 1,
    this.lateWeight = 0.5,
    this.gpsMaxMedianAccuracyMeters = 10,
    this.gpsShareAccuracyMeters = 15,
    this.gpsMinShare = 0.9,
    this.gradientMin = -0.02,
    this.gradientMax = 0.03,
    this.gradientUseFrom = 0.01,
    this.gradientAltitudeFactor = 2,
    this.intensityMin = 0.55,
    this.intensityMax = 0.85,
    this.fullSpeedMetersPerMinute = 134,
    this.limitedSpeedMetersPerMinute = 120,
  });

  /// PAR-020: kürzester Abschnitt nach der Einschwingzeit.
  final Duration minDuration;

  /// PAR-021: Eine Phase der Länge `L` wird in `⌈L / splitLength⌉` gleich
  /// lange Abschnitte geteilt.
  final Duration splitLength;

  /// PAR-022: Variationskoeffizient der 30-s-Tempowerte (Anteil, 0,05 = 5 %).
  final double paceMaxVariation;

  /// PAR-022: größter Unterschied der Hälftentempi, relativ zu deren Mittel.
  final double paceMaxHalfDifference;

  /// PAR-023: größter Unterschied der Hälftenmittel des Pulses (bpm).
  final double heartRateMaxHalfDifferenceBpm;

  /// PAR-024: ab dieser Zeit seit Laufbeginn beginnende Abschnitte zählen mit
  /// [lateWeight].
  final Duration lateHalfWeightFrom;

  /// PAR-024: ab dieser Zeit seit Laufbeginn beginnende Abschnitte entfallen.
  final Duration lateExcludeFrom;

  /// PAR-024: Gewicht eines Abschnitts vor [lateHalfWeightFrom].
  final double fullWeight;

  /// PAR-024: Gewicht späterer Abschnitte.
  final double lateWeight;

  /// PAR-025: größter Median der gemeldeten Genauigkeit (m).
  final double gpsMaxMedianAccuracyMeters;

  /// PAR-025: Genauigkeit (m), die [gpsMinShare] der Punkte einhalten muss.
  final double gpsShareAccuracyMeters;

  /// PAR-025: kleinster Anteil der Punkte mit höchstens
  /// [gpsShareAccuracyMeters].
  final double gpsMinShare;

  /// PAR-026: kleinste zulässige Nettosteigung (Anteil, −0,02 = −2 %).
  final double gradientMin;

  /// PAR-026: größte zulässige Nettosteigung.
  final double gradientMax;

  /// PAR-027: Steigung zählt erst ab diesem Betrag (Anteil).
  final double gradientUseFrom;

  /// PAR-027: Die Höhenänderung muss mindestens so viele Vertikalgenauigkeiten
  /// betragen.
  final double gradientAltitudeFactor;

  /// PAR-028: kleinste Belastung `r`.
  final double intensityMin;

  /// PAR-029: größte Belastung `r`.
  final double intensityMax;

  /// PAR-030: Mindestgeschwindigkeit für die volle Bewertung (m/min).
  final double fullSpeedMetersPerMinute;

  /// PAR-031: darunter keine Schätzung; zwischen beiden Grenzen nur
  /// „vorläufig“ (m/min).
  final double limitedSpeedMetersPerMinute;
}
