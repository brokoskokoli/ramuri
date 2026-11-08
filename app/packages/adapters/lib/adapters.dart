/// Android-Adapter der Ports aus `core`.
library;

import 'package:core/core.dart';

export 'src/archive/archive_verification.dart';
export 'src/archive/cryptography_archive.dart';
export 'src/archive/drift_archive_sink.dart';
export 'src/archive/drift_archive_source.dart';
export 'src/export/method_channel_file_handoff.dart';
export 'src/map/encrypted_map_tile_store.dart';
export 'src/map/map_cache_core.dart'
    show
        MapStoreKind,
        mapCacheFileName,
        mapCacheSuffixes,
        mapThumbnailLimitBytes,
        mapTileLimitBytes;
export 'src/map/map_gate.dart';
export 'src/map/map_provider.dart';
export 'src/map/map_tile_source.dart';
export 'src/location/method_channel_location.dart';
export 'src/permissions/method_channel_permission_status.dart';
export 'src/sensors/ble_heart_rate_sensor.dart';
export 'src/sensors/ble_link.dart';
export 'src/sensors/method_channel_cadence.dart';
export 'src/sensors/universal_ble_link.dart';
export 'src/storage/app_database.dart';
export 'src/storage/connection_setup.dart';
export 'src/storage/database_files.dart';
export 'src/storage/encrypted_storage.dart';
export 'src/storage/no_backup_dir.dart';
export 'src/storage/random_key.dart';
export 'src/storage/secure_key_store.dart';

/// Zeigt, dass `adapters` das Paket `core` nutzen darf.
const String adaptersUsesCore = '$corePackageName-adapters';
