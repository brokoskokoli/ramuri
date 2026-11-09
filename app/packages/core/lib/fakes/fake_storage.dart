import 'dart:typed_data';

import '../ports/storage.dart';
import '../ports/storage_consents.dart';
import '../ports/storage_derived.dart';
import '../ports/storage_devices.dart';
import '../ports/storage_prediction.dart';
import '../ports/storage_profile.dart';
import '../ports/storage_raw.dart';
import '../ports/storage_runs.dart';
import '../ports/storage_settings.dart';
import '../ports/storage_values.dart';
import 'fake_storage_data.dart';
import 'fake_storage_derived.dart';
import 'fake_storage_prediction.dart';
import 'fake_storage_runs.dart';
import 'fake_storage_settings.dart';

/// Speicher im Arbeitsspeicher. Der erste Schlüssel legt die "Datei" an.
class FakeStorage implements Storage {
  FakeStorage({this.encryptionActive = true});

  /// `false` simuliert eine Laufzeit ohne aktive Verschlüsselung.
  bool encryptionActive;

  /// Simuliert eine beschädigte Datei.
  bool corrupted = false;

  /// Wenn gesetzt, scheitert das Öffnen mit dieser Art (etwa `newerVersion`).
  StorageFailure? openFailure;

  Uint8List? _fileKey;

  /// Inhalt der "Datei"; bleibt über Sitzungen erhalten.
  final FakeStorageData data = FakeStorageData();

  /// Simuliert einen nicht durchgelaufenen Checkpoint: Gelöscht wird, danach
  /// meldet das Löschen [StorageFailure.deletedNotErased].
  bool checkpointIncomplete = false;

  int openSessions = 0;

  @override
  Future<StorageSession> open(Uint8List key) async {
    if (!encryptionActive) {
      throw const StorageException(StorageFailure.encryptionNotActive);
    }
    final failure = openFailure;
    if (failure != null) throw StorageException(failure);
    final fileKey = _fileKey;
    if (corrupted || (fileKey != null && !_same(fileKey, key))) {
      throw const StorageException(StorageFailure.unreadable);
    }
    _fileKey ??= Uint8List.fromList(key);
    openSessions++;
    return _FakeSession(this, data);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FakeSession implements StorageSession, PredictionStorage {
  _FakeSession(this._owner, this._data)
    : runs = FakeRunStore(_data),
      markers = FakeRunMarkerStore(_data),
      rawData = FakeRawDataStore(_data),
      preprocessing = FakePreprocessingStore(_data),
      sections = FakeRatedSectionStore(_data),
      values = FakeComputedValueStore(_data),
      profile = FakeProfileStore(_data),
      settings = FakeSettingsStore(_data),
      devices = FakeKnownDeviceStore(_data),
      consents = FakeConsentStore(_data),
      prediction = FakePredictionStore(_data);

  final FakeStorage _owner;
  final FakeStorageData _data;
  bool _closed = false;

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
  final PredictionStore prediction;

  @override
  Future<void> deleteRun(int runId) async {
    _open();
    _data.requireRun(runId);
    _data.deleteRun(runId);
    _afterDelete();
  }

  @override
  Future<void> deleteAll() async {
    _open();
    _data.deleteAll();
    _afterDelete();
  }

  void _open() {
    if (_closed) throw const StorageException(StorageFailure.failed);
  }

  void _afterDelete() {
    if (_owner.checkpointIncomplete) {
      throw const StorageException(StorageFailure.deletedNotErased);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _owner.openSessions--;
  }
}
