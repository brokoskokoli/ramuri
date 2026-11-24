import 'package:flutter/material.dart';

import '../../error_counter.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../export/diagnostics_export_action.dart';

/// Abschnitt „Fehler“ der Entwicklereinstellungen (FR-0223): die lokal
/// gezählten Fehler je Typ und Ort mit Anzahl, erstem und letztem Tag,
/// sortiert nach Anzahl absteigend; „Zähler zurücksetzen“ mit Rückfrage und
/// „Diagnose teilen“. Zeigt nie Nachrichten, Werte oder Stacks.
class ErrorCountsSection extends StatefulWidget {
  const ErrorCountsSection({
    super.key,
    required this.errors,
    required this.appVersion,
    this.clock,
  });

  final ErrorCounter errors;
  final Future<String?> Function() appVersion;

  /// Zeitquelle für den Dateinamen des Exports; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  @override
  State<ErrorCountsSection> createState() => _ErrorCountsSectionState();
}

class _ErrorCountsSectionState extends State<ErrorCountsSection> {
  late Future<List<ErrorCount>?> _entries = _load();

  Future<List<ErrorCount>?> _load() async {
    try {
      return sortErrorCounts(await widget.errors.read());
    } on Object {
      return null;
    }
  }

  Future<void> _reset() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ResetDialog(),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.errors.reset();
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.devErrorsResetFailed)),
      );
    }
    if (!mounted) return;
    final entries = _load();
    setState(() {
      _entries = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final muted = theme.bodySmall!.copyWith(color: c.textMuted);
    return Padding(
      key: const Key('dev_errors'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.devErrorsTitle, style: theme.titleSmall),
          const SizedBox(height: 4),
          FutureBuilder<List<ErrorCount>?>(
            future: _entries,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox.shrink();
              }
              final entries = snap.data;
              if (entries == null) {
                return Text(
                  l10n.devErrorsLoadFailed,
                  key: const Key('dev_errors_failed'),
                  style: muted,
                );
              }
              if (entries.isEmpty) {
                return Text(
                  l10n.devErrorsEmpty,
                  key: const Key('dev_errors_empty'),
                  style: muted,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, e) in entries.indexed)
                    Padding(
                      key: Key('dev_errors_entry_$i'),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.type, style: theme.bodyMedium),
                          Text(e.place, style: muted),
                          Text(
                            l10n.devErrorsEntry(
                              e.count,
                              e.firstDay ?? '–',
                              e.lastDay ?? '–',
                            ),
                            style: muted,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          RamuriSecondaryButton(
            key: const Key('dev_errors_reset'),
            onPressed: _reset,
            label: l10n.devErrorsReset,
          ),
          const SizedBox(height: 8),
          DiagnosticsExportAction(
            errors: widget.errors,
            appVersion: widget.appVersion,
            clock: widget.clock,
          ),
        ],
      ),
    );
  }
}

class _ResetDialog extends StatelessWidget {
  const _ResetDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('dev_errors_reset_dialog'),
      title: Text(l10n.devErrorsResetTitle),
      content: Text(l10n.devErrorsResetBody),
      actions: [
        TextButton(
          key: const Key('dev_errors_reset_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.exportCancel),
        ),
        FilledButton(
          key: const Key('dev_errors_reset_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.devErrorsResetConfirm),
        ),
      ],
    );
  }
}
