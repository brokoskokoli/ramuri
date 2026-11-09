import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Speicher, dessen Einstellungen sich festhalten ([hold]) oder lesend
/// scheitern lassen ([failGets]); alles andere reicht er unverändert durch.
class SettingsGateStorage implements Storage {
  SettingsGateStorage(this.inner);
  final Storage inner;

  /// Solange gesetzt und nicht fertig, wartet jedes `settings.get` darauf.
  Completer<void>? hold;

  /// Lesen der Einstellungen wirft `StorageException`.
  bool failGets = false;

  /// Lesen bzw. Schreiben der Einwilligungen wirft `StorageException`.
  bool failConsentGets = false;
  bool failConsentSets = false;

  @override
  Future<StorageSession> open(Uint8List key) async =>
      _Session(this, await inner.open(key));
}

class _Session implements StorageSession {
  _Session(this.o, this.s);
  final SettingsGateStorage o;
  final StorageSession s;
  @override
  SettingsStore get settings => _Settings(o, s.settings);
  @override
  RunStore get runs => s.runs;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => _Consents(o, s.consents);
  @override
  RunSubjectiveStore get subjective => s.subjective;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _Settings implements SettingsStore {
  _Settings(this.o, this.s);
  final SettingsGateStorage o;
  final SettingsStore s;

  @override
  Future<String?> get(String key) async {
    if (o.failGets) throw const StorageException(StorageFailure.failed);
    final gate = o.hold;
    if (gate != null) await gate.future;
    return s.get(key);
  }

  @override
  Future<Map<String, String>> all() => s.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) =>
      s.set(key, value, at: at);
}

class _Consents implements ConsentStore {
  _Consents(this.o, this.s);
  final SettingsGateStorage o;
  final ConsentStore s;

  @override
  Future<ConsentState?> get(String sourceKey) async {
    if (o.failConsentGets) throw const StorageException(StorageFailure.failed);
    return s.get(sourceKey);
  }

  @override
  Future<Map<String, ConsentState>> all() => s.all();

  @override
  Future<void> set(
    String sourceKey,
    ConsentState state, {
    required DateTime at,
  }) async {
    if (o.failConsentSets) throw const StorageException(StorageFailure.failed);
    return s.set(sourceKey, state, at: at);
  }
}
