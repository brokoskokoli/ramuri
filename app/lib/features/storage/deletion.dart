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

/// Löscht den Lauf [runId] und legt danach die Tageswerte der verbleibenden
/// Lauftage neu an (FR-0058: die Speicherschicht löscht überlappende
/// Tageswerte). Vor dem Löschen steht ein Merker in den Einstellungen (nur
/// Lauf-ID und Zeitpunkt); er wird nach erfolgreichem Neuanlegen entfernt. Ein
/// Fehler beim Neuanlegen macht das Löschen nicht rückgängig und wird nicht
/// angezeigt (keine Gesundheitsdaten in Meldungen); der Merker bleibt, und
/// [completePendingValueRefresh] holt das Neuanlegen beim nächsten Start nach.
/// Scheitert schon der Merker, wird nichts gelöscht (Wurf).
///
/// Das ganze Löschen samt Neuanlegen läuft über [serialize] (in der App
/// `RecalculationController.exclusive`), nie parallel zum Nachholen beim Start,
/// zur Berechnung nach einem Lauf oder zu einer Neuberechnung. [serialize] ist
/// Pflicht, damit es niemand vergisst; Fehler der Aktion gehen an den Aufrufer.
Future<void> deleteRunAndRefresh(
  StorageSession session,
  Clock clock,
  int runId, {
  required Future<void> Function(Future<void> Function() action) serialize,
}) => serialize(() => _deleteRunAndRefresh(session, clock, runId));

Future<void> _deleteRunAndRefresh(
  StorageSession session,
  Clock clock,
  int runId,
) async {
  final calc = ValueCalculationService(session: session, clock: clock);
  // Ein Merker eines früheren, unvollendeten Neuanlegens darf nicht verloren
  // gehen, wenn dieses Löschen nichts löscht.
  final previous = await session.settings.get(
    ValueCalculationService.refreshPendingKey,
  );
  await calc.markRefreshPending(runId);

  Future<void> refresh() async {
    try {
      await calc.completePendingRefresh();
    } on Object {
      // Siehe oben: Löschen gilt, Merker bleibt, Nachholen beim Start.
    }
  }

  try {
    await session.deleteRun(runId);
  } on StorageException catch (e) {
    if (e.failure == StorageFailure.deletedNotErased) {
      // Gelöscht, nur der Checkpoint scheiterte: Tageswerte trotzdem anlegen.
      await refresh();
    } else {
      // Nichts gelöscht: der eigene Merker wird nicht gebraucht, ein älterer
      // (nicht leer vorher) bleibt stehen.
      if (previous == null || previous.isEmpty) {
        try {
          await calc.clearRefreshPending();
        } on Object {
          // Ein stehengebliebener Merker kostet nur ein überflüssiges Neuanlegen.
        }
      }
    }
    rethrow;
  }
  await refresh();
}

/// Holt ein unterbrochenes Neuanlegen der Tageswerte nach einem Löschen nach
/// (beim App-Start, vor einer Neuberechnung; nicht parallel zu ihr), ebenso eine
/// unterbrochene Berechnung nach einem Lauf. Ohne Merker passiert nichts.
/// Fehler werden weitergegeben; der Merker bleibt.
Future<void> completePendingValueRefresh(
  StorageSession session,
  Clock clock,
) async {
  final calc = ValueCalculationService(session: session, clock: clock);
  // Beide Nachholer laufen, auch wenn der erste scheitert; der erste Fehler
  // wird weitergegeben.
  Object? failure;
  for (final step in [
    calc.completePendingRefresh,
    calc.completePendingCalculations,
  ]) {
    try {
      await step();
    } on Object catch (e) {
      failure ??= e;
    }
  }
  if (failure != null) throw failure;
}

/// Fragt nach und löscht den Lauf [runId]. Für WP10 (Eintrag in der Lauf-Liste).
/// Erwartet die [clock], weil nach dem Löschen die Tageswerte der übrigen
/// Lauftage neu angelegt werden ([deleteRunAndRefresh]). Zeigt danach eine
/// kurze Rückmeldung, soweit der Kontext noch steht.
Future<DeletionResult> confirmAndDeleteRun(
  BuildContext context,
  StorageSession session,
  Clock clock,
  int runId, {
  required Future<void> Function(Future<void> Function() action) serialize,
}) => _confirmAndDelete(
  context,
  all: false,
  action: () =>
      deleteRunAndRefresh(session, clock, runId, serialize: serialize),
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
