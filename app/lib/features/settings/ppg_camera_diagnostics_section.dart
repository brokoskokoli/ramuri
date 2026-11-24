import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Karte „Kamera-Bildverarbeitung (Diagnose)“ auf den Entwicklereinstellungen
/// (FR-0217, nur Entwicklermodus): fünf Diagnose-Schalter, Vorgabe jeweils aus,
/// darunter der Hinweis. Sie wirken nur auf die Morgenmessung im
/// Entwicklermodus ([morningCameraDiagnostics]) und nur, soweit die Kamera sie
/// anbietet (ADR-0011). Geräteeinstellung wie die Kamerawahl.
class PpgCameraDiagnosticsSection extends StatefulWidget {
  const PpgCameraDiagnosticsSection({super.key, required this.store});

  final PpgCameraDiagnosticsStore store;

  /// Schlüssel eines Schalters (Tests, E2E).
  static Key switchKey(PpgCameraDiagnostic d) => Key('dev_ppg_diag_${d.wire}');

  @override
  State<PpgCameraDiagnosticsSection> createState() =>
      _PpgCameraDiagnosticsSectionState();
}

class _PpgCameraDiagnosticsSectionState
    extends State<PpgCameraDiagnosticsSection> {
  /// `null`, bis die Schalter gelesen sind.
  Set<PpgCameraDiagnostic>? _on;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Set<PpgCameraDiagnostic> on;
    try {
      on = await widget.store.read();
    } catch (_) {
      on = const {}; // Nicht lesbar: wie die Vorgabe (alle aus).
    }
    if (!mounted) return;
    setState(() => _on = on);
  }

  /// Speichert den Schalter. Scheitert das Speichern, erscheint
  /// `settingsSaveFailed` (ohne Werte, SEC-0009) und der Schalter zeigt
  /// weiter den gespeicherten Stand.
  Future<void> _set(PpgCameraDiagnostic d, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await widget.store.set(d, on: value);
    } on StorageException {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    if (!mounted) return;
    setState(
      () => _on = {...?_on}
        ..remove(d)
        ..addAll([if (value) d]),
    );
  }

  String _title(AppLocalizations l10n, PpgCameraDiagnostic d) => switch (d) {
    PpgCameraDiagnostic.noiseReductionOff => l10n.devDiagNoiseReductionOff,
    PpgCameraDiagnostic.edgeOff => l10n.devDiagEdgeOff,
    PpgCameraDiagnostic.awbFixed => l10n.devDiagAwbFixed,
    PpgCameraDiagnostic.tonemapLinear => l10n.devDiagTonemapLinear,
    PpgCameraDiagnostic.shadingOff => l10n.devDiagShadingOff,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final on = _on;
    return Column(
      key: const Key('dev_ppg_diag'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(l10n.devDiagTitle, style: theme.titleMedium),
        ),
        for (final d in PpgCameraDiagnostic.values)
          SwitchListTile(
            key: PpgCameraDiagnosticsSection.switchKey(d),
            contentPadding: EdgeInsets.zero,
            title: Text(_title(l10n, d)),
            value: on?.contains(d) ?? false,
            onChanged: on == null ? null : (v) => _set(d, v),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            l10n.devDiagHint,
            style: theme.bodySmall!.copyWith(color: c.textMuted),
          ),
        ),
      ],
    );
  }
}
