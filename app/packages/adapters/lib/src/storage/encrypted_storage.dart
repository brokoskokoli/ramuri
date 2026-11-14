import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:flutter/foundation.dart' show visibleForTesting;
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
import 'goal_access.dart';
import 'plan_access.dart';
import 'prediction_access.dart';
import 'raw_access.dart';
import 'run_access.dart';
import 'settings_access.dart';
import 'subjective_access.dart';
import 'value_access.dart';
import 'health_access.dart';
import 'warning_access.dart';

/// Offene, verschlüsselte Datenbank mit den Zugriffen des Ports. Jeder
/// Zugriff läuft über `guarded` und damit über [translateStorageError].
class EncryptedStorageSession
    implements
        StorageSession,
        PredictionStorage,
        GoalStorage,
        PlanStorage,
        WarningStorage,
        HealthStorage {
  EncryptedStorageSession(this.database, {this.onDeleteAll})
    : runs = DriftRunStore(database),
      markers = DriftRunMarkerStore(database),
      rawData = DriftRawDataStore(database),
      preprocessing = DriftPreprocessingStore(database),
      sections = DriftRatedSectionStore(database),
      values = DriftComputedValueStore(database),
      profile = DriftProfileStore(database),
      settings = DriftSettingsStore(database),
      devices = DriftKnownDeviceStore(database),
      consents = DriftConsentStore(database),
      subjective = DriftRunSubjectiveStore(database),
      manualTrainings = DriftManualTrainingStore(database),
      prediction = DriftPredictionStore(database),
      goals = DriftGoalStore(database),
      plans = DriftPlanRepository(database),
      warning = DriftWarningStore(database),
      health = DriftHealthStore(database);

  final AppDatabase database;

  /// "Alles löschen" räumt auch abgeleitete Dateien ab (Kartenspeicher, WP13). Scheitert das, gilt das Löschen der
  /// Datenbank, aber nicht als vollständig ([StorageFailure.deletedNotErased]).
  final Future<void> Function()? onDeleteAll;
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
  final RunSubjectiveStore subjective;
  @override
  final ManualTrainingStore manualTrainings;
  @override
  final PredictionStore prediction;

  @override
  final GoalStore goals;

  @override
  final PlanRepository plans;

  @override
  final WarningStore warning;

  @override
  final HealthImportStore health;

  @override
  Future<void> deleteRun(int runId) => _deletion.deleteRun(runId);

  @override
  Future<void> deleteAll() async {
    await _deletion.deleteAll();
    final extra = onDeleteAll;
    if (extra == null) return;
    try {
      await extra();
    } catch (_) {
      throw const StorageException(StorageFailure.deletedNotErased);
    }
  }

  /// Schließt die Verbindung. SQLite checkpointet beim Schließen der letzten
  /// Verbindung; ob das gelang, weist diese Methode nicht nach. Wer die Dateien
  /// danach ersetzt (WP12), prüft das `-wal` selbst
  /// ([FileDatabaseFiles.replaceWithImport]).
  @override
  Future<void> close() => database.close();
}

/// Port [Storage] auf drift mit SQLite3MultipleCiphers (ADR-0003 Punkt 1).
/// Öffnen ist fail-closed: Ist die Verschlüsselung nicht belegt aktiv oder der
/// Schlüssel falsch, entsteht eine [StorageException] ohne Inhalte.
class EncryptedStorage implements Storage {
  EncryptedStorage(
    String path, {
    LibraryCipherProbe libraryProbe = defaultLibraryCipherProbe,
    FileEncryptedProbe fileProbe = defaultFileEncryptedProbe,
    AppDatabase Function(QueryExecutor) databaseBuilder = AppDatabase.new,
    Future<void> Function()? onDeleteAll,
  }) : this._(
         path,
         libraryProbe: libraryProbe,
         fileProbe: fileProbe,
         databaseBuilder: databaseBuilder,
         onDeleteAll: onDeleteAll,
       );

