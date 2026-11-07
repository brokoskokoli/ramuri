import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../offload_scope.dart';
import 'file_handoff_scope.dart';

/// Wohin die Datei geht: Teilen-Menü oder System-Dokumentenziel (FR-0201).
enum ExportTarget { share, save }

/// Export eines beendeten Laufs aus dem Lauf-Detail (FR-0182, FR-0201,
/// WP11): Formatwahl, Ziel, Fortschritt und Ergebnis. Erst das Tippen auf
/// „Teilen“ oder „Speichern“ erzeugt und übergibt die Datei; Abbildung und
/// Kodierung rechnen über den [OffloadScope] (in der App ein eigener
/// Isolate). Meldungen enthalten keine Messwerte und keine Pfade.
class RunExportAction extends StatefulWidget {
  const RunExportAction({
    super.key,
    required this.session,
    required this.runId,
  });

  final StorageSession session;
  final int runId;

  @override
  State<RunExportAction> createState() => _RunExportActionState();
}

class _RunExportActionState extends State<RunExportAction> {
  /// Nur beendete Läufe sind exportierbar; Lesefehler blenden die Aktion aus.
  late final Future<bool> _exportable = _isFinished();
  bool _busy = false;

  Future<bool> _isFinished() async {
    try {
      final run = await widget.session.runs.get(widget.runId);
      return run != null &&
          run.state == RunState.finished &&
          run.endedAt != null;
    } on Object {
      return false;
    }
  }

  Future<void> _export(FileHandoff handoff) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final offload = OffloadScope.of(context);
    final choice = await showDialog<(ExportFormat, ExportTarget)>(
      context: context,
      builder: (_) => const ExportDialog(),
    );
    if (choice == null || !mounted) return;
    final (format, target) = choice;
    setState(() => _busy = true);
    FileHandoffResult result;
    try {
      final file = await RunFileExportService(
        session: widget.session,
        offload: offload,
      ).build(widget.runId, format);
      result = file == null
          ? FileHandoffResult.failed
          : await switch (target) {
              ExportTarget.share => handoff.share(file),
              ExportTarget.save => handoff.save(file),
            };
    } on Object {
      // Keine Gesundheitsdaten und keine Pfade in Meldungen.
      result = FileHandoffResult.failed;
    }
    if (mounted) setState(() => _busy = false);
    final message = switch ((result, target)) {
      (FileHandoffResult.completed, ExportTarget.share) => l10n.exportShared,
      (FileHandoffResult.completed, ExportTarget.save) => l10n.exportSaved,
      // Abbruch durch den Nutzer: still.
      (FileHandoffResult.cancelled, _) => null,
      (FileHandoffResult.failed, _) => l10n.exportFailed,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final handoff = FileHandoffScope.of(context);
    if (handoff == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<bool>(
      future: _exportable,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        if (_busy) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                key: const Key('export_progress'),
                strokeWidth: 2,
                semanticsLabel: l10n.exportRunning,
              ),
            ),
          );
        }
        return IconButton(
          key: const Key('detail_export'),
          tooltip: l10n.exportAction,
          icon: const Icon(Icons.share_outlined),
          onPressed: () => _export(handoff),
        );
      },
    );
  }
}

/// Formatwahl (GPX, TCX, FIT) und Ziel. Liefert die Wahl oder `null` bei
/// Abbruch; nur „Teilen“ und „Speichern“ lösen etwas aus.
class ExportDialog extends StatefulWidget {
  const ExportDialog({super.key});

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  ExportFormat _format = ExportFormat.gpx;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.exportTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.exportFormat),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            key: const Key('export_format'),
            segments: [
              for (final f in ExportFormat.values)
                ButtonSegment(
                  value: f,
                  // Formatnamen sind Eigennamen, in jeder Sprache gleich.
                  label: Text(
                    f.extension.toUpperCase(),
                    key: Key('export_format_${f.name}'),
                  ),
                ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.single),
          ),
          const SizedBox(height: 12),
          Text(l10n.exportHint),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('export_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exportCancel),
        ),
        TextButton(
          key: const Key('export_save'),
          onPressed: () =>
              Navigator.of(context).pop((_format, ExportTarget.save)),
          child: Text(l10n.exportSave),
        ),
        FilledButton(
          key: const Key('export_share'),
          onPressed: () =>
              Navigator.of(context).pop((_format, ExportTarget.share)),
          child: Text(l10n.exportShare),
        ),
      ],
    );
  }
}
