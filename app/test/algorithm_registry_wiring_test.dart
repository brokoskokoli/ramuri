import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/storage/deletion.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show openHistory;
import 'run_test.dart' show openRun, walk;

/// Anschlüsse der einen Algorithmen-Registry der App (ADR-0004, NFR-0005):
/// Laufende, Nachholen beim Start, App-Start und Löschen rechnen mit der
/// Registry, die die App übergibt, nicht mit einer eigenen Standardbestückung.

/// Gleicher Wert wie [v], aber mit der Methode [method] und Version [version].
AdvancedFitnessValue<double> _retag(
  AdvancedFitnessValue<double> v,
  String method,
  int version,
) {
  final m = v.metadata;
  return AdvancedFitnessValue<double>(
    value: v.value,
    reason: v.reason,
    metadata: FitnessValueMetadata(
      calculatedAt: m.calculatedAt,
      dataFrom: m.dataFrom,
      dataTo: m.dataTo,
      usableMeasurements: m.usableMeasurements,
      dataSources: m.dataSources,
      method: method,
      methodVersion: version,
      parameterVersion: m.parameterVersion,
      tier: m.tier,
    ),
  );
}

/// Test-Schätzer: rechnet wie der Standard, mit anderer Methode und Version.
class _OtherEstimator extends Vo2maxEstimator {
  const _OtherEstimator();

  static const _inner = AcsmReserveVo2maxEstimator();

  @override
  String get method => 'test-vo2max';
  @override
  int get methodVersion => 7;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  @override
  Vo2maxRunEstimate estimate({
    required SectionSelection selection,
    required HeartRateBasis basis,
    required FitnessParameters p,
    required DateTime calculatedAt,
    required DateTime runStart,
    required DateTime runEnd,
    Set<String> dataSources = const {},
    bool treadmill = false,
  }) {
    final e = _inner.estimate(
      selection: selection,
      basis: basis,
      p: p,
      calculatedAt: calculatedAt,
      runStart: runStart,
      runEnd: runEnd,
      dataSources: dataSources,
      treadmill: treadmill,
    );
    return Vo2maxRunEstimate(
      result: _retag(e.result, method, methodVersion),
      sections: e.sections,
      spreadPercent: e.spreadPercent,
      caps: e.caps,
      maxIsEstimated: e.maxIsEstimated,
    );
  }
}

/// Test-Langzeitwert: rechnet wie der Standard, mit anderer Methode und Version.
class _OtherLongTerm extends Vo2maxLongTerm {
  const _OtherLongTerm();

  static const _inner = SmoothedVo2maxLongTerm();

  @override
  String get method => 'test-long-term';
  @override
  int get methodVersion => 5;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  @override
  AdvancedFitnessValue<double> compute({
    required List<AdvancedFitnessValue<double>> runs,
    required FitnessParameters p,
    required DateTime now,
  }) =>
      _retag(_inner.compute(runs: runs, p: p, now: now), method, methodVersion);
}

AlgorithmRegistry _withOther() => AlgorithmRegistry.standard()
  ..register(vo2maxEstimatorFamily, const _OtherEstimator())
  ..setActive(vo2maxEstimatorFamily, 'test-vo2max', 7)
  ..register(vo2maxLongTermFamily, const _OtherLongTerm())
  ..setActive(vo2maxLongTermFamily, 'test-long-term', 5);

Future<ComputedValue?> _runValue(StorageSession s, int id) async =>
    (await s.values.readRunValues({vo2maxRunValueKey}))[id]?[vo2maxRunValueKey];

Future<void> _direct(Future<void> Function() action) => action();

Future<StorageSession> _session() async {
  final session = await FakeStorage().open(Uint8List(32));
  await session.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  return session;
}

/// Beendeter Lauf mit Rohdaten (30 min, 3 m/s, 150 /min), ohne Werte.
Future<int> _seedRun(StorageSession s, FakeClock? clock, DateTime start) async {
  final run = await s.runs.create(startedAt: start);
  const seconds = 30 * 60;
  final positions = <RawPosition>[];
  final hrs = <RawHeartRate>[];
  for (var i = 0; i <= seconds; i++) {
    final t = start.add(Duration(seconds: i));
    positions.add(
      RawPosition(
        time: t,
        source: 'gps',
        latitude: 10 + i * 3.0 / 111320,
        longitude: 20,
        accuracyMeters: 5,
      ),
    );
    hrs.add(
      RawHeartRate(
        time: t,
        source: 'strap',
        bpm: 150,
        contact: SensorContact.good,
      ),
    );
  }
  await s.rawData.append(
    run.id,
    RawBatch(positions: positions, heartRates: hrs),
  );
  final end = start.add(const Duration(seconds: seconds));
  await s.runs.setState(run.id, RunState.finished, endedAt: end);
  clock?.set(end.add(const Duration(minutes: 1)));
  return run.id;
}

