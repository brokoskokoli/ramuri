import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Zählt Zugriffe auf die Werte (kein Zugriff je Lauf).
class _CountingValues implements ComputedValueStore {
  _CountingValues(this.i);
  final ComputedValueStore i;
  int reads = 0;
  int bulkReads = 0;
  bool failBulk = false;

  @override
  Future<List<ValuePair>> read(ValueOwner owner) {
    reads++;
    return i.read(owner);
  }

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(Set<String> k) {
    bulkReads++;
    if (failBulk) throw const StorageException(StorageFailure.failed);
    return i.readRunValues(k);
  }

  @override
  Future<void> createOriginals(ValueOwner o, List<ComputedValue> v) =>
      i.createOriginals(o, v);
  @override
  Future<void> swapCurrent(ValueOwner o, List<ComputedValue> v) =>
      i.swapCurrent(o, v);
  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> c) =>
      i.swapCurrentAll(c);
  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) => i.writeAll(create: create, swap: swap);
}

Future<List<StoredRun>> _finished(StorageSession s) async => [
  for (final r in await s.runs.list())
    if (r.state == RunState.finished) r,
];

void main() {
  test(
    'vier berechnete Läufe: Schätzungen, Tageswerte, gebündelt gelesen',
    () async {
      final w = await RecalcWorld.create();
      await w.seedFourRunsCalculated();
      final counting = _CountingValues(w.session.values);
      final session = FaultySession(
        w.session,
        rawData: w.session.rawData,
        values: counting,
      );
      final o = await FitnessOverviewService(session: session)
          .load(await _finished(w.session));
      expect(o.runEstimates, hasLength(4));
      // Aufsteigend nach Laufende.
      expect(
        o.runEstimates.map((e) => e.endedAt).toList(),
        [...o.runEstimates.map((e) => e.endedAt)]..sort(),
      );
      expect(o.pendingRuns, 0);
      expect(o.day, '2030-02-25');
      expect(o.longTerm?.key, vo2maxLongTermValueKey);
      expect(o.efficiency?.key, aerobicEfficiencyValueKey);
      // Eine Abfrage für alle Laufwerte, eine für die Tageswerte.
      expect(counting.bulkReads, 1);
      expect(counting.reads, 1);
    },
  );

  test(
    'Lauf ohne Laufwert zählt als ausstehend, ohne Läufe kein Tag',
    () async {
      final w = await RecalcWorld.create();
      final empty = await FitnessOverviewService(session: w.session)
          .load(const []);
      expect(empty.runEstimates, isEmpty);
      expect(empty.day, isNull);
      expect(empty.longTerm, isNull);
      await w.seedRun(DateTime.utc(2030, 2, 20, 8));
      final o = await FitnessOverviewService(session: w.session)
          .load(await _finished(w.session));
      expect(o.pendingRuns, 1);
      expect(o.runEstimates, isEmpty);
      expect(o.longTerm, isNull);
    },
  );

  test('Lesefehler: failed, kein Wert erfunden', () async {
    final w = await RecalcWorld.create();
    await w.seedFourRunsCalculated();
    final counting = _CountingValues(w.session.values)..failBulk = true;
    final o = await FitnessOverviewService(
      session: FaultySession(
        w.session,
        rawData: w.session.rawData,
        values: counting,
      ),
    ).load(await _finished(w.session));
    expect(o.readFailed, isTrue);
    expect(o.runEstimates, isEmpty);
    expect(o.longTerm, isNull);
  });

  test('Gewicht-0-Abschnitt wird erkannt', () {
    ComputedValue value(EstimateDiscard? discard) => ComputedValue(
      key: vo2maxRunValueKey,
      value: 40,
      unit: vo2maxUnit,
      computedAt: DateTime.utc(2030),
      measurementCount: 1,
      sources: const [],
      method: 'm',
      methodVersion: 1,
      parameterVersion: 1,
      quality: ValueQuality.good,
      sections: [
        ValueSection(
          start: DateTime.utc(2030),
          end: DateTime.utc(2030, 1, 1, 0, 5),
          weight: 0,
          lateFactor: 0,
          status: SectionStatus.eligible,
          discard: discard,
        ),
      ],
    );
    expect(hasZeroWeightSection(value(EstimateDiscard.zeroWeight)), isTrue);
    expect(hasZeroWeightSection(value(EstimateDiscard.implausible)), isFalse);
    expect(hasZeroWeightSection(value(null)), isFalse);
  });
}
