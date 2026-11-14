import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../measure/morning_entry.dart';
import '../../l10n/app_localizations.dart';
import '../profile/profile_screen.dart';
import '../recalculation/recalculation_controller.dart';
import '../measure/morning_belt.dart';
import '../sensors/sensor_manager.dart';
import '../sensors/sensors_screen.dart';
import '../settings/about_screen.dart';
import '../settings/app_version.dart';
import '../settings/permissions_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/zones_screen.dart';
import '../storage/data_screen.dart';

/// Übersicht hinter dem Profil-Symbol auf Heute (FR-0208): Profil,
/// Einstellungen, Sensoren, Zonen, Berechtigungen, Daten und Über (Name, Version, Lizenzen, Entwicklermodus).
///
/// Sensoren, Zonen, Berechtigungen und Daten sind während einer
/// Neuberechnung gesperrt: Sie könnten Werte ändern oder löschen (Sperre,
/// FR-0006). Die Einstellungen, in denen die Neuberechnung läuft, lassen sich
/// dabei nicht verlassen; die Sperre hier ist die zweite Absicherung.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.permissions,
    required this.recalculation,
    required this.sensors,
    this.appVersion = readAppVersion,
  });

  final StorageSession session;
  final Clock clock;
  final PermissionStatusPort permissions;
  final RecalculationController recalculation;
  final SensorManager sensors;

  /// Quelle der Versionsangabe auf „Über“ (Tests setzen eine feste).
  final Future<String?> Function() appVersion;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  /// Zählt die Rückkehr von einer Unterseite: Der Entwicklermodus (Über)
  /// ändert, ob der Eintrag Morgenmessung da ist, also lädt er neu.
  int _returns = 0;

  StorageSession get session => widget.session;
  Clock get clock => widget.clock;
  PermissionStatusPort get permissions => widget.permissions;
  RecalculationController get recalculation => widget.recalculation;
  SensorManager get sensors => widget.sensors;
  Future<String?> Function() get appVersion => widget.appVersion;

  Future<void> _open(BuildContext context, WidgetBuilder builder) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: builder));
    if (mounted) setState(() => _returns++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.overviewTitle)),
      body: ListenableBuilder(
        listenable: recalculation,
        builder: (context, _) {
          final busy = recalculation.busy;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Entry(
                key: const Key('home_profile'),
                icon: Icons.person_outline_rounded,
                label: l10n.homeProfile,
                onTap: () => _open(
                  context,
                  (_) => ProfileScreen(
                    session: session,
                    clock: clock,
                    recalculation: recalculation,
                  ),
                ),
              ),
              MorningTile(
                key: ValueKey(_returns),
                session: session,
                clock: clock,
                beltFactory: () =>
                    MorningBelt.of(sensors, session.settings, clock),
              ),
              _Entry(
                key: const Key('home_settings'),
                icon: Icons.settings_outlined,
                label: l10n.homeSettings,
                onTap: () => _open(
                  context,
                  (_) => SettingsScreen(
                    session: session,
                    recalculation: recalculation,
                    clock: clock,
                  ),
                ),
              ),
              _Entry(
                key: const Key('overview_sensors'),
                icon: Icons.monitor_heart_outlined,
                label: l10n.settingsSensors,
                onTap: busy
                    ? null
                    : () => _open(
                        context,
                        (_) => SensorsScreen(manager: sensors),
                      ),
              ),
              _Entry(
                key: const Key('overview_zones'),
                icon: Icons.stacked_bar_chart_rounded,
                label: l10n.settingsZones,
                onTap: busy
                    ? null
                    : () => _open(context, (_) => const ZonesScreen()),
              ),
              _Entry(
                key: const Key('overview_permissions'),
                icon: Icons.shield_outlined,
                label: l10n.settingsPermissions,
                onTap: busy
                    ? null
                    : () => _open(
                        context,
                        (_) => PermissionsScreen(permissions: permissions),
                      ),
              ),
              _Entry(
                key: const Key('overview_data'),
                icon: Icons.storage_outlined,
                label: l10n.dataTitle,
                onTap: busy
                    ? null
                    : () => _open(
                        context,
                        (_) => DataScreen(
                          session: session,
                          sensors: sensors,
                          serialize: recalculation.exclusive,
                        ),
                      ),
              ),
              _Entry(
                key: const Key('overview_about'),
                icon: Icons.info_outline_rounded,
                label: l10n.overviewAbout,
                onTap: () => _open(
                  context,
                  (_) => AboutScreen(
                    developerMode: SettingsDeveloperModeStore(
                      session.settings,
                      clock,
                    ),
                    appVersion: appVersion,
                    morning: session is MorningStorage
                        ? (session as MorningStorage).morning
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    enabled: onTap != null,
    onTap: onTap,
  );
}
