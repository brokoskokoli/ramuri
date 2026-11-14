import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'plan_data_reader.dart';

enum PlanLoadPhase { loading, ready, failed }

/// Einstellungsschlüssel: Ortstag (`JJJJ-MM-TT`) der letzten Antwort auf die
/// Nachfrage nach PAR-200. Fehlt er, zählt die Anlage des Plans.
const String planFeedbackKey = 'plan.feedback_answered_on';

/// Einstellungsschlüssel: letzter Tag (`JJJJ-MM-TT`) der Programmwoche, deren
/// Vorschlag „Woche wiederholen“ der Nutzer abgelehnt hat (PAR-140).
const String planWalkRunRepeatDeclinedKey = 'plan.walk_run_repeat_declined';

/// Ergebnis von [PlanController.answerFeedback].
class PlanFeedbackOutcome {
  const PlanFeedbackOutcome(this.result, {this.raiseGoalSignal = false});

  final PlanActionResult result;

  /// „Zu leicht“ am Regler: Die App fragt, ob das Ziel steigen soll; der Plan
  /// ist unverändert.
  final bool raiseGoalSignal;
}

String _dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDay(String? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v ?? '');
  if (m == null) return null;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return _dayText(d) == v ? d : null;
}

/// Ergebnis einer Aktion des [PlanController]. Der Inhalt eines Fehlers wird
/// nie gezeigt (Gesundheitsdaten).
enum PlanActionResult {
  /// Ausgeführt.
  done,

  /// Vom Speicher abgelehnt (ungültiges Ziel, Termin vor heute, belegter Tag,
  /// Einheit mit Lauf, …); nichts geändert.
  rejected,

  /// Einheit, Lauf oder Ziel fehlt.
  notFound,

  /// Speicher nicht erreichbar oder Rechnung gescheitert.
  failed,

  /// Nur [PlanController.saveGoal]: das Ziel ist gespeichert, die
  /// Neuberechnung des Plans scheiterte. Der Plan gehört noch zum alten Ziel;
  /// die nächste Neuberechnung (erneutes Speichern, Öffnen, auch nach einem
  /// Neustart, [PlanController.recalculate], [PlanController.assignRun]) holt
  /// die Zieländerung nach: Das Ziel weicht vom Fingerabdruck der neuesten
  /// Fassung ab ([planGoalChangedSince]).
  savedNotPlanned,
}

/// Das Ziel ist gespeichert, die Neuberechnung danach scheiterte.
class _SavedNotPlanned implements Exception {
  const _SavedNotPlanned();
}

/// Prüfung eines Ziels vor dem Speichern ([PlanController.checkGoal]).
class GoalDraftCheck {
  const GoalDraftCheck({required this.assessment, required this.walkRun});

  /// Einschätzung nach PAR-206; [GoalAssessment.fitsFrom] ist das Angebot
  /// eines Datums.
  final GoalAssessment assessment;

  /// Der Plan beginnt mit der Geh-Lauf-Abfolge (PAR-065); vor dem Speichern
  /// steht der Hinweis aus PAR-115.
  final bool walkRun;
}

/// Stand der Plan-Seite (WP22). Nur Daten, keine Texte.
class PlanViewState {
  const PlanViewState.loading()
    : phase = PlanLoadPhase.loading,
      goal = null,
      version = null,
      hints = null,
      lastChange = null,
      weekUnits = const [],
      assessment = null,
      warning = null,
      warningReminderDue = false,
      feedbackDue = false,
      changeNotice = null,
      walkRunProposal = null;

  const PlanViewState.failed()
    : phase = PlanLoadPhase.failed,
      goal = null,
      version = null,
      hints = null,
      lastChange = null,
      weekUnits = const [],
      assessment = null,
      warning = null,
      warningReminderDue = false,
      feedbackDue = false,
      changeNotice = null,
      walkRunProposal = null;

  const PlanViewState.ready({
    required this.goal,
    required this.version,
    required this.hints,
    required this.lastChange,
    required this.weekUnits,
    this.assessment,
    this.warning,
    this.warningReminderDue = false,
    this.feedbackDue = false,
    this.changeNotice,
    this.walkRunProposal,
  }) : phase = PlanLoadPhase.ready;

  final PlanLoadPhase phase;

  /// Das gespeicherte Ziel oder `null` (leerer Zustand).
  final TrainingGoal? goal;

  /// Die neueste Fassung oder `null` ohne Plan.
  final PlanVersionRecord? version;

  /// Hinweise zum Plan: [GeneratedPlan.pinnedConflicts],
  /// [GeneratedPlan.droppedDaysByWeek], [GeneratedPlan.hardOmissions],
  /// [GeneratedPlan.hardFit] (inkl. `partialAtPeak`),
  /// [GeneratedPlan.walkRunStaysAtWeek], [GeneratedPlan.walkRunNoWeekFits],
  /// [GeneratedPlan.weeks]. Nach einer Neuberechnung in dieser Sitzung deren
  /// Ergebnis, sonst die an der neuesten Fassung gespeicherten
  /// ([planHintsFromSummary]); nur für Fassungen ohne gespeicherte Hinweise
  /// eine Vorschau ([previewPlan]). Abstandskonflikte kommen immer aus den
  /// gespeicherten Einheiten ([planSpacingConflicts]), damit eine bestätigte
  /// Verschiebung sofort sichtbar ist. `null` ohne Plan.
  final GeneratedPlan? hints;

  /// Alt-Neu-Bild der letzten Neuberechnung dieser Sitzung (PAR-204), sonst
  /// `null`. Die gespeicherte Fassung trägt es in [PlanVersionRecord.summary].
  final PlanChangeSummary? lastChange;

  /// Einheiten der Kalenderwoche (Montag bis Sonntag) von heute.
  final List<PlanUnit> weekUnits;

  /// Einschätzung des Ziels nach PAR-206 ([assessGoal]) mit den Eingaben der
  /// neuesten Fassung und heute; nie gespeichert. `null` ohne Plan oder wenn
  /// sie sich nicht rechnen ließ (die Seite lässt die Zeile dann weg).
  final GoalAssessment? assessment;

