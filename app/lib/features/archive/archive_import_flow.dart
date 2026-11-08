import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import 'archive_wiring.dart';

/// Bausteine des Archiv-Imports (WP12, FR-0198, SEC-0009), gemeinsam für den
/// Daten-Bildschirm und den Weg aus "nicht zu öffnen". Meldungen enthalten
/// weder Inhalte noch Pfade noch das Passwort.

/// Text zu einem Fehler des Imports. Unbekannte Fehler ergeben die allgemeine
/// Meldung.
String archiveImportMessage(AppLocalizations l10n, Object error) {
  if (error is ArchiveImportException) {
    return switch (error.failure) {
      ArchiveImportFailure.notAnArchive => l10n.archiveImportNotArchive,
      ArchiveImportFailure.unsupportedVersion ||
      ArchiveImportFailure.newerSchema ||
      ArchiveImportFailure.unsupportedSchema => l10n.archiveImportVersion,
      ArchiveImportFailure.wrongPasswordOrDamaged =>
        l10n.archiveImportWrongPassword,
      ArchiveImportFailure.unsupportedParameters ||
      ArchiveImportFailure.damaged => l10n.archiveImportDamaged,
      ArchiveImportFailure.readFailed => l10n.archiveImportReadFailed,
      ArchiveImportFailure.targetFailed => l10n.archiveImportTargetFailed,
      ArchiveImportFailure.cancelled => l10n.archiveImportCancelled,
    };
  }
  if (error is ArchiveRestoreException) {
    return switch (error.failure) {
      ArchiveRestoreFailure.swapFailed => l10n.archiveImportSwapFailed,
      ArchiveRestoreFailure.reopenFailed => l10n.archiveImportReopenFailed,
      ArchiveRestoreFailure.notEmpty ||
      ArchiveRestoreFailure.keyUnavailable => l10n.archiveImportFailed,
    };
  }
  return l10n.archiveImportFailed;
}

/// Hinweis vor dem Import (OQ-0050). [replaces]: Die App enthält Daten; sie
/// werden ersetzt, und erst die ausdrückliche Bestätigung setzt zurück. Gibt
/// nur bei der Hauptschaltfläche `true` zurück.
Future<bool> confirmArchiveImport(
  BuildContext context, {
  required bool replaces,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        key: const Key('archive_import_notice_dialog'),
        title: Text(l10n.archiveImportTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replaces) ...[
                Text(
                  l10n.archiveImportReplaceWarning,
                  key: const Key('archive_import_replace_warning'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                l10n.archiveImportNotice,
                key: const Key('archive_import_notice'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            key: const Key('archive_import_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.exportCancel),
          ),
          FilledButton(
            key: const Key('archive_import_confirm'),
            style: replaces ? ramuriDangerFilledStyle(context) : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              replaces
                  ? l10n.archiveImportReplaceAction
                  : l10n.archiveImportChooseAction,
            ),
          ),
        ],
      );
    },
  );
  return ok == true;
}

/// Fragt das Passwort einmal ab (verdeckt, ohne Autofill). `null`: abgebrochen.
/// [wrong]: zeigt den Fehler "falsches Passwort oder beschädigter Anfang".
Future<String?> askArchivePassword(
  BuildContext context, {
  bool wrong = false,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ArchivePasswordDialog(wrong: wrong),
);

class _ArchivePasswordDialog extends StatefulWidget {
  const _ArchivePasswordDialog({required this.wrong});

  final bool wrong;

  @override
  State<_ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<_ArchivePasswordDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _password.text;
    if (text.isEmpty) return;
    // Das Feld wird sofort geleert; das Passwort wandert nur zum Aufrufer.
    _password.clear();
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('archive_import_password_dialog'),
      title: Text(l10n.archiveImportPasswordTitle),
      content: TextField(
        key: const Key('archive_import_password'),
        controller: _password,
        autofocus: true,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        enableIMEPersonalizedLearning: false,
        autofillHints: const <String>[],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.archivePassword,
          errorText: widget.wrong ? l10n.archiveImportWrongPassword : null,
          errorMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('archive_import_password_cancel'),
          onPressed: () {
            _password.clear();
            Navigator.of(context).pop();
          },
          child: Text(l10n.exportCancel),
        ),
        FilledButton(
          key: const Key('archive_import_password_ok'),
          onPressed: _submit,
          child: Text(l10n.archiveImportPasswordAction),
        ),
      ],
    );
  }
}

/// Zeigt einen Fortschrittsdialog (nicht schließbar, nur Abbrechen über
/// [cancel]) und schließt ihn, wenn [run] fertig ist, auch bei einem Fehler.
Future<T> withArchiveProgress<T>(
  BuildContext context, {
  required String text,
  required ArchiveCancel cancel,
  required Future<T> Function() run,
}) async {
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const Key('archive_import_working'),
          title: Text(AppLocalizations.of(context).archiveImportTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              const SizedBox(height: 16),
              const LinearProgressIndicator(
                key: Key('archive_import_progress'),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('archive_import_abort'),
              onPressed: cancel.cancel,
              child: Text(AppLocalizations.of(context).exportCancel),
            ),
          ],
        ),
      ),
    ),
  );
  try {
    return await run();
  } finally {
    if (navigator.mounted) navigator.pop();
  }
}

/// Fehlerdialog mit dem Text zu [error] (Titel "Import fehlgeschlagen").
Future<void> showArchiveImportError(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('archive_import_error_dialog'),
      title: Text(l10n.archiveImportErrorTitle),
      content: Text(
        archiveImportMessage(l10n, error),
        key: const Key('archive_import_error'),
      ),
      actions: [
        TextButton(
          key: const Key('archive_import_error_close'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.archiveImportClose),
        ),
      ],
    ),
  );
}

/// Der Aufnahmeschutz: bricht den Import ab, weil ein Lauf offen ist.
class ArchiveRunActive implements Exception {
  const ArchiveRunActive();
}

/// Reiht [action] hinter Aufnahme und Neuberechnung ein und prüft darin, dass
/// kein Lauf offen ist (aktiv, pausiert oder unterbrochen). Wirft
/// [ArchiveRunActive].
Future<T> serializeWithoutOpenRun<T>(
  SerializeAction serialize,
  StorageSession session,
  Future<T> Function() action,
) => serialize(() async {
  if ((await session.runs.unfinished()).isNotEmpty) {
    throw const ArchiveRunActive();
  }
  return action();
});
