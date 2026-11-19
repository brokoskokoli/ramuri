import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Ein Lauf, der erst nachträglich gerechnet wird (Wiederherstellung, Nachholen
/// beim Start): Die Tageswerte der späteren Tage folgen dem neuen Laufwert
/// (ADR-0004, FR-0078); das `original` bleibt (FR-0058).
void main() {
  const from = '2030-01-01';
  const to = '2030-03-31';

  String show(ComputedValue v) =>
      '${v.key}=${v.value}|n${v.measurementCount}|${v.dataFrom}|${v.dataTo}'
      '|${v.method}/${v.methodVersion}|p${v.parameterVersion}'
      '|${v.heartRateBasis?.maxBpm}|${v.computedAt.toIso8601String()}';

  Future<Map<String, List<String>>> currents(RecalcWorld w) async => {
    for (final e in (await w.daysWithValues(from, to)).entries)
      e.key: [for (final p in e.value) show(p.current)],
  };

  /// Stand der Tageswerte gegen eine vollständige Neuberechnung (gleiche Uhr).
  Future<void> expectFullRecalculation(RecalcWorld w) async {
    final before = await currents(w);
    await w.calc().refreshAfterDelete();
    expect(before, await currents(w));
  }

  Future<ValuePair> longTermOf(RecalcWorld w, String day) async =>
      (await w.session.values.read(ValueOwner.day(day)))
          .firstWhere((p) => p.original.key == vo2maxLongTermValueKey);

  ({CountingValues values, FaultySession session}) counting(RecalcWorld w) {
    final values = CountingValues(w.session.values);
    return (
      values: values,
      session: FaultySession(
        w.session,
        rawData: w.session.rawData,
        values: values,
      ),
    );
  }

  test(
    'Lauf B heute gerechnet, danach Lauf A von vor 3 Tagen nachgeholt: '
    'Tageswerte ab dem Tag von A wie bei vollständiger Neuberechnung',
    () async {
      final w = await RecalcWorld.create();
      final a = await w.seedRun(DateTime.utc(2030, 2, 26, 8), speed: 2.6);
      final c = await w.seedRun(DateTime.utc(2030, 2, 27, 8), speed: 3.0);
      final b = await w.seedRun(DateTime.utc(2030, 3, 1, 8), speed: 3.4);
      w.clock.set(recalcNow);
      await w.calc().calculateAfterRun(c);
      await w.calc().calculateAfterRun(b);
      final bBefore = await longTermOf(w, '2030-03-01');
      expect(bBefore.current.measurementCount, 2);

      await w.calc().calculateAfterRun(a);

      final bAfter = await longTermOf(w, '2030-03-01');
      expect(bAfter.current.measurementCount, 3, reason: 'A ist enthalten');
      expect((await longTermOf(w, '2030-02-27')).current.measurementCount, 2);
      // FR-0058: Das Original bleibt, nur das current folgt.
      expect(show(bAfter.original), show(bBefore.original));
      expect(bAfter.current.methodVersion, bBefore.current.methodVersion);
      await expectFullRecalculation(w);
    },
  );

  test('mehrere nachgeholte Läufe beim Start: jeder Tag höchstens einmal '
      'gerechnet, Ergebnis wie bei vollständiger Neuberechnung', () async {
    final w = await RecalcWorld.create();
    // Offen (ohne Laufwert), absichtlich nicht in zeitlicher Reihenfolge
    // angelegt: 22., 10., 14.
    final open22 = await w.seedRun(DateTime.utc(2030, 2, 22, 8), speed: 3.2);
    final open10 = await w.seedRun(DateTime.utc(2030, 2, 10, 8), speed: 2.7);
    final open14 = await w.seedRun(DateTime.utc(2030, 2, 14, 8), speed: 2.9);
    final done18 = await w.seedRun(DateTime.utc(2030, 2, 18, 8), speed: 3.0);
    final done26 = await w.seedRun(DateTime.utc(2030, 2, 26, 8), speed: 3.3);
    w.clock.set(recalcNow);
    await w.calc().calculateAfterRun(done18);
    await w.calc().calculateAfterRun(done26);

    final probe = counting(w);
    await w.calc(over: probe.session).completePendingCalculations();

    for (final id in [open10, open14, open22]) {
      expect(await runVo2Pairs(w.session, id), hasLength(1));
    }
    expect(
      probe.values.dayWrites.values.every((n) => n == 1),
      isTrue,
      reason: '${probe.values.dayWrites}',
    );
    expect(probe.values.dayWrites.keys.toSet(), {
      '2030-02-10',
      '2030-02-14',
      '2030-02-18',
      '2030-02-22',
      '2030-02-26',
    });
    expect((await longTermOf(w, '2030-02-26')).current.measurementCount, 5);
    await expectFullRecalculation(w);
  });

  test('nachgeholter Lauf scheitert nach einem gelungenen: die Tage ab ihm '
      'folgen trotzdem dem gelungenen, jeder Tag höchstens einmal', () async {
    final w = await RecalcWorld.create();
    final open10 = await w.seedRun(DateTime.utc(2030, 2, 10, 8), speed: 2.7);
    final failing = await w.seedRun(DateTime.utc(2030, 2, 14, 8));
    final done20 = await w.seedRun(DateTime.utc(2030, 2, 20, 8), speed: 3.1);
    w.clock.set(recalcNow);
    await w.calc().calculateAfterRun(done20);

    final probe = counting(w)..values.failRun = failing;
    await expectLater(
      w.calc(over: probe.session).completePendingCalculations(),
      throwsA(isA<StorageException>()),
    );

    expect(await runVo2Pairs(w.session, open10), hasLength(1));
    expect(await runVo2Pairs(w.session, failing), isEmpty);
    expect(
      probe.values.dayWrites.values.every((n) => n == 1),
      isTrue,
      reason: '${probe.values.dayWrites}',
    );
    expect((await longTermOf(w, '2030-02-20')).current.measurementCount, 2);
    await expectFullRecalculation(w);
  });

  test('gelungen, gescheitert, gelungen: der zweite gelungene rechnet die '
      'Tage ab dem gescheiterten mit, jeder Tag höchstens einmal', () async {
    final w = await RecalcWorld.create();
    final open10 = await w.seedRun(DateTime.utc(2030, 2, 10, 8), speed: 2.7);
    final failing = await w.seedRun(DateTime.utc(2030, 2, 14, 8));
    final done16 = await w.seedRun(DateTime.utc(2030, 2, 16, 8), speed: 3.0);
    final open18 = await w.seedRun(DateTime.utc(2030, 2, 18, 8), speed: 2.9);
    final done20 = await w.seedRun(DateTime.utc(2030, 2, 20, 8), speed: 3.1);
    w.clock.set(recalcNow);
    await w.calc().calculateAfterRun(done16);
    await w.calc().calculateAfterRun(done20);

    final probe = counting(w)..values.failRun = failing;
    await expectLater(
      w.calc(over: probe.session).completePendingCalculations(),
      throwsA(isA<StorageException>()),
    );

    for (final id in [open10, open18]) {
      expect(await runVo2Pairs(w.session, id), hasLength(1));
    }
    expect(await runVo2Pairs(w.session, failing), isEmpty);
    expect(
      probe.values.dayWrites.values.every((n) => n == 1),
      isTrue,
      reason: '${probe.values.dayWrites}',
    );
    expect((await longTermOf(w, '2030-02-16')).current.measurementCount, 2);
    await expectFullRecalculation(w);
  });

  test('gerade beendeter Lauf ohne spätere Tageswerte: nur sein Tag wird '
      'gerechnet', () async {
    final w = await RecalcWorld.create();
    for (final d in [20, 25]) {
      await w.calc().calculateAfterRun(
        await w.seedRun(DateTime.utc(2030, 2, d, 8)),
      );
    }
    final id = await w.seedRun(DateTime.utc(2030, 3, 1, 8));
    final probe = counting(w);
    await w.calc(over: probe.session).calculateAfterRun(id);
    expect(probe.values.dayWrites, {'2030-03-01': 1});
    expect(probe.values.writeAlls, 1);
  });
}

/// Zählt je Tag, wie oft Tageswerte geschrieben werden (angelegt oder
/// getauscht); [failRun]: das Schreiben der Werte dieses Laufs scheitert.
class CountingValues implements ComputedValueStore {
  CountingValues(this.inner);

  final ComputedValueStore inner;
  final dayWrites = <String, int>{};
  int writeAlls = 0;
  int? failRun;

  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) {
    writeAlls++;
    if (failRun != null && create.containsKey(ValueOwner.run(failRun!))) {
      throw const StorageException(StorageFailure.failed);
    }
    for (final o in {...create.keys, ...swap.keys}) {
      final day = o.day;
      if (day != null) dayWrites[day] = (dayWrites[day] ?? 0) + 1;
    }
    return inner.writeAll(create: create, swap: swap);
  }

  @override
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values) =>
      inner.createOriginals(owner, values);
  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) =>
      inner.swapCurrent(owner, values);
  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> changes) =>
      inner.swapCurrentAll(changes);
  @override
  Future<List<ValuePair>> read(ValueOwner owner) => inner.read(owner);
  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(
    Set<String> keys,
  ) => inner.readRunValues(keys);
  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) => inner.readDayValues(keys);
}
