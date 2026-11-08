import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/ramuri_colors.dart';
import '../../ui/section_heading.dart';
import 'sensor_manager.dart';

/// Sensorverwaltung (FR-0011 bis FR-0016): suchen, verbinden, trennen,
/// bekannte Geräte, Bevorzugung, Puls und Batterie. Beim Öffnen wird nichts
/// vom Sensor angefragt; Rechte folgen erst bei „Geräte suchen“ oder
/// „Verbinden“.
class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.manager});

  final SensorManager manager;

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  @override
  void initState() {
    super.initState();
    // Stand aus dem Speicher; Sensor und Rechte bleiben unberührt.
    widget.manager.reloadKnown().catchError((Object _) {});
  }

  @override
  void dispose() {
    widget.manager.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final m = widget.manager;
    final c = RamuriColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sensorsTitle)),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) {
          final known = m.knownEntries;
          final found = m.foundEntries;
          final problem = switch (m.problem) {
            SensorProblem.permissionDenied => l10n.sensorsProblemPermission,
            SensorProblem.bluetoothUnavailable => l10n.sensorsProblemBluetooth,
            SensorProblem.connectFailed => l10n.sensorsProblemConnect,
            null => null,
          };
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(l10n.sensorsIntro),
              if (problem != null) ...[
                const SizedBox(height: 12),
                RamuriCard(
                  key: const Key('sensors_problem'),
                  child: Text(problem, style: TextStyle(color: c.danger)),
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: RamuriPrimaryButton(
                  key: const Key('sensors_scan'),
                  onPressed: m.scanning ? m.stopScan : m.startScan,
                  label: m.scanning
                      ? l10n.sensorsStopSearch
                      : l10n.sensorsSearch,
                ),
              ),
              if (m.scanning) ...[
                const SizedBox(height: 8),
                Text(l10n.sensorsSearching),
              ],
              const SizedBox(height: 16),
              SectionHeading(l10n.sensorsKnown),
              const SizedBox(height: 8),
              if (known.isEmpty) Text(l10n.sensorsNoneKnown),
              for (final e in known) _DeviceTile(entry: e, manager: m),
              if (m.scanning || found.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionHeading(l10n.sensorsFound),
                const SizedBox(height: 8),
                if (found.isEmpty) Text(l10n.sensorsNoneFound),
                for (final e in found) _DeviceTile(entry: e, manager: m),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.entry, required this.manager});

  final SensorEntry entry;
  final SensorManager manager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final e = entry;
    final state = switch (e.state) {
      SensorLinkState.idle => l10n.sensorsStateIdle,
      SensorLinkState.connecting => l10n.sensorsStateConnecting,
      SensorLinkState.connected => l10n.sensorsStateConnected,
      SensorLinkState.reconnecting => l10n.sensorsStateReconnecting,
    };
    final active = e.state != SensorLinkState.idle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RamuriCard(
        key: Key('sensor_${e.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.name ?? l10n.sensorsUnnamed,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(state),
            if (e.state == SensorLinkState.connected)
              Text(
                e.bpm == null ? l10n.sensorsNoValue : l10n.sensorsBpm(e.bpm!),
                key: Key('sensor_bpm_${e.id}'),
              ),
            // Nur ein gemeldeter Stand wird angezeigt (FR-0016).
            if (e.batteryPercent != null)
              Text(
                l10n.sensorsBattery(e.batteryPercent!),
                key: Key('sensor_battery_${e.id}'),
              ),
            if (e.preferred) Text(l10n.sensorsPreferred),
            Wrap(
              spacing: 8,
              children: [
                active
                    ? RamuriSecondaryButton(
                        key: Key('sensor_disconnect_${e.id}'),
                        onPressed: () => manager.disconnect(e.id),
                        label: l10n.sensorsDisconnect,
                      )
                    : RamuriPrimaryButton(
                        key: Key('sensor_connect_${e.id}'),
                        onPressed: () => manager.connect(e.id, name: e.name),
                        label: l10n.sensorsConnect,
                      ),
                if (e.known)
                  TextButton(
                    key: Key('sensor_prefer_${e.id}'),
                    onPressed: () =>
                        manager.setPreferred(e.preferred ? null : e.id),
                    child: Text(
                      e.preferred
                          ? l10n.sensorsClearPreferred
                          : l10n.sensorsMakePreferred,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
