import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_ports.dart';

import 'dart:typed_data';

import 'app_harness.dart';
import 'run_test.dart' show openRun, walk;

/// Speicher, dessen Lauf sich nicht als beendet speichern lässt, solange
/// [failFinish] gesetzt ist.
class _FinishFailStorage implements Storage {
  _FinishFailStorage(this.inner);
  final Storage inner;
  bool failFinish = false;
  @override
  Future<StorageSession> open(Uint8List key) async =>
      _Session(this, await inner.open(key));
}

class _Session implements StorageSession {
  _Session(this.o, this.s);
  final _FinishFailStorage o;
  final StorageSession s;
  @override
  RunStore get runs => _Runs(o, s.runs);
  @override
  RawDataStore get rawData => s.rawData;
  @override
  SettingsStore get settings => s.settings;
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
  ConsentStore get consents => s.consents;
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

class _Runs implements RunStore {
  _Runs(this.o, this.inner);
  final _FinishFailStorage o;
  final RunStore inner;
  @override
  Future<StoredRun> create({
    required DateTime startedAt,
    RunMode mode = RunMode.gps,
  }) => inner.create(startedAt: startedAt, mode: mode);
  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) {
    if (o.failFinish && state == RunState.finished) {
      return Future.error(const StorageException(StorageFailure.failed));
    }
    return inner.setState(
      runId,
      state,
      endedAt: endedAt,
      endedUtcOffset: endedUtcOffset,
    );
  }

  @override
  Future<StoredRun?> get(int runId) => inner.get(runId);
  @override
  Future<List<StoredRun>> list() => inner.list();
  @override
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to) =>
      inner.finishedBetween(from, to);

  @override
  Future<List<StoredRun>> unfinished() => inner.unfinished();
}

/// Ein Lauf, den der Prozess nicht mehr beendet: App zu, Lauf bleibt aktiv.
Future<int> crash(Device d, WidgetTester tester) async {
  await openRun(d, tester);
  await walk(d, tester, 20);
  final id = (await d.session.runs.list()).single.id;
  await d.stop(tester);
  return id;
}

Future<void> restart(Device d, WidgetTester tester) async {
  await d.start(tester, const Locale('de'));
}

void main() {
  group('Wiederaufnahme (FR-0193)', () {
    testWidgets('ohne unfertigen Lauf kein Angebot', (tester) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('nach normalem Ende kein Angebot', (tester) async {
      final d = Device();
      await openRun(d, tester);
      await walk(d, tester, 10);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect((await d.session.runs.list()).single.state, RunState.finished);
      await d.stop(tester);
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('unfertiger Lauf: Angebot; Speichern beendet ihn, danach '
        'kein Angebot mehr', (tester) async {
      final d = Device();
      await crash(d, tester);
      d.clock.advance(const Duration(hours: 1));
      await restart(d, tester);
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      final runs = await d.session.runs.list();
      expect(runs.single.state, RunState.finished);
      expect(runs.single.endedAt, isNot(d.clock.now()));
      expect(runs.single.endedUtcOffset, isNotNull);
      await d.stop(tester);
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('Fortsetzen nach 400 Tagen: gleicher Lauf, Lücke markiert', (
      tester,
    ) async {
      final d = Device();
      final id = await crash(d, tester);
      d.clock.advance(const Duration(days: 400));
      await restart(d, tester);
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      final runs = await d.session.runs.list();
      expect(runs.single.id, id);
      expect(runs.single.state, RunState.active);
      final gaps = await d.session.markers.gaps(id);
      expect(gaps.map((g) => g.kind), contains(RunGapKind.interruption));
      // Lauf läuft weiter: der Bildschirm zeigt die Steuerung.
      expect(key('run_pause'), findsOneWidget);
    });

    testWidgets('mit laufendem Dienst kein Angebot', (tester) async {
      final d = Device();
      await crash(d, tester);
      d.recordingService = FakeRecordingServicePort()..running = true;
      await restart(d, tester);
      expect(key('recover_dialog'), findsNothing);
    });

    testWidgets('ohne Standortrecht: Fortsetzen blockiert, zurück, das '
        'Angebot kommt im selben Prozess wieder, Speichern geht', (
      tester,
    ) async {
      final d = Device();
      await crash(d, tester);
      d.locationAccess.current = LocationAccess.denied;
      await restart(d, tester);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(key('run_block_permissionDenied'), findsOneWidget);
      expect((await d.session.runs.list()).single.state, RunState.active);
      // Zurück aus dem Block-Bildschirm.
      Navigator.of(tester.element(key('run_block_permissionDenied'))).pop();
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      expect((await d.session.runs.list()).single.state, RunState.finished);
    });

    testWidgets(
      'Speichern scheitert: Hinweis, Angebot bleibt, danach geht es',
      (tester) async {
        final d = Device();
        final id = await crash(d, tester);
        final flaky = _FinishFailStorage(d.storage)..failFinish = true;
        d.storageOverride = flaky;
        await restart(d, tester);
        await tester.tap(key('recover_save'));
        await tester.pumpAndSettle();
        expect(
          find.text('Der Lauf konnte nicht gespeichert werden.'),
          findsOne,
        );
        expect(key('recover_dialog'), findsOneWidget);
        expect((await d.session.runs.get(id))!.state, RunState.active);
        flaky.failFinish = false;
        await tester.tap(key('recover_save'));
        await tester.pumpAndSettle();
        expect(key('recover_dialog'), findsNothing);
        expect((await d.session.runs.get(id))!.state, RunState.finished);
      },
    );

    testWidgets('nach Speichern hat der Lauf Werte (FR-0006)', (tester) async {
      final d = Device();
      final id = await crash(d, tester);
      expect(await d.session.values.read(ValueOwner.run(id)), isEmpty);
      await restart(d, tester);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect(await d.session.values.read(ValueOwner.run(id)), isNotEmpty);
    });

    testWidgets('mehrere unfertige Läufe: ältester zuerst, dann der nächste', (
      tester,
    ) async {
      final d = Device();
      final first = await crash(d, tester);
      // Ein zweiter, späterer unfertiger Lauf (Prozess ist beendet).
      final other = await d.storage.open(
        Uint8List.fromList(List.filled(32, 7)),
      );
      final second = (await other.runs.create(
        startedAt: d.clock.now().add(const Duration(hours: 1)),
      )).id;
      await other.close();
      await restart(d, tester);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      final runs = {for (final r in await d.session.runs.list()) r.id: r};
      expect(runs[first]!.state, RunState.finished);
      expect(runs[second]!.state, RunState.active);
      // Das Angebot für den zweiten Lauf kommt im selben Prozess.
      expect(key('recover_dialog'), findsOneWidget);
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      expect(key('recover_dialog'), findsNothing);
      expect((await d.session.runs.get(second))!.state, RunState.finished);
    });

    testWidgets('Uhr vor dem letzten Zeitpunkt: Hinweis im Dialog', (
      tester,
    ) async {
      final d = Device();
      await crash(d, tester);
      await restart(d, tester);
      expect(key('recover_dialog'), findsOneWidget);
      expect(find.textContaining('Uhr des Geräts'), findsNothing);
      await d.stop(tester);
      d.clock.advance(const Duration(days: -1));
      await restart(d, tester);
      expect(find.textContaining('Uhr des Geräts'), findsOneWidget);
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    });
  });
}
