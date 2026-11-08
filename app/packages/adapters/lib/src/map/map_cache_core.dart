import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../storage/connection_setup.dart';
import 'map_gate.dart' show thumbnailKeyPrefix;

/// Art eines Eintrags im Kartenspeicher. Je Art eine eigene Grenze, damit Kacheln die Miniaturen nicht verdrängen
/// (R008 "Speicher: Entscheidung").
enum MapStoreKind {
  /// Kacheln, Stil, Sprites, Glyphen.
  tile,

  /// Miniaturen der Läufe (WP13 Teil A3).
  thumbnail;

  /// Präfix der Schlüssel von Miniaturen; alles andere ist [tile].
  static const String thumbnailPrefix = thumbnailKeyPrefix;

  static MapStoreKind of(String key) =>
      key.startsWith(thumbnailPrefix) ? thumbnail : tile;
}

/// Grenzen je Art in Byte (Vorschläge aus R008, keine Messwerte).
const int mapTileLimitBytes = 50 * 1000 * 1000;
const int mapThumbnailLimitBytes = 20 * 1000 * 1000;

/// Name der Kartendatei im Verzeichnis ohne Backup.
const String mapCacheFileName = 'map_cache.db';

/// Nebendateien, die neben der Kartendatei stehen können. `-wal` und `-shm` gibt es bei `journal_mode=DELETE` nie;
/// sie werden nur sicherheitshalber mit gelöscht.
const List<String> mapCacheSuffixes = ['-journal', '-wal', '-shm', ''];

/// Die Datei ist nicht benutzbar (beschädigt, falscher Schlüssel, andere Einstellung). Der Aufrufer baut sie neu auf.
class MapCacheUnreadable implements Exception {
  const MapCacheUnreadable();
  @override
  String toString() => 'MapCacheUnreadable';
}

/// Löscht Datei und Nebendateien. Wirft, wenn eine nicht gelöscht werden konnte (Reste kennt der Aufrufer).
void deleteMapCacheFiles(String path) {
  for (final suffix in mapCacheSuffixes) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
}

/// Der Kern des Kartenspeichers: eine verschlüsselte sqlite3mc-Datei, synchron. Läuft im Hintergrund-Isolate
/// (`EncryptedMapTileStore`); Tests rufen ihn direkt. Wirft nie Texte mit Schlüsseln oder Inhalten.
class MapCacheCore {
  MapCacheCore._(this._db, this.path, this.tileLimit, this.thumbnailLimit) {
    final rows = _db.select('SELECT coalesce(max(last_used), 0) FROM entries');
    _clock = rows.first.values.first as int;
  }

  final raw.Database _db;
  final String path;
  final int tileLimit;
  final int thumbnailLimit;

  /// Zugriffszähler statt Uhrzeit: wächst bei jedem Lesen und Schreiben, unabhängig von Zeitsprüngen.
  late int _clock;

  /// Zugriffsmarken, die noch nicht in der Datei stehen (ein Lesen kostet sonst eine Transaktion).
  final Map<(int, String), int> _marks = {};
  static const int _maxMarks = 20000;

  /// Öffnet die Datei, richtet sie ein und legt die Tabelle an. Eine unbrauchbare Datei (falscher Schlüssel,
  /// beschädigt, andere Einstellung) wird gelöscht und neu aufgebaut. Ist die Verschlüsselung nicht belegt aktiv, wirft
  /// es [ConnectionSetupFailure] und es entsteht kein Speicher (fail-closed).
  static MapCacheCore open({
    required String path,
    required String hexKey,
    int tileLimit = mapTileLimitBytes,
    int thumbnailLimit = mapThumbnailLimitBytes,
    LibraryCipherProbe libraryProbe = defaultLibraryCipherProbe,
    FileEncryptedProbe fileProbe = defaultFileEncryptedProbe,
  }) {
    for (var attempt = 0; ; attempt++) {
      raw.Database? db;
      try {
        db = raw.sqlite3.open(path);
        _setup(db, path, hexKey, libraryProbe, fileProbe);
        return MapCacheCore._(db, path, tileLimit, thumbnailLimit);
      } on ConnectionSetupFailure {
        _closeQuietly(db);
        // Nie Klartext auf der Platte stehen lassen.
        _tryDelete(path);
        rethrow;
      } catch (e) {
        _closeQuietly(db);
        if (attempt == 0 && (e is MapCacheUnreadable || _isUnreadable(e))) {
          deleteMapCacheFiles(path);
          continue;
        }
        throw const MapCacheUnreadable();
      }
    }
  }

