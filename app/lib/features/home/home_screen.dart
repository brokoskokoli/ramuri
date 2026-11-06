import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../history/history_screen.dart';
import '../profile/profile_screen.dart';
import '../recalculation/recalculation_controller.dart';
import '../run/run_flow_screen.dart';
import '../run/run_ports.dart';
import '../settings/settings_screen.dart';

/// Startbildschirm. Gebaut wird er erst, wenn der Speicher bereit ist
/// ([session] ist die offene Sitzung) und die Ersteinrichtung erledigt oder
/// übersprungen ist.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
    required this.recalculation,
    required this.runPorts,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final RunPorts runPorts;
  final Clock clock;
  final RecalculationController recalculation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.homeWelcome),
            const SizedBox(height: 16),
            // Der Zugang ist ohne Profil und ohne Freigaben offen (FR-0001,
            // CON-0007); nur der Standort wird geprüft (FR-0195).
            FilledButton(
              key: const Key('home_start_run'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RunFlowScreen(
                    session: session,
                    clock: clock,
                    ports: runPorts,
                    permissions: permissions,
                    serialize: recalculation.exclusive,
                  ),
                ),
              ),
              child: Text(l10n.homeStartRun),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('home_history'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => HistoryScreen(
                    session: session,
                    clock: clock,
                    recalculation: recalculation,
                  ),
                ),
              ),
              child: Text(l10n.homeHistory),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('home_profile'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    session: session,
                    clock: clock,
                    recalculation: recalculation,
                  ),
                ),
              ),
              child: Text(l10n.homeProfile),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('home_settings'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    session: session,
                    permissions: permissions,
                    recalculation: recalculation,
                  ),
                ),
              ),
              child: Text(l10n.homeSettings),
            ),
          ],
        ),
      ),
    );
  }
}
