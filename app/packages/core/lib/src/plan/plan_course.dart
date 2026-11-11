import '../goals/training_goal.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'walk_run_schedule.dart';
import 'week_units.dart';
import 'weekly_time.dart';

/// Wie die harte Einheit das Ziel-Wochenmaß eines Zeitziels bestimmt.
enum HardFitStatus {
  /// Nicht anwendbar (Streckenziel, offenes Ziel oder Schalter aus).
  notApplicable,

  /// Die Passform-Wochenzeit liegt über der Zielspitze; der Plan steigert bis
  /// dorthin (höchstens bis zum Regler).
  raised,

  /// Die harte Einheit passt auf dem Niveau der Zielspitze (höchstens der
  /// Regler), in jeder der drei Formen.
  atPeak,

  /// Die Passform-Wochenzeit liegt über dem Regler; keine harte Einheit, die
  /// Zielspitze gilt wie bisher.
  regulatorBelowFit,

  /// Die harte Einheit passt auf dem Niveau der Zielspitze (höchstens der
  /// Regler) nur in einem Teil der Wochen (nicht in allen drei Formen, z. B.
  /// ab 180 min die lange Form über der maximalen Zeit); mindestens eine Form
  /// passt. Die Rotation rückt in jeder Woche mit vorgesehener harter Einheit
  /// weiter (PAR-198), die passenden Formen erscheinen also reihum: je passender
  /// Form in jeder dritten Woche. Bei höchstens zwei Spitzenwochen kann sie in
  /// den Spitzenwochen trotzdem fehlen. Zielspitze wie bisher.
  partialAtPeak,

  /// Die harte Einheit passt auf dem Niveau der Spitze in keiner Woche, auch
  /// nicht in einer einzelnen Form, und bei keiner Wochenzeit darüber (z. B.
  /// weniger als 3 Lauftage oder maximale Zeit je Einheit zu kurz); Zielspitze
  /// wie bisher.
  neverFits,
}

/// Obergrenze der Suche nach der Passform-Wochenzeit (Minuten, eine Woche).
const int _hardFitSearchLimit = 7 * 24 * 60;

/// Die gemeinsamen Größen von Planerzeugung und Machbarkeitsprüfung: Regler,
/// Zielspitze und Geh-Lauf-Abfolge (PAR-195, PAR-196, PAR-205, PAR-206). Eine
/// Stelle, damit `generatePlan` und `assessGoal` nicht auseinanderlaufen.
class PlanCourseSetup {
  const PlanCourseSetup._({
    required this.goal,
    required this.inputs,
    required this.parameters,
    required this.capMinutes,
    required this.maxSessionMinutes,
    required this.distance,
    required this.longestRunMinutes,
    required this.peakMinutes,
    required this.targetPeakMinutes,
    required this.hardFit,
    required this.hardFitMinutes,
    required this.walkRun,
  });

  final TrainingGoal goal;
  final PlanInputs inputs;
  final PlanParameters parameters;

  /// Regler in Minuten (PAR-196), mindestens 1.
  final int capMinutes;

  /// Maximale Zeit je Einheit in Minuten.
  final int maxSessionMinutes;

  /// Strecke des Ziels; `null` beim offenen Ziel.
  final GoalDistance? distance;

  /// Längster Lauf der Zielspitze (PAR-205); `null` ohne Strecke.
  final int? longestRunMinutes;

  /// Ziel-Wochenwert, auf den der Verlauf steigt: die Zielspitze, bei einem
  /// Zeitziel mit harter Einheit mindestens die Passform-Wochenzeit (höchstens
  /// der Regler). `null` ohne Strecke. Von `generatePlan` und `assessGoal`
  /// gleich benutzt.
  final int? peakMinutes;

  /// Die Zielspitze aus Strecke und längstem Lauf (PAR-205), ohne die harte
  /// Einheit; `null` ohne Strecke.
  final int? targetPeakMinutes;

  /// Wirkung der harten Einheit auf [peakMinutes] (nur Zeitziele).
  final HardFitStatus hardFit;

  /// Wochenzeit der Passform, je Status: [HardFitStatus.atPeak] die kleinste,
  /// bei der alle drei Formen passen (höchstens das Niveau);
  /// [HardFitStatus.raised] die kleinste über dem Niveau (= [peakMinutes]);
  /// [HardFitStatus.partialAtPeak] die kleinste, bei der mindestens eine Form
  /// passt (höchstens das Niveau); [HardFitStatus.regulatorBelowFit] die
  /// kleinste über dem Regler. `null` bei [HardFitStatus.notApplicable] und
  /// [HardFitStatus.neverFits].
  final int? hardFitMinutes;

