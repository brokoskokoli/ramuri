part of 'plan_workflow_service.dart';

/// Was die Plan-Seite aus der gespeicherten Fassung zeigt, ohne zu
/// schreiben: Hinweise mit Konflikten und die Einschätzung des Ziels. Der
/// Aufrufer übernimmt das Ergebnis nur in den Ansichtszustand.
extension PlanViewWorkflow on PlanWorkflowService {
  /// Hinweise zur Fassung [version] für [units] am Ortstag [today]: [fresh]
  /// (Vorschau der letzten Rechnung) oder die gespeicherten aus der
  /// Zusammenfassung, sonst eine Vorschau ([previewPlan]). Abstandskonflikte
  /// kommen immer aus den gespeicherten Einheiten (eine bestätigte
  /// Verschiebung ändert sie ohne neue Fassung); die übrigen Konflikte vor
  /// heute fallen weg. Bei „fix“ zusätzlich der Abstand der nächsten harten
  /// Einheit zu einem intensiven Lauf der Woche (PAR-235, PAR-059). `null`
  /// ohne Ziel oder Fassung und ohne [fresh].
  Future<GeneratedPlan?> planHints({
    required GeneratedPlan? fresh,
    required TrainingGoal? goal,
    required PlanVersionRecord? version,
    required List<PlanUnit> units,
    required DateTime today,
  }) async {
    var hints = fresh;
    if (hints == null && goal != null && version != null) {
      hints =
          planHintsFromSummary(
            version.summary,
            version: version.version,
            units: units,
            today: today,
          ) ??
          previewPlan(
            goal: goal,
            inputs: version.inputs.copyWith(today: today),
            units: units,
            today: today,
            parameters: parameters,
          );
    }
    if (hints == null) return null;
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return hints.copyWith(
      pinnedConflicts: [
        for (final c in hints.pinnedConflicts)
          if (c.kind != PinnedConflictKind.spacing && !c.day.isBefore(today)) c,
        ...planSpacingConflicts(units, today, parameters: parameters),
        if (await _adaptation.read() == PlanAdaptationMode.fixed)
          ...planRunSpacingConflicts(
            units,
            (await reader.intensiveDaysBetween(
              monday.subtract(Duration(days: parameters.minGapDays - 1)),
              today,
            )).toSet(),
            today,
            parameters: parameters,
          ),
      ],
    );
  }

  /// Einschätzung des gespeicherten Ziels [goal] zur Fassung [version]
  /// (PAR-206, [assessGoal]); `null` ohne Ziel oder Fassung oder bei einem
  /// Fehler (die Seite bleibt benutzbar, der Inhalt eines Fehlers wird nie
  /// gezeigt).
  Future<GoalAssessment?> goalAssessment(
    TrainingGoal? goal,
    PlanVersionRecord? version,
    DateTime today,
  ) async {
    if (goal == null || version == null) return null;
    try {
      return assessGoal(
        goal: goal,
        inputs: version.inputs.copyWith(today: today),
        today: today,
        basis: await reader.timeGoalBasis(goal: goal, today: today),
        parameters: parameters,
      );
    } on Object {
      return null;
    }
  }
}
