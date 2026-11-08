import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Speicher, dessen Lauf-Liste sich scheitern lässt (Fortschritt lädt sie).
class _Flaky implements Storage {
  _Flaky(this.inner);
  final Storage inner;
  bool failRuns = false;

  @override
  Future<StorageSession> open(Uint8List key) async =>
      _Session(this, await inner.open(key));
}

class _Session implements StorageSession {
  _Session(this._o, this._s);
  final _Flaky _o;
  final StorageSession _s;

  @override
  SettingsStore get settings => _s.settings;
  @override
  ProfileStore get profile => _s.profile;
  @override
  RunStore get runs => _Runs(_o, _s.runs);
  @override
  RunMarkerStore get markers => _s.markers;
  @override
  RawDataStore get rawData => _s.rawData;
  @override
  PreprocessingStore get preprocessing => _s.preprocessing;
  @override
  RatedSectionStore get sections => _s.sections;
  @override
  ComputedValueStore get values => _s.values;
  @override
  KnownDeviceStore get devices => _s.devices;
  @override
  ConsentStore get consents => _s.consents;
  @override
  Future<void> deleteRun(int runId) => _s.deleteRun(runId);
  @override
  Future<void> deleteAll() => _s.deleteAll();
  @override
  Future<void> close() => _s.close();
}

class _Runs implements RunStore {
  _Runs(this._o, this._s);
  final _Flaky _o;
  final RunStore _s;

  @override
  Future<List<StoredRun>> list() async {
    if (_o.failRuns) throw const StorageException(StorageFailure.failed);
    return _s.list();
  }

  @override
  Future<StoredRun> create({required DateTime startedAt}) =>
      _s.create(startedAt: startedAt);
  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) => _s.setState(
    runId,
    state,
    endedAt: endedAt,
    endedUtcOffset: endedUtcOffset,
  );
  @override
  Future<StoredRun?> get(int runId) => _s.get(runId);
  @override
  Future<List<StoredRun>> unfinished() => _s.unfinished();
}

void main() {
  testWidgets('Fortschritt: Ladefehler, dann Erneut lädt neu (ohne Ausnahme)', (
    tester,
  ) async {
    final d = Device();
    final flaky = _Flaky(d.storage);
    d.storageOverride = flaky;
    await d.start(tester, const Locale('en'));
    await d.skipSetup(tester);
    flaky.failRuns = true;
    await tester.tap(find.byKey(const Key('home_statistics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stat_failed')), findsOneWidget);

    flaky.failRuns = false;
    await tester.tap(find.byKey(const Key('stat_retry')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('stat_failed')), findsNothing);
    expect(find.byKey(const Key('stat_runs_value')), findsOneWidget);
  });
}
