import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../error_counter.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../reminders/reminder_controller.dart';
import 'app_version.dart';
import 'belt_compare_screen.dart';
import 'error_counts_section.dart';
import 'morning_pairs_section.dart';
import 'ppg_camera_diagnostics_section.dart';
import 'ppg_camera_section.dart';

/// Seite „Entwicklereinstellungen“ (FR-0217): bündelt alles, was es nur im
/// Entwicklermodus gibt – in dieser Reihenfolge Schalter „Entwicklermodus“,
/// „Kamera für die Pulsmessung“ (FR-0220), „Messpaare“, „Kamera gegen Gurt“
/// „Kamera-Bildverarbeitung (Diagnose)“ und zuletzt „Fehler“ (gezählte Fehler,
/// Diagnose teilen; FR-0223). Erreichbar über die
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
    this.cameraDiagnostics,
    this.appVersion = readAppVersion,
  });

  final DeveloperModeStore developerMode;

  /// Morgenmessungen für „Messpaare“ und „Kamera gegen Gurt“; ohne Speicher
  /// entfallen beide.
  final MorningStore? morning;

  /// Kamera und gespeicherte Kamerawahl für „Kamera für die Pulsmessung“
  /// (FR-0220); fehlt eines, entfällt die Karte.
  final PpgCamera? ppgCamera;
  final PpgCameraChoiceStore? cameraChoice;

  /// Diagnose-Schalter der Kamera-Bildverarbeitung (FR-0217); ohne Angabe
  /// entfällt die Karte.
  final PpgCameraDiagnosticsStore? cameraDiagnostics;

  /// Zeitquelle für den Dateinamen des Exports; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  /// App-Version für den Diagnose-Export (FR-0223).
  final Future<String?> Function() appVersion;

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
    final errors = ErrorCounterScope.maybeOf(context);
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
              const SizedBox(height: 8),
              RamuriCard(
                key: const Key('dev_compare_card'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: BeltCompareSection(store: widget.morning!),
              ),
            ],
            if (widget.cameraDiagnostics != null) ...[
              const SizedBox(height: 8),
              RamuriCard(
                key: const Key('dev_ppg_diag_card'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PpgCameraDiagnosticsSection(
                  store: widget.cameraDiagnostics!,
                ),
              ),
            ],
            if (errors != null) ...[
              const SizedBox(height: 8),
              RamuriCard(
                key: const Key('dev_errors_card'),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ErrorCountsSection(
                  errors: errors,
                  appVersion: widget.appVersion,
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
