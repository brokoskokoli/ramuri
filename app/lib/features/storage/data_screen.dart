import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'deletion.dart';

/// Einfacher Bildschirm "Daten" mit "Alles löschen". WP05 kann ihn in die
/// Einstellungen verschieben.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key, required this.session});

  final StorageSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dataTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.dataBody),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => confirmAndDeleteAll(context, session),
            child: Text(l10n.deleteAllConfirm),
          ),
        ],
      ),
    );
  }
}
