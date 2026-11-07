import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show Variable;

import '../storage/app_database.dart';
import '../storage/encrypted_storage.dart';

const String _stageValues = 'import_stage_computed_values';
const String _stageSections = 'import_stage_value_sections';

/// Ziel des Archiv-Lesers: eine **neue Zwischendatenbank** neben der aktiven
/// (`docs/contracts/archive.md` 4.6). Sie wird mit demselben Schlüssel und
/// derselben Einrichtung geöffnet wie die aktive (sqlite3mc, nie Klartext),
/// das Schema 4 legt `onCreate` frisch an. Die aktive Datenbank wird nie
/// berührt.
///
/// `computed_values` und `value_sections` stehen im Archiv in zwei Abschnitten,
/// die Trigger verlangen aber Original, dessen Abschnitte, dann `current`.
/// Beide kommen darum zuerst in Hilfstabellen derselben (verschlüsselten)
/// Datei und werden in [commit] in dieser Reihenfolge mit ihren ids
/// eingefügt. Jede Stapel-Einfügung ist eine Transaktion; ein Abbruch
/// dazwischen hinterlässt eine unvollständige Zwischendatenbank, die nie
/// getauscht, sondern beim Start gelöscht wird.
class DriftArchiveSink implements ArchiveSink {
  DriftArchiveSink({
    required this._storage,
    required this._key,
    required this._files,
  });

  final EncryptedStorage _storage;
  final Uint8List Function() _key;
  final DatabaseFiles _files;

  EncryptedStorageSession? _session;
  final Map<String, int> _counts = {};

  AppDatabase get _db => _session!.database;

  @override
  Future<void> begin() async {
    await _files.deleteImport();
    try {
      _session = await _storage.open(_key()) as EncryptedStorageSession;
    } on StorageException {
      throw const ArchiveImportException(ArchiveImportFailure.targetFailed);
    }
    _counts.clear();
    try {
      await _db.customStatement(
        'CREATE TABLE $_stageValues AS SELECT * FROM computed_values WHERE 0',
      );
      await _db.customStatement(
        'CREATE TABLE $_stageSections AS SELECT * FROM value_sections WHERE 0',
      );
    } catch (_) {
      throw const ArchiveImportException(ArchiveImportFailure.targetFailed);
    }
  }

  static String _table(ArchiveSectionSpec s) => switch (s.name) {
    'computed_values' => _stageValues,
    'value_sections' => _stageSections,
    _ => s.name,
  };

  @override
  Future<void> insert(
    ArchiveSectionSpec section,
    List<Map<String, Object?>> rows,
  ) async {
    if (section.isReserved) {
      if (rows.isEmpty) return;
      throw const ArchiveImportException(ArchiveImportFailure.damaged);
    }
    final cols = section.columns.map((c) => c.name).toList();
    final sql =
        'INSERT INTO ${_table(section)} (${cols.join(', ')}) '
        'VALUES (${List.filled(cols.length, '?').join(', ')})';
    try {
      await _db.batch((b) {
        for (final r in rows) {
          b.customStatement(sql, [for (final c in cols) r[c]]);
        }
      });
    } catch (e) {
      throw _translate(e);
    }
    _counts[section.name] = (_counts[section.name] ?? 0) + rows.length;
  }

  @override
  Future<void> commit() async {
    try {
      await _merge();
      await _db.customStatement('DROP TABLE $_stageSections');
      await _db.customStatement('DROP TABLE $_stageValues');
      await _verify();
      // Alles auf den Datenträger: nichts darf im -wal bleiben, bevor die
      // Datei getauscht wird.
      final cp = await _db
          .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
          .get();
      if (cp.isEmpty || cp.first.data.values.first != 0) {
        throw const ArchiveImportException(ArchiveImportFailure.targetFailed);
      }
      final s = _session!;
      _session = null;
      await s.close();
    } catch (e) {
      throw _translate(e);
    }
  }

  /// Je `computed_values`-Zeile in `id`-Reihenfolge: Zeile, dann (bei
  /// `original` zwingend, bei `current` gleichwertig) deren Abschnitte.
  Future<void> _merge() async {
    final cols = archiveSections
        .firstWhere((s) => s.name == 'computed_values')
        .columns
        .map((c) => c.name)
        .join(', ');
    final secCols = archiveSections
        .firstWhere((s) => s.name == 'value_sections')
        .columns
        .map((c) => c.name)
        .join(', ');
    var after = -1;
    while (true) {
      final ids = await _db
          .customSelect(
            'SELECT id FROM $_stageValues WHERE id > ? ORDER BY id LIMIT 200',
            variables: [Variable.withInt(after)],
          )
          .get();
      if (ids.isEmpty) break;
      await _db.batch((b) {
        for (final r in ids) {
          final id = r.data['id']! as int;
          b.customStatement(
            'INSERT INTO computed_values ($cols) '
            'SELECT $cols FROM $_stageValues WHERE id = ?',
            [id],
          );
          b.customStatement(
            'INSERT INTO value_sections ($secCols) '
            'SELECT $secCols FROM $_stageSections '
            'WHERE computed_value_id = ? ORDER BY id',
            [id],
          );
        }
      });
      after = ids.last.data['id']! as int;
    }
  }

  /// Zeilenzahlen gegen das, was der Leser geliefert hat (die Endzeile hat der
  /// Leser schon gegen genau diese Zahlen geprüft), und Fremdschlüssel.
  Future<void> _verify() async {
    for (final s in archiveSections) {
      if (s.isReserved) continue;
      final r = await _db
          .customSelect('SELECT COUNT(*) AS n FROM ${s.name}')
          .get();
      if (r.single.data['n'] != (_counts[s.name] ?? 0)) {
        throw const ArchiveImportException(ArchiveImportFailure.damaged);
      }
    }
    final fk = await _db.customSelect('PRAGMA foreign_key_check').get();
    if (fk.isNotEmpty) {
      throw const ArchiveImportException(ArchiveImportFailure.damaged);
    }
  }

  /// Verletzung einer Beschränkung (Prüfregel, Trigger, Fremdschlüssel,
  /// Eindeutigkeit) heißt: das Archiv passt nicht zum Schema, also beschädigt;
  /// alles andere ist ein Fehler des Ziels. Nie mit Text der Ursache.
  static ArchiveImportException _translate(Object e) {
    if (e is ArchiveImportException) return e;
    final s = translateStorageError(e);
    return ArchiveImportException(
      s.failure == StorageFailure.rejected
          ? ArchiveImportFailure.damaged
          : ArchiveImportFailure.targetFailed,
    );
  }

  @override
  Future<void> abort() async {
    final s = _session;
    _session = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
    }
    try {
      await _files.deleteImport();
    } catch (_) {}
  }
}
