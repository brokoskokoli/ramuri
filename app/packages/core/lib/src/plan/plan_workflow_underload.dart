part of 'plan_workflow_service.dart';

/// Unterforderung (PAR-236) als Ablauf des [PlanWorkflowService]: Schritt
/// beim Öffnen, Sperre und Antworten. Ändert den Plan nur nach „Ja,
/// steigern“.
extension PlanUnderloadWorkflow on PlanWorkflowService {
  /// Gespeicherter Zustand der Unterforderung.
  Future<PlanUnderloadState> underloadState() async => PlanUnderloadState.parse(
    await session.settings.get(planUnderloadStageKey),
    await session.settings.get(planUnderloadSinceKey),
  );

  Future<void> _saveUnderload(PlanUnderloadState state) async {
    final now = clock.now();
    await session.settings.set(planUnderloadStageKey, state.stageText, at: now);
    final since = state.sinceText;
    if (since != null) {
      await session.settings.set(planUnderloadSinceKey, since, at: now);
    }
  }

  /// Offener Hinweis bzw. offene Frage für die Seite: der gespeicherte
  /// Zustand, außer die Sperre ([underloadBlocked]) gilt; `null` ohne Plan.
  Future<PlanUnderloadPrompt?> underloadPrompt(
    List<PlanVersionRecord> history,
    WarningSignal? warning,
  ) async {
    if (history.isEmpty) return null;
    final prompt = (await underloadState()).prompt;
    if (prompt == null || await underloadBlocked(history, warning)) {
      return null;
    }
    return prompt;
  }

  /// Weder Hinweis noch Frage: bei „fix“ (FR-0216), bei einem gemeldeten
  /// Warnsignal (FR-0203), wenn PAR-201 in dieser Woche nach unten
  /// korrigiert hat, oder wenn die Readiness von heute in einem Band nach
  /// PAR-173 liegt. Ein Fehler beim Lesen sperrt (fail-closed).
  Future<bool> underloadBlocked(
    List<PlanVersionRecord> history,
    WarningSignal? warning,
  ) async {
    if (await _adaptation.read() != PlanAdaptationMode.adaptive) return true;
    if (warning != null) return true;
    final today = _today();
    if (planCorrectedDownThisWeek(history, today)) return true;
    // Anders als die Lockerung ([PlanWorkflowService.readinessOn])
    // unterscheidet die Sperre „kein Wert“ (nicht gesperrt) von „Fehler“
    // (gesperrt).
    final load = readinessToday;
    if (load == null) return false;
    try {
      final r = await load(today);
      return r != null && planDay(r.day) == today && r.eases;
    } on Object {
      return true;
    }
  }

  /// Wie [advanceUnderload]; ein Fehler bleibt still: Ohne lesbaren Stand
  /// bleibt die Stufe, das nächste Öffnen prüft neu.
  Future<void> advanceUnderloadQuietly() async {
    try {
      await advanceUnderload();
    } on Object {
      // Siehe oben.
    }
  }

  /// Schritt beim Öffnen: Muster aus den Läufen nach der letzten Stufe bzw.
  /// nach der letzten Änderung der wirksamen HFmax, auch der genäherten zum
  /// Jahreswechsel ([planUnderloadCountFrom]); erstes Muster → Hinweis,
  /// erneutes → Frage ([planUnderloadAdvance]). Ändert den Plan nicht.
  Future<void> advanceUnderload() async {
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    if (history.isEmpty) return;
    final state = await underloadState();
    final changed = DateTime.tryParse(
      await session.settings.get(profileHrMaxChangedAtKey) ?? '',
    )?.toUtc();
    // Genäherte HFmax (FR-0004): Der Jahreswechsel zählt als Änderung, wenn
    // die Näherung damit einen anderen Wert ergibt; abgeleitet, nicht
    // gespeichert.
    final yearStart = estimatedMaxHeartRateChangedAt(
      await session.profile.read(),
      now: clock.now(),
    );
    final runs = await reader.underloadRuns(
      planUnderloadCountFrom(state, changed, estimatedChangedAt: yearStart),
    );
    final pattern = planUnderloadPattern(runs, parameters: parameters);
    if (!pattern) return;
    // Sperre erst nach dem Muster prüfen: ohne Muster liest das Öffnen keine
    // Readiness (FR-0158, Wochenprüfung nur wenn fällig).
    final blocked = await underloadBlocked(history, await _warning?.read());
    var canRaise = false;
    if (state.stage != PlanUnderloadStage.none) {
      canRaise = await _underloadRaise(goal, history.last, _today()) != null;
    }
    final next = planUnderloadAdvance(
      state: state,
      pattern: pattern,
      blocked: blocked,
      canRaise: canRaise,
      now: clock.now(),
    );
    if (next != null) await _saveUnderload(next);
  }

  Future<PlanInputs?> _underloadRaise(
    TrainingGoal goal,
    PlanVersionRecord last,
    DateTime today,
  ) async {
    final built = await reader.read(goal: goal, today: today);
    return applyPlanUnderloadRaise(
      goal: goal,
      inputs: PlanWorkflowService.inputsFor(PlanTrigger.feedback, built, last),
      today: today,
      parameters: parameters,
    );
  }

  /// Antwort auf den Hinweis „HFmax prüfen“ bzw. „Passt so“: Der Hinweis
  /// erscheint nicht wieder; die Zählung für die Frage läuft ab dem Hinweis
  /// weiter. Ohne offenen Hinweis: `rejected`.
  Future<void> answerUnderloadHint() async {
    final state = await underloadState();
    if (state.stage != PlanUnderloadStage.hint) {
      throw const StorageException(StorageFailure.rejected);
    }
    await _saveUnderload(
      PlanUnderloadState(
        stage: PlanUnderloadStage.hintDone,
        since: state.since,
      ),
    );
  }

  /// Antwort auf „Plan etwas steigern?“. „Ja, steigern“: einmalig ein
  /// zusätzlicher Schritt nach PAR-193 ([applyPlanUnderloadRaise]), neue
  /// Fassung mit Auslöser `feedback` und Grund `underload`; die Sperre
  /// ([underloadBlocked]) gilt erneut. „Nein“: keine Änderung. Die Antwort
  /// wird erst nach dem Schreiben gespeichert; danach zählen nur Läufe nach
  /// der Antwort. Ohne offene Frage, unter der Sperre oder ohne mögliche
  /// Steigerung: `rejected`; ohne Ziel oder Plan: `notFound`.
  Future<void> answerUnderloadQuestion(
    bool raise, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final state = await underloadState();
    if (state.stage != PlanUnderloadStage.question) {
      throw const StorageException(StorageFailure.rejected);
    }
    if (raise) {
      final goal = await _goals.goal();
      if (goal == null) throw const StorageException(StorageFailure.notFound);
      final history = await _plans.history();
      if (history.isEmpty) {
        throw const StorageException(StorageFailure.notFound);
      }
      if (await underloadBlocked(history, await _warning?.read())) {
        throw const StorageException(StorageFailure.rejected);
      }
      final today = _today();
      final next = await _underloadRaise(goal, history.last, today);
      if (next == null) throw const StorageException(StorageFailure.rejected);
      events.result(
        await write(
          trigger: PlanTrigger.feedback,
          reason: planReasonUnderload,
          markChecked: false, // bewertet die Woche (PAR-201) nicht
          today: today,
          inputs: next,
        ),
      );
    }
    await _saveUnderload(
      PlanUnderloadState(
        stage: raise
            ? PlanUnderloadStage.accepted
            : PlanUnderloadStage.declined,
        since: clock.now().toUtc(),
      ),
    );
  }
}
