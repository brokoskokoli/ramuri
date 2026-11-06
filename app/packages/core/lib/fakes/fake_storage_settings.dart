import '../ports/storage.dart';
import '../ports/storage_consents.dart';
import '../ports/storage_devices.dart';
import '../ports/storage_profile.dart';
import '../ports/storage_settings.dart';
import 'fake_storage_data.dart';

class FakeProfileStore implements ProfileStore {
  FakeProfileStore(this._d);
  final FakeStorageData _d;

  @override
  Future<ProfileRecord> read() async => _d.profile;

  @override
  Future<void> save(ProfileRecord profile) async {
    validateProfile(profile);
    _d.profile = profile;
  }
}

class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore(this._d);
  final FakeStorageData _d;

  @override
  Future<String?> get(String key) async => _d.settings[key];

  @override
  Future<Map<String, String>> all() async => Map.of(_d.settings);

  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    _d.settings[key] = value;
  }
}

class FakeKnownDeviceStore implements KnownDeviceStore {
  FakeKnownDeviceStore(this._d);
  final FakeStorageData _d;

  @override
  Future<List<KnownDevice>> list() async => List.of(_d.devices);

  @override
  Future<void> upsert(
    String deviceId, {
    String? displayName,
    required DateTime at,
  }) async {
    final i = _d.devices.indexWhere((d) => d.deviceId == deviceId);
    if (i < 0) {
      _d.devices.add(
        KnownDevice(
          deviceId: deviceId,
          displayName: displayName,
          addedAt: at.toUtc(),
        ),
      );
      return;
    }
    final d = _d.devices[i];
    _d.devices[i] = KnownDevice(
      deviceId: deviceId,
      displayName: displayName ?? d.displayName,
      isPreferred: d.isPreferred,
      addedAt: d.addedAt,
    );
  }

  @override
  Future<void> setPreferred(String? deviceId) async {
    if (deviceId != null && !_d.devices.any((d) => d.deviceId == deviceId)) {
      throw const StorageException(StorageFailure.notFound);
    }
    for (var i = 0; i < _d.devices.length; i++) {
      final d = _d.devices[i];
      _d.devices[i] = KnownDevice(
        deviceId: d.deviceId,
        displayName: d.displayName,
        isPreferred: d.deviceId == deviceId,
        addedAt: d.addedAt,
      );
    }
  }
}

class FakeConsentStore implements ConsentStore {
  FakeConsentStore(this._d);
  final FakeStorageData _d;

  @override
  Future<ConsentState?> get(String sourceKey) async => _d.consents[sourceKey];

  @override
  Future<Map<String, ConsentState>> all() async => Map.of(_d.consents);

  @override
  Future<void> set(
    String sourceKey,
    ConsentState state, {
    required DateTime at,
  }) async {
    _d.consents[sourceKey] = state;
  }
}
