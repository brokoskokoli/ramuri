import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../archive/archive_import_flow.dart';
import '../archive/archive_scope.dart';
import '../export/file_handoff_scope.dart';
import 'storage_start.dart';

/// Zeigt je Zustand des App-Starts den passenden Bildschirm. Den Inhalt
/// ([readyBuilder]) gibt es nur im Zustand [StorageReady].
class StorageGate extends StatefulWidget {
  const StorageGate({
    super.key,
    required this.controller,
    required this.readyBuilder,
  });

  final StorageStartController controller;
  final Widget Function(BuildContext context, StorageSession session)
  readyBuilder;

  @override
  State<StorageGate> createState() => _StorageGateState();
}

class _StorageGateState extends State<StorageGate> {
  @override
  void initState() {
    super.initState();
    // Ein schon entschiedener Zustand (etwa "nicht zu öffnen") wird nicht
    // neu geladen; nur "Erneut versuchen" startet wieder.
    if (widget.controller.state is StorageLoading) widget.controller.start();
  }

  bool _canRestore(BuildContext context) =>
      ArchiveScope.verifyOf(context) != null &&
      ArchiveScope.restoreOf(context) != null &&
      FileHandoffScope.of(context) != null;

  /// Weg "Aus Archiv wiederherstellen" im Dialog "nicht zu öffnen" (SEC-0009):
  /// Datei wählen, Passwort, das Archiv vollständig prüfen, ohne etwas zu
  /// schreiben, erst dann die Bestätigung, dass die alte Datei gelöscht wird.
  /// Bis zur Bestätigung bleibt alles unberührt; ein falsches Passwort kostet
  /// nichts. Danach Neubeginn und Einspielen in die leere Datenbank, bevor die
  /// App bereit meldet. Die gewählte Kopie wird immer entsorgt.
  Future<void> _restoreFromArchive() async {
    final handoff = FileHandoffScope.of(context);
    final verify = ArchiveScope.verifyOf(context);
    final factory = ArchiveScope.restoreOf(context);
    if (handoff == null || verify == null || factory == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String text) =>
        messenger?.showSnackBar(SnackBar(content: Text(text)));
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
      if (path == null || !mounted) return;
      var wrong = false;
      String password;
      while (true) {
        if (!mounted) return;
        final asked = await askArchivePassword(context, wrong: wrong);
        if (asked == null || !mounted) return;
        password = asked;
        final cancel = ArchiveCancel();
        try {
          await withArchiveProgress(
            context,
            text: l10n.archiveImportVerifying,
            cancel: cancel,
            run: () => verify(path: path, password: password, cancel: cancel),
          );
          break;
        } on ArchiveImportException catch (e) {
          if (e.failure == ArchiveImportFailure.wrongPasswordOrDamaged) {
            wrong = true;
            continue;
          }
          if (e.failure == ArchiveImportFailure.cancelled) {
            say(l10n.archiveImportCancelled);
          } else if (mounted) {
            await showArchiveImportError(context, e);
          }
          return;
        } on Object catch (e) {
          if (mounted) await showArchiveImportError(context, e);
          return;
        }
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const RestoreConfirmDialog(),
      );
      if (confirmed != true) return;
      await widget.controller.resetStorage(
        restoreInto: (fresh) async {
          if (!mounted) return fresh;
          final cancel = ArchiveCancel();
          try {
            final restored = await withArchiveProgress(
              context,
              text: l10n.archiveImportWorking,
              cancel: cancel,
              run: () async {
                final run = await factory(fresh, <T>(action) => action());
                return run(path: path, password: password, cancel: cancel);
              },
            );
            say(l10n.archiveImportDone);
            return restored;
          } on ArchiveImportException catch (e) {
            if (e.failure == ArchiveImportFailure.cancelled) {
              say(l10n.archiveImportCancelled);
            } else if (mounted) {
              await showArchiveImportError(context, e);
            }
            return fresh;
          } on ArchiveRestoreException catch (e) {
            if (mounted) await showArchiveImportError(context, e);
            // Das Öffnen nach dem Tausch scheiterte: der Start meldet "nicht
            // zu öffnen", "Erneut versuchen" öffnet die Datenbank normal.
            if (e.failure == ArchiveRestoreFailure.reopenFailed) rethrow;
            return e.session ?? fresh;
          } on Object catch (e) {
            if (mounted) await showArchiveImportError(context, e);
            return fresh;
          }
        },
      );
    } finally {
      await handoff.discardPicked();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => switch (widget.controller.state) {
      StorageLoading() => const _LoadingScreen(),
      StorageReady(:final session) => widget.readyBuilder(context, session),
      final StorageNotOpenableState s => NotOpenableScreen(
        state: s,
        onRetry: widget.controller.start,
        onReset: widget.controller.resetStorage,
        onRestoreFromArchive: _canRestore(context) ? _restoreFromArchive : null,
      ),
      StorageEncryptionInactive(:final dataLoss) => EncryptionInactiveScreen(
        dataLoss: dataLoss,
        onRetry: widget.controller.start,
      ),
    },
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  // Fest dunkel wie Splash und Willkommen: kein Hellblitz im hellen System.
  Widget build(BuildContext context) => RamuriDarkScope(
    child: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).storageLoading),
          ],
        ),
      ),
    ),
  );
}

/// Bildschirm "nicht zu öffnen" (OQ-0062) mit dem Weg "Aus Archiv
/// wiederherstellen" (WP12, SEC-0009).
class NotOpenableScreen extends StatelessWidget {
  const NotOpenableScreen({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onReset,
    this.onRestoreFromArchive,
  });

