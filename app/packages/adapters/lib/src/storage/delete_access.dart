import 'package:core/core.dart';

import 'access_support.dart';
import 'app_database.dart' as d;

/// Größter Wert einer INTEGER-Spalte: Ende eines Laufs, der noch läuft.
const int _unboundedEndUs = 9223372036854775807;

/// Löschen je Lauf und komplett (SEC-0004, ADR-0003 Punkt 4). Beides läuft in
/// einer Transaktion; danach folgt der WAL-Checkpoint. `secure_delete=ON` steht
/// im Verbindungs-Setup (connection_setup.dart) und überschreibt gelöschte
/// Seiteninhalte; der Checkpoint (TRUNCATE) bringt die Änderung in die
/// Hauptdatei und leert die Journal-Datei, in der sonst alte Seitenabbilder
/// stehen blieben.
class DriftDeletion {
  DriftDeletion(this._db);
  final d.AppDatabase _db;

  Future<void> deleteRun(int runId) => guarded(() async {
    await _db.transaction(() async {
      final run = await (_db.select(
        _db.runs,
      )..where((t) => t.id.equals(runId))).getSingleOrNull();
      if (run == null) throw const StorageException(StorageFailure.notFound);
      // Tageswerte haben keine Kaskade (Supervisor-Entscheidung): weg gehen die
      // Paare (Tag, Schlüssel), von denen eine Zeile den Lauf überlappt oder
      // keinen bekannten Datenzeitraum hat. WP09 berechnet sie neu. Vor dem
      // Löschen des Laufs, weil sie seine Grenzen brauchen.
      // Die Werte der Tageswerte-Auswahl und des Laufs samt ihrer Abschnitte
      // (value_sections) werden ausdrücklich gelöscht, zuerst die Abschnitte;
      // die Fremdschlüssel-Kaskade ist nur der zweite Boden.
      const dayPairs =
          'SELECT day, value_key FROM computed_values '
          'WHERE day IS NOT NULL AND ('
          '(data_from_us IS NULL AND data_to_us IS NULL) OR '
          '(COALESCE(data_from_us, data_to_us) <= ? '
          'AND COALESCE(data_to_us, data_from_us) >= ?))';
      final bounds = [run.endedAtUs ?? _unboundedEndUs, run.startedAtUs];
      await _db.customStatement(
        'DELETE FROM value_sections WHERE computed_value_id IN ('
        'SELECT id FROM computed_values WHERE run_id = ? OR '
        '(day IS NOT NULL AND (day, value_key) IN ($dayPairs)))',
        [runId, ...bounds],
      );
      await _db.customStatement(
        'DELETE FROM computed_values WHERE run_id = ? OR '
        '(day IS NOT NULL AND (day, value_key) IN ($dayPairs))',
        [runId, ...bounds],
      );
      // Angaben zum Lauf samt sRPE-Wert ausdrücklich (WP18), die Kaskade ist
      // der zweite Boden. Nachgetragene Trainings gehören keinem Lauf.
      await (_db.delete(
        _db.runFeedback,
      )..where((t) => t.runId.equals(runId))).go();
      // Kaskade über die Fremdschlüssel (foreign_keys=ON je Verbindung).
      await (_db.delete(_db.runs)..where((t) => t.id.equals(runId))).go();
    });
    await _checkpoint();
  });

  Future<void> deleteAll() => guarded(() async {
    await _db.transaction(() async {
      // Alle Tabellen des Schemas, auch Tabellen späterer Versionen; keine
      // Ausnahme (storage_meta enthält nur technische Werte, aber nichts davon
      // braucht die App nach dem Löschen). Der Schlüssel liegt im Schlüsselspeicher.
      // Zuerst die Läufe: Die Kaskade räumt die Rohdaten ab, die sich sonst
      // nicht direkt löschen lassen (Trigger).
      await _db.delete(_db.runs).go();
      // Die Schleife löscht jede Tabelle ausdrücklich, auch value_sections
      // (ohne Verlass auf die Kaskade; ein Test mit foreign_keys=OFF belegt es).
      for (final t in _db.allTables) {
        await _db.customStatement('DELETE FROM "${t.actualTableName}"');
      }
      // AUTOINCREMENT-Zähler verraten sonst, wie viele Läufe es gab.
      await _db.customStatement('DELETE FROM sqlite_sequence');
    });
    await _checkpoint();
  });

  /// `PRAGMA wal_checkpoint(TRUNCATE)` liefert (busy, log, checkpointed).
  /// `busy = 1` heißt: nicht fertig (ein Leser hielt die Datei). Das Löschen
  /// bleibt gültig, wird aber nicht als Erfolg gemeldet.
  ///
  /// Die Transaktion ist hier schon abgeschlossen: Auch eine Ausnahme des
  /// Checkpoints (etwa Ein-/Ausgabefehler) ändert daran nichts. Sie darf nicht
  /// als gewöhnlicher Fehler ("nichts wurde gelöscht") durchgehen.
  Future<void> _checkpoint() async {
    final Object? busy;
    try {
      final rows = await _db
          .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
          .get();
      busy = rows.isEmpty ? 1 : rows.first.data.values.first;
    } catch (_) {
      throw const StorageException(StorageFailure.deletedNotErased);
    }
    if (busy != 0) {
      throw const StorageException(StorageFailure.deletedNotErased);
    }
  }
}
