import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import 'deletion.dart';

/// Einfacher Bildschirm "Daten" mit "Alles löschen". WP05 kann ihn in die
/// Einstellungen verschieben.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key, required this.session, required this.sensors});

  final StorageSession session;

  /// Sensordienst: nach dem Löschen trennt er Geräte, die nicht mehr bekannt sind.
  final SensorManager sensors;

  /// Nach dem Löschen gilt sofort der Zustand des ersten Starts: Einstellungen
  /// neu laden und zurück zur Wurzel, wo die Ersteinrichtung erscheint.
  Future<void> _deleteAll(BuildContext context) async {
    final settings = AppSettingsScope.of(context);
    final navigator = Navigator.of(context);
    final result = await confirmAndDeleteAll(context, session);
    if (result != DeletionResult.deleted &&
        result != DeletionResult.deletedNotErased) {
      return;
    }
    try {
      await sensors.reloadKnown();
    } on Object {
      // Der Gerätespeicher ist nicht lesbar: die Einstellungen kommen trotzdem.
    }
    try {
      await settings.reload();
    } on StorageException {
      // Lesen schlägt fehl: die Seite bleibt, der Stand wird beim nächsten
      // Start neu geladen.
      return;
    }
    navigator.popUntil((r) => r.isFirst);
  }

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
            onPressed: () => _deleteAll(context),
            child: Text(l10n.deleteAllConfirm),
          ),
        ],
      ),
    );
  }
}
