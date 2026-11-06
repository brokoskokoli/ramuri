import 'package:adapters/adapters.dart';
import 'package:core/core.dart';

import 'features/run/run_ports.dart';
import 'features/storage/storage_start.dart';
import 'system_clock.dart';

/// Zusammenbau der Abhängigkeiten der App (ohne DI-Bibliothek).
///
/// Hier werden die Adapter aus `adapters` an die Ports aus `core` gebunden.
/// Tests setzen stattdessen die Fakes aus `core` ein.
class AppDependencies {
  const AppDependencies({
    required this.storageStart,
    this.clock = const SystemClock(),
    PermissionStatusPort? permissions,
    RunPorts? runPorts,
  }) : permissions = permissions ?? const _NoPermissionStatus(),
       runPorts = runPorts ?? const _NoRunPorts();

  /// Uhr der App (Tests setzen eine Fake-Uhr).
  final Clock clock;

  /// Stand der Android-Berechtigungen (Tests setzen den Fake aus `core`).
  final PermissionStatusPort permissions;

  /// Standortberechtigung, Standortquelle und Pulsquelle des Laufs.
  final RunPorts runPorts;

  /// App-Start der Speicherung: Schlüssel, Datei, Öffnen.
  final StorageStartController storageStart;

  /// Verdrahtung für den Produktivbetrieb. Der Pfad (`getNoBackupFilesDir()`)
  /// wird erst beim Start aufgelöst.
  factory AppDependencies.create() => AppDependencies(
    permissions: MethodChannelPermissionStatus(),
    runPorts: RunPorts(
      access: MethodChannelLocationAccess(),
      location: MethodChannelLocationSource(),
      // Pulssensoren kommen mit WP07; bis dahin „nicht verfügbar“.
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
