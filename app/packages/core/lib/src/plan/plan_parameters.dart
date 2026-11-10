import '../goals/training_goal.dart';

/// Kennung und Version der Planerzeugung (NFR-0001, NFR-0005).
const String planMethod = 'weekly-time-course';
const int planMethodVersion = 1;

/// Alle Zahlen des Wochenzeit-Verlaufs, jede mit ihrer Regel. Nichts davon
/// steht außerhalb dieser Klasse. Voreinstellung sind die Werte aus
/// `planning-rules.md`; ändert sich einer, steigen Methodenversion und
/// Parameterstand.
class PlanParameters {
  const PlanParameters({
    this.rateBelowMid = 0.10,
    this.rateMid = 0.07,
    this.rateHigh = 0.05,
    this.midThresholdMinutes = 120,
    this.highThresholdMinutes = 240,
    this.lighterWeekEvery = 4,
    this.lighterWeekReduction = 0.20,
    this.reductionWeeksShort = 1,
    this.reductionShareShort = 0.30,
    this.reductionWeeksHalf = 2,
    this.reductionShareHalf = 0.40,
    this.peakLeadWeeks = 4,
    this.longestRunShareThreePlus = 0.40,
    this.longestRunShareTwo = 0.60,
    this.entryWeeks = 4,
    this.openHorizonWeeks = 26,
    this.dampingIterations = 40,
  });

  /// PAR-193: Steigerung je Woche unter [midThresholdMinutes] (+10 %).
  final double rateBelowMid;

  /// PAR-193: von [midThresholdMinutes] bis unter [highThresholdMinutes]
  /// (+7 %).
  final double rateMid;

  /// PAR-193: ab [highThresholdMinutes] (+5 %).
  final double rateHigh;

  /// PAR-193: 2 h.
  final int midThresholdMinutes;

  /// PAR-193: 4 h.
  final int highThresholdMinutes;

  /// PAR-194: jede 4. Woche leichter.
  final int lighterWeekEvery;

  /// PAR-194: 20 % weniger Wochenzeit.
  final double lighterWeekReduction;

  /// PAR-199: 5 km und 10 km, 1 Woche …
  final int reductionWeeksShort;

  /// PAR-199: … mit 30 % weniger.
  final double reductionShareShort;

  /// PAR-199: Halbmarathon, 2 Wochen …
  final int reductionWeeksHalf;

  /// PAR-199: … mit 40 % weniger.
  final double reductionShareHalf;

  /// PAR-199: Die Zielspitze liegt rund 4 Wochen vor der Reduktion.
  final int peakLeadWeeks;

  /// PAR-195: längster Lauf bei 3 und mehr Lauftagen, Anteil der Wochenzeit.
  final double longestRunShareThreePlus;

  /// PAR-195: bei 2 Lauftagen (bei 1 Lauftag der ganze Lauf, Anteil 1).
  final double longestRunShareTwo;

  /// Dauer der Phase „Einstieg“ in Wochen, wenn keine Geh-Lauf-Abfolge
  /// vorausgeht (FR-0141). Keine PAR-Regel, eigene Wahl (gemeldet).
  final int entryWeeks;

  /// Horizont in Wochen für ein Ziel ohne Datum (PAR-196: „läuft fort“).
  /// Keine PAR-Regel, Annahme (gemeldet).
  final int openHorizonWeeks;

  /// Schritte der Bisektion für die gedämpfte Steigerung (PAR-199). Technisch.
  final int dampingIterations;

  /// Reduktionswochen vor dem Termin (PAR-199).
  int reductionWeeks(GoalDistance d) =>
      d == GoalDistance.halfMarathon ? reductionWeeksHalf : reductionWeeksShort;

  /// Anteil, um den die Reduktionswochen unter der Wochenzeit liegen.
  double reductionShare(GoalDistance d) =>
      d == GoalDistance.halfMarathon ? reductionShareHalf : reductionShareShort;

  /// PAR-195: Anteil des längsten Laufs an der Wochenzeit.
  double longestRunShare(int runDays) => runDays <= 1
      ? 1
      : runDays == 2
      ? longestRunShareTwo
      : longestRunShareThreePlus;
}