  /// Geh-Lauf-Abfolge; `null`, wenn die Eingaben keine haben.
  final WalkRunSchedule? walkRun;

  /// Kalenderwochen vor der ersten Laufwoche (PAR-192). Mit Abfolge die
  /// gerechnete Länge, sonst der gespeicherte Wert.
  int get walkRunWeeks => walkRun?.weeks ?? inputs.walkRunWeeks;

  /// Die Zielspitze liegt über dem Regler (PAR-196, PAR-206).
  bool get regulatorTooLow => peakMinutes != null && peakMinutes! > capMinutes;

  /// Der längste Lauf der Zielspitze passt nicht in die maximale Zeit.
  bool get sessionLimitsLongestRun =>
      longestRunMinutes != null && longestRunMinutes! > maxSessionMinutes;

  /// Verlauf der Wochenzeit bis [targetDate] (Standard: das Zieldatum).
  WeeklyTimeResult course({required DateTime today, DateTime? targetDate}) =>
      planWeeklyTime(
        startMinutes: inputs.startWeeklyMinutes,
        capMinutes: capMinutes,
        anchor: inputs.anchor,
        today: today,
        peakMinutes: peakMinutes,
        distance: distance,
        targetDate: targetDate ?? goal.targetDate,
        walkRunWeeks: walkRunWeeks,
        parameters: parameters,
      );
}

/// Rechnet [PlanCourseSetup] aus Ziel und Eingaben.
PlanCourseSetup planCourseSetup(
  TrainingGoal goal,
  PlanInputs inputs, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final cap = (goal.weeklyCapSeconds / 60).floor();
  final distance = goal.type == GoalType.open ? null : goal.distance;
  int? longest, peak;
  if (distance != null) {
    longest = targetLongestRunMinutes(
      distance: distance,
      easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
      easyRunCount: inputs.easyRunCount,
      parameters: parameters,
    );
    peak = peakWeeklyMinutes(
      longestRunMinutes: longest,
      runDays: goal.runDays.length,
      parameters: parameters,
    );
  }
  var hardFit = HardFitStatus.notApplicable;
  int? hardFitMinutes;
  final capped = cap < 1 ? 1 : cap;
  final maxSession = (goal.maxSessionSeconds / 60).floor();
  if (peak != null && goal.type == GoalType.time && goal.hardSessionEnabled) {
    // Passform am tatsächlichen Niveau (Zielspitze, höchstens der Regler),
    // nicht an der kleinsten Passform: sie ist nicht monoton (NB4).
    int? fit(int from, int upTo, {bool anyForm = false}) =>
        hardFitWeeklyMinutes(
          runDays: goal.runDays,
          maxSessionMinutes: maxSession,
          from: from,
          upTo: upTo,
          anyForm: anyForm,
          parameters: parameters,
        );
    final level = peak < capped ? peak : capped;
    if (fit(level, level) != null) {
      hardFitMinutes = fit(1, level);
      hardFit = HardFitStatus.atPeak;
    } else if ((hardFitMinutes = fit(level + 1, capped)) != null) {
      hardFit = HardFitStatus.raised;
    } else if ((hardFitMinutes = fit(1, level, anyForm: true)) != null) {
      hardFit = HardFitStatus.partialAtPeak;
    } else {
      hardFitMinutes = fit(capped + 1, _hardFitSearchLimit);
      hardFit = hardFitMinutes == null
          ? HardFitStatus.neverFits
          : HardFitStatus.regulatorBelowFit;
    }
  }
  final targetPeak = peak;
  if (hardFit == HardFitStatus.raised) peak = hardFitMinutes;
  final start = inputs.walkRunStart;
  return PlanCourseSetup._(
    goal: goal,
    inputs: inputs,
    parameters: parameters,
    capMinutes: capped,
    maxSessionMinutes: maxSession,
    distance: distance,
    longestRunMinutes: longest,
    peakMinutes: peak,
    targetPeakMinutes: targetPeak,
    hardFit: hardFit,
    hardFitMinutes: hardFitMinutes,
    walkRun: start == null
        ? null
        : WalkRunSchedule.forGoal(
            goal,
            start: start,
            anchor: inputs.anchor,
            from: inputs.walkRunFrom,
          ),
  );
}
