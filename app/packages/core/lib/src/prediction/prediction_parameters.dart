/// Kennung und Version der Leistungsprognose (NFR-0001, NFR-0005).
const String predictionMethod = 'riegel-prediction';
const int predictionMethodVersion = 1;

/// Zieldistanzen der Prognose (FR-0128), Meter.
enum PredictionDistance {
  fiveKilometers(5000),
  tenKilometers(10000),
  halfMarathon(21097.5),
  marathon(42195);

  const PredictionDistance(this.meters);
  final double meters;
}

/// Alle Zahlen der Prognose, jede mit ihrer Regel. Nichts davon steht
/// außerhalb dieser Klasse. Die Voreinstellung sind die Werte aus
/// `phase-2-3-rules.md`.
class PredictionParameters {
  const PredictionParameters({
    this.riegelExponent = 1.06,
    this.minimumReferenceMeters = 3000,
    this.maxReferenceAgeDays = 182,
    this.maxPauseDaysExclusive = 56,
    this.provisionalCapAgeDays = 84,
    this.provisionalCapRatio = 3,
    this.sufficientMaxAgeDays = 84,
    this.sufficientMaxRatio = 3,
    this.sufficientRegularWeeks = 6,
    this.goodMaxAgeDays = 42,
    this.goodMaxRatio = 2.2,
    this.goodRegularWeeks = 7,
    this.regularityWeeks = 8,
    this.regularityRunsPerWeek = 2,
    this.goodLongestRunDays = 42,
    this.goodLongestRunShare = 0.6,
    this.suggestionMinimumRpe = 8,
    this.suggestionMinimumMeters = 3000,
    this.testHintWindowDays = 28,
    this.testHintMinimumRuns = 12,
    this.testHintMinimumContinuousMinutes = 30,
  }) : assert(riegelExponent > 0),
       assert(regularityWeeks >= goodRegularWeeks),
       assert(goodRegularWeeks >= sufficientRegularWeeks);

  /// FR-0130: Exponent des Riegel-Modells.
  final double riegelExponent;

  /// FR-0129 / Festlegung WP20: Mindestdistanz einer Referenz.
  final double minimumReferenceMeters;

  /// PAR-143, PAR-144: älter (Tage) ist „nicht bestimmbar“ (26 Wochen).
  final int maxReferenceAgeDays;

  /// PAR-143 (PAR-202): eine Lücke ab so vielen Tagen ist eine Pause.
  final int maxPauseDaysExclusive;

  /// PAR-144: Referenz über so viele Tage (12 Wochen) begrenzt auf vorläufig.
  final int provisionalCapAgeDays;

  /// PAR-144: Verhältnis über diesem Wert begrenzt auf vorläufig.
  final double provisionalCapRatio;

  /// PAR-145: höchstens so alt (12 Wochen).
  final int sufficientMaxAgeDays;

  /// PAR-145: Verhältnis höchstens so groß.
  final double sufficientMaxRatio;

  /// PAR-145: so viele der letzten [regularityWeeks] Wochen mit Läufen.
  final int sufficientRegularWeeks;

  /// PAR-146: höchstens so alt (6 Wochen).
  final int goodMaxAgeDays;

  /// PAR-146: Verhältnis höchstens so groß.
  final double goodMaxRatio;

  /// PAR-146: so viele der letzten [regularityWeeks] Wochen mit Läufen.
  final int goodRegularWeeks;

  /// PAR-145, PAR-146: betrachtete rollende 7-Tage-Wochen.
  final int regularityWeeks;

  /// PAR-145, PAR-146: Läufe je Woche, damit sie zählt.
  final int regularityRunsPerWeek;

  /// PAR-146: Fenster (Tage) der längsten Einheit.
  final int goodLongestRunDays;

  /// PAR-146: Anteil der prognostizierten Zeit für die längste Einheit.
  final double goodLongestRunShare;

  /// PAR-185: Mindest-RPE für den Vorschlag.
  final int suggestionMinimumRpe;

  /// PAR-185: Mindeststrecke (Meter) des Vorschlags (Annahme, Festlegung WP20).
  final double suggestionMinimumMeters;

  /// PAR-117, PAR-143: Ersatzfenster (Tage) für den Testhinweis, solange es
  /// keinen Plan gibt (Annahme, Festlegung WP20; WP21 ersetzt sie).
  final int testHintWindowDays;

  /// Ersatzregel Testhinweis: Mindestzahl Läufe im Fenster.
  final int testHintMinimumRuns;

  /// PAR-117: 30 min am Stück.
  final int testHintMinimumContinuousMinutes;
}
