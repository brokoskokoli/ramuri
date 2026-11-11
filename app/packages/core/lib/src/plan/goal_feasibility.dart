import '../goals/training_goal.dart';
import '../prediction/goal_prediction.dart' show GoalFeasibility;
import 'plan_course.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'weekly_time.dart';

/// Warum die Einschätzung so ausfällt (PAR-206, FR-0154). Nur Codes, die
/// Texte kommen mit der Oberfläche (WP22).
enum FeasibilityReason {
  /// Streckenziel: Die Zielspitze ist zum Datum erreicht.
  peakReached,

  /// Streckenziel: Die Zielspitze ist zum Datum nicht erreicht; ab
  /// [GoalAssessment.fitsFrom] passt es.
  peakTooLate,

  /// Streckenziel: Auch ein späteres Datum hilft nicht, weil der Regler unter
  /// der Zielspitze liegt (siehe [GoalAssessment.regulatorTooLow]).
  peakAboveRegulator,

  /// Streckenziel: Die Zielspitze wird auch bis zum spätesten geprüften Datum
  /// nicht erreicht (ohne dass der Regler schuld ist; praktisch nicht
  /// erreichbar).
  peakNotWithinHorizon,

  /// Zeitziel: nötige Verbesserung bis 0,25 % je Woche.
  improvementSmall,

  /// Zeitziel: nötige Verbesserung bis 0,5 % je Woche.
  improvementMedium,

  /// Zeitziel: nötige Verbesserung über 0,5 % je Woche.
  improvementLarge,

  /// Zeitziel: keine Referenz und keine aktuelle Leistung.
  noReference,

  /// Zeitziel: weniger als 3 Läufe in 4 Wochen.
  tooFewRuns,

  /// Offenes Ziel (oder Ziel ohne Datum): keine Machbarkeitsprüfung, die
  /// Oberfläche zeigt die Regelmäßigkeit (DEC-0036, PAR-206).
  showRegularity,
}

/// Zahlen der Einschätzung (PAR-206). Die Suchweite hat keine PAR (Lücke,
/// eigene Wahl).
class FeasibilityParameters {
  const FeasibilityParameters({
    this.fitsUpToPercentPerWeek = 0.25,
    this.tightUpToPercentPerWeek = 0.5,
    this.minRuns = 3,
    this.runWindowDays = 28,
    this.searchWeeks = 156,
  });

  /// PAR-206: bis 0,25 % je Woche „passt“.
  final double fitsUpToPercentPerWeek;

  /// PAR-206: bis 0,5 % „knapp“, darüber „eher später“.
  final double tightUpToPercentPerWeek;

  /// PAR-206: mindestens 3 Läufe …
  final int minRuns;

  /// PAR-206: … in 4 Wochen.
  final int runWindowDays;

  /// Wie weit nach einem späteren Datum gesucht wird (keine PAR, eigene Wahl).
  final int searchWeeks;
}

/// Einschätzung des Ziels (PAR-206). Wird nie gespeichert und ändert nie das
/// Datum; das Datum [fitsFrom] ist nur ein Angebot.
class GoalAssessment {
  const GoalAssessment({
    required this.feasibility,
    required this.reason,
    this.fitsFrom,
    this.requiredPercentPerWeek,
    this.regulatorTooLow = false,
    this.sessionLimitsLongestRun = false,
    this.hardFit = HardFitStatus.notApplicable,
  });

  /// Der Wert, den [predictGoal] als Eingabe nimmt; `null` bei
  /// [FeasibilityReason.showRegularity] (keine Prüfung).
  final GoalFeasibility? feasibility;
  final FeasibilityReason reason;

  /// „Ab etwa“ dieses Datum passt es (Kalendertag, UTC); nur beim
  /// Streckenziel (PAR-206), sonst `null`, auch wenn es passt oder kein Datum
  /// zu nennen ist.
  final DateTime? fitsFrom;

  /// Zeitziel: nötige Verbesserung der Zeit in Prozent je Woche (ohne
  /// Rundung); sonst `null`.
  final double? requiredPercentPerWeek;

