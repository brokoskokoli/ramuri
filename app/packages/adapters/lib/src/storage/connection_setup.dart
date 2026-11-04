import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Eine Konstante für Journal-Modus und Synchronisation (ADR-0003 Punkt 5).
/// WP08 ändert sie ggf. nach dem Ergebnis von R005; sonst nirgends.
const String journalModeSetting = 'WAL';
const String synchronousSetting = 'FULL';

/// Rückgabewerte der PRAGMAs, die zurückgelesen werden.
const int synchronousFullValue = 2;
const int tempStoreMemoryValue = 2;

/// Kopf einer unverschlüsselten SQLite-Datei (16 Byte inkl. Nullbyte).
const List<int> plainSqliteHeader = [
  0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, //
  0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00,
];

/// Zeigt an, dass die Verbindung nicht sicher eingerichtet werden konnte. Wird
/// im Hintergrund-Isolate geworfen; die Ursache bleibt absichtlich ohne Inhalt.
class ConnectionSetupFailure implements Exception {
  const ConnectionSetupFailure(this.failure);

  final StorageFailure failure;

  /// Kennung, an der die Grenze die Art des Fehlers auch dann erkennt, wenn die
  /// Ausnahme den Isolate nur als Text verlässt.
  String get tag => 'ConnectionSetupFailure:${failure.name}';

  @override
  String toString() => tag;
}

/// Sonde: Enthält die geladene SQLite-Bibliothek eine Verschlüsselung
/// (`PRAGMA cipher` nicht leer)? Top-level, damit sie in den Isolate geht.
typedef LibraryCipherProbe = bool Function(raw.Database db);

/// Sonde: Ist die Datei auf der Platte tatsächlich verschlüsselt, d. h. fehlt
/// der Klartextkopf?
typedef FileEncryptedProbe = bool Function(String path);

bool defaultLibraryCipherProbe(raw.Database db) {
  final rows = db.select('PRAGMA cipher');
  if (rows.isEmpty) return false;
  final v = rows.first.values.first;
  return v is String && v.isNotEmpty;
}

bool defaultFileEncryptedProbe(String path) {
  final f = File(path);
  if (!f.existsSync()) return false;
  final raf = f.openSync();
  try {
    final head = raf.readSync(plainSqliteHeader.length);
    if (head.length < plainSqliteHeader.length) return false;
    for (var i = 0; i < plainSqliteHeader.length; i++) {
      if (head[i] != plainSqliteHeader[i]) return true;
    }
    return false;
  } finally {
    raf.closeSync();
  }
}

/// Alles, was das Setup im Isolate braucht. Nur sendbare Werte.
class ConnectionSetup {
  const ConnectionSetup({
    required this.path,
    required this.hexKey,
    this.libraryProbe = defaultLibraryCipherProbe,
    this.fileProbe = defaultFileEncryptedProbe,
  });

  final String path;
  final String hexKey;
  final LibraryCipherProbe libraryProbe;
  final FileEncryptedProbe fileProbe;

  /// Richtet jede Verbindung ein, an genau dieser Stelle (Falle 5): Schlüssel,
  /// Prüfung, dann Journal, Synchronisation, `secure_delete`, Fremdschlüssel,
  /// Temp im Speicher. Rückgabewerte werden gelesen; jede Abweichung bricht ab.
  void apply(raw.Database db) {
    if (!libraryProbe(db)) {
      throw const ConnectionSetupFailure(StorageFailure.encryptionNotActive);
    }
    try {
      db.execute("PRAGMA hexkey = '$hexKey'");
    } catch (_) {
      // Die Ausnahme trägt das Statement und damit den Schlüssel über die
      // Isolate-Grenze; darum keine Ursache. Ein Schlüssel, den sqlite3mc
      // nicht annimmt, ist ein Fehler der Einrichtung, nicht der Datei.
      throw const ConnectionSetupFailure(StorageFailure.encryptionNotActive);
    }
    configure(db);
    // Erst nach dem ersten Zugriff existiert der Kopf der Datei.
    if (!fileProbe(path)) {
      throw const ConnectionSetupFailure(StorageFailure.encryptionNotActive);
    }
  }

  /// Die PRAGMAs nach dem Schlüssel. Eigene Methode, damit Tests die
  /// Löschprüfung (Marke weg) an einer Klartext-Datenbank mit genau diesen
  /// Einstellungen fahren können (WP02 Teil C, Falle 2).
  static void configure(raw.Database db) {
    _expect(
      db,
      'journal_mode',
      journalModeSetting.toLowerCase(),
      set: journalModeSetting,
    );
    _expect(db, 'synchronous', synchronousFullValue, set: synchronousSetting);
    _expect(db, 'secure_delete', 1, set: 'ON');
    _expect(db, 'foreign_keys', 1, set: 'ON');
    _expect(db, 'temp_store', tempStoreMemoryValue, set: 'MEMORY');
  }

  static void _expect(
    raw.Database db,
    String pragma,
    Object expected, {
    required Object set,
  }) {
    db.execute('PRAGMA $pragma = $set');
    final rows = db.select('PRAGMA $pragma');
    if (rows.isEmpty || rows.first.values.first != expected) {
      throw const ConnectionSetupFailure(StorageFailure.unreadable);
    }
  }
}

String hexOfKey(Uint8List key) {
  final b = StringBuffer();
  for (final v in key) {
    b.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return b.toString();
}
