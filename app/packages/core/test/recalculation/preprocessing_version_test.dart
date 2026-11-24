// Kettenversion der Vorverarbeitung am Laufwert (ADR-0004, NFR-0001,
// NFR-0005): steigt eine Stufenversion, bietet checkVersions eine
// Neuberechnung an; die Bestätigung schreibt die neue Kette an current, das
// original behält die alte. checkVersions und pendingOffer lesen die Werte
// aller Läufe in einer Abfrage, nicht je Lauf.

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Kette mit erhöhter Pulsstufe, wie sie nach einem Update gälte.
final String _raised = preprocessingChainVersion(
  heartRate: heartRateMethodVersion + 1,
);

RecalculationService _service(
  RecalcWorld w, {
  String? chain,
  StorageSession? over,
}) {
  final session = over ?? w.session;
  return RecalculationService(
    session: session,
    clock: w.clock,
    calculation: ValueCalculationService(
      session: session,
      clock: w.clock,
      preprocessingVersion: chain,
    ),
  );
}

/// Kettenversionen aller Laufwerte, die die Neuberechnung prüft.
Future<Map<String, String?>> _chains(RecalcWorld w, int id) async => {
  for (final p in await w.session.values.read(ValueOwner.run(id)))
    if (p.original.key == vo2maxRunValueKey ||
        p.original.key == trimpRunValueKey ||
        p.original.key == highHeartRateTimeValueKey)
      p.original.key:
          '${p.original.preprocessingVersion}|${p.current.preprocessingVersion}',
};

/// Zählt Einzelabfragen der Werte eines Laufs.
class _CountingValues implements ComputedValueStore {
  _CountingValues(this.inner);

  final ComputedValueStore inner;
  int runReads = 0;
  int bulkReads = 0;

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
    if (owner.runId != null) runReads++;
    return inner.read(owner);
  }

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(Set<String> keys) {
    bulkReads++;
    return inner.readRunValues(keys);
  }

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) => inner.readDayValues(keys);
}

void main() {
  test('nach dem Lauf trägt jeder geprüfte Laufwert die heutige Kette; '
      'unverändert kein Angebot', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8));
    await w.calc().calculateAfterRun(id);
    final now = preprocessingChainVersion();
    expect(await _chains(w, id), {
      vo2maxRunValueKey: '$now|$now',
      trimpRunValueKey: '$now|$now',
      highHeartRateTimeValueKey: '$now|$now',
    });
    final s = _service(w);
    addTearDown(s.dispose);
    expect(await s.checkVersions(), isNull);
    expect(await s.pendingOffer(), isNull);
  });

  test('Pulsstufe um 1 erhöht: Angebot mit algorithmVersion; Bestätigen '
      'schreibt die neue Kette an current, original behält die alte, danach '
      'kein Angebot', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8));
    await w.calc().calculateAfterRun(id);
    final old = preprocessingChainVersion();
    expect(_raised, isNot(old));

    final s = _service(w, chain: _raised);
    addTearDown(s.dispose);
    final offer = await s.checkVersions();
    expect(offer?.causes, {RecalculationCause.algorithmVersion});
    expect((await s.pendingOffer())?.causes, {
      RecalculationCause.algorithmVersion,
    });

    final result = await s.confirm(offer!);
    expect(result.runCount, 1);
    expect(await _chains(w, id), {
      vo2maxRunValueKey: '$old|$_raised',
      trimpRunValueKey: '$old|$_raised',
      highHeartRateTimeValueKey: '$old|$_raised',
    });
    expect(await s.checkVersions(), isNull);
    expect(await s.pendingOffer(), isNull);
  });

  test('jede Stufe um 1 erhöht ergibt ein Angebot', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8));
    await w.calc().calculateAfterRun(id);
    for (final chain in [
      preprocessingChainVersion(pace: paceMethodVersion + 1),
      preprocessingChainVersion(movement: movementMethodVersion + 1),
      preprocessingChainVersion(position: positionMethodVersion + 1),
      preprocessingChainVersion(altitude: altitudeMethodVersion + 1),
      preprocessingChainVersion(settling: settlingMethodVersion + 1),
      preprocessingChainVersion(
        sectionQuality: sectionQualityMethodVersion + 1,
      ),
      preprocessingChainVersion(steps: stepsMethodVersion + 1),
    ]) {
      final s = _service(w, chain: chain);
      addTearDown(s.dispose);
      expect((await s.checkVersions())?.causes, {
        RecalculationCause.algorithmVersion,
      }, reason: chain);
    }
  });

  test('checkVersions und pendingOffer: keine Einzelabfrage je Lauf, eine '
      'Sammelabfrage (drei Läufe)', () async {
    final w = await RecalcWorld.create();
    for (final d in [1, 3, 5]) {
      final id = await w.seedRun(DateTime.utc(2030, 2, d, 8));
      await w.calc().calculateAfterRun(id);
    }
    final values = _CountingValues(w.session.values);
    final session = FaultySession(
      w.session,
      rawData: w.session.rawData,
      values: values,
    );
    final same = _service(w, over: session);
    addTearDown(same.dispose);
    expect(await same.checkVersions(), isNull);
    expect(await same.pendingOffer(), isNull);
    expect(values.runReads, 0);
    expect(values.bulkReads, 1);

    final raised = _service(w, over: session, chain: _raised);
    addTearDown(raised.dispose);
    values
      ..runReads = 0
      ..bulkReads = 0;
    expect((await raised.checkVersions())?.causes, {
      RecalculationCause.algorithmVersion,
    });
    expect((await raised.pendingOffer())?.causes, {
      RecalculationCause.algorithmVersion,
    });
    expect(values.runReads, 0);
  });
}