  final StorageNotOpenableState state;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  /// Weg "Aus Archiv wiederherstellen" (SEC-0009); `null`: nicht angeboten.
  final VoidCallback? onRestoreFromArchive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = state.resetProblem;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notOpenableTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(switch (state.dataLoss) {
              StorageDataLoss.deleted => l10n.notOpenableDataDeleted,
              StorageDataLoss.partial => l10n.notOpenableDataPartial,
              StorageDataLoss.none => switch (state.cause) {
                StorageNotOpenableCause.keyMissing =>
                  l10n.notOpenableKeyMissing,
                StorageNotOpenableCause.keyMalformed =>
                  l10n.notOpenableKeyMalformed,
                StorageNotOpenableCause.keyStoreError =>
                  l10n.notOpenableKeyStoreError,
                StorageNotOpenableCause.unreadable =>
                  l10n.notOpenableUnreadable,
                StorageNotOpenableCause.newerVersion =>
                  l10n.notOpenableNewerVersion,
                StorageNotOpenableCause.migrationFailed =>
                  l10n.notOpenableMigrationFailed,
                StorageNotOpenableCause.configurationFailed =>
                  l10n.notOpenableConfigurationFailed,
                StorageNotOpenableCause.fileCheckError =>
                  l10n.notOpenableFileCheckError,
                StorageNotOpenableCause.locationError =>
                  l10n.notOpenableLocationError,
                StorageNotOpenableCause.openFailed =>
                  l10n.notOpenableOpenFailed,
              },
            }),
            // Ein Fehler des Neubeginns nennt nur etwas, wenn noch nichts
            // gelöscht ist (der Start scheiterte vor dem Löschen). Danach sagt
            // der eine Text je Stufe alles Nötige.
            if (problem != null && state.dataLoss == StorageDataLoss.none) ...[
              const SizedBox(height: 16),
              Text(
                l10n.resetProblemStart,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (state.canReset && state.dataLoss == StorageDataLoss.none) ...[
              const SizedBox(height: 16),
              Text(l10n.notOpenableResetHint),
            ],
            const SizedBox(height: 24),
            if (state.busy)
              const Center(child: CircularProgressIndicator())
            else ...[
              RamuriPrimaryButton(
                onPressed: onRetry,
                label: state.dataLoss == StorageDataLoss.none
                    ? l10n.notOpenableRetry
                    : l10n.notOpenableResume,
              ),
              if (state.canReset && state.dataLoss == StorageDataLoss.none) ...[
                const SizedBox(height: 12),
                RamuriSecondaryButton(
                  onPressed: () async {
                    // Nur ein ausdrückliches "true" setzt zurück; Abbrechen,
                    // Zurück und Tippen daneben lassen alles stehen.
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => const ResetConfirmDialog(),
                    );
                    if (confirmed == true) onReset();
                  },
                  label: l10n.notOpenableReset,
                ),
                if (onRestoreFromArchive != null) ...[
                  const SizedBox(height: 12),
                  Text(l10n.notOpenableRestoreHint),
                  const SizedBox(height: 8),
                  RamuriSecondaryButton(
                    key: const Key('not_openable_restore'),
                    onPressed: onRestoreFromArchive,
                    label: l10n.notOpenableRestore,
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Bestätigung des Neubeginns mit Hinweis auf den endgültigen Datenverlust.
/// Gibt `true` nur bei der Schaltfläche zum Löschen zurück.
class ResetConfirmDialog extends StatelessWidget {
  const ResetConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.resetConfirmTitle),
      content: SingleChildScrollView(child: Text(l10n.resetConfirmBody)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.deleteCancel),
        ),
        FilledButton(
          style: ramuriDangerFilledStyle(context),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.resetConfirmAction),
        ),
      ],
    );
  }
}

/// Bestätigung vor dem Löschen der alten Datei, nachdem das Archiv geprüft ist
/// (SEC-0009), mit dem Hinweis aus OQ-0050. Gibt `true` nur bei der
/// Schaltfläche zum Löschen zurück.
class RestoreConfirmDialog extends StatelessWidget {
  const RestoreConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('restore_confirm_dialog'),
      title: Text(l10n.restoreConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restoreConfirmBody),
            const SizedBox(height: 12),
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
          key: const Key('restore_confirm_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.deleteCancel),
        ),
        FilledButton(
          key: const Key('restore_confirm_action'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.restoreConfirmAction),
        ),
      ],
    );
  }
}

/// Bildschirm "Verschlüsselung nicht aktiv": nur Erklärung und erneuter
/// Versuch, kein Neubeginn und kein Weg zu den Inhalten.
class EncryptionInactiveScreen extends StatelessWidget {
  const EncryptionInactiveScreen({
    super.key,
    required this.onRetry,
    this.dataLoss = StorageDataLoss.none,
  });

  final VoidCallback onRetry;

  /// Hat ein bestätigter Neubeginn schon Daten gelöscht, sagt der Bildschirm
  /// das und nicht "nicht verändert".
  final StorageDataLoss dataLoss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inactiveTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (dataLoss == StorageDataLoss.none)
              Text(l10n.inactiveBody)
            else ...[
              Text(switch (dataLoss) {
                StorageDataLoss.partial => l10n.notOpenableDataPartial,
                _ => l10n.notOpenableDataDeleted,
              }),
              const SizedBox(height: 16),
              Text(l10n.inactiveDataLossNote),
            ],
            const SizedBox(height: 24),
            RamuriPrimaryButton(
              onPressed: onRetry,
              label: dataLoss == StorageDataLoss.none
                  ? l10n.notOpenableRetry
                  : l10n.notOpenableResume,
            ),
          ],
        ),
      ),
    );
  }
}
