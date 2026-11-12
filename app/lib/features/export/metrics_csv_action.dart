import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import 'file_handoff_scope.dart';

/// Schaltfläche „Zusatzmetriken exportieren (CSV)“ im Daten-Bildschirm
/// (FR-0184, `docs/contracts/metrics-csv.md`). Erst das Tippen auf „Teilen“
/// oder „Speichern“ erzeugt und übergibt die Datei (FR-0201). Meldungen
/// enthalten weder Werte noch Pfade.
class MetricsCsvAction extends StatefulWidget {
  const MetricsCsvAction({super.key, required this.session, this.clock});

  final StorageSession session;

  /// Zeitquelle für den Dateinamen; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  @override
  State<MetricsCsvAction> createState() => _MetricsCsvActionState();
}

class _MetricsCsvActionState extends State<MetricsCsvAction> {
  bool _busy = false;

  Future<void> _open(FileHandoff handoff) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final share = await showDialog<bool>(
      context: context,
      builder: (_) => const _MetricsDialog(),
    );
    if (share == null || !mounted) return;
    setState(() => _busy = true);
    FileHandoffResult result;
    try {
      final file = await buildMetricsCsvFile(
        widget.session,
        now: (widget.clock ?? DateTime.now)(),
      );
      result = share ? await handoff.share(file) : await handoff.save(file);
    } on Object {
      // Keine Gesundheitsdaten und keine Pfade in Meldungen.
      result = FileHandoffResult.failed;
    }
    if (mounted) setState(() => _busy = false);
    final message = switch (result) {
      FileHandoffResult.completed =>
        share ? l10n.exportShared : l10n.exportSaved,
      FileHandoffResult.cancelled => null,
      FileHandoffResult.failed => l10n.exportFailed,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final handoff = FileHandoffScope.of(context);
    if (handoff == null) return const SizedBox.shrink();
    return RamuriSecondaryButton(
      key: const Key('metrics_export'),
      onPressed: _busy ? null : () => _open(handoff),
      label: AppLocalizations.of(context).metricsExportAction,
    );
  }
}

class _MetricsDialog extends StatelessWidget {
  const _MetricsDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('metrics_dialog'),
      title: Text(l10n.metricsExportTitle),
      content: Text(l10n.metricsExportIntro),
      actions: [
        TextButton(
          key: const Key('metrics_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exportCancel),
        ),
        TextButton(
          key: const Key('metrics_save'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.exportSave),
        ),
        FilledButton(
          key: const Key('metrics_share'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.exportShare),
        ),
      ],
    );
  }
}
