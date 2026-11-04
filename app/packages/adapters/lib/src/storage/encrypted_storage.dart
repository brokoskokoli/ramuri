import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';

import 'app_database.dart';
import 'connection_setup.dart';

/// Offene, verschlüsselte Datenbank. Teil B hängt hier die Zugriffe ein.
class EncryptedStorageSession implements StorageSession {
  EncryptedStorageSession(this.database);

  final AppDatabase database;

  @override
  Future<void> close() => database.close();
}

/// Port [Storage] auf drift mit SQLite3MultipleCiphers (ADR-0003 Punkt 1).
/// Öffnen ist fail-closed: Ist die Verschlüsselung nicht belegt aktiv oder der
/// Schlüssel falsch, entsteht eine [StorageException] ohne Inhalte.
class EncryptedStorage implements Storage {
  EncryptedStorage(
    this.path, {
    this.libraryProbe = defaultLibraryCipherProbe,
    this.fileProbe = defaultFileEncryptedProbe,
    this.databaseBuilder = AppDatabase.new,
  });

  final String path;

  /// Nur für Tests austauschbar (Fehlweg "Verschlüsselung nicht aktiv").
  final LibraryCipherProbe libraryProbe;
  final FileEncryptedProbe fileProbe;

  /// Nur für Tests austauschbar (Migrationstest mit synthetischem Schritt).
  final AppDatabase Function(QueryExecutor) databaseBuilder;

  /// `true`, wenn `db`, `-wal` oder `-shm` existiert (Falle 6).
  Future<bool> filesExist() async {
    for (final suffix in const ['', '-wal', '-shm']) {
      if (await File('$path$suffix').exists()) return true;
    }
    return false;
  }

  @override
  Future<StorageSession> open(Uint8List key) async {
    if (key.length != storageKeyLength) {
      throw const StorageException(StorageFailure.encryptionNotActive);
    }
    final setup = ConnectionSetup(
      path: path,
      hexKey: hexOfKey(key),
      libraryProbe: libraryProbe,
      fileProbe: fileProbe,
    );
    final executor = NativeDatabase.createInBackground(
      File(path),
      logStatements: false,
      setup: setup.apply,
    );
    final db = databaseBuilder(executor);
    try {
      // Sofort öffnen, nicht erst beim ersten Zugriff.
      await db.customSelect('SELECT 1').get();
    } catch (e) {
      final failure = storageFailureOf(e);
      try {
        await db.close();
      } catch (_) {}
      // Absichtlich ohne Ursache: sie könnte Statement und Parameter tragen.
      throw StorageException(failure);
    }
    return EncryptedStorageSession(db);
  }
}

/// Ordnet einen Fehler aus drift oder sqlite3 einer [StorageFailure] zu, nur
/// anhand der Art. `SqliteException` und `DriftRemoteException` tragen im Text
/// Statement und Parameter (Daten, ggf. Schlüssel); darum wird nie der Text
/// weitergegeben (Falle 4).
StorageFailure storageFailureOf(Object e) {
  if (e is ConnectionSetupFailure) return e.failure;
  final text = e.toString();
  for (final f in StorageFailure.values) {
    if (text.contains('ConnectionSetupFailure:${f.name}')) return f;
  }
  return StorageFailure.unreadable;
}

/// Übersetzt jeden Fehler der Zugriffsschicht an der Grenze in eine
/// [StorageException] ohne Inhalte und ohne angehängte Ursache.
StorageException translateStorageError(Object e) =>
    e is StorageException ? e : StorageException(storageFailureOf(e));
