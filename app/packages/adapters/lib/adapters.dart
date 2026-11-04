/// Android-Adapter der Ports aus `core`.
library;

import 'package:core/core.dart';

export 'src/storage/app_database.dart';
export 'src/storage/connection_setup.dart';
export 'src/storage/encrypted_storage.dart';
export 'src/storage/no_backup_dir.dart';
export 'src/storage/random_key.dart';
export 'src/storage/secure_key_store.dart';

/// Zeigt, dass `adapters` das Paket `core` nutzen darf.
const String adaptersUsesCore = '$corePackageName-adapters';
