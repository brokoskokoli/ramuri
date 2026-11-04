import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Ergebnis eines Löschvorgangs mit Bestätigung.
enum DeletionResult {
  /// Der Dialog wurde abgebrochen (Schaltfläche, Zurück, Tippen daneben).
  /// Nichts wurde gelöscht.
  cancelled,

  /// Gelöscht, Speicherdatei bereinigt.
  deleted,

  /// Gelöscht, aber der Checkpoint lief nicht durch ([StorageFailure.deletedNotErased]).
  /// Das Löschen gilt; es ist kein vollständiger Erfolg.
  deletedNotErased,

  /// Nichts gelöscht (Fehler des Speichers).
  failed,
}

/// Führt [action] aus und ordnet die Fehlerart des Speichers zu. Ohne
/// Oberfläche, damit auch Dienste ohne Dialog (etwa nach einem Widerruf, Teil D)
/// sie nutzen können.
Future<DeletionResult> runDeletion(Future<void> Function() action) async {
  try {
    await action();
    return DeletionResult.deleted;
  } on StorageException catch (e) {
    return e.failure == StorageFailure.deletedNotErased
        ? DeletionResult.deletedNotErased
        : DeletionResult.failed;
  }
}

/// Fragt nach und löscht den Lauf [runId]. Für WP10 (Eintrag in der Lauf-Liste).
/// Zeigt danach eine kurze Rückmeldung, soweit der Kontext noch steht.
Future<DeletionResult> confirmAndDeleteRun(
  BuildContext context,
  StorageSession session,
  int runId,
) => _confirmAndDelete(
  context,
  all: false,
  action: () => session.deleteRun(runId),
);

/// Fragt nach und löscht alle Daten der App ("Alles löschen").
Future<DeletionResult> confirmAndDeleteAll(
  BuildContext context,
  StorageSession session,
) => _confirmAndDelete(context, all: true, action: session.deleteAll);

Future<DeletionResult> _confirmAndDelete(
  BuildContext context, {
  required bool all,
  required Future<void> Function() action,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  // Nur ein ausdrückliches "true" löscht; Zurück und Tippen daneben liefern null.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeletionDialog(all: all),
  );
  if (confirmed != true) return DeletionResult.cancelled;
  final result = await runDeletion(action);
  messenger?.showSnackBar(
    SnackBar(
      content: Text(switch (result) {
        DeletionResult.deleted => l10n.deleteDone,
        DeletionResult.deletedNotErased => l10n.deleteNotErased,
        _ => l10n.deleteFailed,
      }),
    ),
  );
  return result;
}

/// Bestätigung mit dem Hinweis nach OQ-0025 (Daten, die schon weitergegeben
/// wurden, bleiben dort). Gibt `true` nur bei der Löschen-Schaltfläche zurück.
class DeletionDialog extends StatelessWidget {
  const DeletionDialog({super.key, required this.all});

  /// `true`: alles löschen, `false`: ein Lauf.
  final bool all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(all ? l10n.deleteAllTitle : l10n.deleteRunTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(all ? l10n.deleteAllBody : l10n.deleteRunBody),
            const SizedBox(height: 12),
            Text(l10n.deleteSharedHint),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.deleteCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(all ? l10n.deleteAllConfirm : l10n.deleteRunConfirm),
        ),
      ],
    );
  }
}
