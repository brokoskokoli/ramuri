part of 'plan_workflow_service.dart';

/// Einstellungsschlüssel: Ortstag (`JJJJ-MM-TT`) der letzten Antwort auf die
/// Nachfrage nach PAR-200. Fehlt er, zählt die Anlage des Plans.
const String planFeedbackKey = 'plan.feedback_answered_on';

/// Einstellungsschlüssel: letzter Tag (`JJJJ-MM-TT`) der Programmwoche, deren
/// Vorschlag „Woche wiederholen“ der Nutzer abgelehnt hat (PAR-140).
const String planWalkRunRepeatDeclinedKey = 'plan.walk_run_repeat_declined';

/// Ortstag als `JJJJ-MM-TT`.
String planDayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Ortstag aus `JJJJ-MM-TT`; `null` bei leerem oder ungültigem Text.
DateTime? planParseDay(String? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v ?? '');
  if (m == null) return null;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return planDayText(d) == v ? d : null;
}

/// Prüfung eines Ziels vor dem Speichern ([PlanGoalWorkflow.checkGoal]).
class GoalDraftCheck {
  const GoalDraftCheck({required this.assessment, required this.walkRun});

  /// Einschätzung nach PAR-206; [GoalAssessment.fitsFrom] ist das Angebot
  /// eines Datums.
  final GoalAssessment assessment;

  /// Der Plan beginnt mit der Geh-Lauf-Abfolge (PAR-065); vor dem Speichern
  /// steht der Hinweis aus PAR-115.
  final bool walkRun;
}

