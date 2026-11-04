import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../storage/data_screen.dart';

/// Startbildschirm. Gebaut wird er erst, wenn der Speicher bereit ist
/// ([session] ist die offene Sitzung).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session});

  final StorageSession session;

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
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DataScreen(session: session),
                ),
              ),
              child: Text(l10n.dataTitle),
            ),
          ],
        ),
      ),
    );
  }
}
