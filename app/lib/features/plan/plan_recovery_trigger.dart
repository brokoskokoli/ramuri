import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'plan_controller.dart';

/// Auslöser „veränderter Erholungszustand“ (FR-0157, Teil „3 (Erholung)“)
/// für eine Sitzung: nach neuen Gesundheitsdaten aus dem Import und nach
/// einer Morgenmessung prüft [recheck] den Plan für heute
/// ([PlanController.recheckRecovery]). Nur bei „adaptiv“ ändert sich etwas
/// (FR-0216); bei „fix“ bleibt der Plan, wie er ist.
///
/// Prüfungen laufen nacheinander; eine schreibende Fassung meldet
/// [onChanged] (Neuladen der Seiten). Fehler bleiben still (keine Lockerung,
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

  Future<void> _tail = Future.value();

  /// Prüft den Plan von heute; `true`, wenn eine Fassung entstand.
  Future<bool> recheck() {
    final run = _tail.then((_) async {
      if (session is! GoalStorage || session is! PlanStorage) return false;
      final plan = PlanController(
        session: session,
        clock: clock,
        readinessToday: readinessToday,
      );
      try {
        return await plan.recheckRecovery();
      } on Object {
        return false;
      } finally {
        plan.dispose();
      }
    });
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run.then((written) {
      if (written) onChanged?.call();
      return written;
    });
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
