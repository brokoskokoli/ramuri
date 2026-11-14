import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

class DriftProfileStore implements ProfileStore {
  DriftProfileStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<ProfileRecord> read() => guarded(() async {
    final r = await _db.select(_db.profile).getSingleOrNull();
    if (r == null) return const ProfileRecord();
    return ProfileRecord(
      birthYear: r.birthYear,
      bodyWeightKg: r.bodyWeightKg,
      bodyHeightMeters: r.bodyHeightM,
      restingHeartRateBpm: r.restingHeartRateBpm,
      maxHeartRateBpm: r.maxHeartRateBpm,
      weeklyRunMinutes: r.weeklyRunMinutes,
      trainingDaysMask: r.trainingDaysMask,
      usualTrainingMinutes: r.usualTrainingMinutes,
    );
  });

  @override
  Future<void> save(ProfileRecord p) => guarded(() async {
    validateProfile(p);
    await _db
        .into(_db.profile)
        .insertOnConflictUpdate(
          d.ProfileCompanion(
            id: const Value(1),
            birthYear: Value(p.birthYear),
            bodyWeightKg: Value(p.bodyWeightKg),
            bodyHeightM: Value(p.bodyHeightMeters),
            restingHeartRateBpm: Value(p.restingHeartRateBpm),
            maxHeartRateBpm: Value(p.maxHeartRateBpm),
            weeklyRunMinutes: Value(p.weeklyRunMinutes),
            trainingDaysMask: Value(p.trainingDaysMask),
            usualTrainingMinutes: Value(p.usualTrainingMinutes),
          ),
        );
  });
}

class DriftSettingsStore implements SettingsStore {
  DriftSettingsStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<String?> get(String key) => guarded(() async {
    final r = await (_db.select(
      _db.settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return r?.value;
  });

  @override
  Future<Map<String, String>> all() => guarded(() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final r in rows) r.key: r.value};
  });

  @override
  Future<void> set(String key, String value, {required DateTime at}) => guarded(
    () => _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          d.SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAtUs: usOf(at),
          ),
        ),
  );
}

class DriftKnownDeviceStore implements KnownDeviceStore {
  DriftKnownDeviceStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<List<KnownDevice>> list() => guarded(() async {
    final rows =
        await (_db.select(_db.knownDevices)..orderBy([
              (t) => OrderingTerm.asc(t.addedAtUs),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return [
      for (final r in rows)
        KnownDevice(
          deviceId: r.deviceId,
          displayName: r.displayName,
          isPreferred: r.isPreferred,
          addedAt: timeOf(r.addedAtUs),
          lastUsedAt: r.lastUsedAtUs == null ? null : timeOf(r.lastUsedAtUs!),
        ),
    ];
  });

  @override
  Future<void> markUsed(String deviceId, {required DateTime at}) =>
      guarded(() async {
        final n =
            await (_db.update(_db.knownDevices)
                  ..where((t) => t.deviceId.equals(deviceId)))
                .write(d.KnownDevicesCompanion(lastUsedAtUs: Value(usOf(at))));
        if (n == 0) throw const StorageException(StorageFailure.notFound);
      });

  @override
  Future<void> upsert(
    String deviceId, {
    String? displayName,
    required DateTime at,
  }) => guarded(
    () => _db.transaction(() async {
      final n = displayName == null
          ? await (_db.select(_db.knownDevices)
                  ..where((t) => t.deviceId.equals(deviceId)))
                .get()
                .then((r) => r.length)
          : await (_db.update(
              _db.knownDevices,
            )..where((t) => t.deviceId.equals(deviceId))).write(
              d.KnownDevicesCompanion(displayName: Value(displayName)),
            );
      if (n == 0) {
        await _db
            .into(_db.knownDevices)
            .insert(
              d.KnownDevicesCompanion.insert(
                deviceId: deviceId,
                displayName: Value(displayName),
                addedAtUs: usOf(at),
              ),
            );
      }
    }),
  );

  @override
  Future<void> setPreferred(String? deviceId) => guarded(
    () => _db.transaction(() async {
      if (deviceId != null) {
        final row = await (_db.select(
          _db.knownDevices,
        )..where((t) => t.deviceId.equals(deviceId))).getSingleOrNull();
        if (row == null) throw const StorageException(StorageFailure.notFound);
      }
      // Erst alle ab, dann einen an: Der Teilindex erlaubt nur einen.
      await _db
          .update(_db.knownDevices)
          .write(const d.KnownDevicesCompanion(isPreferred: Value(false)));
      if (deviceId != null) {
        await (_db.update(_db.knownDevices)
              ..where((t) => t.deviceId.equals(deviceId)))
            .write(const d.KnownDevicesCompanion(isPreferred: Value(true)));
      }
    }),
  );
}

class DriftConsentStore implements ConsentStore {
  DriftConsentStore(this._db);
  final d.AppDatabase _db;

  ConsentState _state(String s) =>
      enumOf(ConsentState.values, s, (v) => v.name);

  @override
  Future<ConsentState?> get(String sourceKey) => guarded(() async {
    final r = await (_db.select(
      _db.consents,
    )..where((t) => t.sourceKey.equals(sourceKey))).getSingleOrNull();
    return r == null ? null : _state(r.state);
  });

  @override
  Future<Map<String, ConsentState>> all() => guarded(() async {
    final rows = await _db.select(_db.consents).get();
    return {for (final r in rows) r.sourceKey: _state(r.state)};
  });

  @override
  Future<void> set(
    String sourceKey,
    ConsentState state, {
    required DateTime at,
  }) => guarded(
    () => _db
        .into(_db.consents)
        .insertOnConflictUpdate(
          d.ConsentsCompanion.insert(
            sourceKey: sourceKey,
            state: state.name,
            changedAtUs: usOf(at),
          ),
        ),
  );
}
