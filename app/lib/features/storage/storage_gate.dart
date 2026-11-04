import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
      ),
      StorageEncryptionInactive() => EncryptionInactiveScreen(
        onRetry: widget.controller.start,
      ),
    },
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
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
  );
}

/// Bildschirm "nicht zu öffnen" (OQ-0062). Hier wäre der Platz für den Eintrag
/// "Reimport aus dem Archiv" (WP12); er ist absichtlich noch nicht gebaut.
class NotOpenableScreen extends StatelessWidget {
  const NotOpenableScreen({
    super.key,
    required this.state,
    required this.onRetry,
    required this.onReset,
  });

  final StorageNotOpenableState state;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = state.resetProblem;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notOpenableTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(switch (state.cause) {
              StorageNotOpenableCause.keyMissing => l10n.notOpenableKeyMissing,
              StorageNotOpenableCause.keyMalformed =>
                l10n.notOpenableKeyMalformed,
              StorageNotOpenableCause.keyStoreError =>
                l10n.notOpenableKeyStoreError,
              StorageNotOpenableCause.unreadable => l10n.notOpenableUnreadable,
              StorageNotOpenableCause.newerVersion =>
                l10n.notOpenableNewerVersion,
              StorageNotOpenableCause.migrationFailed =>
                l10n.notOpenableMigrationFailed,
              StorageNotOpenableCause.fileCheckError =>
                l10n.notOpenableFileCheckError,
              StorageNotOpenableCause.locationError =>
                l10n.notOpenableLocationError,
            }),
            if (problem != null) ...[
              const SizedBox(height: 16),
              Text(switch (problem) {
                StorageResetProblem.filesNotDeleted => l10n.resetProblemFiles,
                StorageResetProblem.keyNotReplaced => l10n.resetProblemKey,
              }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (state.canReset) ...[
              const SizedBox(height: 16),
              Text(l10n.notOpenableResetHint),
            ],
            const SizedBox(height: 24),
            if (state.busy)
              const Center(child: CircularProgressIndicator())
            else ...[
              FilledButton(
                onPressed: onRetry,
                child: Text(l10n.notOpenableRetry),
              ),
              if (state.canReset) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () async {
                    // Nur ein ausdrückliches "true" setzt zurück; Abbrechen,
                    // Zurück und Tippen daneben lassen alles stehen.
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => const ResetConfirmDialog(),
                    );
                    if (confirmed == true) onReset();
                  },
                  child: Text(l10n.notOpenableReset),
                ),
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
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.resetConfirmAction),
        ),
      ],
    );
  }
}

/// Bildschirm "Verschlüsselung nicht aktiv": nur Erklärung und erneuter
/// Versuch, kein Neubeginn und kein Weg zu den Inhalten.
class EncryptionInactiveScreen extends StatelessWidget {
  const EncryptionInactiveScreen({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inactiveTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.inactiveBody),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              child: Text(l10n.notOpenableRetry),
            ),
          ],
        ),
      ),
    );
  }
}
