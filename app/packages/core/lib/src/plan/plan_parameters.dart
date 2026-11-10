import '../goals/training_goal.dart';

/// Kennung und Version der Planerzeugung (NFR-0001, NFR-0005).
const String planMethod = 'weekly-time-course';
const int planMethodVersion = 1;

/// Stand der Parameter (ADR-0010 Punkt 1: `parameter_version`). Steigt, wenn
/// sich ein Wert in [PlanParameters] ändert.
const int planParameterVersion = 1;

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
    this.hardMinContinuousMinutes = 30,
    this.hardLongFromWeeklyMinutes = 180,
    this.intervalsShort = const HardBlocks(
      reps: 4,
      workMinutes: 3,
      pauseMinutes: 3,
    ),
    this.intervalsLong = const HardBlocks(
      reps: 6,
      workMinutes: 3,
      pauseMinutes: 3,
    ),
    this.tempoShort = const HardBlocks(
      reps: 2,
      workMinutes: 8,
      pauseMinutes: 2,
    ),
    this.tempoLong = const HardBlocks(
      reps: 2,
      workMinutes: 12,
      pauseMinutes: 2,
    ),
    this.progressiveBlockShort = 10,
    this.progressiveBlockLong = 15,
    this.warmUpMinutes = 10,
    this.coolDownMinutes = 5,
    this.minGapDays = 2,
    this.continuousRunMinutes = 30,
    this.peakFallbackShort = 35,
    this.peakFallbackTen = 65,
    this.peakFallbackHalf = 100,
    this.peakHalfMarathonKm = 16,
    this.peakMaxMinutes = 120,
    this.peakMinEasyRuns = 3,
    this.easyWindowWeeks = 6,
    this.largeChangeShare = 0.10,
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

  /// PAR-198: harte Einheit nur, wenn 30 min am Stück gehen (und ab 3 Läufen,
  /// siehe [hardMinRunDays]). Zugleich die Mindestdauer des progressiven Laufs
  /// (eigene Wahl, gemeldet).
  final int hardMinContinuousMinutes;

  /// PAR-198: ab 3 h Wochenzeit die längere Form der harten Einheit.
  final int hardLongFromWeeklyMinutes;

  /// PAR-198: Intervalle 4 × 3 min, Trabpause 3 min (kürzere Form).
  final HardBlocks intervalsShort;

  /// PAR-198: Intervalle 6 × 3 min ab 3 h Wochenzeit.
  final HardBlocks intervalsLong;

  /// PAR-198: Tempodauerlauf 2 × 8 min, Trabpause 2 min (kürzere Form).
  final HardBlocks tempoShort;

  /// PAR-198: Tempodauerlauf 2 × 12 min ab 3 h Wochenzeit.
  final HardBlocks tempoLong;

  /// PAR-198: progressiver Lauf mit 10 min Endblock (kürzere Form).
  final int progressiveBlockShort;

  /// PAR-198: 15 min Endblock ab 3 h Wochenzeit.
  final int progressiveBlockLong;

  /// PAR-120: Aufwärmen 10 min locker (die optionalen Steigerungen entfallen).
  final int warmUpMinutes;

  /// PAR-121: Abwärmen 5 bis 10 min; gewählt ist der untere Wert (eigene
  /// Wahl, gemeldet).
  final int coolDownMinutes;

  /// PAR-059: Zwischen zwei intensiven Einheiten liegt ein voller Kalendertag,
  /// der Abstand der Tage ist also mindestens 2.
  final int minGapDays;

  /// PAR-192: „30 min am Stück“; Grenze für die Ableitung aus dem Stand.
  final int continuousRunMinutes;

  /// PAR-205: Zielspitze (längster Lauf) ohne lockeres Tempo für 5 km.
  final int peakFallbackShort;

  /// PAR-205: ohne lockeres Tempo für 10 km.
  final int peakFallbackTen;

  /// PAR-205: ohne lockeres Tempo für den Halbmarathon.
  final int peakFallbackHalf;

  /// PAR-205: beim Halbmarathon läuft der längste Lauf 16 km im lockeren Tempo.
  final int peakHalfMarathonKm;

  /// PAR-205: höchstens 2 h.
  final int peakMaxMinutes;

  /// PAR-205: lockeres Tempo = Median aus mindestens 3 lockeren Läufen.
  final int peakMinEasyRuns;

  /// PAR-205: Fenster für lockere Läufe und (PAR-192) für den Stand aus
  /// vorhandenen Läufen, in Wochen.
  final int easyWindowWeeks;

  /// PAR-204: größere Änderung ab diesem Anteil Änderung der Wochenzeit.
  final double largeChangeShare;

  /// PAR-198: harte Einheit ab 3 Läufen je Woche.
  int get hardMinRunDays => 3;

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

/// Aufbau einer harten Einheit aus gleichen Blöcken (PAR-198): [reps]
/// Wiederholungen zu [workMinutes], dazwischen [pauseMinutes] Trabpause
/// (zwischen den Wiederholungen, nicht danach; Annahme, gemeldet).
class HardBlocks {
  const HardBlocks({
    required this.reps,
    required this.workMinutes,
    required this.pauseMinutes,
  });

  final int reps;
  final int workMinutes;
  final int pauseMinutes;

  /// Hauptteil in Minuten.
  int get mainMinutes => reps * workMinutes + (reps - 1) * pauseMinutes;
}