  /// Die Zielspitze liegt über dem Regler: Der Plan kann sie nicht erreichen
  /// und hält beim Regler (PAR-196, PAR-206). Gilt für Strecken- und
  /// Zeitziele, ohne die Einschätzung eines Zeitziels zu ändern.
  final bool regulatorTooLow;

  /// Der längste Lauf der Zielspitze passt nicht in die maximale Zeit je
  /// Einheit (PAR-195, PAR-205); der Rest bleibt unverplant. Nicht in PAR-206
  /// genannt (Lücke), nur als Hinweis.
  final bool sessionLimitsLongestRun;

  /// Zeitziel mit harter Einheit: derselbe Ziel-Wochenwert wie in
  /// `generatePlan` (siehe [PlanCourseSetup.hardFit]).
  final HardFitStatus hardFit;
}

/// Grundlage eines Zeitziels (FR-0129, FR-0130): aktuelle Leistung auf der
/// Zielstrecke (letzte Läufe oder Referenz) und die Läufe der letzten 4
/// Wochen. Der Aufrufer liefert beides (aus der Prognose).
class TimeGoalBasis {
  const TimeGoalBasis({this.currentSeconds, this.runsInWindow = 0});
  final double? currentSeconds;
  final int runsInWindow;
}

/// Einschätzung nach PAR-206 und FR-0154. Ein Ziel ohne Datum (offene Ziele
/// zeigen die Regelmäßigkeit, OQ-0027, DEC-0036) liefert
/// [FeasibilityReason.showRegularity] ohne Zahlen.
///
/// Streckenziel: Der Verlauf der Wochenzeit wird mit demselben Aufruf
/// simuliert wie in `generatePlan`. Passt die Zielspitze zum Datum, ist es
/// „passt“, sonst „knapp“ mit dem frühesten Datum (gleicher Wochentag wie das
/// Ziel), zu dem sie passt. Ein späteres Datum ist nie schlechter, weil der
/// Verlauf bis zum Aufbauende derselbe bleibt. Liegt der Regler unter der
/// Zielspitze, gilt „knapp“ ohne Datum und [GoalAssessment.regulatorTooLow].
///
/// Zeitziel: nötige Verbesserung je Woche, linear (Annahme; PAR-206 nennt
/// keine Form) über die Wochen von [today] bis zum Datum.
GoalAssessment assessGoal({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  TimeGoalBasis basis = const TimeGoalBasis(),
  FeasibilityParameters feasibility = const FeasibilityParameters(),
  PlanParameters parameters = const PlanParameters(),
}) {
  final date = goal.targetDate;
  final distance = goal.distance;
  if (goal.type == GoalType.open || date == null || distance == null) {
    return const GoalAssessment(
      feasibility: null,
      reason: FeasibilityReason.showRegularity,
    );
  }
  final todayDay = planDay(today);
  final target = planDay(date);
  final setup = planCourseSetup(goal, inputs, parameters: parameters);
  final peak = setup.peakMinutes!;
  final tooLow = setup.regulatorTooLow;
  final sessionLimits = setup.sessionLimitsLongestRun;

  if (goal.type == GoalType.time) {
    return _timeGoal(
      goal: goal,
      today: todayDay,
      target: target,
      basis: basis,
      f: feasibility,
      regulatorTooLow: tooLow,
      sessionLimits: sessionLimits,
      hardFit: setup.hardFit,
    );
  }

  bool reached(DateTime d) {
    // Mit Geh-Lauf-Abfolge wird die Spitze erst danach erreicht.
    if (setup.walkRunWeeks == 0 && inputs.startWeeklyMinutes >= peak) {
      return true;
    }
    return setup.course(today: todayDay, targetDate: d).reachedLevelWeek !=
        null;
  }

  if (tooLow) {
    return GoalAssessment(
      feasibility: GoalFeasibility.tight,
      reason: FeasibilityReason.peakAboveRegulator,
      regulatorTooLow: true,
      sessionLimitsLongestRun: sessionLimits,
    );
  }
  if (reached(target)) {
    return GoalAssessment(
      feasibility: GoalFeasibility.fits,
      reason: FeasibilityReason.peakReached,
      sessionLimitsLongestRun: sessionLimits,
    );
  }
  for (var k = 1; k <= feasibility.searchWeeks; k++) {
    final d = target.add(Duration(days: 7 * k));
    if (reached(d)) {
      return GoalAssessment(
        feasibility: GoalFeasibility.tight,
        reason: FeasibilityReason.peakTooLate,
        fitsFrom: d,
        sessionLimitsLongestRun: sessionLimits,
      );
    }
  }
  return GoalAssessment(
    feasibility: GoalFeasibility.tight,
    reason: FeasibilityReason.peakNotWithinHorizon,
    sessionLimitsLongestRun: sessionLimits,
  );
}

