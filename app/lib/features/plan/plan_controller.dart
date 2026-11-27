import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'plan_data_reader.dart';
import 'plan_view_state.dart';

export 'plan_data_reader.dart' show PlanCalendarRun, PlanDoneRun;
export 'plan_view_state.dart';

/// Liest und ändert Ziel und Plan (WP22 Punkt 7). Gerechnet und entschieden wird in `core`
/// ([PlanWorkflowService], [previewPlan]); „heute“ ist der
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
    this.readinessToday,
    this.exclusive,
  }) : _writes = PlanWriteQueue.of(session),
       reader =
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

  /// Readiness des Tags (heute; Modell, FR-0116) für die Lockerung nach
  /// PAR-173, als Band und senkende Faktoren ([PlanReadinessDay.of]); `null`
  /// oder ein Fehler: keine Lockerung (fail-closed). Gesundheitsdatum: nie
  /// loggen.
  final Future<PlanReadinessDay?> Function(DateTime day)? readinessToday;

  /// Sperre der Neuberechnung der Werte (`RecalculationController`), hinter
  /// der die automatische Zuordnung beim Öffnen läuft (PAR-231): wie nach dem
  /// Lauf-Ende erst nach dessen Wertberechnung, nie parallel zu ihr. `null`
  /// (Tests, Aufrufer schon innerhalb der Sperre): ohne. Nie innerhalb der
  /// Sperre an einen Controller mit Sperre übergeben (nicht wiedereintretend).
  final Future<void> Function(Future<void> Function() action)? exclusive;

  /// Die Schreibreihe des Plans dieser Sitzung, gemeinsam mit jedem anderen
  /// Controller und dem Erholungs-Auslöser ([PlanWriteQueue.of]).
  final PlanWriteQueue _writes;

  /// Die Abläufe des Plans (Prüfung beim Öffnen, Wochen- und
  /// Erholungsprüfung, Warnsignal, Neuberechnung) ohne Oberfläche.
  late final PlanWorkflowService _workflow = planWorkflowFor(
    session: session,
    clock: clock,
    reader: reader,
    parameters: parameters,
    readinessToday: readinessToday,
  );

  /// Rückmeldungen der Abläufe an den Ansichtszustand.
  late final PlanWorkflowEvents _events = PlanWorkflowEvents(
    onResult: _took,
    onStored: _stored,
  );

  SettingsPlanAdaptationStore get _adaptation =>
      SettingsPlanAdaptationStore(session.settings);

  GoalStore get _goals => (session as GoalStorage).goals;
  PlanRepository get _plans => (session as PlanStorage).plans;
  WarningStore? get _warning =>
      session is WarningStorage ? (session as WarningStorage).warning : null;

  PlanViewState _state = const PlanViewState.loading();
  PlanViewState get state => _state;

  GeneratedPlan? _fresh;
  PlanChangeSummary? _lastChange;

  bool _disposed = false;

  DateTime _today() => calendarDay(clock.now());

  /// Führt [action] in der Schreibreihe der Sitzung aus: nach allen vorher
  /// angestoßenen Aktionen jedes Plan-Controllers der Sitzung, nie parallel.
  Future<T> _serial<T>(Future<T> Function() action) => _writes.run(action);

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
  ///
  /// Danach ordnet das Öffnen Läufe der Woche bis heute ihren offenen
  /// Einheiten zu (PAR-231); mit [exclusive] hinter der Wertberechnung, dann
  /// erst nach dem ersten Laden der Seite. Erst nach der Zuordnung prüft es
  /// das Muster der Unterforderung (PAR-236), auch wenn die Zuordnung
  /// scheitert; dann zählen die schon zugeordneten Läufe.
  Future<void> open() async {
    final lock = exclusive;
    await _serial(() async {
      _fresh = null;
      try {
        // Pause hat Vorrang (PAR-202): ihre Fassung gilt für diese Woche und
        // setzt den Prüftag, die Wochenprüfung schreibt danach keine zweite.
        await _workflow.restartIfDue(events: _events);
        await _checkDue();
      } on Object {
        // Die Prüfung holt der nächste Start nach; die Seite zeigt den
        // gespeicherten Plan.
      }
      // Erst zuordnen, dann das Muster prüfen (PAR-236): Ein Lauf, dessen
      // Zuordnung erst dieses Öffnen nachholt, zählt schon jetzt.
      if (lock == null) {
        await _workflow.autoAssignQuietly(events: _events);
        await _workflow.advanceUnderloadQuietly();
      }
      await _load();
    });
    if (lock == null) return;
    // Sperre zuerst, dann die Schreibreihe (wie nach dem Lauf-Ende), nie
    // umgekehrt: sonst warteten beide aufeinander.
    var advanced = false;
    try {
      await lock(
        () => _serial(() async {
          await _workflow.autoAssignQuietly(events: _events);
          await _workflow.advanceUnderloadQuietly();
          advanced = true;
        }),
      );
    } on Object {
      // Das nächste Öffnen holt die Zuordnung nach.
    }
    // Neu laden, auch ohne eigene Zuordnung: Während des Wartens auf die
    // Sperre kann eine andere Stelle (Lauf-Ende) zugeordnet haben. Ohne
    // Sperre prüft das Öffnen das Muster trotzdem mit den schon zugeordneten
    // Läufen.
    await _serial(() async {
      if (!advanced) await _workflow.advanceUnderloadQuietly();
      await _load();
    });
  }

  /// Lädt den Stand neu (ohne Prüfung).
  Future<void> reload() => _serial(_load);

  /// Prüfung beim Öffnen ([PlanWorkflowService.dueCheck]). Bei der Heilung
  /// des Warnsignals zeigt die Seite Banner bzw. Erinnerung zuerst, nicht
  /// erst nach der Rechnung; unter gespeichertem Signal mit
  /// Fortschrittsanzeige wie nach dem Melden, bis die Rechnung endet (auch
  /// wenn sie scheitert). Das anschließende Laden in [open] blendet sie aus.
  Future<void> _checkDue() async {
    final due = await _workflow.dueCheck();
    if (due.kind != PlanDueKind.warningHeal) {
      await _workflow.runDue(due, onResult: _took);
      return;
    }
    _warningRecalculating = due.warned;
    try {
      await _load();
      await _workflow.runDue(due, onResult: _took);
    } finally {
      _warningRecalculating = false;
    }
  }

  /// Übernimmt Vorschau und Änderung einer gerechneten Fassung in den
  /// Ansichtszustand; meldet eine geschriebene ([onChanged]).
  bool _took(PlanRecalculation r) {
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
    return r.wasWritten;
  }

  /// Eine gespeicherte Änderung ohne eigene Rechnung (Ziel, Zuordnung,
  /// Verschieben): Die Vorschau gilt nicht mehr.
  void _stored() {
    _fresh = null;
    onChanged?.call();
  }

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
    final units = version == null
        ? const <PlanUnit>[]
        : await _plans.unitsBetween(version.inputs.anchor, planFarFuture);
    final hints = await _workflow.planHints(
      fresh: _fresh,
      goal: goal,
      version: version,
      units: units,
      today: today,
    );
    final assessment = await _workflow.goalAssessment(goal, version, today);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final warning = await _warning?.read();
    final reminderDue =
        warning != null &&
        warningReminderDue(reportedOn: warning.reportedOn, today: today);
    final feedbackDue = await _workflow.feedbackDue(history, warning, today);
    final seen = await WarningState(session.settings).planChangeSeen();
    // Unter Warnsignal zeigt das Banner den Grund; die Karte „Plan angepasst“
    // mit dem Grund `warning` käme doppelt (K58, D2).
    var notice = planChangeNotice(history, seenPlanId: seen);
    if (warning != null && notice?.explanation.code == planReasonWarning) {
      notice = null;
    }
    final proposal = await _workflow.walkRunProposal(
      version,
      units,
      warning,
      today,
    );
    final underload = await _workflow.underloadPrompt(history, warning);
    return PlanViewState.ready(
      adaptation: await _adaptation.read(),
      underloadPrompt: underload,
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

  /// Früheste Einheit vor [before] ([PlanEditWorkflow.firstUnitDayBefore]).
  Future<DateTime?> firstUnitDayBefore(DateTime before) =>
      _workflow.firstUnitDayBefore(before);

  /// Beendete Läufe mit Ortstag in `from <= Tag <= to`
  /// ([PlanDataReader.runsBetween]).
  Future<List<PlanCalendarRun>> runsBetween(DateTime from, DateTime to) =>
      reader.runsBetween(from, to);

  /// Die zugeordneten Läufe der erledigten Einheiten
  /// ([PlanDataReader.doneRuns]).
  Future<Map<int, PlanDoneRun>> doneRuns(Iterable<PlanUnit> units) =>
      reader.doneRuns(units);

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

  /// Einschätzung eines noch nicht gespeicherten Ziels (PAR-206) vor dem
  /// Speichern ([PlanGoalWorkflow.checkGoal]); speichert nichts.
  Future<GoalDraftCheck> checkGoal(
    TrainingGoal draft, {
    bool newStart = false,
  }) => _workflow.checkGoal(draft, newStart: newStart);

  /// Speichert das Ziel und rechnet den Plan neu ([PlanGoalWorkflow.saveGoal]).
  /// Ungültiges Ziel: [PlanActionResult.rejected], nichts geändert. Scheitert
  /// nur die Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> saveGoal(TrainingGoal goal) =>
      _act(() => _workflow.saveGoal(goal, events: _events));

  /// Ausdrückliche Neuberechnung durch den Nutzer (`manual`,
  /// [PlanGoalWorkflow.recalculateManual]).
  Future<PlanActionResult> recalculate() =>
      _act(() => _workflow.recalculateManual(events: _events));

  /// Ordnet der Einheit den Lauf zu (`null` hebt die Zuordnung auf) und
  /// rechnet neu ([PlanAssignWorkflow.assignRun]). Veraltet (die Einheit
  /// trägt beim Schreiben einen anderen Lauf als beim Lesen): `rejected`,
  /// der Stand wird neu geladen.
  Future<PlanActionResult> assignRun(int unitId, int? runId) =>
      _act(() => _workflow.assignRun(unitId, runId, events: _events));

  /// Zuordnung über „Einheit starten“ ([PlanAssignWorkflow.assignStartedRun]):
  /// ersetzte Einheit → die offene Einheit desselben Ortstags [day].
  Future<PlanActionResult> assignStartedRun({
    required int unitId,
    required String day,
    required int runId,
  }) => _act(
    () => _workflow.assignStartedRun(
      unitId: unitId,
      day: day,
      runId: runId,
      events: _events,
    ),
  );

  /// Ordnet beendete Läufe den offenen Einheiten ihres Ortstags zu (PAR-231,
  /// [PlanAssignWorkflow.autoAssign]), ab dem Sonntag der Vorwoche oder dem
  /// früheren Tag [since].
  Future<PlanActionResult> autoAssignRuns({DateTime? since}) =>
      _act(() => _workflow.autoAssign(since: since, events: _events));

  /// Darf die Sporteinheit [runId] (FR-0221) die Einheit [unit] ersetzen
  /// (PAR-233, [PlanAssignWorkflow.sportReplacementBlock])? `null`: ja.
  Future<SportReplacementBlock?> sportReplacementBlock(
    PlanUnit? unit,
    int runId,
  ) => _serial(() => _workflow.sportReplacementBlock(unit, runId));

  /// Verschiebt die Einheit nach Bestätigung des Nutzers auf [day]
  /// ([PlanAssignWorkflow.confirmMove]); keine Neuberechnung.
  Future<PlanActionResult> confirmMove(int unitId, DateTime day) =>
      _act(() => _workflow.confirmMove(unitId, day, events: _events));

  /// Anker und Geh-Lauf-Wochen des Wochenverlaufs
  /// ([PlanEditWorkflow.courseWeeks]); `null` ohne Ziel oder Fassung.
  Future<({DateTime anchor, int walkRunWeeks})?> courseWeeks() =>
      _serial(_workflow.courseWeeks);

  /// Prüfung vor dem Ersetzen ([PlanEditWorkflow.checkReplace]).
  Future<PlanReplaceCheck?> checkReplace(PlanUnit unit, PlanUnitKind kind) =>
      _serial(() => _workflow.checkReplace(unit, kind));

  /// Prüfung vor dem Ruhetag ([PlanEditWorkflow.checkRestDay]).
  Future<PlanRestDayCheck?> checkRestDay(DateTime day) =>
      _serial(() => _workflow.checkRestDay(day));

  /// Ersetzt die Art der Einheit nach Bestätigung
  /// ([PlanEditWorkflow.replaceUnit]); keine Neuberechnung.
  Future<PlanActionResult> replaceUnit(int unitId, PlanUnitKind kind) =>
      _act(() => _workflow.replaceUnit(unitId, kind, events: _events));

  /// Legt [day] nach Bestätigung als Ruhetag fest
  /// ([PlanEditWorkflow.setRestDay]); keine Neuberechnung.
  Future<PlanActionResult> setRestDay(
    DateTime day, {
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) => _act(
    () => _workflow.setRestDay(
      day,
      expectedUnitId: expectedUnitId,
      moveUnitTo: moveUnitTo,
      events: _events,
    ),
  );

  /// Hebt den Ruhetag an [day] nach Bestätigung auf
  /// ([PlanEditWorkflow.clearRestDay]).
  Future<PlanActionResult> clearRestDay(DateTime day) =>
      _act(() => _workflow.clearRestDay(day, events: _events));

  /// Meldet Beschwerden, Krankheit oder Überlastung (FR-0203, Quelle
  /// `manual`): Warnsignal setzen, Plan zeigt nur Ruhetage. Doppeltes
  /// Melden ändert nichts. Sobald das Signal gespeichert ist, lädt die Seite
  /// (Banner) und [onSaved] meldet es; erst danach läuft die Neuberechnung,
  /// solange ist [warningRecalculating] gesetzt. Scheitert sie, bleibt das
  /// Signal gespeichert und das Ergebnis nennt den Fehler; das nächste
  /// Öffnen stellt den Plan her ([open]).
  Future<PlanActionResult> reportWarning({void Function()? onSaved}) =>
      _serial(() async {
        final saved = await _resultOf(_workflow.markWarning);
        if (saved != PlanActionResult.done) {
          await _load();
          return saved;
        }
        _warningRecalculating = true;
        await _load();
        if (!_disposed) onSaved?.call();
        final result = await _resultOf(() async {
          final r = await _workflow.recalculateWarned();
          _fresh = null;
          if (r.wasWritten) onChanged?.call();
        });
        _warningRecalculating = false;
        await _load();
        return result;
      });

  /// Läuft unter Warnsignal noch die Neuberechnung: nach dem Melden
  /// ([reportWarning]) oder beim Nachholen der Ruhetag-Fassung in [open]?
  bool get warningRecalculating => _warningRecalculating;
  bool _warningRecalculating = false;

  /// Hebt das Warnsignal auf; die Festlegungen des Nutzers gelten wieder.
  Future<PlanActionResult> liftWarning() => _act(() async {
    final r = await _workflow.liftWarning();
    _fresh = null;
    if (r.wasWritten) onChanged?.call();
  });

  /// Antwort auf die Nachfrage (PAR-200, [PlanGoalWorkflow.answerFeedback]).
  /// Ohne Antwort ändert sich nichts.
  Future<PlanFeedbackOutcome> answerFeedback(PlanFeedback answer) async {
    var out = (raiseGoalSignal: false, planChanged: false);
    final r = await _act(() async {
      out = await _workflow.answerFeedback(answer, events: _events);
    });
    return PlanFeedbackOutcome(
      r,
      raiseGoalSignal: r == PlanActionResult.done && out.raiseGoalSignal,
      planChanged: r == PlanActionResult.done && out.planChanged,
    );
  }

  /// Antwort auf die Pausenfrage (PAR-202, [PlanPauseWorkflow.answerPause]).
  /// Ohne offene Frage: `rejected`.
  Future<PlanActionResult> answerPause(bool paused) =>
      _act(() => _workflow.answerPause(paused, events: _events));

  /// Würde der Plan beim neuen Einstieg nach langer Pause neu beginnen
  /// (PAR-181, [PlanPauseWorkflow.newStartPossible])?
  Future<bool> newStartPossible() => _workflow.newStartPossible();

  /// Neuer Einstieg nach langer Pause (PAR-181, PAR-192,
  /// [PlanPauseWorkflow.restartAfterLongPause]). Scheitert nur die
  /// Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> restartAfterLongPause(TrainingGoal goal) =>
      _act(() => _workflow.restartAfterLongPause(goal, events: _events));

  /// Alle Fassungen, älteste zuerst (Verlauf der Änderungen, FR-0170).
  Future<List<PlanVersionRecord>> changeHistory() => _plans.history();

  /// Die Karte „Plan angepasst“ gilt bis zur Plan-ID [planId] als gesehen.
  Future<PlanActionResult> markChangeSeen(int planId) => _act(() async {
    await WarningState(session.settings)
        .setPlanChangeSeen(planId, at: clock.now());
  });

  /// Nimmt „Wiederholen“ für den gezeigten Vorschlag an (PAR-140,
  /// [PlanGoalWorkflow.acceptWalkRunRepeat]).
  Future<PlanActionResult> acceptWalkRunRepeat() => _act(
    () =>
        _workflow.acceptWalkRunRepeat(_state.walkRunProposal, events: _events),
  );

  /// Lehnt „Woche wiederholen“ für diese Programmwoche ab; nichts ändert sich.
  Future<PlanActionResult> declineWalkRunRepeat() =>
      _act(() => _workflow.declineWalkRunRepeat(_state.walkRunProposal));

  /// Schalter „Plananpassung an Erholung“ (FR-0216). Der Wechsel wirkt ab
  /// heute, nie rückwirkend: Vergangene Einheiten und Lockerungen bleiben.
  /// Eine neue Fassung (`feedback`) entsteht nur, wenn heute eine harte
  /// Einheit betroffen ist: bei „adaptiv“ eine heutige harte Einheit an einem
  /// Tag mit niedrigem Wert (PAR-173, Grund `readiness`), bei „fix“ eine heute
  /// gelockerte (sie kehrt zurück, Grund `adaptationFixed`).
  Future<PlanActionResult> setAdaptation(PlanAdaptationMode mode) =>
      _act(() async {
        final r = await _workflow.setAdaptation(mode);
        if (r != null) _took(r);
      });

  /// Auslöser „veränderter Erholungszustand“ (FR-0157, Teil „3 (Erholung)“):
  /// nach neuen Gesundheitsdaten aus dem Import und nach einer Morgenmessung.
  /// Nur bei „adaptiv“ und nur für heute: Ist heute eine harte Einheit offen
  /// ([recoveryEasable]) und liegt der heutige Wert in einem Band nach
  /// PAR-173, entsteht eine Fassung (`feedback`, Grund `readiness`), in der
  /// genau diese Einheit locker ist. Sonst (auch bei „fix“, ohne Wert oder bei
  /// einem Fehler) geschieht nichts. `true`, wenn eine Fassung geschrieben
  /// wurde.
  Future<bool> recheckRecovery() => _serial(() async {
    var written = false;
    try {
      final r = await _workflow.recheckRecoveryToday();
      written = r != null && _took(r);
    } on Object {
      written = false;
    }
    if (written) await _load();
    return written;
  });

  /// Antwort auf den Hinweis „HFmax prüfen“ bzw. „Passt so“ (PAR-236,
  /// [PlanUnderloadWorkflow.answerUnderloadHint]).
  Future<PlanActionResult> answerUnderloadHint() =>
      _act(_workflow.answerUnderloadHint);

  /// Antwort auf „Plan etwas steigern?“ (PAR-236,
  /// [PlanUnderloadWorkflow.answerUnderloadQuestion]).
  Future<PlanActionResult> answerUnderloadQuestion(bool raise) =>
      _act(() => _workflow.answerUnderloadQuestion(raise, events: _events));

  Future<PlanActionResult> _act(Future<void> Function() action) =>
      _serial(() async {
        final result = await _resultOf(action);
        await _load();
        return result;
      });

  /// Führt [action] aus und übersetzt Fehler in ein [PlanActionResult].
  Future<PlanActionResult> _resultOf(Future<void> Function() action) async {
    try {
      await action();
      return PlanActionResult.done;
    } on PlanSavedNotPlanned {
      return PlanActionResult.savedNotPlanned;
    } on StorageException catch (e) {
      return switch (e.failure) {
        StorageFailure.rejected => PlanActionResult.rejected,
        StorageFailure.notFound => PlanActionResult.notFound,
        _ => PlanActionResult.failed,
      };
    } on Object {
      return PlanActionResult.failed;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Die Abläufe des Plans für [session] ([PlanWorkflowService]): gemeinsam
/// für den [PlanController] und den Erholungs-Auslöser; die Pausenfrage
/// (PAR-202) kommt aus dem [HintService].
PlanWorkflowService planWorkflowFor({
  required StorageSession session,
  required Clock clock,
  required PlanDataReader reader,
  PlanParameters parameters = const PlanParameters(),
  Future<PlanReadinessDay?> Function(DateTime day)? readinessToday,
}) => PlanWorkflowService(
  session: session,
  clock: clock,
  reader: reader,
  parameters: parameters,
  readinessToday: readinessToday,
  pauses: HintService(session: session, clock: clock),
);
