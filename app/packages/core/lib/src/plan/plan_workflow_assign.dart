part of 'plan_workflow_service.dart';

/// Zuordnung von Läufen zu Einheiten (PAR-231, PAR-233) als Ablauf des
/// [PlanWorkflowService]. Jede Zuordnung rechnet den Plan neu (Auslöser
/// `run`, bei ausstehender Zieländerung `goalChange`); Termine ändern sich
/// dabei nie.
extension PlanAssignWorkflow on PlanWorkflowService {
  /// Ordnet der Einheit [unitId] den Lauf [runId] zu (`null` hebt die
  /// Zuordnung auf) und rechnet danach ab heute neu (die Zuordnung zählt für
  /// „locker“, PAR-205, und friert die Einheit ein). Fehlt die Einheit:
  /// `notFound`. [expectedRunId] ist der Lauf, den die Einheit in der Ansicht
  /// des Aufrufers trug (`null`: offen gesehen; beim Aufheben der bisher
  /// zugeordnete Lauf). Trägt sie beim Schreiben einen anderen (veraltet,
  /// etwa nach einer automatischen Zuordnung), oder sperrt PAR-233 die
  /// Sporteinheit: nichts geschrieben, `rejected`.
  Future<void> assignRun(
    int unitId,
    int? runId, {
    required int? expectedRunId,
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final unit = await _unitById(unitId);
    if (unit == null) throw const StorageException(StorageFailure.notFound);
    if (!await _assignAndRecalculate(
      unitId,
      runId,
      expectedRunId: expectedRunId,
      events: events,
    )) {
      throw const StorageException(StorageFailure.rejected);
    }
  }

  /// Zuordnung über „Einheit starten“ ([PlanStartedUnit]): wie [assignRun];
  /// hat eine Neuberechnung die gemerkte Einheit ersetzt (`notFound`), gilt
  /// die offene Einheit (kein Ruhetag, ohne Lauf) desselben Ortstags [day]
  /// (`JJJJ-MM-TT`). Beide Einheiten hat der Aufrufer als offen gesehen bzw.
  /// geprüft: erwartet wird kein Lauf.
  Future<void> assignStartedRun({
    required int unitId,
    required String day,
    required int runId,
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    try {
      await assignRun(unitId, runId, expectedRunId: null, events: events);
    } on StorageException catch (e) {
      if (e.failure != StorageFailure.notFound) rethrow;
      final unit = await _plans.unitOn(DateTime.parse('${day}T00:00:00Z'));
      final id = unit?.id;
      if (unit == null ||
          id == null ||
          id == unitId ||
          unit.kind == PlanUnitKind.rest ||
          unit.runId != null) {
        rethrow;
      }
      await assignRun(id, runId, expectedRunId: null, events: events);
    }
  }

  /// Ordnet beendete Läufe den offenen Einheiten ihres Ortstags zu (PAR-231,
  /// [planAutoAssignments]): Einheiten vom Sonntag der Vorwoche (oder dem
  /// früheren Tag [since], etwa dem Starttag eines Laufs über Mitternacht)
  /// bis heute. Jede Zuordnung rechnet wie [assignRun] neu; gibt es nichts
  /// zuzuordnen, ändert sich nichts und es wird nicht gerechnet. Gibt die
  /// Zahl der geschriebenen Zuordnungen zurück.
  Future<int> autoAssign({
    DateTime? since,
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final today = _today();
    final from = planAutoAssignFrom(today, since: since);
    // Jede Zuordnung rechnet neu und kann Einheiten ab heute ersetzen (neue
    // Kennung): darum nach jeder Zuordnung neu lesen. Jede Runde füllt eine
    // offene Einheit; mehr Runden als Einheiten gibt es nicht.
    var rounds = 0;
    var assigned = 0;
    while (true) {
      final units = await _plans.unitsBetween(
        DateTime.utc(2000),
        planFarFuture,
      );
      if (rounds++ > units.length) return assigned;
      final overviews = await session.preprocessing.readOverviews();
      // Läufe ab dem Start über „Einheit starten“ ordnet der Merker zu
      // (auch der Nachholversuch nach einer gescheiterten Neuberechnung);
      // erst danach zählen sie hier.
      final started = PlanStartedUnit.decode(
        await session.settings.get(SettingKeys.planStartedUnit),
      );
      final runs = [
        for (final r in await session.runs.list())
          if (started == null || r.startedAt.isBefore(started.since))
            ?PlanRunCandidate.of(
              r,
              movingTime: overviews[r.id]?.summary.movingTime,
            ),
      ];
      final next = planAutoAssignments(
        units: units,
        runs: runs,
        today: today,
        from: from,
      ).firstOrNull;
      if (next == null) return assigned;
      // Die Einheit war beim Lesen offen; trägt sie inzwischen einen Lauf
      // (veraltet), liest die nächste Runde neu.
      if (await _assignAndRecalculate(
        next.unitId,
        next.runId,
        expectedRunId: null,
        events: events,
      )) {
        assigned++;
      }
    }
  }

  /// Wie [autoAssign]; ein Fehler bleibt still (das nächste Öffnen holt die
  /// Zuordnung nach), dann 0.
  Future<int> autoAssignQuietly({
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    try {
      return await autoAssign(events: events);
    } on Object {
      return 0;
    }
  }

  /// Verschiebt die Einheit nach Bestätigung des Nutzers auf [day] (setzt
  /// `pinned`, OQ-0011), mit „heute“; keine Neuberechnung. Danach zählt ein
  /// Lauf am neuen Tag für die verschobene Einheit (PAR-231).
  Future<void> confirmMove(
    int unitId,
    DateTime day, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    await _plans.confirmMove(unitId, day, today: _today());
    events.stored();
    await autoAssignQuietly(events: events);
  }

  /// Darf die Sporteinheit [runId] (FR-0221) die Einheit [unit] ersetzen
  /// (PAR-233, [planSportReplacementBlock])? `null`: ja; sonst der Grund.
  /// Ohne Plan oder ohne offene Einheit: [SportReplacementBlock.noEasyUnit].
  /// Liest Puls, RPE und Zeit ab 80 % HFmax der Einheit; nie loggen.
  Future<SportReplacementBlock?> sportReplacementBlock(
    PlanUnit? unit,
    int runId,
  ) async {
    final sport = await reader.sportFigures(runId);
    if (sport == null) return SportReplacementBlock.noEasyUnit;
    if (unit == null || unit.runId != null && unit.runId != runId) {
      return SportReplacementBlock.noEasyUnit;
    }
    final units = await _plans.unitsBetween(DateTime.utc(2000), planFarFuture);
    final sportIds = <int>{
      for (final r in await session.runs.list())
        if (!r.mode.isRunning) r.id,
    };
    double? highHr;
    for (final v in await session.values.read(ValueOwner.run(runId))) {
      if (v.current.key == highHeartRateTimeValueKey) highHr = v.current.value;
    }
    final percents = await ReserveZoneSettings.load(session.settings);
    return planSportReplacementBlock(
      unit: unit,
      sport: sport,
      units: units,
      sportRunIds: sportIds,
      rpe: (await session.subjective.read(runId))?.subjective.rpe,
      highHrMinutes: highHr,
      heartRate: resolveHeartRate(
        await session.profile.read(),
        currentYear: clock.now().year,
      ).basis,
      zoneBounds: [for (final p in percents) p / 100],
      parameters: parameters,
    );
  }

  Future<PlanUnit?> _unitById(int unitId) async {
    for (final u in await _plans.unitsBetween(
      DateTime.utc(2000),
      planFarFuture,
    )) {
      if (u.id == unitId) return u;
    }
    return null;
  }

  /// Schreibt die Zuordnung, wenn die Einheit noch [expectedRunId] trägt, und
  /// rechnet neu; `false` (veraltet): nichts geschrieben, nicht gerechnet.
  Future<bool> _assignAndRecalculate(
    int unitId,
    int? runId, {
    required int? expectedRunId,
    required PlanWorkflowEvents events,
  }) async {
    // Eine andere Sportart ersetzt nur eine lockere Einheit nach PAR-233.
    if (runId != null &&
        !((await session.runs.get(runId))?.mode.isRunning ?? true)) {
      if (await sportReplacementBlock(await _unitById(unitId), runId) != null) {
        throw const StorageException(StorageFailure.rejected);
      }
    }
    final written = await _plans.assignRun(
      unitId,
      runId,
      expectedRunId: expectedRunId,
    );
    if (written == PlanAssignResult.stale) return false;
    events.stored();
    final goal = await _goals.goal();
    if (goal == null) return true;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final goalChanged =
        last != null && planGoalChangedSince(last.summary, goal);
    events.result(
      await recalculate(
        goalChanged ? PlanTrigger.goalChange : PlanTrigger.run,
        goal,
        last,
        // `run` bewertet die Woche nicht: Der Prüftag bleibt, sonst fiele die
        // Bewertung der Vorwoche weg (Lauf über Mitternacht in den Montag).
        // `goalChange` bewertet bei Fälligkeit selbst.
        markChecked: goalChanged,
      ),
    );
    return true;
  }
}

/// Erster Tag des Zuordnungsfensters (PAR-231) am Ortstag [today]: der
/// Sonntag der Vorwoche, damit ein Sonntagslauf, dessen Zuordnung nach dem
/// Lauf ausblieb (Absturz, Fehler, Lauf über Mitternacht), beim Öffnen am
/// Montag oder später noch zählt; ein früherer Tag [since] (Starttag eines
/// Laufs über Mitternacht) erweitert das Fenster, ein späterer nicht.
DateTime planAutoAssignFrom(DateTime today, {DateTime? since}) {
  final t = planDay(today);
  final sunday = t.subtract(Duration(days: t.weekday));
  final s = since == null ? null : planDay(since);
  return s != null && s.isBefore(sunday) ? s : sunday;
}
