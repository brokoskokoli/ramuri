import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../sensors/sensor_manager.dart';
import '../sensors/sensors_screen.dart';
import '../storage/data_screen.dart';
import 'app_settings.dart';
import 'permissions_screen.dart';
import 'zones_screen.dart';

/// Einstellungen: Einheit für Strecken (reine Anzeige) und der Zugang zu den
/// gespeicherten Daten.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.session,
    required this.permissions,
    required this.sensors,
  });

  final StorageSession session;
  final PermissionStatusPort permissions;
  final SensorManager sensors;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = AppSettingsScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.settingsUnits,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<DistanceUnit>(
            key: const Key('settings_unit'),
            segments: [
              ButtonSegment(
                value: DistanceUnit.kilometers,
                label: Text(l10n.settingsUnitKm),
              ),
              ButtonSegment(
                value: DistanceUnit.miles,
                label: Text(l10n.settingsUnitMi),
              ),
            ],
            selected: {settings.distanceUnit},
            onSelectionChanged: (s) => _change(context, settings, s.first),
          ),
          const SizedBox(height: 8),
          Text(l10n.settingsUnitNote),
          const SizedBox(height: 24),
          OutlinedButton(
            key: const Key('settings_permissions'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => PermissionsScreen(permissions: permissions),
              ),
            ),
            child: Text(l10n.settingsPermissions),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('settings_sensors'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => SensorsScreen(manager: sensors),
              ),
            ),
            child: Text(l10n.settingsSensors),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('settings_zones'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ZonesScreen()),
            ),
            child: Text(l10n.settingsZones),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => DataScreen(session: session, sensors: sensors),
              ),
            ),
            child: Text(l10n.dataTitle),
          ),
        ],
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    AppSettings settings,
    DistanceUnit unit,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await settings.setDistanceUnit(unit);
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