/// Toleranz gegen Gleitkommafehler an den Grenzen „bis 0,25 %“ und „bis
/// 0,5 %“ (PAR-206: einschließlich).
const double _eps = 1e-9;

GoalAssessment _timeGoal({
  required TrainingGoal goal,
  required DateTime today,
  required DateTime target,
  required TimeGoalBasis basis,
  required FeasibilityParameters f,
  required bool regulatorTooLow,
  required bool sessionLimits,
  required HardFitStatus hardFit,
}) {
  GoalAssessment make(
    GoalFeasibility feasibility,
    FeasibilityReason reason, {
    double? percent,
  }) => GoalAssessment(
    feasibility: feasibility,
    reason: reason,
    requiredPercentPerWeek: percent,
    regulatorTooLow: regulatorTooLow,
    sessionLimitsLongestRun: sessionLimits,
    hardFit: hardFit,
  );

  final current = basis.currentSeconds;
  if (current == null || !current.isFinite || current <= 0) {
    return make(GoalFeasibility.notEnoughData, FeasibilityReason.noReference);
  }
  if (basis.runsInWindow < f.minRuns) {
    return make(GoalFeasibility.notEnoughData, FeasibilityReason.tooFewRuns);
  }
  final goalSeconds = goal.targetSeconds!;
  final needed = (current - goalSeconds) / current * 100; // Prozent gesamt
  if (needed <= 0) {
    return make(
      GoalFeasibility.fits,
      FeasibilityReason.improvementSmall,
      percent: 0,
    );
  }
  final days = target.difference(today).inDays;
  final weeks = days / 7;
  final perWeek = weeks > 0 ? needed / weeks : double.infinity;
  final percent = perWeek.isFinite ? perWeek : null;
  if (perWeek <= f.fitsUpToPercentPerWeek + _eps) {
    return make(
      GoalFeasibility.fits,
      FeasibilityReason.improvementSmall,
      percent: percent,
    );
  }
  if (perWeek <= f.tightUpToPercentPerWeek + _eps) {
    return make(
      GoalFeasibility.tight,
      FeasibilityReason.improvementMedium,
      percent: percent,
    );
  }
  return make(
    GoalFeasibility.later,
    FeasibilityReason.improvementLarge,
    percent: percent,
  );
}

/// Darf der Plan einen 5-km-Test enthalten (PAR-117)? Mindestens 3 Läufe je
/// Woche im Plan ([PlanParameters.hardMinRunDays], „wie PAR-198“) und 30 min
/// am Stück ([canRunContinuous30] für die Woche von [today]).
bool planAllowsFiveKilometerTest({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  PlanParameters parameters = const PlanParameters(),
}) {
  if (goal.runDays.length < parameters.hardMinRunDays) return false;
  final anchorMonday = planDay(inputs.anchor);
  final week = planDay(today).difference(anchorMonday).inDays ~/ 7;
  return planCanRunContinuous30(
    goal,
    inputs,
    weekIndex: week < 0 ? 0 : week,
    walkRunWeeks: planCourseSetup(
      goal,
      inputs,
      parameters: parameters,
    ).walkRunWeeks,
    parameters: parameters,
  );
}