/// Ziel speichern, ausdrückliche Neuberechnung und die Antworten des Nutzers
/// auf Nachfrage (PAR-200) und „Woche wiederholen“ (PAR-140) als Ablauf des
/// [PlanWorkflowService].
extension PlanGoalWorkflow on PlanWorkflowService {
  /// Auslöser beim Speichern eines Ziels: `goalChange`, wenn schon ein Ziel
  /// mit Fassung besteht, sonst `create`.
  static PlanTrigger _saveTrigger(
    bool goalExisted,
    List<PlanVersionRecord> history,
  ) => goalExisted && history.isNotEmpty
      ? PlanTrigger.goalChange
      : PlanTrigger.create;

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
    var inputs = PlanWorkflowService.inputsFor(
      _saveTrigger(existed, history),
      built,
      last,
    );
    var goal = built.goal;
    if (newStart && last != null) {
      final restart = await _newStartInputs(draft, inputs, today);
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
  /// Fassung, sonst `goalChange`), mit dem gespeicherten Ziel; danach die
  /// Zuordnung (PAR-231: auch ein Lauf vor dem Anlegen des Plans zählt für
  /// die heutige Einheit). Ungültiges Ziel: `rejected` (vom Speicher), nichts
  /// geändert. Scheitert nur die Neuberechnung: [PlanSavedNotPlanned].
  Future<void> saveGoal(
    TrainingGoal goal, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final existed = await _goals.goal() != null;
    // Zeitpunkt statt Ortstag: `validate` liest ihn im Ortstag.
    await _goals.save(goal, today: clock.now());
    events.stored();
    try {
      final saved = await _goals.goal();
      if (saved == null) {
        throw const StorageException(StorageFailure.notFound);
      }
      final history = await _plans.history();
      events.result(
        await recalculate(
          _saveTrigger(existed, history),
          saved,
          history.isEmpty ? null : history.last,
        ),
      );
    } on Object {
      throw const PlanSavedNotPlanned();
    }
    await autoAssignQuietly(events: events);
  }

  /// Ausdrückliche Neuberechnung durch den Nutzer: `manual`; ohne Fassung
  /// `create`, bei ausstehender Zieländerung `goalChange`. Ohne Ziel:
  /// `notFound`.
  Future<void> recalculateManual({
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final goal = await _goals.goal();
    if (goal == null) throw const StorageException(StorageFailure.notFound);
    final history = await _plans.history();
    events.result(
      await recalculate(
        history.isEmpty
            ? PlanTrigger.create
            : (planGoalChangedSince(history.last.summary, goal)
                  ? PlanTrigger.goalChange
                  : PlanTrigger.manual),
        goal,
        history.isEmpty ? null : history.last,
      ),
    );
  }

  /// Antwort auf die Nachfrage (PAR-200). „Passt“ und „zu leicht“ am Regler
  /// ändern den Plan nicht; „zu leicht“ davor und „zu schwer“ legen einen
  /// neuen Anker an (`feedback`). Die Antwort zählt erst, wenn alles
  /// geschrieben ist (sonst bleibt die Nachfrage fällig). Eine offene
  /// Pausenfrage hat Vorrang (PAR-202): `rejected`. Ohne Ziel oder Plan:
  /// `notFound`. Ergebnis: ob das Ziel steigen soll („zu leicht“ am Regler)
  /// und ob eine Fassung geschrieben wurde.
  Future<({bool raiseGoalSignal, bool planChanged})> answerFeedback(
    PlanFeedback answer, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    // Die Karte ist bei offener Pausenfrage nicht mehr gültig (etwa nach
    // Mitternacht bei offener Seite).
    if (await pauseQuestionOpen()) {
      throw const StorageException(StorageFailure.rejected);
    }
    final goal = await _goals.goal();
    if (goal == null) throw const StorageException(StorageFailure.notFound);
    final history = await _plans.history();
    if (history.isEmpty) throw const StorageException(StorageFailure.notFound);
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    final result = applyPlanFeedback(
      goal: goal,
      inputs: PlanWorkflowService.inputsFor(
        PlanTrigger.feedback,
        built,
        history.last,
      ),
      answer: answer,
      today: today,
    );
    var written = false;
    final next = result.inputs;
    if (next != null) {
      final w = await write(
        trigger: PlanTrigger.feedback,
        markChecked: false, // bewertet die Woche (PAR-201) nicht
        today: today,
        inputs: next,
      );
      events.result(w);
      written = w.wasWritten;
    }
    await session.settings.set(
      planFeedbackKey,
      planDayText(today),
      at: clock.now(),
    );
    return (raiseGoalSignal: result.raiseGoalSignal, planChanged: written);
  }

  /// Ist die Nachfrage nach PAR-200 am Ortstag [today] fällig (2 Wochen ab
  /// der letzten Antwort bzw. Anlage des Plans, [planFeedbackDue])? Nicht
  /// unter Warnsignal [warning], ohne Plan und bei offener Pausenfrage
  /// (PAR-202).
  Future<bool> feedbackDue(
    List<PlanVersionRecord> history,
    WarningSignal? warning,
    DateTime today,
  ) async {
    if (warning != null || history.isEmpty) return false;
    return planFeedbackDue(
      created: calendarDay(history.first.createdAt),
      lastAnswer: planParseDay(await session.settings.get(planFeedbackKey)),
      today: today,
      pauseOpen: await pauseQuestionOpen(),
    );
  }

  /// Vorschlag „Woche wiederholen“ in der Geh-Lauf-Phase (PAR-140) für die
  /// Fassung [version] mit ihren Einheiten [units] am Ortstag [today]; nicht
  /// unter Warnsignal [warning] und nicht für eine schon abgelehnte
  /// Programmwoche. Sonst `null`.
  Future<WalkRunWeekProposal?> walkRunProposal(
    PlanVersionRecord? version,
    List<PlanUnit> units,
    WarningSignal? warning,
    DateTime today,
  ) async {
    final walkStart = version?.inputs.walkRunStart;
    if (warning != null || version == null || walkStart == null) return null;
    final declined = planParseDay(
      await session.settings.get(planWalkRunRepeatDeclinedKey),
    );
    final proposal = walkRunWeekProposal(
      units: units,
      start: walkStart,
      from: version.inputs.walkRunFrom,
      rpeByRunId: {
        for (final e in (await session.subjective.readAll()).entries)
          if (e.value.subjective.rpe case final int r) e.key: r,
      },
      today: today,
    );
    return proposal != null && declined == proposal.lastDay ? null : proposal;
  }

  /// Nimmt „Wiederholen“ an (PAR-140): neue Fassung, die Abfolge beginnt ab
  /// heute (nach einem Lauf heute ab morgen) an der Stelle des Vorschlags
  /// [proposal] wieder; vergangene Tage bleiben unverändert. Ohne Vorschlag,
  /// Ziel oder Plan: `notFound`.
  Future<void> acceptWalkRunRepeat(
    WalkRunWeekProposal? proposal, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
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
    events.result(
      await write(
        trigger: PlanTrigger.manual,
        reason: walkRunRepeatReason,
        markChecked: false, // bewertet die Woche nicht
        today: today,
        inputs: inputs,
      ),
    );
  }

  /// Lehnt „Woche wiederholen“ für die Programmwoche von [proposal] ab;
  /// nichts ändert sich am Plan. Ohne Vorschlag geschieht nichts.
  Future<void> declineWalkRunRepeat(WalkRunWeekProposal? proposal) async {
    if (proposal == null) return;
    await session.settings.set(
      planWalkRunRepeatDeclinedKey,
      planDayText(proposal.lastDay),
      at: clock.now(),
    );
  }
}
