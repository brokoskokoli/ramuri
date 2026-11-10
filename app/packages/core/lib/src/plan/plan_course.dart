import '../goals/training_goal.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'walk_run_schedule.dart';
import 'weekly_time.dart';

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

  /// Längster Lauf der Zielspitze und die Zielspitze als Wochenzeit
  /// (PAR-205); `null` ohne Strecke.
  final int? longestRunMinutes;
  final int? peakMinutes;

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
  final start = inputs.walkRunStart;
  return PlanCourseSetup._(
    goal: goal,
    inputs: inputs,
    parameters: parameters,
    capMinutes: cap < 1 ? 1 : cap,
    maxSessionMinutes: (goal.maxSessionSeconds / 60).floor(),
    distance: distance,
    longestRunMinutes: longest,
    peakMinutes: peak,
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
