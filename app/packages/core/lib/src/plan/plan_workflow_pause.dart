part of 'plan_workflow_service.dart';

/// Neustart zur Pause (PAR-202) und neuer Einstieg nach langer Pause
/// (PAR-181, PAR-192) als Ablauf des [PlanWorkflowService]. Einmal je Pause:
/// Der Merker [planPauseRestartKey] trägt den Tag des letzten Trainings und
/// ob eine Fassung entstand.
extension PlanPauseWorkflow on PlanWorkflowService {
  /// Steht die Pause durch die Zusage „alles erfasst“ ohne Frage fest,
  /// startet der Plan beim Öffnen neu (PAR-202), einmal je Pause.
  Future<void> restartIfDue({
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final q = await pauses.pauseRestartDue();
    if (q != null) await _restartForPause(q, events: events);
  }

  /// Antwort auf die Pausenfrage (PAR-202). „Ja“ startet den Plan neu
  /// ([planPauseRestart], Auslöser `pause`), sofern ein Plan besteht und der
  /// Neustart nötig ist; „Nein“ ändert nichts. Die Antwort wird erst nach dem
  /// Schreiben gespeichert: Scheitert der Neustart, bleibt die Frage offen.
  /// Ohne offene Frage: `rejected`.
  Future<void> answerPause(
    bool paused, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final today = _today();
    final q = await pauses.pauseQuestion();
    if (q == null) throw const StorageException(StorageFailure.rejected);
    if (paused) await _restartForPause(q, events: events);
    await WarningState(session.settings).setPauseAnswer(
      PauseAnswer(paused: paused, on: today),
      at: clock.now(),
    );
  }

  /// Neuer Einstieg nach langer Pause (PAR-181, PAR-192): speichert [goal]
  /// (mit dem vom Nutzer genannten Stand) und startet den Plan neu; danach
  /// die Zuordnung (PAR-231). Ohne anstehenden Einstieg oder bei ungültigem
  /// Ziel: `rejected`; ohne Plan: `notFound`. Scheitert nur die
  /// Neuberechnung: [PlanSavedNotPlanned].
  Future<void> restartAfterLongPause(
    TrainingGoal goal, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final q = await pauses.newStartDue();
    if (q == null) throw const StorageException(StorageFailure.rejected);
    if ((await _plans.history()).isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    // Zeitpunkt statt Ortstag: `validate` liest ihn im Ortstag.
    final now = clock.now();
    if (goal.validate(now, null, true) != null) {
      throw const StorageException(StorageFailure.rejected);
    }
    await _goals.save(goal, today: now);
    events.stored();
    try {
      await _restartForPause(q, chosen: true, events: events);
    } on Object {
      throw const PlanSavedNotPlanned();
    }
    await autoAssignQuietly(events: events);
  }

  /// Würde der Plan beim neuen Einstieg nach langer Pause neu beginnen
  /// (PAR-181)? `false` ohne anstehenden Einstieg, ohne Plan, bei einem
  /// Fehler und wenn kein Neustart möglich ist ([planPauseRestart] liefert
  /// nichts).
  Future<bool> newStartPossible() async {
    try {
      final q = await pauses.newStartDue();
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
            inputsBeforeAdjustment: planInputsBeforeAdjustment(history),
            replacesProvisional: await _pauseProvisional(q),
          ).inputs !=
          null;
    } on Object {
      return false;
    }
  }

  /// Eingaben des neuen Einstiegs (PAR-181) mit dem Stand aus [draft] auf
  /// der Grundlage [inputs], für die Einschätzung vor dem Speichern; `null`
  /// ohne anstehenden Einstieg oder wenn kein Neustart möglich ist.
  Future<PlanInputs?> _newStartInputs(
    TrainingGoal draft,
    PlanInputs inputs,
    DateTime today,
  ) async {
    final q = await pauses.newStartDue();
    if (q == null) return null;
    return planPauseRestart(
      goal: draft,
      inputs: inputs,
      today: today,
      lastTrainingDay: q.lastTrainingDay,
      baseWeekMinutes: q.baseWeekMinutes,
      parameters: parameters,
      replacesProvisional: await _pauseProvisional(q),
    ).inputs;
  }

  /// Neustart zur Pause (Auslöser `pause`), einmal je Pause. Ohne Plan oder
  /// Ziel geschieht nichts (kein Merker).
  ///
  /// Ab 8 Wochen ([PlanParameters.pauseNewStartDays]) gilt ohne Wahl
  /// vorläufig die Stufe 2 (sichere Vorgabe, Merker `provisional`); der
  /// Nutzer wählt den Einstieg ([restartAfterLongPause], PAR-181) und ersetzt
  /// sie damit. Mit [chosen] hat der Nutzer den Einstieg gewählt; sein Ziel
  /// mit dem neuen Stand ist schon gespeichert.
  Future<void> _restartForPause(
    PauseQuestion q, {
    bool chosen = false,
    required PlanWorkflowEvents events,
  }) async {
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
      inputsBeforeAdjustment: planInputsBeforeAdjustment(history),
      provisional: longPause && !chosen,
      replacesProvisional: chosen && wasProvisional && mark.restarted,
    );
    final next = restart.inputs;
    if (next == null && chosen) {
      // Kein Neustart möglich: das neue Ziel gilt trotzdem für den Plan.
      events.result(
        await recalculate(
          PlanTrigger.goalChange,
          goal,
          history.last,
          adjust: false,
        ),
      );
    }
    if (next != null) {
      events.result(
        await write(
          // Der gewählte Einstieg ist eine Zieländerung des Nutzers (Stand
          // neu): `goalChange` hält sie fest, sonst bliebe sie ausstehend.
          trigger: chosen ? PlanTrigger.goalChange : PlanTrigger.pause,
          today: today,
          inputs: next,
        ),
      );
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
}
