part of 'plan_workflow_service.dart';

/// Änderungen einzelner Einheiten nach Bestätigung des Nutzers (FR-0173,
/// FR-0176, FR-0177) als Ablauf des [PlanWorkflowService]: Prüfung vor der
/// Bestätigung und das Schreiben danach. Keine Neuberechnung; Ziel und
/// Eingaben stammen aus der neuesten Fassung, „heute“ ist der Ortstag der
/// [PlanWorkflowService.clock].
extension PlanEditWorkflow on PlanWorkflowService {
  /// Ortstag der frühesten gespeicherten Planeinheit vor [before] über alle
  /// Fassungen, `null` ohne solche Einheit: untere Blättergrenze des
  /// Kalenders (FR-0172). Liest nur die Einheiten vor [before].
  Future<DateTime?> firstUnitDayBefore(DateTime before) async {
    final units = await _plans.unitsBetween(
      DateTime.utc(2000),
      planDay(before).subtract(const Duration(days: 1)),
    );
    DateTime? first;
    for (final u in units) {
      final d = planDay(u.day);
      if (first == null || d.isBefore(first)) first = d;
    }
    return first;
  }

  /// Anker der Wochenzählung und Länge der Geh-Lauf-Abfolge (PAR-192), wie
  /// sie der Wochenverlauf des Plans nutzt ([planCourseSetup] aus dem
  /// gespeicherten Ziel und den Eingaben der letzten Fassung). Für den
  /// Hinweis auf die Reduktion beim Verschieben ([checkPlanMove], FR-0177).
  /// `null` ohne Ziel oder Fassung.
  Future<({DateTime anchor, int walkRunWeeks})?> courseWeeks() async {
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) return null;
    final inputs = history.last.inputs;
    return (
      anchor: inputs.anchor,
      walkRunWeeks: planCourseSetup(
        goal,
        inputs,
        parameters: parameters,
      ).walkRunWeeks,
    );
  }

  /// Prüft vor der Bestätigung, ob [unit] die Art [kind] bekommen kann
  /// ([checkPlanReplace] mit Ziel und Eingaben der neuesten Fassung, Einheiten
  /// und absolvierten intensiven Läufen um die Woche, „heute“). `null` ohne
  /// Ziel oder Fassung.
  Future<PlanReplaceCheck?> checkReplace(PlanUnit unit, PlanUnitKind kind) =>
      _replaceCheck(unit, kind, _today());

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
  Future<PlanRestDayCheck?> checkRestDay(DateTime day) async {
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
  }

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
      intensive: await reader.intensiveDaysBetween(from, to),
    );
  }

  /// Ersetzt die Art der Einheit nach Bestätigung des Nutzers durch [kind]
  /// (FR-0173, `fixed = kind`): Dauer, Abschnitte und Zielintensität rechnet
  /// [checkPlanReplace] mit „heute“ neu, wie beim Bestätigen gezeigt. Keine
  /// Neuberechnung (wie [PlanAssignWorkflow.confirmMove]). Fehlt die
  /// Einheit, das Ziel oder die Fassung: `notFound`; sperrt die Prüfung
  /// (eingefroren, vergangen, Geh-Lauf, Art passt nicht in die maximale
  /// Zeit, …): `rejected`.
  Future<void> replaceUnit(
    int unitId,
    PlanUnitKind kind, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    final today = _today();
    final history = await _plans.history();
    if (history.isEmpty) throw const StorageException(StorageFailure.notFound);
    final unit = (await _plans.unitsBetween(
      history.last.inputs.anchor,
      planFarFuture,
    )).where((u) => u.id == unitId).firstOrNull;
    if (unit == null) throw const StorageException(StorageFailure.notFound);
    final check = await _replaceCheck(unit, kind, today);
    if (check == null) throw const StorageException(StorageFailure.notFound);
    if (!check.allowed) throw const StorageException(StorageFailure.rejected);
    await _plans.replaceUnit(unitId, check.unit!, today: today);
    events.stored();
  }

  /// Legt [day] nach Bestätigung als Ruhetag fest ([planRestDayUnit] mit Ziel
  /// und Eingaben der neuesten Fassung). Eine Einheit auf dem Tag geht auf
  /// [moveUnitTo] (gewählter Alternativtag aus [checkRestDay]) oder entfällt
  /// ohne ihn. [expectedUnitId] ist die Einheit, die [checkRestDay] auf dem
  /// Tag gezeigt hat (`null`: Tag frei); liegt jetzt eine andere dort, ändert
  /// sich nichts (FR-0176). Keine Neuberechnung. Ohne Ziel oder Fassung:
  /// `notFound`; Tag vor heute, Einheit mit Lauf, schon festgelegter
  /// Ruhetag, abweichende Einheit, ungültiger Zieltag: `rejected`.
  Future<void> setRestDay(
    DateTime day, {
    required int? expectedUnitId,
    DateTime? moveUnitTo,
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
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
    events.stored();
  }

  /// Hebt den Ruhetag an [day] nach Bestätigung auf; die App plant dort erst
  /// bei der nächsten Neuberechnung wieder (OQ-0011). Kein Ruhetag:
  /// `notFound`; Tag vor heute: `rejected`.
  Future<void> clearRestDay(
    DateTime day, {
    PlanWorkflowEvents events = PlanWorkflowEvents.none,
  }) async {
    await _plans.clearRestDay(day, today: _today());
    events.stored();
  }
}
