import '../preprocessing/preprocessing_parameters.dart';

/// Schwellen der Fitness- und Belastungsverfahren (docs/model-parameters.md,
/// Version 4, PAR-018, PAR-019, FR-0062, FR-0092, OQ-0014, OQ-0051).
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
    this.vo2max = const Vo2maxParameters(),
    this.aerobicEfficiency = const AerobicEfficiencyParameters(),
  });

  /// Die Startwerte aus Version 4 von docs/model-parameters.md.
  const FitnessParameters.v4()
    : this(parameterVersion: currentParameterVersion);

  /// Kopie mit ersetzten Zonengrenzen; alles andere bleibt wie in diesem Satz.
  FitnessParameters copyWith({
    List<double>? reserveZoneBounds,
    SectionSelectionParameters? sectionSelection,
    Vo2maxParameters? vo2max,
    AerobicEfficiencyParameters? aerobicEfficiency,
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
    vo2max: vo2max ?? this.vo2max,
    aerobicEfficiency: aerobicEfficiency ?? this.aerobicEfficiency,
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

  /// FR-0069, FR-0071, PAR-032, PAR-033, PAR-036 bis PAR-040: Schätzer und
  /// Laufstufe der VO₂max.
  final Vo2maxParameters vo2max;

  /// OQ-0036, PAR-044 bis PAR-047: aerobe Effizienz.
  final AerobicEfficiencyParameters aerobicEfficiency;
}

/// Grenzen der Abschnittsauswahl (FR-0073, FR-0074, FR-0075;
/// docs/model-parameters.md PAR-020 bis PAR-031, Version 4). PAR-006, PAR-010,
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

/// Konstanten und Grenzen des VO₂max-Schätzers (FR-0069, FR-0071,
/// docs/model-parameters.md PAR-032, PAR-033, PAR-036 bis PAR-040, Version 4).
class Vo2maxParameters {
  const Vo2maxParameters({
    this.restingOxygen = 3.5,
    this.runCoefficient = 0.2,
    this.gradeCoefficient = 0.9,
    this.plausibleMin = 25,
    this.plausibleMax = 90,
    this.weightMaxDuration = const Duration(minutes: 10),
    this.gpsGoodMedianMeters = 5,
    this.gpsGoodFactor = 1,
    this.gpsOtherFactor = 0.75,
    this.trendFromSections = 3,
    this.percentileFromSections = 5,
    this.percentileLow = 0.1,
    this.percentileHigh = 0.9,
    this.undeterminableAbovePercent = 20,
    this.sufficientMaxPercent = 10,
    this.goodMaxPercent = 5,
    this.sufficientMinSections = 2,
    this.goodMinSections = 3,
    this.goodMinDuration = const Duration(minutes: 20),
    this.preliminaryMaxSections = 1,
    this.alphaGoodMin = 0.15,
    this.alphaSufficientMin = 0.10,
    this.alphaPreliminaryMin = 0.05,
    this.alphaPreliminaryDivisorFactor = 2,
    this.restartAfter = const Duration(days: 56),
    this.restartRunNumber = 2,
    this.longTermRecentWindow = const Duration(days: 42),
    this.longTermGoodWindow = const Duration(days: 56),
    this.longTermMinRecentRuns = 3,
    this.longTermSufficientMinQualityRuns = 2,
    this.longTermGoodMinRuns = 5,
    this.longTermGoodMinGoodRuns = 3,
  });

  /// FR-0069: Ruheumsatz (ml/kg/min), auch in FR-0071.
  final double restingOxygen;

  /// FR-0069: Anteil je m/min Geschwindigkeit (ml/kg/min je m/min).
  final double runCoefficient;

  /// FR-0069: Anteil je m/min und Steigung als Dezimalzahl.
  final double gradeCoefficient;

  /// PAR-032: kleinste plausible VO₂max (ml/kg/min), inklusiv.
  final double plausibleMin;

  /// PAR-032: größte plausible VO₂max (ml/kg/min), inklusiv.
  final double plausibleMax;

  /// PAR-033: Dauer, bis zu der die Minuten in das Gewicht eingehen.
  final Duration weightMaxDuration;

  /// PAR-033: GPS-Median (m), bis zu dem der gute Faktor gilt (inklusiv).
  final double gpsGoodMedianMeters;

  /// PAR-033: GPS-Faktor bei Median bis [gpsGoodMedianMeters].
  final double gpsGoodFactor;

  /// PAR-033: GPS-Faktor sonst, auch ohne gemeldete Genauigkeit.
  final double gpsOtherFactor;

  /// PAR-036: ab so vielen Abschnitten wird zuerst der Zeittrend entfernt.
  final int trendFromSections;

  /// PAR-036: ab so vielen Abschnitten zählt P10 bis P90 statt Spannweite.
  final int percentileFromSections;

  /// PAR-036: unteres Perzentil als Anteil (0,1 = P10).
  final double percentileLow;

  /// PAR-036: oberes Perzentil als Anteil (0,9 = P90).
  final double percentileHigh;

  /// PAR-037: `S` darüber (Prozent, exklusiv) ist „nicht bestimmbar“.
  final double undeterminableAbovePercent;

  /// PAR-039: größtes `S` (Prozent, inklusiv) für „ausreichend“.
  final double sufficientMaxPercent;

  /// PAR-040: größtes `S` (Prozent, inklusiv) für „gut“.
  final double goodMaxPercent;

  /// PAR-039: kleinste Abschnittszahl für „ausreichend“.
  final int sufficientMinSections;

  /// PAR-040: kleinste Abschnittszahl für „gut“.
  final int goodMinSections;

  /// PAR-040: kleinste Summe der Abschnittsdauern für „gut“ (inklusiv).
  final Duration goodMinDuration;

  /// PAR-038: bis zu dieser Abschnittszahl ist der Lauf höchstens „vorläufig“.
  final int preliminaryMaxSections;

  /// PAR-034: untere Grenze von α bei „gut“ (`max(0,15; 1/n)`).
  final double alphaGoodMin;

  /// PAR-034: untere Grenze von α bei „ausreichend“.
  final double alphaSufficientMin;

  /// PAR-034: untere Grenze von α bei „vorläufig“ (`max(0,05; 1/(2n))`).
  final double alphaPreliminaryMin;

  /// PAR-034: Faktor vor `n` im Nenner bei „vorläufig“ (2).
  final int alphaPreliminaryDivisorFactor;

  /// PAR-035: Pause darüber (exklusiv) ohne verwertbaren Lauf startet neu.
  final Duration restartAfter;

  /// PAR-035: Laufnummer `n` des ersten Laufs nach dem Neustart.
  final int restartRunNumber;

  /// PAR-041 bis PAR-043: „letzte 6 Wochen“ (inklusiv).
  final Duration longTermRecentWindow;

  /// PAR-043: „letzte 8 Wochen“ (inklusiv).
  final Duration longTermGoodWindow;

  /// PAR-041 bis PAR-043: Läufe in [longTermRecentWindow]; weniger ist
  /// „vorläufig“, mindestens so viele sind Voraussetzung für die höheren
  /// Stufen.
  final int longTermMinRecentRuns;

  /// PAR-042: davon mindestens so viele „ausreichend“ oder „gut“.
  final int longTermSufficientMinQualityRuns;

  /// PAR-043: Läufe in [longTermGoodWindow].
  final int longTermGoodMinRuns;

  /// PAR-043: davon mindestens so viele „gut“.
  final int longTermGoodMinGoodRuns;
}

/// Grenzen der aeroben Effizienz (FR-0085 bis FR-0087, OQ-0036;
/// docs/model-parameters.md PAR-044 bis PAR-047, Version 4). Die Regeln
/// PAR-010, PAR-011, PAR-020 bis PAR-023, PAR-025 und der Ausschluss ab
/// PAR-024 kommen aus [SectionSelectionParameters]; hier stehen nur die
/// Werte, die von der VO₂max abweichen oder neu sind.
///
/// Jede Grenze ist inklusiv („höchstens“, „mindestens“, „zwischen“).
class AerobicEfficiencyParameters {
  const AerobicEfficiencyParameters({
    this.loadMin = 0.65,
    this.loadMax = 0.75,
    this.gradientMaxAbs = 0.02,
    this.windowLength = const Duration(days: 28),
    this.minSections = 3,
    this.minRuns = 2,
    this.minDuration = const Duration(minutes: 30),
    this.sufficientMinSections = 6,
    this.sufficientMinRuns = 3,
    this.goodMinSections = 10,
    this.goodMinRuns = 4,
    this.maxGradientDifference = 0.01,
  });

  /// OQ-0036: kleinstes mittleres `r` eines Abschnitts (65 %).
  final double loadMin;

  /// OQ-0036: größtes mittleres `r` eines Abschnitts (75 %).
  final double loadMax;

  /// PAR-045: größter Betrag der Nettosteigung (Anteil, 0,02 = 2 %). Unter
  /// der Höhengrenze aus PAR-027 gilt sie bereits als 0.
  final double gradientMaxAbs;

  /// OQ-0036: Länge eines Fensters (4 Wochen). Das aktuelle reicht bis
  /// „jetzt“, das Vergleichsfenster liegt davor.
  final Duration windowLength;

  /// PAR-046: Abschnitte je Fenster mindestens.
  final int minSections;

  /// PAR-046: Läufe je Fenster mindestens.
  final int minRuns;

  /// PAR-046: Summe der Abschnittsdauern je Fenster mindestens.
  final Duration minDuration;

  /// PAR-047: Abschnitte und Läufe für „ausreichend“ (schwächeres Fenster).
  final int sufficientMinSections;
  final int sufficientMinRuns;

  /// PAR-047: Abschnitte und Läufe für „gut“ (schwächeres Fenster).
  final int goodMinSections;
  final int goodMinRuns;

  /// PAR-047: Unterschied der mittleren Steigungen (Anteil, 0,01 = 1
  /// Prozentpunkt), über dem höchstens „vorläufig“ gilt.
  final double maxGradientDifference;
}