  static void _tryDelete(String path) {
    try {
      deleteMapCacheFiles(path);
    } catch (_) {}
  }

  static void _closeQuietly(raw.Database? db) {
    try {
      db?.close();
    } catch (_) {}
  }

  /// SQLITE_NOTADB (26, falscher Schlüssel oder keine Datenbank) und SQLITE_CORRUPT (11).
  static bool _isUnreadable(Object e) {
    if (e is! raw.SqliteException) return false;
    final code = e.extendedResultCode & 0xff;
    return code == 26 || code == 11;
  }

  static void _setup(
    raw.Database db,
    String path,
    String hexKey,
    LibraryCipherProbe libraryProbe,
    FileEncryptedProbe fileProbe,
  ) {
    ConnectionSetup.unlock(db, hexKey, libraryProbe);
    // Erster Zugriff: scheitert mit falschem Schlüssel oder beschädigter Datei.
    db.select('SELECT count(*) FROM sqlite_master');
    // auto_vacuum gilt nur, solange noch keine Tabelle existiert.
    final fresh =
        db.select('SELECT count(*) FROM sqlite_master').first.values.first == 0;
    if (fresh) db.execute('PRAGMA auto_vacuum = INCREMENTAL');
    // Journal ohne WAL: Kein Klartext-Abbild im WAL; zurückgelesen, sonst Abbruch.
    ConnectionSetup.expectPragma(db, 'journal_mode', 'delete', set: 'DELETE');
    ConnectionSetup.expectPragma(db, 'synchronous', 1, set: 'NORMAL');
    ConnectionSetup.expectPragma(db, 'secure_delete', 1, set: 'ON');
    ConnectionSetup.expectPragma(
      db,
      'temp_store',
      tempStoreMemoryValue,
      set: 'MEMORY',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS entries ('
      'kind INTEGER NOT NULL, key TEXT NOT NULL, data BLOB NOT NULL, '
      'size INTEGER NOT NULL, last_used INTEGER NOT NULL, '
      'PRIMARY KEY (kind, key))',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS entries_lru ON entries (kind, last_used)',
    );
    // Eine ältere Datei mit anderer Einstellung wird neu aufgebaut, nicht angepasst.
    final av = db.select('PRAGMA auto_vacuum').first.values.first;
    if (av != 2) throw const MapCacheUnreadable();
    if (!fileProbe(path)) {
      throw const ConnectionSetupFailure(StorageFailure.encryptionNotActive);
    }
  }

  int _limit(MapStoreKind k) =>
      k == MapStoreKind.tile ? tileLimit : thumbnailLimit;

  /// Liest einen Eintrag und merkt sich den Zugriff im Speicher.
  Uint8List? read(String key) {
    final kind = MapStoreKind.of(key).index;
    final rows = _db.select(
      'SELECT data FROM entries WHERE kind = ? AND key = ?',
      [kind, key],
    );
    if (rows.isEmpty) return null;
    if (_marks.length >= _maxMarks) _marks.remove(_marks.keys.first);
    _marks[(kind, key)] = ++_clock;
    return rows.first['data'] as Uint8List;
  }

  /// Schreibt einen Eintrag, legt die Zugriffsmarken ab, verdrängt über der Grenze die am längsten ungenutzten
  /// Einträge der Art und gibt danach den freien Platz zurück. Ein Eintrag über der Grenze wird nicht gespeichert.
  void write(String key, Uint8List bytes) {
    final kindEnum = MapStoreKind.of(key);
    final kind = kindEnum.index;
    final limit = _limit(kindEnum);
    if (bytes.length > limit) return;
    var evicted = false;
    _db.execute('BEGIN IMMEDIATE');
    try {
      _flushMarks();
      _db.execute(
        'INSERT OR REPLACE INTO entries (kind, key, data, size, last_used) '
        'VALUES (?, ?, ?, ?, ?)',
        [kind, key, bytes, bytes.length, ++_clock],
      );
      evicted = _evict(kind, limit);
      _db.execute('COMMIT');
    } catch (_) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
    if (evicted) _db.execute('PRAGMA incremental_vacuum');
  }

  /// Entfernt die Miniaturen des Laufs [runId] (Schlüssel `thumb:<Variante>:<Lauf>`), jede Variante. Gibt den Platz
  /// zurück. Ergebnis: Zahl der entfernten Einträge.
  int deleteRunThumbnails(int runId) {
    final kind = MapStoreKind.thumbnail.index;
    // Das Muster endet auf ":<Lauf>"; "%" und "_" in der Variante sind nicht vorgesehen, die Lauf-Nummer ist eine Zahl.
    var n = 0;
    _db.execute('BEGIN IMMEDIATE');
    try {
      _db.execute('DELETE FROM entries WHERE kind = ? AND key LIKE ?', [
        kind,
        '${MapStoreKind.thumbnailPrefix}%:$runId',
      ]);
      _marks.removeWhere((k, _) => k.$1 == kind && k.$2.endsWith(':$runId'));
      n = _db.updatedRows;
      _db.execute('COMMIT');
    } catch (_) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
    if (n > 0) _db.execute('PRAGMA incremental_vacuum');
    return n;
  }

  void _flushMarks() {
    if (_marks.isEmpty) return;
    final stmt = _db.prepare(
      'UPDATE entries SET last_used = ? WHERE kind = ? AND key = ?',
    );
    try {
      _marks.forEach((k, v) => stmt.execute([v, k.$1, k.$2]));
    } finally {
      stmt.close();
    }
    _marks.clear();
  }

  /// Löscht die am längsten ungenutzten Einträge der Art, bis die Summe unter der Grenze liegt.
  bool _evict(int kind, int limit) {
    var total =
        _db
                .select(
                  'SELECT coalesce(sum(size), 0) FROM entries WHERE kind = ?',
                  [kind],
                )
                .first
                .values
                .first
            as int;
    if (total <= limit) return false;
    final rows = _db.select(
      'SELECT rowid, size FROM entries WHERE kind = ? ORDER BY last_used, rowid',
      [kind],
    );
    final doomed = <int>[];
    for (final r in rows) {
      if (total <= limit) break;
      doomed.add(r['rowid'] as int);
      total -= r['size'] as int;
    }
    final stmt = _db.prepare('DELETE FROM entries WHERE rowid = ?');
    try {
      for (final id in doomed) {
        stmt.execute([id]);
      }
    } finally {
      stmt.close();
    }
    return doomed.isNotEmpty;
  }

  /// Summe der Inhalte je Art (für Tests und die Anzeige).
  int contentBytes(MapStoreKind kind) =>
      _db
              .select(
                'SELECT coalesce(sum(size), 0) FROM entries WHERE kind = ?',
                [kind.index],
              )
              .first
              .values
              .first
          as int;

  int count(MapStoreKind kind) =>
      _db
              .select('SELECT count(*) FROM entries WHERE kind = ?', [
                kind.index,
              ])
              .first
              .values
              .first
          as int;

  /// Wert eines PRAGMA (für Tests).
  Object? pragma(String name) => _db.select('PRAGMA $name').first.values.first;

  void close() => _db.close();
}