  /// Das aktive Warnsignal (FR-0203) oder `null`. Solange es besteht, zeigt
  /// der Plan nur Ruhetage; gehaltene festgelegte Ruhetage sind dann keine
  /// Festlegung des Nutzers.
  final WarningSignal? warning;

  /// Die Meldung besteht seit mindestens 7 Tagen (nur Karte, keine
  /// Benachrichtigung).
  final bool warningReminderDue;

  /// Die Nachfrage nach PAR-200 ist fällig (2 Wochen ab der letzten Antwort
  /// bzw. Anlage des Plans); ohne Warnsignal.
  final bool feedbackDue;

  /// Größere Änderung, die der Nutzer noch nicht gesehen hat (PAR-204,
  /// FR-0170): Karte „Plan angepasst“ bis [PlanController.markChangeSeen].
  final PlanChangeNotice? changeNotice;

  /// Vorschlag „Woche wiederholen“ in der Geh-Lauf-Phase (PAR-140); die App
  /// fragt, der Nutzer entscheidet. Nicht unter Warnsignal.
  final WalkRunWeekProposal? walkRunProposal;

  bool get hasPlan => version != null;

  /// Die neueste Fassung stammt aus einer älteren Regelversion (ADR-0010
  /// Punkt 7); die nächste wöchentliche Prüfung rechnet mit `ruleVersion`.
  bool get ruleVersionPending => version != null && !version!.version.isCurrent;
}

/// Liest und ändert Ziel und Plan (WP22 Punkt 7). Gerechnet wird in `core`
/// ([buildPlanInputs], [recalculatePlan], [previewPlan]); „heute“ ist der
/// Ortstag der [clock] und geht an jeden Schreiber.
///
/// Alle Aktionen und Neuberechnungen laufen nacheinander (eine Warteschlange):
/// Eine Zuordnung oder Terminbestätigung schiebt sich nie zwischen Lesen und
/// Schreiben einer Neuberechnung. Termine ändern sich nur über
/// [confirmMove] (Bestätigung des Nutzers); automatische Neuberechnungen
/// halten die Tage (ADR-0010 Punkt 8, in [recalculatePlan]).
class PlanController extends ChangeNotifier {
  PlanController({
    required this.session,
    required this.clock,
    PlanDataReader? reader,
    this.parameters = const PlanParameters(),
    this.onChanged,
  }) : reader =
           reader ??
           PlanDataReader(
             session: session,
             clock: clock,
             parameters: parameters,
           );

  final StorageSession session;
  final Clock clock;
  final PlanDataReader reader;
  final PlanParameters parameters;

  /// Nach jeder Änderung der gespeicherten Daten (Ziel, Plan, Zuordnung).
  final VoidCallback? onChanged;

  GoalStore get _goals => (session as GoalStorage).goals;
  PlanRepository get _plans => (session as PlanStorage).plans;
  WarningStore? get _warning =>
      session is WarningStorage ? (session as WarningStorage).warning : null;

  PlanViewState _state = const PlanViewState.loading();
  PlanViewState get state => _state;

  GeneratedPlan? _fresh;
  PlanChangeSummary? _lastChange;

  Future<void> _tail = Future.value();
  bool _disposed = false;

  DateTime _today() => calendarDay(clock.now());

