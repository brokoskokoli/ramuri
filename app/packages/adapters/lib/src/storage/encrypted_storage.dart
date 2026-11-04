import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show QueryExecutor;
// Nur hier erreichbar: Der Fehler aus dem Hintergrund-Isolate trägt die
// SqliteException als remoteCause. Die Bibliothek markiert das als
// experimentell; ein Test (Zugriffstests) fängt eine Änderung ab.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:drift/native.dart';

import 'app_database.dart';
import 'connection_setup.dart';
import 'database_files.dart';
import 'delete_access.dart';
import 'derived_access.dart';
import 'raw_access.dart';
import 'run_access.dart';
import 'settings_access.dart';
import 'value_access.dart';

/// Offene, verschlüsselte Datenbank mit den Zugriffen des Ports. Jeder
/// Zugriff läuft über `guarded` und damit über [translateStorageError].
class EncryptedStorageSession implements StorageSession {
  EncryptedStorageSession(this.database)
    : runs = DriftRunStore(database),
      markers = DriftRunMarkerStore(database),
      rawData = DriftRawDataStore(database),
      preprocessing = DriftPreprocessingStore(database),
      sections = DriftRatedSectionStore(database),
      values = DriftComputedValueStore(database),
      profile = DriftProfileStore(database),
      settings = DriftSettingsStore(database),
      devices = DriftKnownDeviceStore(database),
      consents = DriftConsentStore(database);

  final AppDatabase database;
  late final DriftDeletion _deletion = DriftDeletion(database);

  @override
  final RunStore runs;
  @override
  final RunMarkerStore markers;
  @override
  final RawDataStore rawData;
  @override
  final PreprocessingStore preprocessing;
  @override
  final RatedSectionStore sections;
  @override
  final ComputedValueStore values;
  @override
  final ProfileStore profile;
  @override
  final SettingsStore settings;
  @override
  final KnownDeviceStore devices;
  @override
  final ConsentStore consents;

  @override
  Future<void> deleteRun(int runId) => _deletion.deleteRun(runId);

  @override
  Future<void> deleteAll() => _deletion.deleteAll();

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

  /// `true`, wenn `db`, `-wal`, `-shm` oder `-journal` existiert (Falle 6).
  Future<bool> filesExist() => FileDatabaseFiles(path).exist();

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

/// Ordnet einen Fehler beim Öffnen einer [StorageFailure] zu, nur anhand der
/// Art. `SqliteException` und `DriftRemoteException` tragen im Text Statement
/// und Parameter (Daten, ggf. Schlüssel); darum wird nie der Text
/// weitergegeben (Falle 4).
StorageFailure storageFailureOf(Object e) =>
    _setupFailureOf(e) ?? StorageFailure.unreadable;

StorageFailure? _setupFailureOf(Object e) {
  if (e is ConnectionSetupFailure) return e.failure;
  final text = e.toString();
  for (final f in StorageFailure.values) {
    if (text.contains('ConnectionSetupFailure:${f.name}')) return f;
  }
  return null;
}

/// SQLITE_CONSTRAINT (19) und seine Unterarten (Trigger, Prüfregel,
/// Eindeutigkeit, Fremdschlüssel). Aus dem Hintergrund-Isolate kommt die
/// SqliteException als `remoteCause` der DriftRemoteException an.
bool _isConstraintViolation(Object e) {
  final cause = e is DriftRemoteException ? e.remoteCause : e;
  return cause is SqliteException && (cause.extendedResultCode & 0xff) == 19;
}

/// Übersetzt jeden Fehler der Zugriffsschicht an der Grenze in eine
/// [StorageException] ohne Inhalte und ohne angehängte Ursache. Abgelehnte
/// Eingaben (Beschränkung, Trigger) sind `rejected`, alles andere `failed`;
/// `unreadable` bleibt dem Öffnen vorbehalten (Dialog OQ-0062).
StorageException translateStorageError(Object e) {
  if (e is StorageException) return e;
  final setup = _setupFailureOf(e);
  if (setup != null) return StorageException(setup);
  if (_isConstraintViolation(e)) {
    return const StorageException(StorageFailure.rejected);
  }
  return const StorageException(StorageFailure.failed);
}
