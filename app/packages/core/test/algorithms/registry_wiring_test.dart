import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Test-Schätzer: rechnet wie der Standard, trägt aber eine andere Methode und
/// Version (Verfahrenswechsel über die Registry, ADR-0004, NFR-0005).
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
    final m = e.result.metadata;
    return Vo2maxRunEstimate(
      result: AdvancedFitnessValue<double>(
        value: e.result.value,
        reason: e.result.reason,
        metadata: FitnessValueMetadata(
          calculatedAt: m.calculatedAt,
          dataFrom: m.dataFrom,
          dataTo: m.dataTo,
          usableMeasurements: m.usableMeasurements,
          dataSources: m.dataSources,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: m.parameterVersion,
          tier: m.tier,
        ),
      ),
      sections: e.sections,
      spreadPercent: e.spreadPercent,
      caps: e.caps,
      maxIsEstimated: e.maxIsEstimated,
    );
  }
}

/// Standardbestückung mit dem Test-Schätzer als aktiver VO₂max-Variante.
AlgorithmRegistry _withOther() => AlgorithmRegistry.standard()
  ..register(vo2maxEstimatorFamily, const _OtherEstimator())
  ..setActive(vo2maxEstimatorFamily, 'test-vo2max', 7);

Future<ComputedValue> _runValue(RecalcWorld w, int id) async => (await w
    .session
    .values
    .readRunValues({vo2maxRunValueKey}))[id]![vo2maxRunValueKey]!;

void main() {
  late RecalcWorld w;
  setUp(() async => w = await RecalcWorld.create());

  test('Analyse rechnet mit dem aktiven Schätzer der Registry', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    await w.calc(algorithms: _withOther()).calculateAfterRun(id);
    final v = await _runValue(w, id);
    expect((v.method, v.methodVersion), ('test-vo2max', 7));
    expect(v.value, isNotNull);
  });

  test('Standardbestückung: Analyse schreibt die Standardmethode', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    await w.calc().calculateAfterRun(id);
    final v = await _runValue(w, id);
    const standard = AcsmReserveVo2maxEstimator();
    expect(
      (v.method, v.methodVersion),
      (standard.method, standard.methodVersion),
    );
  });

  test('checkVersions mit dem Test-Schätzer: Angebot für Werte, die mit dem '
      'Standard gerechnet sind', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    await w.calc().calculateAfterRun(id);
    // Mit dem Standard: kein Angebot.
    expect(await w.recalc().checkVersions(), isNull);
    final offer = await w.recalc(algorithms: _withOther()).checkVersions();
    expect(offer, isNotNull);
    expect(offer!.causes, {RecalculationCause.algorithmVersion});
  });

  test('checkVersions mit dem Test-Schätzer: kein Angebot für Werte, die mit '
      'ihm gerechnet sind', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    final other = _withOther();
    await w.calc(algorithms: other).calculateAfterRun(id);
    expect(await w.recalc(algorithms: other).checkVersions(), isNull);
    // Zurück auf den Standard: jetzt ist der gespeicherte Wert veraltet.
    expect(await w.recalc().checkVersions(), isNotNull);
  });

  test('Bestätigen rechnet mit dem Test-Schätzer neu', () async {
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    await w.calc().calculateAfterRun(id);
    final s = w.recalc(algorithms: _withOther());
    final offer = await s.checkVersions();
    await s.confirm(offer!);
    final v = await _runValue(w, id);
    expect((v.method, v.methodVersion), ('test-vo2max', 7));
    expect(await s.checkVersions(), isNull);
  });

  test('Wertberechnung nimmt jede Familie aus der Registry', () {
    final reg = _withOther();
    final c = w.calc(algorithms: reg);
    expect(c.vo2maxEstimator, same(reg.active(vo2maxEstimatorFamily)));
    expect(c.longTerm, same(reg.active(vo2maxLongTermFamily)));
    expect(c.efficiency, same(reg.active(aerobicEfficiencyFamily)));
    expect(c.highHeartRateTime, same(reg.active(highHeartRateTimeFamily)));
  });
}
