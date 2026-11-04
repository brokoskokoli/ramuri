import 'package:adapters/adapters.dart';

import 'features/storage/storage_start.dart';

/// Zusammenbau der Abhängigkeiten der App (ohne DI-Bibliothek).
///
/// Hier werden die Adapter aus `adapters` an die Ports aus `core` gebunden.
/// Tests setzen stattdessen die Fakes aus `core` ein.
class AppDependencies {
  const AppDependencies({required this.storageStart});

  /// App-Start der Speicherung: Schlüssel, Datei, Öffnen.
  final StorageStartController storageStart;

  /// Verdrahtung für den Produktivbetrieb. Der Pfad (`getNoBackupFilesDir()`)
  /// wird erst beim Start aufgelöst.
  factory AppDependencies.create() => AppDependencies(
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