void main() {
  test(
    'Laufende: RunController rechnet mit der übergebenen Registry',
    () async {
      final s = await _session();
      final clock = FakeClock(DateTime.utc(2030, 3, 1, 8));
      final c = RunController(
        algorithms: _withOther(),
        clock: clock,
        storage: s,
        location: FakeLocationSource(),
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      clock.advance(const Duration(minutes: 5));
      await c.finish();

      final id = (await s.runs.list()).single.id;
      final v = await _runValue(s, id);
      expect((v?.method, v?.methodVersion), ('test-vo2max', 7));
    },
  );

  test('Nachholen beim Start rechnet mit der übergebenen Registry', () async {
    final s = await _session();
    final clock = FakeClock(DateTime.utc(2030, 3, 1, 8));
    final id = await _seedRun(s, clock, DateTime.utc(2030, 3, 1, 8));
    await s.settings.set(
      ValueCalculationService.calculationPendingKey,
      '$id',
      at: clock.now(),
    );

    await completePendingValueRefresh(s, clock, algorithms: _withOther());

    final v = await _runValue(s, id);
    expect((v?.method, v?.methodVersion), ('test-vo2max', 7));
  });

  test(
    'Löschen legt die Tageswerte mit der übergebenen Registry neu an',
    () async {
      final s = await _session();
      final clock = FakeClock(DateTime.utc(2030, 3, 1, 8));
      final standard = ValueCalculationService(
        session: s,
        clock: clock,
        algorithms: AlgorithmRegistry.standard(),
      );
      final first = await _seedRun(s, clock, DateTime.utc(2030, 3, 1, 8));
      await standard.calculateAfterRun(first);
      final second = await _seedRun(s, clock, DateTime.utc(2030, 3, 3, 8));
      await standard.calculateAfterRun(second);
      const day = ValueOwner.day('2030-03-03');
      final before = (await s.values.read(day))
          .firstWhere((p) => p.current.key == vo2maxLongTermValueKey)
          .current;
      expect(before.method, isNot('test-long-term'));

      await deleteRunAndRefresh(
        s,
        clock,
        first,
        serialize: _direct,
        algorithms: _withOther(),
      );

      final after = (await s.values.read(day))
          .firstWhere((p) => p.current.key == vo2maxLongTermValueKey)
          .current;
      expect((after.method, after.methodVersion), ('test-long-term', 5));
    },
  );

  testWidgets('App-Start: die Registry aus AppDependencies rechnet die '
      'nachgeholten Werte', (tester) async {
    final d = Device()..algorithms = _withOther();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    final id = await tester.runAsync(() async {
      final s = d.session;
      await s.profile.save(
        const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
      );
      final id = await _seedRun(s, null, DateTime.utc(2026, 5, 30, 8));
      await s.settings.set(
        ValueCalculationService.calculationPendingKey,
        '$id',
        at: d.clock.now(),
      );
      return id;
    });
    await d.stop(tester);

    await d.start(tester, const Locale('de'));
    final v = await tester.runAsync(() => _runValue(d.session, id!));
    expect((v?.method, v?.methodVersion), ('test-vo2max', 7));
    // Die Versionsprüfung beim Start nimmt dieselbe Registry: kein Angebot.
    expect(
      await tester.runAsync(
        () => d.session.settings.get(RecalculationService.pendingKey),
      ),
      anyOf(isNull, ''),
    );
    await d.stop(tester);
  });

  testWidgets('Lauf über den Startknopf rechnet mit der Registry aus '
      'AppDependencies', (tester) async {
    final d = Device()..algorithms = _withOther();
    await openRun(d, tester);
    await walk(d, tester, 30);
    await tester.tap(find.byKey(const Key('run_pause')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('run_finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('run_finish_confirm')));
    await tester.pumpAndSettle();
    final id = (await d.session.runs.list()).single.id;
    final v = await _runValue(d.session, id);
    expect((v?.method, v?.methodVersion), ('test-vo2max', 7));
  });

  /// Zwei Läufe mit Werten der Standardbestückung; das Löschen des ersten legt
  /// den Langzeitwert am Tag des zweiten neu an.
  Future<(Device, int, ValueOwner)> twoRuns(WidgetTester tester) async {
    final d = Device()..algorithms = _withOther();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    final s = d.session;
    await s.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    final standard = ValueCalculationService(
      session: s,
      clock: d.clock,
      algorithms: AlgorithmRegistry.standard(),
    );
    final first = await _seedRun(s, null, DateTime.utc(2026, 5, 20, 8));
    await standard.calculateAfterRun(first);
    final second = await _seedRun(s, null, DateTime.utc(2026, 5, 22, 8));
    await standard.calculateAfterRun(second);
    final day = ValueOwner.day(dayOfRun((await s.runs.get(second))!));
    final before = await _longTerm(s, day);
    expect(before?.method, isNot('test-long-term'));
    return (d, first, day);
  }

  testWidgets('Löschen am Eintrag der Historie: Tageswerte mit der Registry '
      'aus AppDependencies', (tester) async {
    final (d, first, day) = await twoRuns(tester);
    await openHistory(d, tester);
    await tester.tap(find.byKey(Key('history_delete_$first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    expect(await d.session.runs.get(first), isNull);
    final after = await _longTerm(d.session, day);
    expect((after?.method, after?.methodVersion), ('test-long-term', 5));
  });

  testWidgets('Löschen im Detail: Tageswerte mit der Registry aus '
      'AppDependencies', (tester) async {
    final (d, first, day) = await twoRuns(tester);
    await openHistory(d, tester);
    await tester.ensureVisible(find.byKey(Key('history_run_$first')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('history_run_$first')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('detail_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    expect(await d.session.runs.get(first), isNull);
    final after = await _longTerm(d.session, day);
    expect((after?.method, after?.methodVersion), ('test-long-term', 5));
  });
}

Future<ComputedValue?> _longTerm(StorageSession s, ValueOwner day) async {
  for (final p in await s.values.read(day)) {
    if (p.current.key == vo2maxLongTermValueKey) return p.current;
  }
  return null;
}
