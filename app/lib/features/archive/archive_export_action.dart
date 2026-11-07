import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../export/file_handoff_scope.dart';
import 'archive_scope.dart';
import 'archive_wiring.dart';

/// Ziel der Archivdatei: Teilen-Menü oder System-Dokumentenziel (FR-0201).
enum ArchiveTarget { share, save }

/// Wie der Dialog endete. Der Aufrufer zeigt die Meldung.
enum ArchiveExportOutcome { shared, saved, failed, cancelled, runActive }

/// Schaltfläche „Archiv exportieren“ im Daten-Bildschirm (FR-0192, SEC-0011,
/// WP12). Ein offener Lauf (aktiv, pausiert oder unterbrochen) sperrt den
/// Export; während des Exports bleiben Aufnahme und Neuberechnung
/// ausgeschlossen ([serialize]). Meldungen enthalten weder Inhalte noch Pfade
/// noch das Passwort.
class ArchiveExportAction extends StatelessWidget {
  const ArchiveExportAction({
    super.key,
    required this.session,
    required this.serialize,
  });

  final StorageSession session;

  /// In der App `RecalculationController.exclusive`.
  final SerializeAction serialize;

  Future<void> _open(
    BuildContext context,
    ArchiveExportFactory factory,
    FileHandoff handoff,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await showDialog<ArchiveExportOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveExportDialog(
        session: session,
        runner: factory(session),
        handoff: handoff,
        serialize: serialize,
      ),
    );
    final message = switch (outcome) {
      ArchiveExportOutcome.shared => l10n.archiveExportShared,
      ArchiveExportOutcome.saved => l10n.archiveExportSaved,
      ArchiveExportOutcome.failed => l10n.archiveExportFailed,
      ArchiveExportOutcome.cancelled => l10n.archiveExportCancelled,
      ArchiveExportOutcome.runActive => l10n.archiveExportRunActive,
      null => null,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final factory = ArchiveScope.exportOf(context);
    final handoff = FileHandoffScope.of(context);
    if (factory == null || handoff == null) return const SizedBox.shrink();
    return OutlinedButton(
      key: const Key('archive_export'),
      onPressed: () => _open(context, factory, handoff),
      child: Text(AppLocalizations.of(context).archiveExportAction),
    );
  }
}

/// Passwort zweimal, Hinweis zum vergessenen Passwort, dann Fortschritt und
/// Übergabe. Das Passwort steht nur so lange im Eingabefeld, bis der Export
/// beginnt; Autofill, Vorschläge und Lernen der Tastatur sind aus.
class ArchiveExportDialog extends StatefulWidget {
  const ArchiveExportDialog({
    super.key,
    required this.session,
    required this.runner,
    required this.handoff,
    required this.serialize,
  });

  final StorageSession session;
  final ArchiveExportRunner runner;
  final FileHandoff handoff;
  final SerializeAction serialize;

  @override
  State<ArchiveExportDialog> createState() => _ArchiveExportDialogState();
}

