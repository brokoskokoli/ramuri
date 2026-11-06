import 'package:adapters/adapters.dart';
import 'package:core/core.dart';

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
  }) : permissions = permissions ?? const _NoPermissionStatus();

  /// Uhr der App (Tests setzen eine Fake-Uhr).
  final Clock clock;

  /// Stand der Android-Berechtigungen (Tests setzen den Fake aus `core`).
  final PermissionStatusPort permissions;

  /// App-Start der Speicherung: Schlüssel, Datei, Öffnen.
  final StorageStartController storageStart;

  /// Verdrahtung für den Produktivbetrieb. Der Pfad (`getNoBackupFilesDir()`)
  /// wird erst beim Start aufgelöst.
  factory AppDependencies.create() => AppDependencies(
    permissions: MethodChannelPermissionStatus(),
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
  Future<void> openSystemSettings() async {}
}
