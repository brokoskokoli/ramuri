import 'package:adapters/adapters.dart';
import 'package:core/core.dart';

import 'features/archive/archive_wiring.dart';
import 'features/map/map_services.dart';
import 'features/run/method_channel_recording_service.dart';
import 'features/run/run_ports.dart';
import 'features/sensors/run_heart_rate.dart';
import 'features/sensors/sensor_manager.dart';
import 'features/storage/storage_start.dart';
import 'system_clock.dart';

/// Zusammenbau der Abhängigkeiten der App (ohne DI-Bibliothek).
///
/// Hier werden die Adapter aus `adapters` an die Ports aus `core` gebunden.
/// Tests setzen stattdessen die Fakes aus `core` ein.
class AppDependencies {
  AppDependencies({
    required this.storageStart,
    this.clock = const SystemClock(),
    PermissionStatusPort? permissions,
    RunPorts? runPorts,
    this.heartRateSensor,
    SensorManager? sensors,
    this.offload = isolateOffload,
    FileHandoff? fileHandoff,
    this.archiveExport,
    this.archiveRestore,
    this.archiveVerify,
    this.mapCache,
    this.map,
  }) : fileHandoff = fileHandoff ?? const _NoFileHandoff(),
       permissions = permissions ?? const _NoPermissionStatus(),
       runPorts = runPorts ?? const _NoRunPorts(),
       sensors =
           sensors ??
           SensorManager(
             sensor: heartRateSensor ?? const _NoHeartRateSensor(),
             clock: clock,
           );

  /// Uhr der App (Tests setzen eine Fake-Uhr).
  final Clock clock;

  /// Stand der Android-Berechtigungen (Tests setzen den Fake aus `core`).
  final PermissionStatusPort permissions;

  /// Standortberechtigung, Standortquelle und Pulsquelle des Laufs.
  final RunPorts runPorts;

  /// Pulssensoren (Suche und Verbindung). `null` in Tests ohne Sensor.
  final HeartRateSensor? heartRateSensor;

  /// Wo die Wiedergabe der Rohdaten rechnet (Zusammenfassung, Historie,
  /// Statistik). Vorgabe: eigener Isolate; Tests setzen den Inline-Offload.
  final Offload offload;

  /// Teilen und Speichern von Exportdateien (FR-0201); Tests setzen den Fake
  /// aus `core`.
  final FileHandoff fileHandoff;

  /// Export des Gesamtarchivs (WP12). `null`: Die Oberfläche bietet ihn nicht
  /// an (Tests ohne Archiv); Tests setzen einen Fake.
  final ArchiveExportFactory? archiveExport;

  /// Wiederherstellung aus einem Archiv (WP12, FR-0198). `null`: nicht
  /// verdrahtet (Tests), dann bietet die Oberfläche den Import nicht an.
  final ArchiveRestoreFactory? archiveRestore;

  /// Prüfung eines Archivs ohne Schreiben (SEC-0009, Weg im Dialog "nicht zu
  /// öffnen"). `null`: nicht verdrahtet.
  final ArchiveVerifier? archiveVerify;

  /// Kartenspeicher (WP13). `null` in Tests. Löschen und Größe gibt Teil A3 an die Oberfläche; "Alles löschen" und
  /// der Neubeginn räumen ihn ab.
  final EncryptedMapTileStore? mapCache;

  /// Kartenanbieter für die Oberfläche (Tor, Speichergröße, Löschen). `null`: nicht verdrahtet (Tests), dann bietet die
  /// Oberfläche keine Karte an.
  final MapServices? map;

  /// App-weiter Sensordienst: Verbindungen, bekannte Geräte, Puls (WP07).
  final SensorManager sensors;

  /// App-Start der Speicherung: Schlüssel, Datei, Öffnen.
  final StorageStartController storageStart;

