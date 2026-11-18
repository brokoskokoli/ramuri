import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../reminders/reminder_controller.dart';
import 'morning_pairs_section.dart';
import 'ppg_camera_section.dart';

/// Seite „Entwicklereinstellungen“ (FR-0217): bündelt alles, was es nur im
/// Entwicklermodus gibt – in dieser Reihenfolge Schalter „Entwicklermodus“,
/// „Kamera für die Pulsmessung“ (FR-0220) und „Messpaare“. Erreichbar über die
/// Übersicht (nur bei eingeschaltetem Modus) und den Verweis auf „Über“.
///
/// Schaltet man den Modus hier aus, schließt sich die Seite; wer sie geöffnet
/// hat, liest den Modus beim Zurückkehren neu.
class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({
    super.key,
    required this.developerMode,
    this.morning,
    this.clock,
    this.ppgCamera,
    this.cameraChoice,
  });

  final DeveloperModeStore developerMode;

  /// Morgenmessungen für „Messpaare“; ohne Speicher entfällt der Teil.
  final MorningStore? morning;

  /// Kamera und gespeicherte Kamerawahl für „Kamera für die Pulsmessung“
  /// (FR-0220); fehlt eines, entfällt die Karte.
  final PpgCamera? ppgCamera;
  final PpgCameraChoiceStore? cameraChoice;

  /// Zeitquelle für den Dateinamen des Exports; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  @override
  State<DeveloperSettingsScreen> createState() =>
      _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  /// `null`, bis der Modus gelesen ist.
  bool? _on;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = await widget.developerMode.read();
    if (!mounted) return;
    setState(() => _on = on);
  }

  Future<void> _off(bool value) async {
    if (value) return;
    final reminders = ReminderScope.read(context);
    final navigator = Navigator.of(context);
    await widget.developerMode.set(false);
    // Ohne Erreichbarkeit der Morgenmessung gilt keine Morgen-Erinnerung mehr
    // (FR-0217): eine geplante wird sofort gestrichen.
    try {
      await reminders?.syncMorning();
    } on Object {
      // Die nächste Synchronisierung holt es nach.
    }
    if (!mounted) return;
    setState(() => _on = false);
    await navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final on = _on == true;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (on) ...[
            RamuriCard(
              key: const Key('about_dev_section'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SwitchListTile(
                key: const Key('about_dev_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.devSwitchTitle),
                subtitle: Text(
                  l10n.devSwitchBody,
                  style: theme.bodySmall!.copyWith(color: c.textMuted),
                ),
                value: on,
                onChanged: _off,
              ),
            ),
            if (widget.ppgCamera != null && widget.cameraChoice != null) ...[
              const SizedBox(height: 8),
              RamuriCard(
                key: const Key('about_ppg_camera_card'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PpgCameraSection(
                  camera: widget.ppgCamera!,
                  choice: widget.cameraChoice!,
                ),
              ),
            ],
            if (widget.morning != null) ...[
              const SizedBox(height: 8),
              RamuriCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MorningPairsSection(
                  store: widget.morning!,
                  clock: widget.clock,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
