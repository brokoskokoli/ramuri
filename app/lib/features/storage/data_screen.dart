import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../reminders/reminder_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../../ui/ramuri_card.dart';
import '../archive/archive_export_action.dart';
import '../archive/archive_import_action.dart';
import '../archive/archive_wiring.dart';
import '../export/metrics_csv_action.dart';
import '../map/map_consent_scope.dart';
import '../sensors/sensor_manager.dart';
import '../settings/app_settings.dart';
import 'deletion.dart';

/// Einfacher Bildschirm "Daten" mit "Alles löschen". WP05 kann ihn in die
/// Einstellungen verschieben.
class DataScreen extends StatelessWidget {
  const DataScreen({
    super.key,
    required this.session,
    required this.sensors,
    required this.serialize,
  });

  final StorageSession session;

  /// Sensordienst: nach dem Löschen trennt er Geräte, die nicht mehr bekannt sind.
  final SensorManager sensors;

  /// Reiht den Archiv-Export hinter Aufnahme und Neuberechnung ein
  /// (`RecalculationController.exclusive`).
  final SerializeAction serialize;

  /// Nach dem Löschen gilt sofort der Zustand des ersten Starts: Einstellungen
  /// neu laden und zurück zur Wurzel, wo die Ersteinrichtung erscheint.
  Future<void> _deleteAll(BuildContext context) async {
    final settings = AppSettingsScope.of(context);
    final navigator = Navigator.of(context);
    final reminders = ReminderScope.read(context);
    final result = await confirmAndDeleteAll(
      context,
      session,
      map: MapConsentScope.of(context),
    );
    if (result != DeletionResult.deleted &&
        result != DeletionResult.deletedNotErased) {
      return;
    }
    // FR-0174: Nach dem Löschen keine Erinnerung mehr.
    await reminders?.cancelAll();
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
        padding: const EdgeInsets.all(20),
        children: [
          RamuriCard(child: Text(l10n.dataBody)),
          const SizedBox(height: 16),
          ArchiveExportAction(session: session, serialize: serialize),
          const SizedBox(height: 8),
          ArchiveImportAction(session: session, serialize: serialize),
          const SizedBox(height: 8),
          MetricsCsvAction(session: session),
          const SizedBox(height: 8),
          OutlinedButton(
            style: ramuriDangerOutlinedStyle(context),
            onPressed: () => _deleteAll(context),
            child: Text(l10n.deleteAllConfirm),
          ),
        ],
      ),
    );
  }
}