  /// Verdrahtung für den Produktivbetrieb. Der Pfad (`getNoBackupFilesDir()`)
  /// wird erst beim Start aufgelöst.
  ///
  /// [heartRateSensor]: Vorgabe ist der Bluetooth-Adapter. Nur der Debug-
  /// Einstiegspunkt (`main_debug.dart`) setzt hier den Test-Sensor ein.
  factory AppDependencies.create({HeartRateSensor? heartRateSensor}) {
    final sensor =
        heartRateSensor ??
        BleHeartRateSensor(const UniversalBleLink(), const SystemClock());
    final permissions = MethodChannelPermissionStatus();
    final fileHandoff = MethodChannelFileHandoff();
    final keyStore = SecureKeyStore();
    // WP13: Kartenspeicher mit dem Schlüssel der Datenbank; geöffnet wird er erst beim ersten Zugriff.
    final mapCache = EncryptedMapTileStore(
      directory: noBackupFilesDir,
      key: () => keyStore.read(storageKeyName),
    );
    final sensors = SensorManager(
      sensor: sensor,
      clock: const SystemClock(),
      // Nur der echte Adapter braucht Bluetooth-Rechte; sie werden erst
      // beim Einrichten eines Sensors angefragt.
      requestPermissions: sensor is BleHeartRateSensor
          ? sensor.requestPermissions
          : null,
      bluetoothAvailable: sensor is BleHeartRateSensor
          ? sensor.isBluetoothOn
          : null,
      // Nur lesen (kein Dialog): Stand aus der Berechtigungsseite (WP05).
      bluetoothGranted: sensor is BleHeartRateSensor
          ? () async =>
                (await permissions.status())[AppPermission.bluetooth] ==
                PermissionState.granted
          : null,
    );
    return AppDependencies(
      heartRateSensor: sensor,
      mapCache: mapCache,
      map: MapServices.production(mapCache),
      sensors: sensors,
      permissions: permissions,
      fileHandoff: fileHandoff,
      archiveExport: (session) {
        // Nur die echte Sitzung hat eine Datenbank, die das Archiv liest.
        final exporter = ArchiveExporter(
          source: DriftArchiveSource(
            (session as EncryptedStorageSession).database,
          ),
          handoff: fileHandoff,
          clock: const SystemClock(),
          cipherFactory: createArchiveCipherInWorker,
        );
        return exporter.export;
      },
      archiveRestore: (session, serialize) async {
        final path = await databasePath();
        final files = FileDatabaseFiles(path);
        final storage = EncryptedStorage(path, onDeleteAll: mapCache.delete);
        final key = await keyStore.read(storageKeyName);
        if (key == null) {
          throw const ArchiveRestoreException(
            ArchiveRestoreFailure.keyUnavailable,
          );
        }
        final service = ArchiveRestoreService(
          session: session,
          sink: DriftArchiveSink(
            storage: EncryptedStorage(files.importPath),
            key: () => key,
            files: files,
          ),
          files: files,
          cipherFactory: createArchiveCipherInWorker,
          reopen: () => storage.open(key),
          serialize: serialize,
        );
        return service.restore;
      },
      // SEC-0009: Zwischendatenbank mit flüchtigem Zufallsschlüssel (nie im
      // KeyStore), damit auch die Beschränkungen der Datenbank prüfen.
      archiveVerify: ({required path, required password, cancel}) async =>
          verifyArchive(
            path: path,
            password: password,
            files: FileDatabaseFiles(await databasePath()),
            cipherFactory: createArchiveCipherInWorker,
            cancel: cancel,
          ),
      runPorts: RunPorts(
        access: MethodChannelLocationAccess(),
        location: MethodChannelLocationSource(),
        heartRateRun: sensors.beginRun,
        connectSensors: sensors.connectKnown,
        recordingService: MethodChannelRecordingService(),
        requestNotifications: requestNotificationPermission,
        cadence: MethodChannelCadenceSensor(),
        requestActivityRecognition: requestActivityRecognitionPermission,
      ),
      storageStart: StorageStartController(
        keyStore: keyStore,
        generateKey: generateStorageKey,
        wire: () async {
          final path = await databasePath();
          return StorageWiring(
            storage: EncryptedStorage(path, onDeleteAll: mapCache.delete),
            files: FileDatabaseFiles(path, alsoDelete: mapCache.delete),
          );
        },
      ),
    );
  }
}

/// Vorgabe ohne Sensor (Tests): nichts zu finden, Verbinden scheitert.
class _NoHeartRateSensor implements HeartRateSensor {
  const _NoHeartRateSensor();

  @override
  Stream<HeartRateDevice> scan() => const Stream.empty();

  @override
  Stream<HeartRateEvent> connect(String deviceId) =>
      Stream.error(StateError('kein Sensor'));
}

/// Vorgabe ohne Plattform (Tests, die nichts exportieren): Jede Übergabe
/// scheitert. Produktiv setzt `create` den Plattformkanal.
class _NoFileHandoff implements FileHandoff {
  const _NoFileHandoff();

  @override
  Future<FileHandoffResult> share(ExportFile file) async =>
      FileHandoffResult.failed;

  @override
  Future<FileHandoffResult> save(ExportFile file) async =>
      FileHandoffResult.failed;

  @override
  Future<String?> exportDirectory() async => null;

  @override
  Future<FilePickResult> pickFile() async => const FilePickResult.failed();

  @override
  Future<void> discardPicked() async {}
}

/// Vorgabe ohne Plattform: Der Stand ist unbekannt (Tests, die ihn nicht
/// brauchen). Produktiv setzt `create` den Plattformaufruf.
class _NoPermissionStatus implements PermissionStatusPort {
  const _NoPermissionStatus();

  @override
  Future<Map<AppPermission, PermissionState>> status() async => {
    for (final p in AppPermission.values) p: PermissionState.unknown,
  };

  @override
  Future<Set<AppPermission>> requested() async => {...AppPermission.values};

  @override
  Future<void> openSystemSettings() async {}
}

/// Vorgabe ohne Plattform (Tests, die keinen Lauf brauchen): kein Standort
/// erteilt, keine Punkte. Produktiv setzt `create` die Adapter.
class _NoRunPorts implements RunPorts {
  const _NoRunPorts();

  @override
  LocationAccessPort get access => _DeniedAccess();

  @override
  LocationSource get location => _EmptySource();

  @override
  RunHeartRate Function()? get heartRateRun => null;

  @override
  Future<void> Function()? get connectSensors => null;

  @override
  RecordingServicePort? get recordingService => null;

  @override
  Future<void> Function()? get requestNotifications => null;

  @override
  CadenceSensor? get cadence => null;

  @override
  Future<void> Function()? get requestActivityRecognition => null;
}

class _DeniedAccess implements LocationAccessPort {
  @override
  Future<LocationAccess> access() async => LocationAccess.denied;
  @override
  Future<LocationAccess> request() async => LocationAccess.denied;
  @override
  Future<bool> gpsEnabled() async => false;
}

class _EmptySource implements LocationSource {
  @override
  Stream<LocationSample> samples() => const Stream.empty();
}
