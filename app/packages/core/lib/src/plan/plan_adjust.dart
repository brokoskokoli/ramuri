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
/// die Nachfrage bleibt dann fällig. Solange die Pausenfrage offen ist
/// ([pauseOpen], PAR-202), wird sie nicht angeboten: Ihre Antwort setzt den
/// Anker in die nächste Woche, und der Neustart der Pausenregel entfiele.
bool planFeedbackDue({
  required DateTime created,
  DateTime? lastAnswer,
  required DateTime today,
  bool pauseOpen = false,
  PlanParameters parameters = const PlanParameters(),
}) =>
    !pauseOpen &&
    !planDay(today).isBefore(
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

/// Montag der Basiswoche für [planPauseRestart] (PAR-202): die letzte
/// vollständige Kalenderwoche (Montag bis Sonntag) vor Beginn der Pause, also
/// vor dem Tag nach dem letzten erfassten Training [lastTrainingDay]. War das
/// Training ein Sonntag, ist es die Woche dieses Sonntags, sonst die Woche
/// davor (die angebrochene Woche zählt nicht).
DateTime pauseBaseWeek(DateTime lastTrainingDay) =>
    _monday(planDay(lastTrainingDay).add(const Duration(days: 1)))
        .subtract(const Duration(days: 7));

/// Neustart nach einer Pause (PAR-202, FR-0164, FR-0167), wenn die Pause
/// feststeht (der Nutzer erfasst alles oder hat sie bestätigt; das prüft der
/// Aufrufer). Jedes erfasste Training zählt: [lastTrainingDay] ist der
/// Tag des letzten erfassten Trainings, [baseWeekMinutes] die gelaufenen
/// Minuten der Basiswoche ([pauseBaseWeek]: letzte vollständige
/// Kalenderwoche vor Pausenbeginn, nicht die angebrochene), nicht die
/// geplanten; unter 1 Minute (keine vollständige Woche vor der Pause) gilt
/// der bisherige Plan dieser Woche als Basis.
///
/// 7 bis 13 Tage: 80 % von [baseWeekMinutes] ab dieser Woche, keine harte
/// Einheit in dieser Woche. 14 bis 55 Tage: 50 %, 2 Wochen ohne harte
/// Einheit. Ab 56 Tagen: neuer Start nach PAR-192 ([PlanInputs.forNewGoal],
/// mit Tempo und Intensitätsgrundlage der alten Eingaben). Mit [provisional]
/// gilt ab 56 Tagen vorläufig die Stufe 14 bis 55 Tage (sichere Vorgabe bis
/// der Nutzer den Einstieg wählt, PAR-181), Art [PauseRestartKind.long].
/// Mit [replacesProvisional] ersetzt der neue Start (gewählter Einstieg) eine
/// solche vorläufige Fassung: ohne Prüfung der laufenden Woche und ohne die
/// Kappung auf die Minuten der vorläufigen Woche. Alle Stufen: nie
/// höher als der bisherige Plan dieser Woche und nie über dem Regler; die
/// Zählung nach PAR-194 beginnt neu. In der Geh-Lauf-Abfolge, in der
/// Reduktion vor dem Termin: [PauseRestartKind.none]. Ein Anker in dieser
/// oder einer späteren Woche (aus Rückmeldung oder Wochenbewertung) hindert
/// den Neustart nicht: Er ersetzt diese Anpassung (Anker dieser Montag). Den
/// zweiten Neustart derselben Pause verhindert der Aufrufer mit seinem Merker.
PauseRestart planPauseRestart({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  required DateTime lastTrainingDay,
  required double baseWeekMinutes,
  PlanParameters parameters = const PlanParameters(),
  bool provisional = false,
  bool replacesProvisional = false,
}) {
  final p = parameters;
  final t = planDay(today);
  final gap = t.difference(planDay(lastTrainingDay)).inDays;
  if (gap < p.pauseMinDays) return const PauseRestart(PauseRestartKind.none);
  final restartsFresh = gap >= p.pauseNewStartDays && !provisional;
  if (restartsFresh && replacesProvisional) {
    return PauseRestart(
      PauseRestartKind.newStart,
      _freshStart(goal, inputs, t, p, cap: null),
    );
  }
  final monday = _monday(t);
  // Die Pause hat Vorrang (PAR-202): Der Neustart gilt auch, wenn eine
  // Rückmeldung oder Wochenbewertung den Anker auf diese oder eine spätere
  // Woche gelegt hat; er ersetzt deren Anpassung (Anker = dieser Montag).
  // Vor einem zweiten Neustart derselben Pause schützt der Merker des Aufrufers
  // ([planPauseRestartKey]). Bei einem Anker in einer späteren Woche liefert
  // die Zählung ab diesem Montag die Minuten der Woche, die den Neustart deckeln.
  final from = inputs.anchor.isAfter(monday)
      ? inputs.copyWith(anchor: monday)
      : inputs;
  final setup = planCourseSetup(goal, from, parameters: p);
  final week = _weekAt(setup, monday);
  if (week == null || !_adjustable(week)) {
    return const PauseRestart(PauseRestartKind.none);
  }
  if (restartsFresh) {
    return PauseRestart(
      PauseRestartKind.newStart,
      _freshStart(goal, inputs, t, p, cap: week.minutes!),
    );
  }
  final long = gap >= p.pauseLongDays;
  final share = long ? p.pauseLongShare : p.pauseShortShare;
  final noHardWeeks = long ? p.pauseLongNoHardWeeks : p.pauseShortNoHardWeeks;
  // Ohne Basis (keine vollständige Woche vor der Pause erfasst, z. B. das
  // erste Training erst in der Woche davor): der bisherige Plan dieser Woche.
  final base = baseWeekMinutes >= 1 ? baseWeekMinutes : week.minutes!;
  var target = (base * share).round();
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

/// Eingaben des neuen Starts nach PAR-192 mit Tempo und Intensitätsgrundlage
/// der alten [inputs]; [cap]: höchstens die Minuten des bisherigen Plans.
PlanInputs _freshStart(
  TrainingGoal goal,
  PlanInputs inputs,
  DateTime t,
  PlanParameters p, {
  required int? cap,
}) {
  final fresh = PlanInputs.forNewGoal(goal, t, parameters: p);
  var start = fresh.startWeeklyMinutes;
  if (cap != null && start > cap) start = cap;
  if (start < 1) start = 1;
  return PlanInputs(
    anchor: fresh.anchor,
    startWeeklyMinutes: start,
    today: t,
    walkRunWeeks: fresh.walkRunWeeks,
    walkRunStart: fresh.walkRunStart,
    walkRunFrom: fresh.walkRunFrom,
    easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
    easyRunCount: inputs.easyRunCount,
    intensity: inputs.intensity,
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

/// Erster Tag, an dem nach Annahme von „Wiederholen“ (PAR-140) die Abfolge
/// geplant wird: heute, nach einem Lauf von heute ([lastDay]) erst morgen.
DateTime walkRunRepeatFrom(DateTime today, DateTime lastDay) {
  final t = planDay(today);
  final next = planDay(lastDay).add(const Duration(days: 1));
  return next.isAfter(t) ? next : t;
}

/// Wendet einen angenommenen Vorschlag nach PAR-140 an: die Abfolge beginnt
/// ab dem Tag [from] (dem ersten Tag, an dem noch geplant wird) wieder an der
/// Stelle von [suggestion]. Der Anker ist der Montag dieser Woche, Lauftage
/// davor gehören nicht mehr zur Abfolge.
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
    walkRunFrom: from,
    easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
    easyRunCount: inputs.easyRunCount,
    intensity: inputs.intensity,
    weekCountOffset: inputs.weekCountOffset,
    noHardUntil: inputs.noHardUntil,
  );
}
