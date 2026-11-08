import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../export/file_handoff_scope.dart';
import '../storage/storage_start.dart';
import 'archive_import_flow.dart';
import 'archive_scope.dart';
import 'archive_wiring.dart';

/// Schaltfläche "Archiv importieren" im Daten-Bildschirm (FR-0198, OQ-0050,
/// WP12). Ablauf: Hinweis (bei nicht leerer App mit Warnung und ausdrücklicher
/// Bestätigung des Zurücksetzens), Datei wählen, Passwort einmal, Einlesen in
/// die Zwischendatenbank, Tausch. Danach gilt die neue Sitzung. Ein offener
/// Lauf sperrt den Import; Aufnahme und Neuberechnung sind ausgeschlossen
/// ([serialize]). Die gewählte Kopie wird immer entsorgt.
class ArchiveImportAction extends StatelessWidget {
  const ArchiveImportAction({
    super.key,
    required this.session,
    required this.serialize,
    this.buttonKey = const Key('archive_import'),
    this.label,
    this.prepare,
  });

  final StorageSession session;

  /// Schlüssel und Beschriftung der Schaltfläche (Standard: Daten-Bildschirm).
  final Key buttonKey;
  final String? label;

  /// Läuft mit der neuen Sitzung, bevor sie übernommen wird (Ersteinrichtung:
  /// Einrichtung als erledigt markieren). Fehler hindern die Übernahme nicht.
  final Future<void> Function(StorageSession fresh)? prepare;

  /// In der App `RecalculationController.exclusive`.
  final SerializeAction serialize;

  Future<void> _import(
    BuildContext context,
    ArchiveRestoreFactory factory,
    FileHandoff handoff,
    StorageStartController start,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    void say(String text) =>
        messenger?.showSnackBar(SnackBar(content: Text(text)));

    final bool empty;
    try {
      // Schnelle Absage vor der Dateiwahl; verbindlich prüft `serialize` unten.
      if ((await session.runs.unfinished()).isNotEmpty) {
        say(l10n.archiveImportRunActive);
        return;
      }
      empty = await ArchiveRestoreService.isEmpty(session);
    } on Object {
      say(l10n.archiveImportFailed);
      return;
    }
    if (!context.mounted) return;
    if (!await confirmArchiveImport(context, replaces: !empty)) return;
    if (!context.mounted) return;

    try {
      final pick = await handoff.pickFile();
      switch (pick.result) {
        case FileHandoffResult.cancelled:
          return;
        case FileHandoffResult.failed:
          say(l10n.archiveImportPickFailed);
          return;
        case FileHandoffResult.completed:
          break;
      }
      final path = pick.path;
      if (path == null || !context.mounted) return;
      var wrong = false;
      while (true) {
        if (!context.mounted) return;
        final password = await askArchivePassword(context, wrong: wrong);
        if (password == null || !context.mounted) return;
        final cancel = ArchiveCancel();
        try {
          final fresh = await withArchiveProgress(
            context,
            text: l10n.archiveImportWorking,
            cancel: cancel,
            run: () async {
              final run = await factory(
                session,
                <T>(action) =>
                    serializeWithoutOpenRun(serialize, session, action),
              );
              return run(
                path: path,
                password: password,
                resetConfirmed: !empty,
                cancel: cancel,
              );
            },
          );
          try {
            await prepare?.call(fresh);
          } on Object {
            // Die Daten sind eingespielt; die Übernahme hängt nicht daran.
          }
          start.adoptSession(fresh);
          navigator.popUntil((r) => r.isFirst);
          say(l10n.archiveImportDone);
          return;
        } on ArchiveRunActive {
          say(l10n.archiveImportRunActive);
          return;
        } on ArchiveImportException catch (e) {
          if (e.failure == ArchiveImportFailure.wrongPasswordOrDamaged) {
            wrong = true;
            continue;
          }
          if (e.failure == ArchiveImportFailure.cancelled) {
            say(l10n.archiveImportCancelled);
            return;
          }
          if (context.mounted) await showArchiveImportError(context, e);
          return;
        } on Object catch (e) {
          // Nach einem Tausch ist die bisherige Sitzung geschlossen: Die neue
          // (oder ein Neustart des Öffnens) muss übernommen werden.
          final swapped = e is ArchiveRestoreException ? e : null;
          if (context.mounted) await showArchiveImportError(context, e);
          if (swapped?.failure == ArchiveRestoreFailure.swapFailed &&
              swapped!.session != null) {
            start.adoptSession(swapped.session!);
            navigator.popUntil((r) => r.isFirst);
          } else if (swapped?.failure == ArchiveRestoreFailure.reopenFailed) {
            navigator.popUntil((r) => r.isFirst);
            await start.restart();
          }
          return;
        }
      }
    } finally {
      await handoff.discardPicked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final factory = ArchiveScope.restoreOf(context);
    final start = ArchiveScope.startOf(context);
    final handoff = FileHandoffScope.of(context);
    if (factory == null || start == null || handoff == null) {
      return const SizedBox.shrink();
    }
    return RamuriSecondaryButton(
      key: buttonKey,
      onPressed: () => _import(context, factory, handoff, start),
      label: label ?? AppLocalizations.of(context).archiveImportAction,
    );
  }
}
