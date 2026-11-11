import '../goals/training_goal.dart';
import 'plan_course.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'walk_run_units.dart';
import 'weekly_time.dart';

/// Anpassung des Plans von selbst und auf Antwort des Nutzers (PAR-200 bis
/// PAR-202). Alles rein: kein `DateTime.now()`, kein Speicher. Eine Änderung
/// ist ein neuer Anker mit neuer Startwochenzeit in den [PlanInputs]
/// (inputsVersion 1); wer sie schreibt, ruft danach `recalculatePlan` mit den
/// neuen Eingaben auf. Absolvierte Einheiten bleiben unverändert (sie sind
/// eingefroren, `generatePlan`).

/// Antwort auf „zu leicht, passt oder zu schwer?“ (PAR-200).
enum PlanFeedback { tooEasy, fits, tooHard }

/// Warum die Woche angepasst wurde (PAR-201), für die Erklärung (FR-0179).
enum WeekAdjustmentReason { repeatWeek, noIncrease, fatigue }

DateTime _monday(DateTime d) {
  final day = planDay(d);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// Tag, an dem die nächste Nachfrage fällig ist (PAR-200): [feedbackIntervalDays]
/// nach der letzten Antwort [lastAnswer], sonst nach [created] (Anlage).
DateTime planFeedbackDueOn({
  required DateTime created,
  DateTime? lastAnswer,
  PlanParameters parameters = const PlanParameters(),
}) =>
    planDay(lastAnswer ?? created)
        .add(Duration(days: parameters.feedbackIntervalDays));

/// Ist die Nachfrage am Ortstag [today] fällig? Keine Antwort ändert nichts;
/// die Nachfrage bleibt dann fällig.
bool planFeedbackDue({
  required DateTime created,
  DateTime? lastAnswer,
  required DateTime today,
  PlanParameters parameters = const PlanParameters(),
}) => !planDay(today).isBefore(
  planFeedbackDueOn(
    created: created,
    lastAnswer: lastAnswer,
    parameters: parameters,
  ),
);

/// Ergebnis von [applyPlanFeedback].
class PlanFeedbackResult {
  const PlanFeedbackResult({this.inputs, this.raiseGoalSignal = false});

  /// Neue Eingaben (neuer Anker ab der nächsten Woche); `null`: keine
  /// Änderung.
  final PlanInputs? inputs;

  /// „zu leicht“ am Regler: Die Wochenzeit kann nicht steigen. Die App fragt,
  /// ob das Ziel (der Regler) steigen soll; geändert wird nichts.
  final bool raiseGoalSignal;
}

/// Wirkung der Antwort [answer] (PAR-200) ab der nächsten Woche: „zu leicht“
/// +10 %, höchstens bis zum Regler (am Regler nur [PlanFeedbackResult
/// .raiseGoalSignal]); „zu schwer“ −10 %; „passt“ ändert nichts. Danach gilt
/// wieder PAR-193 vom neuen Wert aus; die Zählung nach PAR-194 läuft weiter.
/// In der Geh-Lauf-Abfolge und in der Reduktion vor dem Termin (PAR-199)
/// ändert sich nichts.
PlanFeedbackResult applyPlanFeedback({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required PlanFeedback answer,
  required DateTime today,
  PlanParameters parameters = const PlanParameters(),
}) {
  if (answer == PlanFeedback.fits) return const PlanFeedbackResult();
  final setup = planCourseSetup(goal, inputs, parameters: parameters);
  final next = _weekAt(setup, _monday(today).add(const Duration(days: 7)));
  if (next == null || !_adjustable(next)) return const PlanFeedbackResult();
  final cap = setup.capMinutes;
  final base = next.baseMinutes!;
  final p = parameters;
  if (answer == PlanFeedback.tooEasy) {
    if (base >= cap) return const PlanFeedbackResult(raiseGoalSignal: true);
    final raised = (base * (1 + p.feedbackStep)).round();
    final target = raised > cap ? cap : raised;
    if (target <= base) return const PlanFeedbackResult();
    return PlanFeedbackResult(inputs: _reanchor(inputs, setup, next, target));
  }
  final lowered = (base * (1 - p.feedbackStep)).round();
  final target = lowered < 1 ? 1 : lowered;
  if (target >= base) return const PlanFeedbackResult();
  return PlanFeedbackResult(inputs: _reanchor(inputs, setup, next, target));
}

/// Ergebnis von [evaluateWeekAdjustment].
class WeekAdjustment {
  const WeekAdjustment({
    required this.inputs,
    required this.share,
    required this.reasons,
  });

  /// Neue Eingaben mit neuem Anker (die Woche nach der bewerteten Woche).
  final PlanInputs inputs;

  /// Erreichter Anteil der bewerteten Woche, 0 bis 1.
  final double share;
  final Set<WeekAdjustmentReason> reasons;
}

/// Wochenprüfung (PAR-201, FR-0158) am Ortstag [today] für die letzte
/// abgeschlossene Woche (die Woche vor der von [today]): von selbst nur nach
/// unten.
///
/// - [doneMinutes]: Minuten der der Woche zugeordneten und freien Läufe
///   (Zusatzläufe über den Plan hinaus erhöhen nichts: der Anteil ist höchstens 1).
/// - [plannedMinutes]: geplante Minuten der Woche; `null`: Wochenzeit des
///   Verlaufs.
/// - [recentEasyRpe]: RPE der letzten lockeren Läufe (die letzten
///   [PlanParameters.fatigueWindowRuns] zählen), `null` für Läufe ohne Angabe.
/// - [fatigueReported]: gemeldete Ermüdung (PAR-188).
///
/// Weniger als die Hälfte geschafft: Die nächste Woche hat dieselbe Wochenzeit
/// wie die abgeschlossene (PAR-194 zählt weiter). Hälfte bis unter 80 %: keine
/// Steigerung. Ermüdung: −10 % und keine harte Einheit in der nächsten Woche.
/// Ausgefallenes wird nicht nachgeholt. `null`: nichts zu ändern, nichts zu
/// bewerten (Geh-Lauf-Abfolge: dort gilt nur PAR-140, [suggestWalkRunRepeat]).
/// Die Woche muss ab dem Anker liegen und nicht schon bewertet sein.
WeekAdjustment? evaluateWeekAdjustment({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  required double doneMinutes,
  int? plannedMinutes,
  List<int?> recentEasyRpe = const [],
  bool fatigueReported = false,
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final thisMonday = _monday(today);
  final lastMonday = thisMonday.subtract(const Duration(days: 7));
  if (lastMonday.isBefore(inputs.anchor)) return null;
  final setup = planCourseSetup(goal, inputs, parameters: p);
  final done = _weekAt(setup, lastMonday);
  final next = _weekAt(setup, thisMonday);
  if (done == null || next == null) return null;
  if (!_adjustable(done) || !_adjustable(next)) return null;
  final planned = plannedMinutes ?? done.minutes!;
  if (planned < 1 || doneMinutes.isNaN || doneMinutes < 0) return null;
  final share = doneMinutes >= planned ? 1.0 : doneMinutes / planned;

  final window = recentEasyRpe.length > p.fatigueWindowRuns
      ? recentEasyRpe.sublist(recentEasyRpe.length - p.fatigueWindowRuns)
      : recentEasyRpe;
  final tired =
      fatigueReported ||
      window.where((r) => r != null && r >= p.fatigueRpe).length >=
          p.fatigueRuns;

  final reasons = <WeekAdjustmentReason>{};
  // Wunsch-Wochenzeit der nächsten Woche (geplant, nach Verringerung der
  // leichteren Woche); der niedrigste Wert gewinnt, nie ein höherer als der
  // bisherige Plan.
  var target = next.minutes!;
  final nextLighter = next.kind == WeekKind.lighter;
  int baseFor(int minutes) =>
      nextLighter ? (minutes / (1 - p.lighterWeekReduction)).round() : minutes;
  if (share < p.repeatBelowShare) {
    // Gleiche Wochenzeit wie die abgeschlossene Woche.
    if (done.minutes! < target) {
      target = done.minutes!;
      reasons.add(WeekAdjustmentReason.repeatWeek);
    }
  } else if (share < p.holdBelowShare) {
    // Keine Steigerung: Grundwert der abgeschlossenen Woche.
    final held = nextLighter
        ? (done.baseMinutes! * (1 - p.lighterWeekReduction)).round()
        : done.baseMinutes!;
    if (held < target) {
      target = held;
      reasons.add(WeekAdjustmentReason.noIncrease);
    }
  }
  var noHard = false;
  if (tired) {
    final lowered = (next.minutes! * (1 - p.fatigueReduction)).round();
    final t = lowered < 1 ? 1 : lowered;
    if (t < target) target = t;
    noHard = true;
    reasons.add(WeekAdjustmentReason.fatigue);
  }
  if (reasons.isEmpty) return null;
  if (target < 1) target = 1;
  final base = baseFor(target);
  final changed = target < next.minutes! || noHard;
  if (!changed) return null;
  var out = _reanchor(
    inputs,
    setup,
    next,
    base,
    noHardUntil: noHard
        ? thisMonday.add(const Duration(days: 6))
        : inputs.noHardUntil,
  );
  out = out.copyWith(lastWeekMinutes: done.minutes!, achievedShare: share);
  return WeekAdjustment(inputs: out, share: share, reasons: reasons);
}

/// Stufe des Neustarts nach einer Pause (PAR-202).
enum PauseRestartKind { none, short, long, newStart }

/// Ergebnis von [planPauseRestart].
class PauseRestart {
  const PauseRestart(this.kind, [this.inputs]);

  final PauseRestartKind kind;

  /// Neue Eingaben; `null` bei [PauseRestartKind.none].
  final PlanInputs? inputs;
}

/// Neustart nach einer Pause (PAR-202, FR-0164, FR-0167), wenn die Pause
/// feststeht (der Nutzer erfasst alles oder hat sie bestätigt; das prüft der
/// Aufrufer). Jedes erfasste Training zählt: [lastTrainingDay] ist der
/// Tag des letzten erfassten Trainings, [ranWeekMinutes] die Minuten der
/// gelaufenen Woche (Kalenderwoche des letzten Trainings), nicht der
/// geplanten.
///
/// 7 bis 13 Tage: 80 % von [ranWeekMinutes] ab dieser Woche, keine harte
/// Einheit in dieser Woche. 14 bis 55 Tage: 50 %, 2 Wochen ohne harte
/// Einheit. Ab 56 Tagen: neuer Start nach PAR-192 ([PlanInputs.forNewGoal],
/// mit Tempo und Intensitätsgrundlage der alten Eingaben). Nie höher als der
/// bisherige Plan dieser Woche und nie über dem Regler; die Zählung nach
/// PAR-194 beginnt neu. In der Geh-Lauf-Abfolge, in der Reduktion und wenn
/// der Neustart in dieser Woche schon gilt: [PauseRestartKind.none].
PauseRestart planPauseRestart({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  required DateTime lastTrainingDay,
  required double ranWeekMinutes,
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final t = planDay(today);
  final gap = t.difference(planDay(lastTrainingDay)).inDays;
  if (gap < p.pauseMinDays) return const PauseRestart(PauseRestartKind.none);
  final monday = _monday(t);
  if (!inputs.anchor.isBefore(monday)) {
    return const PauseRestart(PauseRestartKind.none);
  }
  if (gap >= p.pauseNewStartDays) {
    final fresh = PlanInputs.forNewGoal(goal, t, parameters: p);
    return PauseRestart(
      PauseRestartKind.newStart,
      PlanInputs(
        anchor: fresh.anchor,
        startWeeklyMinutes: fresh.startWeeklyMinutes,
        today: t,
        walkRunWeeks: fresh.walkRunWeeks,
        walkRunStart: fresh.walkRunStart,
        walkRunFrom: fresh.walkRunFrom,
        easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
        easyRunCount: inputs.easyRunCount,
        intensity: inputs.intensity,
      ),
    );
  }
  final setup = planCourseSetup(goal, inputs, parameters: p);
  final week = _weekAt(setup, monday);
  if (week == null || !_adjustable(week)) {
    return const PauseRestart(PauseRestartKind.none);
  }
  final long = gap >= p.pauseLongDays;
  final share = long ? p.pauseLongShare : p.pauseShortShare;
  final noHardWeeks = long ? p.pauseLongNoHardWeeks : p.pauseShortNoHardWeeks;
  var target = (ranWeekMinutes * share).round();
  if (target > week.minutes!) target = week.minutes!;
  if (target > setup.capMinutes) target = setup.capMinutes;
  if (target < 1) target = 1;
  final out = PlanInputs(
    anchor: monday,
    startWeeklyMinutes: target,
    today: t,
    walkRunWeeks: 0,
    easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
    easyRunCount: inputs.easyRunCount,
    intensity: inputs.intensity,
    weekCountOffset: 0,
    noHardUntil: monday.add(Duration(days: 7 * noHardWeeks - 1)),
  );
  return PauseRestart(
    long ? PauseRestartKind.long : PauseRestartKind.short,
    out,
  );
}

bool _adjustable(PlanWeek w) =>
    w.minutes != null &&
    (w.kind == WeekKind.climbing ||
        w.kind == WeekKind.holding ||
        w.kind == WeekKind.lighter);

PlanWeek? _weekAt(PlanCourseSetup setup, DateTime monday) {
  for (final w in setup.course(today: monday).weeks) {
    if (w.start == monday) return w;
  }
  return null;
}

/// Neuer Anker an [week] mit Grundwert [startBase] (Wochenzeit vor der
/// Verringerung einer leichteren Woche), begrenzt auf 1 bis Regler. Die
/// Zählung nach PAR-194 läuft weiter.
PlanInputs _reanchor(
  PlanInputs inputs,
  PlanCourseSetup setup,
  PlanWeek week,
  int startBase, {
  DateTime? noHardUntil,
}) {
  final first = setup.walkRunWeeks;
  final offset = inputs.weekCountOffset + (week.index - first);
  final cap = setup.capMinutes;
  final start = startBase < 1 ? 1 : (startBase > cap ? cap : startBase);
  return PlanInputs(
    anchor: week.start,
    startWeeklyMinutes: start,
    today: inputs.today,
    walkRunWeeks: 0,
    easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
    easyRunCount: inputs.easyRunCount,
    intensity: inputs.intensity,
    weekCountOffset: offset < 0 ? 0 : offset,
    noHardUntil: noHardUntil ?? inputs.noHardUntil,
  );
}

/// Wendet einen angenommenen Vorschlag nach PAR-140 an: die Abfolge beginnt
/// ab dem Montag [from] wieder an der Stelle von [suggestion] (neuer Anker).
/// PAR-194 zählt erst nach der Abfolge, die Wochenzeit danach bleibt wie in
/// den Eingaben.
PlanInputs applyWalkRunRepeat(
  PlanInputs inputs,
  WalkRunRepeatSuggestion suggestion, {
  required DateTime from,
}) {
  final monday = _monday(from);
  return PlanInputs(
    anchor: monday,
    startWeeklyMinutes: inputs.startWeeklyMinutes,
    today: inputs.today,
    walkRunWeeks: inputs.walkRunWeeks,
    walkRunStart: suggestion.position,
    walkRunFrom: monday,
    easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
    easyRunCount: inputs.easyRunCount,
    intensity: inputs.intensity,
    weekCountOffset: inputs.weekCountOffset,
    noHardUntil: inputs.noHardUntil,
  );
}