class _ArchiveExportDialogState extends State<ArchiveExportDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  ArchivePasswordCheck? _problem;
  bool _failed = false;
  bool _working = false;
  ArchiveCancel? _cancel;

  @override
  void dispose() {
    _password.clear();
    _repeat.clear();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _start(ArchiveTarget target) async {
    if (_working) return;
    final check = checkArchivePassword(_password.text, _repeat.text);
    if (check != ArchivePasswordCheck.ok) {
      setState(() {
        _problem = check;
        _failed = false;
      });
      return;
    }
    // Das Passwort wandert in eine lokale Variable; die Felder werden sofort
    // geleert, damit es nicht länger als nötig im Controller bleibt.
    final password = _password.text;
    _password.clear();
    _repeat.clear();
    final cancel = ArchiveCancel();
    setState(() {
      _problem = null;
      _failed = false;
      _working = true;
      _cancel = cancel;
    });
    final outcome = await _run(password, target, cancel);
    if (!mounted) return;
    if (outcome == ArchiveExportOutcome.failed) {
      // Fehler im Dialog; das Passwort muss neu eingegeben werden.
      setState(() {
        _working = false;
        _failed = true;
        _cancel = null;
      });
      return;
    }
    Navigator.of(context).pop(outcome);
  }

  Future<ArchiveExportOutcome> _run(
    String password,
    ArchiveTarget target,
    ArchiveCancel cancel,
  ) async {
    final ExportFile file;
    try {
      file = await widget.serialize(() async {
        // Erst wenn Aufnahme und Neuberechnung ausgeschlossen sind, ist der
        // Stand der Läufe verbindlich.
        if ((await widget.session.runs.unfinished()).isNotEmpty) {
          throw const _RunActive();
        }
        return widget.runner(password: password, cancel: cancel);
      });
    } on _RunActive {
      return ArchiveExportOutcome.runActive;
    } on ArchiveExportException catch (e) {
      return e.failure == ArchiveExportFailure.cancelled
          ? ArchiveExportOutcome.cancelled
          : ArchiveExportOutcome.failed;
    } on Object {
      return ArchiveExportOutcome.failed;
    }
    if (cancel.isCancelled) return ArchiveExportOutcome.cancelled;
    final FileHandoffResult result;
    try {
      result = await switch (target) {
        ArchiveTarget.share => widget.handoff.share(file),
        ArchiveTarget.save => widget.handoff.save(file),
      };
    } on Object {
      return ArchiveExportOutcome.failed;
    }
    return switch ((result, target)) {
      (FileHandoffResult.completed, ArchiveTarget.share) =>
        ArchiveExportOutcome.shared,
      (FileHandoffResult.completed, ArchiveTarget.save) =>
        ArchiveExportOutcome.saved,
      (FileHandoffResult.cancelled, _) => ArchiveExportOutcome.cancelled,
      (FileHandoffResult.failed, _) => ArchiveExportOutcome.failed,
    };
  }

  /// Fortschritt ohne Prozentangabe; der Abbruch wirkt beim nächsten
  /// Zwischenschritt des Exports.
  void _abort() {
    _cancel?.cancel();
  }

  Widget _field(
    Key key,
    TextEditingController controller,
    String label, {
    String? error,
  }) => TextField(
    key: key,
    controller: controller,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    enableIMEPersonalizedLearning: false,
    autofillHints: const <String>[],
    decoration: InputDecoration(labelText: label, errorText: error),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = Text(l10n.archiveExportTitle);
    if (_working) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          key: const Key('archive_working'),
          title: title,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.archiveExportWorking),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                key: const Key('archive_progress'),
                semanticsLabel: l10n.archiveExportWorking,
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('archive_abort'),
              onPressed: _abort,
              child: Text(l10n.exportCancel),
            ),
          ],
        ),
      );
    }
    return AlertDialog(
      key: const Key('archive_dialog'),
      title: title,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.archiveExportIntro),
            const SizedBox(height: 12),
            Text(
              l10n.archiveExportWarning,
              key: const Key('archive_warning'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            _field(
              const Key('archive_password'),
              _password,
              l10n.archivePassword,
              error: _problem == ArchivePasswordCheck.tooShort
                  ? l10n.archivePasswordTooShort
                  : null,
            ),
            const SizedBox(height: 8),
            _field(
              const Key('archive_password_repeat'),
              _repeat,
              l10n.archivePasswordRepeat,
              error: _problem == ArchivePasswordCheck.mismatch
                  ? l10n.archivePasswordMismatch
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.archivePasswordRule,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_failed) ...[
              const SizedBox(height: 8),
              Text(
                l10n.archiveExportFailed,
                key: const Key('archive_error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('archive_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.exportCancel),
        ),
        TextButton(
          key: const Key('archive_save'),
          onPressed: () => _start(ArchiveTarget.save),
          child: Text(l10n.exportSave),
        ),
        FilledButton(
          key: const Key('archive_share'),
          onPressed: () => _start(ArchiveTarget.share),
          child: Text(l10n.exportShare),
        ),
      ],
    );
  }
}

class _RunActive implements Exception {
  const _RunActive();
}
