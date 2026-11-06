import 'package:core/core.dart';
import 'package:test/test.dart';

import 'package:core/testing/contract_samples.dart' show sampleValue;

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

  int dayBulkReads = 0;

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(Set<String> k) {
    dayBulkReads++;
    if (failBulk) throw const StorageException(StorageFailure.failed);
    return i.readDayValues(k);
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
      expect(counting.dayBulkReads, 1);
      expect(counting.reads, 0);
      // Verlauf aus den Tageswerten, aufsteigend nach Tag.
      final days = o.longTermByDay.map((e) => e.day).toList();
      expect(days, isNotEmpty);
      expect(days, [...days]..sort());
      expect(days, contains('2030-02-25'));
      expect(
        o.longTermByDay.every((e) => e.value.key == vo2maxLongTermValueKey),
        isTrue,
      );
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

  test('Wochenverlauf: je Woche der letzte bestimmbare Tageswert, neueste '
      'Wochen, aufsteigend', () {
    DayEstimate d(String day, double? v) =>
        DayEstimate(day: day, value: sampleValue(vo2maxLongTermValueKey, v));
    final o = FitnessOverview(
      runEstimates: const [],
      longTerm: null,
      efficiency: null,
      pendingRuns: 0,
      longTermByDay: [
        d('2030-01-07', 40), // Montag
        d('2030-01-09', 40.5),
        d('2030-01-10', null), // nicht bestimmbar: zählt nicht
        d('2030-01-13', 41), // Sonntag derselben Woche: gewinnt
        d('2030-01-14', 42), // nächste Woche
        d('2030-02-04', 43),
        d('2030-02-05', null), // Woche nur mit nicht bestimmbarem Wert
        d('2030-02-12', null),
      ],
    );
    expect(o.weeklyLongTerm().map((e) => (e.day, e.value.value)).toList(), [
      ('2030-01-13', 41.0),
      ('2030-01-14', 42.0),
      ('2030-02-04', 43.0),
    ]);
    // Nur die neuesten zwei Wochen, weiter aufsteigend.
    expect(o.weeklyLongTerm(maxWeeks: 2).map((e) => e.day).toList(), [
      '2030-01-14',
      '2030-02-04',
    ]);
    // Wochenbeginn Sonntag: der 13. beginnt eine neue Woche.
    expect(
      o.weeklyLongTerm(firstDayOfWeek: DateTime.sunday).map((e) => e.day),
      ['2030-01-09', '2030-01-14', '2030-02-04'],
    );
  });
}
