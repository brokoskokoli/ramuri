import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../sensors/sensor_manager.dart';
import '../sensors/sensors_screen.dart';
import 'resting_widgets.dart';

/// Gurtzeile oben im Einstieg der Morgenmessung (Design `morgen/Main`):
/// „verbunden: Name“, „verbinde …“ oder „kein Gurt“. Ohne Gurt führt
/// „Gurt verbinden“ in die Geräteauswahl der Sensorverwaltung und danach
/// zurück in den Einstieg. Die Messung geht auch ohne Gurt.
class MorningBeltRow extends StatelessWidget {
  const MorningBeltRow({super.key, required this.manager});

  final SensorManager manager;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final live = [
          for (final e in manager.knownEntries)
            if (e.state == SensorLinkState.connected) e,
        ];
        final connected = manager.connectedIds.isNotEmpty;
        final connecting =
            !connected &&
            (manager.autoConnecting ||
                manager.knownEntries.any(
                  (e) =>
                      e.state == SensorLinkState.connecting ||
                      e.state == SensorLinkState.reconnecting,
                ));
        final name = live.isEmpty ? null : live.first.name;
        final text = connected
            ? (name == null || name.isEmpty
                  ? l10n.morningGurtConnectedNoName
                  : l10n.morningGurtConnected(name))
            : connecting
            ? l10n.morningGurtConnecting
            : l10n.morningGurtNone;
        final note = connected
            ? null
            : connecting
            ? l10n.morningGurtNoteConnecting
            : l10n.morningGurtNoteNone;
        return RestingCard(
          radius: 24,
          child: Column(
            key: const Key('morning_gurt'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c.tint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.monitor_heart_outlined,
                        size: 20,
                        color: connected ? c.action : c.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.morningGurtLabel,
                          style: theme.labelSmall!.copyWith(color: c.textMuted),
                        ),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            text,
                            key: const Key('morning_gurt_text'),
                            style: theme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!connected && !connecting)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: OutlinedButton(
                        key: const Key('morning_gurt_pick'),
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => SensorsScreen(manager: manager),
                          ),
                        ),
                        child: Text(l10n.morningGurtPick),
                      ),
                    ),
                ],
              ),
              if (note != null) ...[
                const SizedBox(height: 8),
                Text(
                  note,
                  key: const Key('morning_gurt_note'),
                  style: theme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
