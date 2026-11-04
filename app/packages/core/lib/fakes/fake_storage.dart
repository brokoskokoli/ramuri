import 'dart:typed_data';

import '../ports/storage.dart';
import '../ports/storage_consents.dart';
import '../ports/storage_derived.dart';
import '../ports/storage_devices.dart';
import '../ports/storage_profile.dart';
import '../ports/storage_raw.dart';
import '../ports/storage_runs.dart';
import '../ports/storage_settings.dart';
import '../ports/storage_values.dart';
import 'fake_storage_data.dart';
import 'fake_storage_derived.dart';
import 'fake_storage_runs.dart';
import 'fake_storage_settings.dart';

/// Speicher im Arbeitsspeicher. Der erste Schlüssel legt die "Datei" an.
class FakeStorage implements Storage {
  FakeStorage({this.encryptionActive = true});

  /// `false` simuliert eine Laufzeit ohne aktive Verschlüsselung.
  bool encryptionActive;

  /// Simuliert eine beschädigte Datei.
  bool corrupted = false;

  Uint8List? _fileKey;

  /// Inhalt der "Datei"; bleibt über Sitzungen erhalten.
  final FakeStorageData data = FakeStorageData();

  /// Entspricht `DELETE FROM runs WHERE id = ?`: Kaskade über alles unter dem
  /// Lauf. Der Port hat dafür noch keine Methode (WP02 Teil C legt sie an).
  void deleteRun(int runId) => data.deleteRun(runId);
  int openSessions = 0;

  @override
  Future<StorageSession> open(Uint8List key) async {
    if (!encryptionActive) {
      throw const StorageException(StorageFailure.encryptionNotActive);
    }
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

class _FakeSession implements StorageSession {
  _FakeSession(this._owner, FakeStorageData d)
    : runs = FakeRunStore(d),
      markers = FakeRunMarkerStore(d),
      rawData = FakeRawDataStore(d),
      preprocessing = FakePreprocessingStore(d),
      sections = FakeRatedSectionStore(d),
      values = FakeComputedValueStore(d),
      profile = FakeProfileStore(d),
      settings = FakeSettingsStore(d),
      devices = FakeKnownDeviceStore(d),
      consents = FakeConsentStore(d);

  final FakeStorage _owner;
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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _owner.openSessions--;
  }
}
