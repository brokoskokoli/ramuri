import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../sensors/sensor_manager.dart';
import 'data_changes.dart';
import 'overview_screen.dart';

/// Bereich „Heute“ in der Hülle ([AppShell]). Gebaut wird er erst, wenn der
/// Speicher bereit ist ([session] ist die offene Sitzung) und die
/// Ersteinrichtung erledigt oder übersprungen ist. Vorläufig nur der
/// Startknopf und das Profil-Symbol; den Inhalt baut WP14 Teil C2.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
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

  /// Legt [page] über die Hülle (Root-Navigator, Vollbild) und meldet danach
  /// mögliche Änderungen der Daten.
  Future<void> _push(BuildContext context, WidgetBuilder page) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: page));
    changes.changed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('home_screen'),
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            key: const Key('home_overview'),
            tooltip: l10n.homeOverview,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _push(
              context,
              (_) => OverviewScreen(
                session: session,
                clock: clock,
                permissions: permissions,
                recalculation: recalculation,
                sensors: sensors,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        // Der Zugang ist ohne Profil und ohne Freigaben offen (FR-0001,
        // CON-0007); nur der Standort wird geprüft (FR-0195).
        child: FilledButton(
          key: const Key('home_start_run'),
          onPressed: () => _push(
            context,
            (_) => RunFlowScreen(
              session: session,
              clock: clock,
              ports: runPorts,
              permissions: permissions,
              serialize: recalculation.exclusive,
            ),
          ),
          child: Text(l10n.homeStartRun),
        ),
      ),
    );
  }
}
