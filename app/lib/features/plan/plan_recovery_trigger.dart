import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'plan_controller.dart';
import 'plan_data_reader.dart';

/// Auslöser „veränderter Erholungszustand“ (FR-0157, Teil „3 (Erholung)“)
/// für eine Sitzung: nach neuen Gesundheitsdaten aus dem Import und nach
/// einer Morgenmessung prüft [recheck] den Plan für heute
/// ([PlanWorkflowService.recheckRecoveryToday]). Nur bei „adaptiv“ ändert sich etwas
/// (FR-0216); bei „fix“ bleibt der Plan, wie er ist.
///
/// Prüfungen laufen nacheinander in der Schreibreihe des Plans; eine
/// schreibende Fassung meldet [onChanged] (Neuladen der Seiten). Fehler bleiben still (keine Lockerung,
/// fail-closed); Werte erscheinen nie in Fehlern oder Logs.
class PlanRecoveryTrigger {
  PlanRecoveryTrigger({
    required this.session,
    required this.clock,
    required this.readinessToday,
    this.onChanged,
  });

  final StorageSession session;
  final Clock clock;

  /// Readiness von heute für die Regel PAR-173 (`planReadinessSource`).
  final Future<PlanReadinessDay?> Function(DateTime day) readinessToday;

  /// Nach einer geschriebenen Fassung.
  final VoidCallback? onChanged;

  /// Prüft den Plan von heute; `true`, wenn eine Fassung entstand. Die
  /// Prüfung reiht sich in die Schreibreihe der Sitzung ein
  /// ([PlanWriteQueue.of]), gemeinsam mit jedem Plan-Controller: Prüfungen
  /// laufen nacheinander und nie parallel zu einer anderen Planänderung.
  Future<bool> recheck() async {
    if (session is! GoalStorage || session is! PlanStorage) return false;
    final workflow = planWorkflowFor(
      session: session,
      clock: clock,
      reader: PlanDataReader(session: session, clock: clock),
      readinessToday: readinessToday,
    );
    bool written;
    try {
      written = await PlanWriteQueue.of(session).run(
        () async =>
            (await workflow.recheckRecoveryToday())?.wasWritten ?? false,
      );
    } on Object {
      written = false;
    }
    if (written) onChanged?.call();
    return written;
  }
}

/// Stellt den [PlanRecoveryTrigger] der Sitzung den Seiten darunter bereit
/// (Morgenmessung von „Heute“ und „Übersicht“).
class PlanRecoveryScope extends InheritedWidget {
  const PlanRecoveryScope({
    super.key,
    required this.trigger,
    required super.child,
  });

  final PlanRecoveryTrigger trigger;

  /// `null` ohne Scope (z. B. in Widget-Tests ohne Sitzung).
  static PlanRecoveryTrigger? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlanRecoveryScope>()?.trigger;

  @override
  bool updateShouldNotify(PlanRecoveryScope old) => trigger != old.trigger;
}
