// Speicherzugriffe der Neuberechnung: buildSnapshot, das Nachrechnen der
// Tageswerte (refreshAfterDelete) und die Berechnung nach einem Lauf lesen
// die gespeicherten Werte aller Läufe und Tage mit je einer Sammelabfrage,
// nicht je Lauf oder je Tag. Die Zahl der Zugriffe hängt nicht von der Zahl
// der Läufe ab; die Ergebnisse bleiben gleich (ADR-0004, NFR-0001).

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Zählt Einzel- und Sammelabfragen auf Lauf- und Tageswerte.
class _CountingValues implements ComputedValueStore {
  _CountingValues(this.inner);

  final ComputedValueStore inner;
  int runReads = 0;
  int dayReads = 0;
  int runBulkReads = 0;
  int dayBulkReads = 0;

  void reset() {
    runReads = 0;
    dayReads = 0;
    runBulkReads = 0;
    dayBulkReads = 0;
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
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) => inner.writeAll(create: create, swap: swap);

  @override
  Future<List<ValuePair>> read(ValueOwner owner) {
    if (owner.runId != null) {
      runReads++;
    } else {
      dayReads++;
    }
    return inner.read(owner);
  }

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(Set<String> keys) {
    runBulkReads++;
    return inner.readRunValues(keys);
  }

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) {
    dayBulkReads++;
    return inner.readDayValues(keys);
  }
}

/// Synthetischer Bestand: drei Läufe an zwei Tagen.
/// - [full] (Tag 1): nach dem Lauf gerechnet (VO2max, TRIMP, Zeit bei
///   mindestens 80 % HFmax, Tageswerte an Tag 1).
/// - [trimpOnly] (Tag 1): nur ein TRIMP (älterer Bestand), ohne VO2max und
///   ohne Zeit über der Schwelle.
/// - [noHigh] (Tag 2): nur ein VO2max-Laufwert (vor der Methode der Zeit
///   über der Schwelle gerechnet); Tag 2 hat keine gespeicherten Tageswerte.
class _World {
  _World(this.w, this.full, this.trimpOnly, this.noHigh, this.values);

  final RecalcWorld w;
  final int full;
  final int trimpOnly;
  final int noHigh;
  final _CountingValues values;

  static const String day1 = '2030-02-10';
  static const String day2 = '2030-02-12';

  static Future<_World> create() async {
    final w = await RecalcWorld.create();
    final full = await w.seedRun(DateTime.utc(2030, 2, 10, 8), bpm: 160);
    await w.calc().calculateAfterRun(full);
    final stored = await w.session.values.read(ValueOwner.run(full));
    ComputedValue of(String key) =>
        stored.singleWhere((p) => p.original.key == key).original;

    final trimpOnly = await w.seedRun(DateTime.utc(2030, 2, 10, 17), bpm: 160);
    await w.session.values.createOriginals(ValueOwner.run(trimpOnly), [
      of(trimpRunValueKey),
    ]);
    final noHigh = await w.seedRun(DateTime.utc(2030, 2, 12, 8), bpm: 160);
    await w.session.values.createOriginals(ValueOwner.run(noHigh), [
      of(vo2maxRunValueKey),
    ]);
    return _World(
      w,
      full,
      trimpOnly,
      noHigh,
      _CountingValues(w.session.values),
    );
  }

  ValueCalculationService calc() => w.calc(
    over: FaultySession(w.session, rawData: w.session.rawData, values: values),
  );
}

List<String> _keys(List<ComputedValue>? values) =>
    [for (final v in values ?? const <ComputedValue>[]) v.key]..sort();

void main() {
  test('buildSnapshot: keine Einzelabfrage auf Lauf- und Tageswerte, je eine '
      'Sammelabfrage (drei Läufe an zwei Tagen)', () async {
    final x = await _World.create();
    expect(
      await x.w.session.values.read(const ValueOwner.day(_World.day1)),
      isNotEmpty,
    );
    expect(
      await x.w.session.values.read(const ValueOwner.day(_World.day2)),
      isEmpty,
    );

    final snapshot = await x.calc().buildSnapshot();

    expect(x.values.runReads, 0, reason: 'Einzelabfragen auf Laufwerte');
    expect(x.values.dayReads, 0, reason: 'Einzelabfragen auf Tageswerte');
    expect(x.values.runBulkReads, 1, reason: 'Sammelabfrage auf Laufwerte');
    expect(x.values.dayBulkReads, 1, reason: 'Sammelabfrage auf Tageswerte');

    // Ergebnisse wie bisher: vollständiger Lauf tauscht alle drei Werte, der
    // Lauf nur mit TRIMP tauscht den TRIMP und bekommt die Zeit über der
    // Schwelle neu, dem VO2max-Lauf ohne sie wird sie angelegt.
    expect(_keys(snapshot.runValues[ValueOwner.run(x.full)]), [
      highHeartRateTimeValueKey,
      trimpRunValueKey,
      vo2maxRunValueKey,
    ]);
    expect(_keys(snapshot.runValues[ValueOwner.run(x.trimpOnly)]), [
      trimpRunValueKey,
    ]);
    expect(_keys(snapshot.runCreates[ValueOwner.run(x.trimpOnly)]), [
      highHeartRateTimeValueKey,
    ]);
    expect(_keys(snapshot.runValues[ValueOwner.run(x.noHigh)]), [
      vo2maxRunValueKey,
    ]);
    expect(_keys(snapshot.runCreates[ValueOwner.run(x.noHigh)]), [
      highHeartRateTimeValueKey,
    ]);
    expect(snapshot.runCreates.keys, isNot(contains(ValueOwner.run(x.full))));
    // Tageswerte nur für den Tag, der schon welche hat.
    expect(snapshot.dayValues.keys, [const ValueOwner.day(_World.day1)]);
    expect(
      _keys(snapshot.dayValues[const ValueOwner.day(_World.day1)]),
      [
        ...(await x.w.session.values.read(const ValueOwner.day(_World.day1)))
            .map((p) => p.original.key),
      ]..sort(),
    );
  });

  test('refreshAfterDelete: keine Einzelabfrage auf Laufwerte, eine '
      'Sammelabfrage', () async {
    final x = await _World.create();
    await x.w.session.deleteRun(x.full);

    await x.calc().refreshAfterDelete();

    expect(x.values.runReads, 0, reason: 'Einzelabfragen auf Laufwerte');
    expect(x.values.runBulkReads, 1, reason: 'Sammelabfrage auf Laufwerte');
    // Der verbliebene Lauf mit Laufwert bekommt seine Tageswerte (Tag 2).
    expect(
      await x.w.session.values.read(const ValueOwner.day(_World.day2)),
      isNotEmpty,
    );
  });

  test('calculateAfterRun: keine Einzelabfrage auf Laufwerte anderer Läufe, '
      'eine Sammelabfrage', () async {
    final x = await _World.create();
    final next = await x.w.seedRun(DateTime.utc(2030, 2, 14, 8), bpm: 160);

    await x.calc().calculateAfterRun(next);

    expect(x.values.runReads, 0, reason: 'Einzelabfragen auf Laufwerte');
    expect(x.values.runBulkReads, 1, reason: 'Sammelabfrage auf Laufwerte');
  });
}
