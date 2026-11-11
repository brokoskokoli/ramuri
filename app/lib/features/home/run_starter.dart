import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../plan/plan_controller.dart';
import '../plan/plan_started_unit.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../sensors/sensor_manager.dart';
import 'data_changes.dart';

/// Startet einen Lauf aus „Heute“ („Frei laufen“, „Einheit starten“) oder
/// von der Plan-Seite („Start“ an der heutigen Einheit): ein Weg mit
/// Merker, Zuordnung nach dem Lauf und Nachfrage nach „Frei laufen“.
class RunStarter {
  const RunStarter({
    required this.session,
    required this.clock,
    required this.permissions,
    required this.recalculation,
    required this.runPorts,
    required this.sensors,
    required this.changes,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final RunPorts runPorts;
  final SensorManager sensors;
  final Clock clock;
  final RecalculationController recalculation;
  final DataChanges changes;

  /// Heutiger Ortstag nach dem Versatz der Uhr (wie in der Statistik).
  String get _today {
    final now = clock.now().toUtc();
    return isoDay(now.add(clock.utcOffsetAt(now)));
  }

  /// Lauf starten: frei ([unit] `null`) oder für die geplante Einheit. Der
  /// Lauf ist vorerst der normale Lauf (die Führung kommt mit WP24).
  ///
  /// „Einheit starten“ merkt die Einheit vorher in `settings`
  /// ([PlanStartedUnitStore]); so überlebt sie Absturz und Wiederaufnahme.
  /// Nach dem Schließen wird ein beendeter Lauf ihr zugeordnet, eingereiht
  /// hinter die Wertberechnung des Laufs (auch wenn „Fertig“ vor deren Ende
  /// getippt wurde). „Frei laufen“ löscht den Merker; ist am Starttag eine
  /// Einheit offen, fragt die App nach dem Ende, ob der Lauf zu ihr zählt.
  /// Termine ändern sich nie. Die Datenmeldung folgt erst nach der Zuordnung.
  Future<void> start(BuildContext context, {PlanUnit? unit}) async {
    final day = _today;
    final unitId = unit?.id;
    final started = PlanStartedUnitStore(session: session, clock: clock);
    try {
      if (unitId != null) {
        await started.remember(unitId, day);
      } else {
        await started.forget();
      }
    } on Object {
      // Ohne Merker ordnet nur der normale Weg zu (nach dem Schließen).
    }
    if (!context.mounted) return;
    // Die Hülle baut „Heute“ bei jeder Datenmeldung neu (neuer Zustand); die
    // Nachfrage und der Hinweis nach dem Lauf brauchen darum Navigator und
    // Messenger der App, nicht diesen Zustand.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    int? finishedId;
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => RunFlowScreen(
          session: session,
          clock: clock,
          ports: runPorts,
          permissions: permissions,
          serialize: recalculation.exclusive,
          sensors: sensors,
          recalculation: recalculation,
          onFinished: (runId) => finishedId = runId,
        ),
      ),
    );
    PlanActionResult? result;
    try {
      if (unitId != null) {
        result = await started.settle(
          serialize: recalculation.exclusive,
          runId: finishedId,
          forgetWithoutRun: true,
        );
      } else if (finishedId != null) {
        result = await _askFreeRun(navigator, finishedId!, day);
      }
    } on Object {
      result = PlanActionResult.failed;
    }
    // Scheitert nur die Neuberechnung, ist der Lauf trotzdem zugeordnet.
    var assigned = false;
    if (result == PlanActionResult.failed) {
      try {
        assigned = await planRunAssignedOn(session, day, finishedId);
      } on Object {
        assigned = false;
      }
    }
    if (result != null && navigator.mounted) {
      _showAssignResult(
        navigator.context,
        messenger,
        result,
        assigned: assigned,
      );
    }
    changes.changed();
  }

  /// Nach „Frei laufen“: Ist am Ortstag [day] eine Einheit offen, fragt die
  /// App, ob der Lauf zu ihr zählt (Entscheidung des Maintainers
  /// 2026-11-10). Ja ordnet zu, Nein lässt die Einheit offen. `null`: keine
  /// Frage oder Nein.
  Future<PlanActionResult?> _askFreeRun(
    NavigatorState navigator,
    int runId,
    String day,
  ) async {
    final unit = await openPlanUnitOn(session, day);
    if (unit == null || !navigator.mounted) return null;
    final yes = await showDialog<bool>(
      context: navigator.context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          key: const Key('home_assign_ask'),
          title: Text(
            l.planTodayAskTitle,
            key: const Key('home_assign_ask_title'),
          ),
          content: Text(l.planTodayAskBody),
          actions: [
            TextButton(
              key: const Key('home_assign_no'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.planTodayAskNo),
            ),
            FilledButton(
              key: const Key('home_assign_yes'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.planTodayAskYes),
            ),
          ],
        );
      },
    );
    if (yes != true) return null;
    return recalculation.exclusive(
      () => assignRunToUnit(
        session: session,
        clock: clock,
        unitId: unit.id!,
        day: day,
        runId: runId,
      ),
    );
  }

  /// Ein Fehlschlag der Zuordnung bleibt nicht stumm: Der Lauf ist
  /// gespeichert, die Einheit bleibt offen (kein Fehlerinhalt nach außen).
  /// Ist der Lauf zugeordnet ([assigned]) und nur die Neuberechnung
  /// gescheitert, sagt der Hinweis genau das.
  static void _showAssignResult(
    BuildContext context,
    ScaffoldMessengerState messenger,
    PlanActionResult result, {
    bool assigned = false,
  }) {
    if (result == PlanActionResult.done ||
        result == PlanActionResult.savedNotPlanned) {
      return;
    }
    final l = AppLocalizations.of(context);
    messenger.showSnackBar(
      assigned
          ? SnackBar(
              key: const Key('home_assign_not_recalculated'),
              content: Text(l.planTodayAssignNotRecalculated),
            )
          : SnackBar(
              key: const Key('home_assign_failed'),
              content: Text(l.planTodayAssignFailed),
            ),
    );
  }
}