  /// Nur für Tests: dazu `isolateSetup` und `logStatements`. Die Analyse
  /// meldet jede Nutzung außerhalb von Tests (`invalid_use_of_visible_for_
  /// testing_member`), sodass `logStatements: true` nie unbemerkt in die
  /// App gelangt.
  @visibleForTesting
  EncryptedStorage.forTest(
    String path, {
    LibraryCipherProbe libraryProbe = defaultLibraryCipherProbe,
    FileEncryptedProbe fileProbe = defaultFileEncryptedProbe,
    AppDatabase Function(QueryExecutor) databaseBuilder = AppDatabase.new,
    FutureOr<void> Function()? isolateSetup,
    bool logStatements = false,
  }) : this._(
         path,
         libraryProbe: libraryProbe,
         fileProbe: fileProbe,
         databaseBuilder: databaseBuilder,
         isolateSetup: isolateSetup,
         logStatements: logStatements,
       );

  EncryptedStorage._(
    this.path, {
    required this.libraryProbe,
    required this.fileProbe,
    required this.databaseBuilder,
    this.isolateSetup,
    this.logStatements = false,
    this.onDeleteAll,
  });

  final String path;

  /// Siehe [EncryptedStorageSession.onDeleteAll].
  final Future<void> Function()? onDeleteAll;

  /// Nur für Tests austauschbar (Fehlweg "Verschlüsselung nicht aktiv").
  final LibraryCipherProbe libraryProbe;
  final FileEncryptedProbe fileProbe;

  /// Nur für Tests: läuft im Hintergrund-Isolate vor dem Öffnen (etwa um dessen
  /// Log-Ausgabe umzuleiten, denn `driftRuntimeOptions` gilt je Isolate).
  final FutureOr<void> Function()? isolateSetup;

  /// Nur für Tests (Positivkontrolle des Log-Tests). Produktiv immer `false`:
  /// Die Statements tragen Parameter, also Daten.
  final bool logStatements;

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
      logStatements: logStatements,
      setup: setup.apply,
      isolateSetup: isolateSetup,
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
    return EncryptedStorageSession(db, onDeleteAll: onDeleteAll);
  }
}

/// Ordnet einen Fehler beim Öffnen einer [StorageFailure] zu, nur anhand der
/// Art. `unreadable` (sofortiger Neubeginn) gilt nur für SQLITE_NOTADB (26,
/// falscher Schlüssel oder keine Datenbank) und SQLITE_CORRUPT (11); jeder
/// andere Fehler (E/A, Rechte, Sperre, voller Speicher) ist `openFailed`,
/// denn die Datei kann gesund sein. `SqliteException` und `DriftRemoteException` tragen im Text Statement
/// und Parameter (Daten, ggf. Schlüssel); darum wird nie der Text
/// weitergegeben (Falle 4). Die Textprüfung gilt nur hier: Beim Öffnen stehen
/// keine Nutzdaten im Text.
StorageFailure storageFailureOf(Object e) =>
    _setupFailureOf(e) ??
    (_isUnreadableFile(e)
        ? StorageFailure.unreadable
        : StorageFailure.openFailed);

/// Gemessen (WP02 fix4): Falscher Schlüssel, Datei aus Müll, abgeschnittene
/// Datei und beschädigte erste Seite kommen über den Hintergrund-Isolate als
/// `DriftRemoteException` mit `remoteCause` SqliteException Code 26 an; ein
/// Verzeichnis statt Datei als Code 14 (CANTOPEN).
bool _isUnreadableFile(Object e) {
  final cause = e is DriftRemoteException ? e.remoteCause : e;
  if (cause is! SqliteException) return false;
  final code = cause.extendedResultCode & 0xff;
  return code == 26 || code == 11;
}

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
/// `unreadable` bleibt dem Öffnen vorbehalten (Dialog OQ-0062). Die Kennung der
/// Einrichtung ([ConnectionSetupFailure]) wird hier nie aus dem Text gelesen:
/// Nach dem Öffnen steht im Text der Parameter, also Nutzdaten, die die Art
/// fälschen könnten.
StorageException translateStorageError(Object e) {
  if (e is StorageException) return e;
  if (_isConstraintViolation(e)) {
    return const StorageException(StorageFailure.rejected);
  }
  return const StorageException(StorageFailure.failed);
}
