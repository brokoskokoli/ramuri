import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../profile/profile_screen.dart';
import '../settings/app_settings.dart';
import '../settings/settings_screen.dart';

/// Startbildschirm. Gebaut wird er erst, wenn der Speicher bereit ist
/// ([session] ist die offene Sitzung) und die Ersteinrichtung erledigt oder
/// übersprungen ist.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

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
            // Die Aufzeichnung kommt mit einem späteren Paket; der Zugang
            // ist ohne Profil und ohne Freigaben offen (FR-0001, CON-0007).
            FilledButton(
              key: const Key('home_start_run'),
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l10n.homeStartRunSoon))),
              child: Text(l10n.homeStartRun),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('home_profile'),
              onPressed: () => AppSettingsScope.push<void>(
                context,
                (_) => ProfileScreen(session: session, clock: clock),
              ),
              child: Text(l10n.homeProfile),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('home_settings'),
              onPressed: () => AppSettingsScope.push<void>(
                context,
                (_) => SettingsScreen(session: session),
              ),
              child: Text(l10n.homeSettings),
            ),
          ],
        ),
      ),
    );
  }
}