  /// Führt [action] nach allen vorher angestoßenen aus.
  Future<T> _serial<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await action());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  /// Öffnen der Plan-Seite: wöchentliche Prüfung (FR-0158), falls fällig,
  /// dann laden. Fällig ist sie, wenn `plan.last_check_day` fehlt oder in
  /// einer früheren Kalenderwoche (ab Montag) liegt. Stammt die neueste
  /// Fassung aus einer älteren Regelversion (`!version.isCurrent`), ist der
  /// Auslöser `ruleVersion`, sonst `weekly`; außerhalb der fälligen Prüfung
  /// rechnet das Öffnen nicht (ADR-0010 Punkt 7: keine stille Neuberechnung
  /// beim Start). Ein Ziel ohne Fassung bekommt seine erste (`create`).
  /// Weicht das Ziel von dem der neuesten Fassung ab (Neuberechnung nach dem
  /// Speichern gescheitert, [PlanActionResult.savedNotPlanned]), rechnet das
  /// Öffnen sofort mit `goalChange`.
  Future<void> open() => _serial(() async {
    _fresh = null;
    try {
      // Pause hat Vorrang (PAR-202): ihre Fassung gilt für diese Woche und
      // setzt den Prüftag, die Wochenprüfung schreibt danach keine zweite.
      await _checkPauseRestart();
      await _checkDue();
    } on Object {
      // Die Prüfung holt der nächste Start nach; die Seite zeigt den
      // gespeicherten Plan.
    }
    await _load();
  });

  /// Lädt den Stand neu (ohne Prüfung).
  Future<void> reload() => _serial(_load);

  Future<void> _checkDue() async {
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    if (history.isEmpty) {
      await _recalculate(PlanTrigger.create, goal, null);
      return;
    }
    final last = history.last;
    if (planGoalChangedSince(last.summary, goal)) {
      await _recalculate(PlanTrigger.goalChange, goal, last);
      return;
    }
    // Warnsignal-Zeile und letzte Fassung müssen zueinander passen: Scheiterte
    // das Schreiben nach dem Setzen oder Aufheben der Zeile (und auch deren
    // Rücknahme), stellt das Öffnen den Plan her, ohne die Wochenprüfung
    // abzuwarten.
    final warning = _warning;
    if (warning != null) {
      final warned = await warning.read() != null;
      final held = warningHeldFromSummary(last.summary) != null;
      if (warned != held) {
        await _recalculate(
          PlanTrigger.feedback,
          goal,
          last,
          reason: warned ? planReasonWarning : planReasonWarningLifted,
          // Die Heilung ist keine Wochenprüfung: der Prüftag bleibt, damit
          // eine fällige Bewertung der Vorwoche beim nächsten Öffnen läuft.
          markChecked: false,
        );
        return;
      }
    }
    final today = _today();
    final checked = await session.settings.get(planLastCheckDayKey);
    if (!weeklyCheckDue(checked, today)) return;
    // Solange die Pausenfrage offen ist (PAR-202), rechnet das Öffnen keine
    // Wochenprüfung: Nach der Antwort greift erst die Pausenregel, die
    // Prüfung gilt dann für die Woche (Prüftag) oder läuft beim nächsten
    // Öffnen normal. Die Wochenfassung würde sonst den Anker auf den Montag
    // setzen und die Pausenregel ins Leere laufen lassen.
    if (await HintService(session: session, clock: clock).pauseQuestion() !=
        null) {
      return;
    }
    // Auch unter einer älteren Regelversion bewertet die Prüfung die Woche
    // (PAR-201, NB6 1).
    await _recalculate(
      last.version.isCurrent ? PlanTrigger.weekly : PlanTrigger.ruleVersion,
      goal,
      last,
      adjust: true,
    );
  }

  /// Rechnet mit Eingaben aus dem Speicher. Anlegen: neue Eingaben aus
  /// [buildPlanInputs]; sonst die der letzten Fassung mit den heute
  /// gemessenen Werten ([refreshMeasuredInputs]).
  ///
  /// [adjust]: die wöchentliche Prüfung bewertet zuerst die letzte Woche
  /// (PAR-201, [evaluateWeekAdjustment]); ergibt sie eine Anpassung, gilt ihr
  /// neuer Anker, der Grund-Code der Fassung nennt die Gründe. Einmal je
  /// Woche (die Prüfung merkt sich den Tag), und die bewertete Woche liegt
  /// danach vor dem Anker.
  Future<void> _recalculate(
    PlanTrigger trigger,
    TrainingGoal goal,
    PlanVersionRecord? last, {
    bool? adjust,
    String? reason,
    bool markChecked = true,
  }) async {
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    var inputs = _inputsFor(trigger, built, last);
    // Eine Zieländerung setzt den Prüftag; eine fällige Wochenbewertung der
    // Vorwoche fällt dadurch nicht weg (NB7 6), sie geht in dieselbe Fassung
    // ein (Grund bleibt `goalChange`).
    // Bei offener Pausenfrage (PAR-202) nicht: Die Bewertung setzte den
    // Anker auf den Montag und die Pausenregel liefe danach ins Leere (NB8 1).
    // Dann bleibt auch der Prüftag unberührt: Nach „Nein“ läuft die
    // Wochenprüfung beim nächsten Öffnen (NB9 1).
    final dueOnGoalChange =
        adjust == null &&
        trigger == PlanTrigger.goalChange &&
        weeklyCheckDue(await session.settings.get(planLastCheckDayKey), today);
    final skippedForPause =
        dueOnGoalChange &&
        await HintService(session: session, clock: clock).pauseQuestion() !=
            null;
    final doAdjust = adjust ?? (dueOnGoalChange && !skippedForPause);
    if (doAdjust && last != null) {
      final evidence = await reader.weekEvidence(today);
      final a = evaluateWeekAdjustment(
        goal: goal,
        inputs: inputs,
        today: today,
        doneMinutes: evidence.doneMinutes,
        plannedMinutes: evidence.plannedMinutes,
        recentEasyRpe: evidence.recentEasyRpe,
        fatigueReported: evidence.fatigueReported,
        parameters: parameters,
      );
      if (a != null) {
        inputs = refreshMeasuredInputs(a.inputs, built.inputs);
        // Bei `goalChange` bleibt der Grund-Code vorn, die Gründe der
        // Bewertung folgen (NB8 6): `goalChange,repeatWeek`.
        final codes = ([
          ...a.reasons,
        ]..sort((x, y) => x.index - y.index)).map((r) => r.name).join(',');
        if (trigger == PlanTrigger.weekly) {
          reason = codes;
        } else if (trigger == PlanTrigger.goalChange) {
          reason = 'goalChange,$codes';
        } else if (trigger == PlanTrigger.ruleVersion) {
          reason = 'ruleVersion,$codes';
        }
      }
    }
    final r = await recalculatePlan(
      plans: _plans,
      settings: session.settings,
      trigger: trigger,
      today: today,
      now: clock.now(),
      reason: reason,
      inputs: inputs,
      parameters: parameters,
      warning: _warning,
      // `manual` bewertet die Woche nicht (ADR-0010 Nachtrag WP24, K63): Der
      // Prüftag bleibt, sonst fiele die fällige Wochenbewertung weg.
      markChecked:
          markChecked && !skippedForPause && trigger != PlanTrigger.manual,
    );
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
  }

  /// Eingaben der Rechnung für [trigger]: beim Anlegen (oder ohne Fassung)
  /// die frischen aus [buildPlanInputs], sonst die der letzten Fassung mit den
  /// heute gemessenen Werten ([refreshMeasuredInputs]). Gemeinsam für das
  /// Speichern ([_recalculate]) und die Einschätzung davor ([checkGoal]).
  static PlanInputs _inputsFor(
    PlanTrigger trigger,
    BuiltPlanInputs built,
    PlanVersionRecord? last,
  ) => (trigger == PlanTrigger.create || last == null)
      ? built.inputs
      : refreshMeasuredInputs(last.inputs, built.inputs);

  /// Auslöser beim Speichern eines Ziels: `goalChange`, wenn schon ein Ziel
  /// mit Fassung besteht, sonst `create`.
  static PlanTrigger _saveTrigger(
    bool goalExisted,
    List<PlanVersionRecord> history,
  ) => goalExisted && history.isNotEmpty
      ? PlanTrigger.goalChange
      : PlanTrigger.create;

  Future<void> _load() async {
    if (_disposed) return;
    PlanViewState next;
    try {
      next = await _compute();
    } on Object {
      next = const PlanViewState.failed();
    }
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<PlanViewState> _compute() async {
    final today = _today();
    final goal = await _goals.goal();
    final history = await _plans.history();
    final version = history.isEmpty ? null : history.last;
    GeneratedPlan? hints = _fresh;
    final units = version == null
        ? const <PlanUnit>[]
        : await _plans.unitsBetween(version.inputs.anchor, planFarFuture);
    if (hints == null && goal != null && version != null) {
      final inputs = version.inputs.copyWith(today: today);
      hints =
          planHintsFromSummary(
            version.summary,
            version: version.version,
            units: units,
            today: today,
          ) ??
          previewPlan(
            goal: goal,
            inputs: inputs,
            units: units,
            today: today,
            parameters: parameters,
          );
    }
    // Abstandskonflikte immer aus den gespeicherten Einheiten: Eine bestätigte
    // Verschiebung ändert sie ohne neue Fassung. Die übrigen Konflikte
    // stammen aus der letzten Rechnung, die vor heute fallen weg.
    if (hints != null) {
      hints = hints.copyWith(
        pinnedConflicts: [
          for (final c in hints.pinnedConflicts)
            if (c.kind != PinnedConflictKind.spacing && !c.day.isBefore(today))
              c,
          ...planSpacingConflicts(units, today, parameters: parameters),
        ],
      );
    }
    final monday = today.subtract(Duration(days: today.weekday - 1));
    GoalAssessment? assessment;
    if (goal != null && version != null) {
      try {
        assessment = assessGoal(
          goal: goal,
          inputs: version.inputs.copyWith(today: today),
          today: today,
          basis: await reader.timeGoalBasis(goal: goal, today: today),
          parameters: parameters,
        );
      } on Object {
        // Ohne Einschätzung bleibt die Seite benutzbar; der Inhalt eines
        // Fehlers wird nie gezeigt.
        assessment = null;
      }
    }
    final warning = await _warning?.read();
    final reminderDue =
        warning != null &&
        warningReminderDue(reportedOn: warning.reportedOn, today: today);
    var feedbackDue = false;
    if (warning == null && version != null && history.isNotEmpty) {
      feedbackDue = planFeedbackDue(
        created: calendarDay(history.first.createdAt),
        lastAnswer: _parseDay(await session.settings.get(planFeedbackKey)),
        today: today,
        pauseOpen:
            await HintService(session: session, clock: clock).pauseQuestion() !=
            null,
      );
    }
    final seen = await WarningState(session.settings).planChangeSeen();
    // Unter Warnsignal zeigt das Banner den Grund; die Karte „Plan angepasst“
    // mit dem Grund `warning` käme doppelt (K58, D2).
    var notice = planChangeNotice(history, seenPlanId: seen);
    if (warning != null && notice?.explanation.code == planReasonWarning) {
      notice = null;
    }
    WalkRunWeekProposal? proposal;
    final walkStart = version?.inputs.walkRunStart;
    if (warning == null && walkStart != null) {
      final declined = _parseDay(
        await session.settings.get(planWalkRunRepeatDeclinedKey),
      );
      proposal = walkRunWeekProposal(
        units: units,
        start: walkStart,
        from: version?.inputs.walkRunFrom,
        rpeByRunId: {
          for (final e in (await session.subjective.readAll()).entries)
            if (e.value.subjective.rpe case final int r) e.key: r,
        },
        today: today,
      );
      if (proposal != null && declined == proposal.lastDay) proposal = null;
    }
    return PlanViewState.ready(
      changeNotice: notice,
      walkRunProposal: proposal,
      warning: warning,
      warningReminderDue: reminderDue,
      feedbackDue: feedbackDue,
      assessment: assessment,
      goal: goal,
      version: version,
      hints: version == null ? null : hints,
      lastChange: _lastChange,
      weekUnits: version == null
          ? const []
          : await _plans.unitsBetween(
              monday,
              monday.add(const Duration(days: 6)),
            ),
    );
  }

  /// Einheiten mit `from <= Tag <= to` (Ortstage), z. B. für den Kalender.
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      _plans.unitsBetween(from, to);

  /// Beendete Läufe mit Ortstag (Tag des Laufendes, [dayOfRun]) in
  /// `from <= Tag <= to`, für den Kalender (FR-0171) und die Prüfung beim
  /// Verschieben: [PlanCalendarRun.intensive] nach PAR-058 aus der
  /// RPE-Angabe ([PlanParameters.completedIntensiveMinRpe]).
  ///
  /// Liest nur die Läufe, deren Ende höchstens den größten UTC-Versatz
  /// ([maxRunEndUtcOffset]) außerhalb des Zeitraums liegt, und nur deren
  /// subjektive Angaben (Befund E2-6).
  Future<List<PlanCalendarRun>> runsBetween(DateTime from, DateTime to) async {
    final f = planDay(from), t = planDay(to);
    final result = <PlanCalendarRun>[];
    for (final r in await session.runs.finishedBetween(
      f.subtract(maxRunEndUtcOffset),
      t.add(const Duration(days: 1) + maxRunEndUtcOffset),
    )) {
      final p = DateTime.parse(dayOfRun(r));
      final day = DateTime.utc(p.year, p.month, p.day);
      if (day.isBefore(f) || day.isAfter(t)) continue;
      final value = (await session.subjective.read(r.id))?.subjective.rpe;
      result.add(
        PlanCalendarRun(
          id: r.id,
          day: day,
          intensive:
              value != null && value >= parameters.completedIntensiveMinRpe,
        ),
      );
    }
    return result;
  }

  /// Die Einheit an [day] oder `null`.
  Future<PlanUnit?> unitOn(DateTime day) => _plans.unitOn(day);

  /// Plan-Eingaben für [goal] (ohne: das gespeicherte) aus dem Speicher, für
  /// die Einschätzung ([assessGoal]) vor dem Speichern. Das Ergebnis trägt
  /// mit `goal` den Stand aus Läufen (PAR-192). `null` ohne Ziel.
  Future<BuiltPlanInputs?> inputsFor([TrainingGoal? goal]) async {
    final g = goal ?? await _goals.goal();
    if (g == null) return null;
    return reader.read(goal: g, today: _today());
  }

  /// Stand aus vorhandenen Läufen (PAR-192: „Vorhandene Läufe in der App
  /// ersetzen die Angabe zum Stand“) als Wochenzeit in Sekunden, `null` ohne
  /// Läufe im Fenster. Für das Zielformular: Mit Läufen entfällt die Frage
  /// nach dem Stand. Gelesen wie bei der Planrechnung ([buildPlanInputs]);
  /// das Ziel dafür ist ein Platzhalter ohne eigenen Stand.
  Future<double?> standFromRuns() async {
    final probe = TrainingGoal(
      type: GoalType.open,
      runDays: const {DateTime.monday},
      maxSessionSeconds: 1,
      weeklyCapSeconds: 1,
      createdAt: clock.now(),
      hardSessionEnabled: false,
    );
    final built = await reader.read(goal: probe, today: _today());
    return built.goal.currentWeeklySeconds;
  }

  /// Einschätzung eines noch nicht gespeicherten Ziels (PAR-206) mit genau
  /// den Eingaben, mit denen [saveGoal] danach rechnen würde: beim Anlegen
  /// die frischen ([buildPlanInputs], Stand ggf. aus Läufen), beim Ändern die
  /// der letzten Fassung mit heute gemessenen Werten (Stand und Geh-Lauf-
  /// Abfolge bleiben, [refreshMeasuredInputs]); dazu, ob der Plan mit einer
  /// Geh-Lauf-Abfolge beginnt (PAR-065, Hinweis PAR-115). Speichert nichts.
  ///
  /// Mit [newStart] (neuer Einstieg nach langer Pause, PAR-181) rechnet die
  /// Einschätzung mit den Eingaben des Neustarts mit dem Stand aus [draft].
  Future<GoalDraftCheck> checkGoal(
    TrainingGoal draft, {
    bool newStart = false,
  }) async {
    final today = _today();
    final existed = await _goals.goal() != null;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final built = await reader.read(goal: draft, today: today);
    var inputs = _inputsFor(_saveTrigger(existed, history), built, last);
    var goal = built.goal;
    if (newStart && last != null) {
      final q = await HintService(session: session, clock: clock).newStartDue();
      final restart = q == null
          ? null
          : planPauseRestart(
              goal: draft,
              inputs: inputs,
              today: today,
              lastTrainingDay: q.lastTrainingDay,
              baseWeekMinutes: q.baseWeekMinutes,
              parameters: parameters,
              replacesProvisional: await _pauseProvisional(q),
            ).inputs;
      if (restart != null) {
        inputs = restart;
        goal = draft;
      }
    }
    final assessment = assessGoal(
      goal: goal,
      inputs: inputs,
      today: today,
      basis: await reader.timeGoalBasis(goal: goal, today: today),
      parameters: parameters,
    );
    final setup = planCourseSetup(goal, inputs, parameters: parameters);
    return GoalDraftCheck(
      assessment: assessment,
      walkRun: setup.walkRunWeeks > 0,
    );
  }

  /// Speichert das Ziel (Anlegen oder Ändern, PAR-203) mit „heute“ und
  /// rechnet den Plan ab heute neu (`create` ohne bisheriges Ziel oder ohne
  /// Fassung, sonst `goalChange`), mit dem gespeicherten Ziel. Ungültiges Ziel:
  /// [PlanActionResult.rejected], nichts geändert. Scheitert nur die
  /// Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> saveGoal(TrainingGoal goal) => _act(() async {
    final existed = await _goals.goal() != null;
    await _goals.save(goal, today: _today());
    onChanged?.call();
    try {
      final saved = await _goals.goal();
      if (saved == null) {
        throw const StorageException(StorageFailure.notFound);
      }
      final history = await _plans.history();
      await _recalculate(
        _saveTrigger(existed, history),
        saved,
        history.isEmpty ? null : history.last,
      );
    } on Object {
      throw const _SavedNotPlanned();
    }
  });

  /// Ausdrückliche Neuberechnung durch den Nutzer (`manual`).
  Future<PlanActionResult> recalculate() => _act(() async {
    final goal = await _goals.goal();
    if (goal == null) {
      throw const StorageException(StorageFailure.notFound);
    }
    final history = await _plans.history();
    await _recalculate(
      history.isEmpty
          ? PlanTrigger.create
          : (planGoalChangedSince(history.last.summary, goal)
                ? PlanTrigger.goalChange
                : PlanTrigger.manual),
      goal,
      history.isEmpty ? null : history.last,
    );
  });

  /// Ordnet der Einheit den Lauf zu (`null` hebt die Zuordnung auf) und
  /// rechnet danach ab heute neu (Auslöser `run`; die Zuordnung zählt für
  /// „locker“, PAR-205, und friert die Einheit ein).
  Future<PlanActionResult> assignRun(int unitId, int? runId) => _act(() async {
    await _plans.assignRun(unitId, runId);
    _fresh = null;
    onChanged?.call();
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final goalChanged =
        last != null && planGoalChangedSince(last.summary, goal);
    await _recalculate(
      goalChanged ? PlanTrigger.goalChange : PlanTrigger.run,
      goal,
      last,
      // `run` bewertet die Woche nicht: Der Prüftag bleibt, sonst fiele die
      // Bewertung der Vorwoche weg (Lauf über Mitternacht in den Montag,
      // NB7 1). `goalChange` bewertet bei Fälligkeit selbst.
      markChecked: goalChanged,
    );
  });

  /// Verschiebt die Einheit nach Bestätigung des Nutzers auf [day] (setzt
  /// `pinned`, OQ-0011), mit „heute“. Keine Neuberechnung.
  Future<PlanActionResult> confirmMove(int unitId, DateTime day) =>
      _act(() async {
        await _plans.confirmMove(unitId, day, today: _today());
        _fresh = null;
        onChanged?.call();
      });

  /// Prüft vor der Bestätigung, ob [unit] die Art [kind] bekommen kann
  /// ([checkPlanReplace] mit Ziel und Eingaben der neuesten Fassung, Einheiten
  /// und absolvierten intensiven Läufen um die Woche, „heute“). `null` ohne
  /// Ziel oder Fassung.
  Future<PlanReplaceCheck?> checkReplace(PlanUnit unit, PlanUnitKind kind) =>
      _serial(() => _replaceCheck(unit, kind, _today()));

  Future<PlanReplaceCheck?> _replaceCheck(
    PlanUnit unit,
    PlanUnitKind kind,
    DateTime today,
  ) async {
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) return null;
    final w = await _weekAround(unit.day);
    return checkPlanReplace(
      units: w.units,
      unit: unit,
      kind: kind,
      goal: goal,
      inputs: history.last.inputs,
      today: today,
      completedIntensiveDays: w.intensive,
      parameters: parameters,
    );
  }

  /// Prüft vor der Bestätigung, ob [day] Ruhetag werden kann
  /// ([checkPlanRestDay]: Alternativtage derselben Woche für eine Einheit
  /// auf dem Tag). `null` ohne Ziel oder Fassung.
  Future<PlanRestDayCheck?> checkRestDay(DateTime day) => _serial(() async {
    final goal = await _goals.goal();
    if (goal == null || (await _plans.history()).isEmpty) return null;
    final w = await _weekAround(day);
    return checkPlanRestDay(
      units: w.units,
      day: day,
      today: _today(),
      weeklyCapSeconds: goal.weeklyCapSeconds,
      completedIntensiveDays: w.intensive,
      runDays: goal.runDays,
      parameters: parameters,
    );
  });

  /// Einheiten und absolvierte intensive Läufe von einer Woche vor bis eine
  /// Woche nach der Woche von [day] (Abstand PAR-059/PAR-060 über die
  /// Wochengrenze).
  Future<({List<PlanUnit> units, List<DateTime> intensive})> _weekAround(
    DateTime day,
  ) async {
    final d = planDay(day);
    final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
    final from = monday.subtract(const Duration(days: 7));
    final to = monday.add(const Duration(days: 13));
    return (
      units: await _plans.unitsBetween(from, to),
      intensive: [
        for (final r in await runsBetween(from, to))
          if (r.intensive) r.day,
      ],
    );
  }

  /// Ersetzt die Art der Einheit nach Bestätigung des Nutzers durch [kind]
  /// (FR-0173, `fixed = kind`): Dauer, Abschnitte und Zielintensität rechnet
  /// [checkPlanReplace] mit „heute“ neu, wie beim Bestätigen gezeigt. Keine
  /// Neuberechnung (wie [confirmMove]). Fehlt die Einheit, das Ziel oder die
  /// Fassung: `notFound`; sperrt die Prüfung (eingefroren, vergangen,
  /// Geh-Lauf, Art passt nicht in die maximale Zeit, …): `rejected`.
  Future<PlanActionResult> replaceUnit(int unitId, PlanUnitKind kind) =>
      _act(() async {
        final today = _today();
        final history = await _plans.history();
        if (history.isEmpty) {
          throw const StorageException(StorageFailure.notFound);
        }
        final unit = (await _plans.unitsBetween(
          history.last.inputs.anchor,
          planFarFuture,
        )).where((u) => u.id == unitId).firstOrNull;
        if (unit == null) throw const StorageException(StorageFailure.notFound);
        final check = await _replaceCheck(unit, kind, today);
        if (check == null) {
          throw const StorageException(StorageFailure.notFound);
        }
        if (!check.allowed) {
          throw const StorageException(StorageFailure.rejected);
        }
        await _plans.replaceUnit(unitId, check.unit!, today: today);
        _fresh = null;
        onChanged?.call();
      });

  /// Legt [day] nach Bestätigung als Ruhetag fest ([planRestDayUnit] mit Ziel
  /// und Eingaben der neuesten Fassung). Eine Einheit auf dem Tag geht auf
  /// [moveUnitTo] (gewählter Alternativtag aus [checkRestDay]) oder entfällt
  /// ohne ihn. [expectedUnitId] ist die Einheit, die [checkRestDay] auf dem
  /// Tag gezeigt hat (`null`: Tag frei); liegt jetzt eine andere dort, ändert
  /// sich nichts (FR-0176). Keine Neuberechnung. Ohne Ziel oder Fassung:
  /// `notFound`; Tag vor heute, Einheit mit Lauf, schon festgelegter
  /// Ruhetag, abweichende Einheit, ungültiger Zieltag: `rejected`.
  Future<PlanActionResult> setRestDay(
    DateTime day, {
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) => _act(() async {
    final today = _today();
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    await _plans.setRestDay(
      planRestDayUnit(
        day: day,
        goal: goal,
        inputs: history.last.inputs,
        today: today,
        parameters: parameters,
      ),
      today: today,
      expectedUnitId: expectedUnitId,
      moveUnitTo: moveUnitTo,
    );
    _fresh = null;
    onChanged?.call();
  });

  /// Hebt den Ruhetag an [day] nach Bestätigung auf; die App plant dort erst
  /// bei der nächsten Neuberechnung wieder (OQ-0011). Kein Ruhetag:
  /// `notFound`; Tag vor heute: `rejected`.
  Future<PlanActionResult> clearRestDay(DateTime day) => _act(() async {
    await _plans.clearRestDay(day, today: _today());
    _fresh = null;
    onChanged?.call();
  });

  /// Meldet Beschwerden, Krankheit oder Überlastung (FR-0203, Quelle
  /// `manual`): Warnsignal setzen, Plan zeigt nur Ruhetage. Doppeltes
  /// Melden ändert nichts.
  Future<PlanActionResult> reportWarning() => _act(() async {
    final w = _warning;
    if (w == null) throw StateError('kein Warnspeicher');
    final r = await _warningService(
      w,
    ).report(source: WarningSource.manual, today: _today(), now: clock.now());
    _fresh = null;
    if (r.wasWritten) onChanged?.call();
  });

  /// Hebt das Warnsignal auf; die Festlegungen des Nutzers gelten wieder.
  Future<PlanActionResult> liftWarning() => _act(() async {
    final w = _warning;
    if (w == null) throw StateError('kein Warnspeicher');
    final r = await _warningService(w).lift(today: _today(), now: clock.now());
    _fresh = null;
    if (r.wasWritten) onChanged?.call();
  });

  WarningService _warningService(WarningStore w) => WarningService(
    plans: _plans,
    settings: session.settings,
    warning: w,
    parameters: parameters,
    measuredInputs: (goal, today) async =>
        (await reader.read(goal: goal, today: today)).inputs,
  );

  /// Antwort auf die Nachfrage (PAR-200). „Passt“ und „zu leicht“ am Regler
  /// ändern den Plan nicht; „zu leicht“ davor und „zu schwer“ legen einen
  /// neuen Anker an (`feedback`). Die Antwort zählt erst, wenn alles
  /// geschrieben ist (sonst bleibt die Nachfrage fällig). Ohne Antwort
  /// ändert sich nichts.
  Future<PlanFeedbackOutcome> answerFeedback(PlanFeedback answer) async {
    var raise = false;
    final r = await _act(() async {
      // Eine offene Pausenfrage hat Vorrang (PAR-202): Die Karte ist dann nicht
      // mehr gültig (etwa nach Mitternacht bei offener Seite).
      if (await HintService(session: session, clock: clock).pauseQuestion() !=
          null) {
        throw const StorageException(StorageFailure.rejected);
      }
      final goal = await _goals.goal();
      if (goal == null) throw const StorageException(StorageFailure.notFound);
      final history = await _plans.history();
      if (history.isEmpty) {
        throw const StorageException(StorageFailure.notFound);
      }
      final today = _today();
      final built = await reader.read(goal: goal, today: today);
      final inputs = _inputsFor(PlanTrigger.feedback, built, history.last);
      final result = applyPlanFeedback(
        goal: goal,
        inputs: inputs,
        answer: answer,
        today: today,
      );
      raise = result.raiseGoalSignal;
      final next = result.inputs;
      if (next != null) {
        final w = await recalculatePlan(
          plans: _plans,
          settings: session.settings,
          trigger: PlanTrigger.feedback,
          markChecked: false, // bewertet die Woche (PAR-201) nicht
          today: today,
          now: clock.now(),
          inputs: next,
          parameters: parameters,
          warning: _warning,
        );
        _fresh = w.generated;
        _lastChange = w.summary;
        if (w.wasWritten) onChanged?.call();
      }
      await session.settings.set(
        planFeedbackKey,
        _dayText(today),
        at: clock.now(),
      );
    });
    return PlanFeedbackOutcome(
      r,
      raiseGoalSignal: r == PlanActionResult.done && raise,
    );
  }

  /// Antwort auf die Pausenfrage (PAR-202, „Heute“). „Ja“ startet den Plan
  /// neu ([planPauseRestart], Auslöser `pause`), sofern ein Plan besteht und
  /// der Neustart nötig ist; „Nein“ ändert nichts. Die Antwort wird erst nach
  /// dem Schreiben gespeichert: Scheitert der Neustart, bleibt die Frage
  /// offen. Ohne offene Frage ([HintService.pauseQuestion]): `rejected`.
  Future<PlanActionResult> answerPause(bool paused) => _act(() async {
    final today = _today();
    final q = await HintService(session: session, clock: clock).pauseQuestion();
    if (q == null) throw const StorageException(StorageFailure.rejected);
    if (paused) await _restartForPause(q);
    await WarningState(session.settings).setPauseAnswer(
      PauseAnswer(paused: paused, on: today),
      at: clock.now(),
    );
  });

  /// Neustart zur Pause (PAR-202, Auslöser `pause`), einmal je Pause: Der
  /// Merker [planPauseRestartKey] trägt den Tag des letzten Trainings und ob
  /// eine Fassung entstand. Ohne Plan oder Ziel geschieht nichts (kein Merker).
  ///
  /// Ab 8 Wochen ([PlanParameters.pauseNewStartDays]) gilt ohne Wahl
  /// vorläufig die Stufe 2 (sichere Vorgabe, Merker `provisional`); der
  /// Nutzer wählt den Einstieg ([restartAfterLongPause], PAR-181) und ersetzt
  /// sie damit. Mit [chosen] hat der Nutzer den Einstieg gewählt; sein Ziel mit
  /// dem neuen Stand ist schon gespeichert.
  Future<void> _restartForPause(PauseQuestion q, {bool chosen = false}) async {
    final today = _today();
    final history = await _plans.history();
    final goal = await _goals.goal();
    if (goal == null || history.isEmpty) return;
    final mark = PauseRestartMark.parse(
      await session.settings.get(planPauseRestartKey),
    );
    final marked = mark?.day == warningDay(q.lastTrainingDay);
    final wasProvisional = marked && mark!.provisional;
    if (marked && !(chosen && wasProvisional)) return;
    final longPause = q.daysSinceTraining >= parameters.pauseNewStartDays;
    final built = await reader.read(goal: goal, today: today);
    final base = refreshMeasuredInputs(history.last.inputs, built.inputs);
    final restart = planPauseRestart(
      goal: goal,
      inputs: base,
      today: today,
      lastTrainingDay: q.lastTrainingDay,
      baseWeekMinutes: q.baseWeekMinutes,
      parameters: parameters,
      anchorFromAdjustment: planAnchorFromAdjustment(history),
      provisional: longPause && !chosen,
      replacesProvisional: chosen && wasProvisional && mark.restarted,
    );
    final next = restart.inputs;
    if (next == null && chosen) {
      // Kein Neustart möglich: das neue Ziel gilt trotzdem für den Plan.
      await _recalculate(
        PlanTrigger.goalChange,
        goal,
        history.last,
        adjust: false,
      );
    }
    if (next != null) {
      final r = await recalculatePlan(
        plans: _plans,
        settings: session.settings,
        // Der gewählte Einstieg ist eine Zieländerung des Nutzers (Stand neu):
        // `goalChange` hält sie fest, sonst bliebe sie ausstehend.
        trigger: chosen ? PlanTrigger.goalChange : PlanTrigger.pause,
        today: today,
        now: clock.now(),
        inputs: next,
        parameters: parameters,
        warning: _warning,
      );
      _fresh = r.generated;
      _lastChange = r.summary;
      if (r.wasWritten) onChanged?.call();
    }
    await session.settings.set(
      planPauseRestartKey,
      PauseRestartMark(
        day: q.lastTrainingDay,
        restarted: next != null,
        provisional: longPause && !chosen,
      ).format(),
      at: clock.now(),
    );
  }

  /// Würde der Plan beim neuen Einstieg nach langer Pause neu beginnen
  /// (PAR-181)? `false` ohne anstehenden Einstieg, ohne Plan und wenn kein
  /// Neustart möglich ist ([planPauseRestart] liefert nichts).
  Future<bool> newStartPossible() async {
    try {
      final q = await HintService(session: session, clock: clock).newStartDue();
      final goal = await _goals.goal();
      final history = await _plans.history();
      if (q == null || goal == null || history.isEmpty) return false;
      final today = _today();
      final built = await reader.read(goal: goal, today: today);
      return planPauseRestart(
            goal: goal,
            inputs: refreshMeasuredInputs(history.last.inputs, built.inputs),
            today: today,
            lastTrainingDay: q.lastTrainingDay,
            baseWeekMinutes: q.baseWeekMinutes,
            parameters: parameters,
            anchorFromAdjustment: planAnchorFromAdjustment(history),
            replacesProvisional: await _pauseProvisional(q),
          ).inputs !=
          null;
    } on Object {
      return false;
    }
  }

  /// Gilt für die Pause nach [q] schon die vorläufige Vorgabe (als Fassung)?
  Future<bool> _pauseProvisional(PauseQuestion q) async {
    final mark = PauseRestartMark.parse(
      await session.settings.get(planPauseRestartKey),
    );
    return mark != null &&
        mark.provisional &&
        mark.restarted &&
        mark.day == warningDay(q.lastTrainingDay);
  }

  /// Steht die Pause durch die Zusage „alles erfasst“ ohne Frage fest, startet
  /// der Plan beim Öffnen neu (PAR-202), einmal je Pause.
  Future<void> _checkPauseRestart() async {
    final q = await HintService(
      session: session,
      clock: clock,
    ).pauseRestartDue();
    if (q != null) await _restartForPause(q);
  }

  /// Neuer Einstieg nach langer Pause (PAR-181, PAR-192): speichert [goal]
  /// (mit dem vom Nutzer genannten Stand) und startet den Plan neu. Ohne
  /// anstehenden Einstieg ([HintService.newStartDue]): `rejected`. Scheitert
  /// nur die Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> restartAfterLongPause(TrainingGoal goal) => _act(
    () async {
      final q = await HintService(session: session, clock: clock).newStartDue();
      if (q == null) throw const StorageException(StorageFailure.rejected);
      if ((await _plans.history()).isEmpty) {
        throw const StorageException(StorageFailure.notFound);
      }
      final today = _today();
      if (goal.validate(today, null, true) != null) {
        throw const StorageException(StorageFailure.rejected);
      }
      await _goals.save(goal, today: today);
      onChanged?.call();
      try {
        await _restartForPause(q, chosen: true);
      } on Object {
        throw const _SavedNotPlanned();
      }
    },
  );

  /// Alle Fassungen, älteste zuerst (Verlauf der Änderungen, FR-0170).
  Future<List<PlanVersionRecord>> changeHistory() => _plans.history();

  /// Die Karte „Plan angepasst“ gilt bis zur Plan-ID [planId] als gesehen.
  Future<PlanActionResult> markChangeSeen(int planId) => _act(() async {
    await WarningState(session.settings)
        .setPlanChangeSeen(planId, at: clock.now());
  });

  /// Nimmt „Wiederholen“ an (PAR-140): neue Fassung, die Abfolge beginnt ab
  /// heute (nach einem Lauf heute ab morgen) an der Stelle des Vorschlags
  /// wieder; vergangene Tage bleiben unverändert. Ändert
  /// nur nach dieser Entscheidung des Nutzers.
  Future<PlanActionResult> acceptWalkRunRepeat() => _act(() async {
    final proposal = _state.walkRunProposal;
    if (proposal == null) throw const StorageException(StorageFailure.notFound);
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    final base = refreshMeasuredInputs(history.last.inputs, built.inputs);
    final inputs = applyWalkRunRepeat(
      base,
      proposal.suggestion,
      from: walkRunRepeatFrom(today, proposal.lastDay),
    ).copyWith(today: today);
    final r = await recalculatePlan(
      plans: _plans,
      settings: session.settings,
      trigger: PlanTrigger.manual,
      reason: walkRunRepeatReason,
      markChecked: false, // bewertet die Woche nicht
      today: today,
      now: clock.now(),
      inputs: inputs,
      parameters: parameters,
      warning: _warning,
    );
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
  });

  /// Lehnt „Woche wiederholen“ für diese Programmwoche ab; nichts ändert sich.
  Future<PlanActionResult> declineWalkRunRepeat() => _act(() async {
    final proposal = _state.walkRunProposal;
    if (proposal == null) return;
    await session.settings.set(
      planWalkRunRepeatDeclinedKey,
      _dayText(proposal.lastDay),
      at: clock.now(),
    );
  });

  Future<PlanActionResult> _act(Future<void> Function() action) =>
      _serial(() async {
        PlanActionResult result;
        try {
          await action();
          result = PlanActionResult.done;
        } on _SavedNotPlanned {
          result = PlanActionResult.savedNotPlanned;
        } on StorageException catch (e) {
          result = switch (e.failure) {
            StorageFailure.rejected => PlanActionResult.rejected,
            StorageFailure.notFound => PlanActionResult.notFound,
            _ => PlanActionResult.failed,
          };
        } on Object {
          result = PlanActionResult.failed;
        }
        await _load();
        return result;
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Ist die wöchentliche Prüfung fällig (FR-0158)? [lastCheckDay] ist der
/// Wert von `plan.last_check_day` (`JJJJ-MM-TT`); fehlt er oder ist er
/// unlesbar, ja; sonst, wenn er in einer früheren Kalenderwoche (ab Montag)
/// als [today] liegt.
bool weeklyCheckDue(String? lastCheckDay, DateTime today) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(lastCheckDay ?? '');
  if (m == null) return true;
  final last = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  );
  DateTime monday(DateTime d) {
    final x = planDay(d);
    return x.subtract(Duration(days: x.weekday - DateTime.monday));
  }

  return monday(last).isBefore(monday(today));
}

/// Ein beendeter Lauf im Kalender ([PlanController.runsBetween]).
class PlanCalendarRun {
  const PlanCalendarRun({
    required this.id,
    required this.day,
    required this.intensive,
  });

  final int id;

  /// Ortstag des Laufendes.
  final DateTime day;

  /// Gilt nach PAR-058 als intensiv (RPE-Angabe).
  final bool intensive;
}
