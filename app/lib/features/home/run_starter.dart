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
/// Merker und Zuordnung nach dem Lauf (PAR-231).
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

  /// Lauf starten: frei ([unit] `null`) oder für die geplante Einheit. Die
  /// Seite „Lauf vorbereiten“ bietet die offene Einheit von heute zur Führung
  /// an (WP24); „Einheit starten“ wählt sie vor, „Frei laufen“ nicht.
  ///
  /// „Einheit starten“ merkt die Einheit vorher in `settings`
  /// ([PlanStartedUnitStore]); so überlebt sie Absturz und Wiederaufnahme.
  /// Nach dem Schließen wird ein beendeter Lauf ihr zugeordnet, eingereiht
  /// hinter die Wertberechnung des Laufs (auch wenn „Fertig“ vor deren Ende
  /// getippt wurde). „Frei laufen“ löscht den Merker; ist am Starttag eine
  /// Einheit offen, zählt der Lauf ohne Rückfrage als sie (PAR-231).
  /// Termine ändern sich nie. Die Datenmeldung folgt erst nach der Zuordnung.
  Future<void> start(BuildContext context, {PlanUnit? unit}) async {
    final day = _today;
    // Die Einheit kann auf „Lauf vorbereiten“ noch gewechselt werden.
    var unitId = unit?.id;
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
    // Die offene Einheit von heute für den Umschalter auf „Lauf vorbereiten“
    // (bei „Frei laufen“ ist sie wählbar, aber nicht gemerkt).
    PlanUnit? planned = unit;
    if (planned == null) {
      try {
        planned = await openPlanUnitOn(session, day);
      } on Object {
        planned = null;
      }
    }
    if (!context.mounted) return;
    // Die Hülle baut „Heute“ bei jeder Datenmeldung neu (neuer Zustand); der
    // Hinweis nach dem Lauf braucht darum Navigator und
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
          plannedUnit: planned,
          startPlanned: unit != null,
          onGuidanceChosen: (chosen) async {
            unitId = chosen?.id;
            if (chosen?.id != null) {
              await started.remember(chosen!.id!, day);
            } else {
              await started.forget();
            }
          },
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
      }
      if (finishedId != null && result != PlanActionResult.failed) {
        final auto = await _autoAssign(day);
        if (result == null || auto == PlanActionResult.failed) result = auto;
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

  /// Nach jedem beendeten Lauf (PAR-231): Läufe zählen ohne Rückfrage für
  /// die offene Einheit ihres Ortstags, ab dem Sonntag der Vorwoche oder dem
  /// früheren Starttag [day] (Lauf über Mitternacht). Eingereiht hinter die
  /// Wertberechnung des Laufs wie die Zuordnung nach „Einheit starten“.
  Future<PlanActionResult> _autoAssign(String day) =>
      recalculation.exclusive(() async {
        final plan = PlanController(session: session, clock: clock);
        try {
          return await plan.autoAssignRuns(
            since: DateTime.parse('${day}T00:00:00Z'),
          );
        } finally {
          plan.dispose();
        }
      });

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
