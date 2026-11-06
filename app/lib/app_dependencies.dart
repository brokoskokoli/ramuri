import 'package:adapters/adapters.dart';
import 'package:core/core.dart';

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
  }) : permissions = permissions ?? const _NoPermissionStatus(),
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
      sensors: sensors,
      permissions: permissions,
      runPorts: RunPorts(
        access: MethodChannelLocationAccess(),
        location: MethodChannelLocationSource(),
        heartRateRun: sensors.beginRun,
        connectSensors: sensors.connectKnown,
        recordingService: MethodChannelRecordingService(),
      ),
      storageStart: StorageStartController(
        keyStore: SecureKeyStore(),
        generateKey: generateStorageKey,
        wire: () async {
          final path = await databasePath();
          return StorageWiring(
            storage: EncryptedStorage(path),
            files: FileDatabaseFiles(path),
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
  Stream<HeartRateReading> Function()? get heartRate => null;

  @override
  RunHeartRate Function()? get heartRateRun => null;

  @override
  Future<void> Function()? get connectSensors => null;

  @override
  RecordingServicePort? get recordingService => null;
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
