import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/support.dart';
import 'fitness_support.dart';

/// Nur im Test: ein weiteres Belastungsmodell, ohne dass sich Aufzeichnung
/// oder Rohdatenschema ändern (NFR-0005).
class FakeLoad extends LoadModel {
  const FakeLoad();
  @override
  String get method => 'fake-load';
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  @override
  FitnessResult<TrimpResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) => FitnessAvailable(
    value: TrimpResult(
      points: 42,
      incomplete: false,
      coveredMicros: 1,
      movingMicros: 1,
      aboveHint: false,
    ),
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
}

void main() {
  test('Fake-Variante läuft über die Registry auf denselben Rohdaten', () {
    final pre = RunPreprocessor(start: t0);
    for (var s = 0; s <= 60; s++) {
      pre.addPosition(pos(s, 3.0 * s));
      pre.addHeartRate(RawHeartRate(time: at(s), source: 'x', bpm: 150));
    }
    final x = pre.result(at: at(60));
    FitnessResult<TrimpResult> via(AlgorithmRegistry r) => r
        .active(loadModelFamily)
        .compute(
          basis: const HeartRateBasis(maxBpm: 200),
          heartRate: x.heartRate,
          movement: x.movement,
          p: const FitnessParameters.v3(),
        );

    final r = AlgorithmRegistry.standard()
      ..register(loadModelFamily, const FakeLoad());
    expect(via(r).method, 'edwards-trimp');
    final edwards = (via(r) as FitnessAvailable<TrimpResult>).value.points;
    expect(edwards, closeTo(60 * 3 / 60, 1e-9));
    r.setActive(loadModelFamily, 'fake-load', 1);
    final res = via(r);
    expect(res.method, 'fake-load');
    expect((res as FitnessAvailable<TrimpResult>).value.points, 42);
    expect(r.variants(loadModelFamily).map((v) => v.method), [
      'edwards-trimp',
      'fake-load',
    ]);
  });

  test('NFR-0005: lib/src/fitness importiert weder ports noch Speicher', () {
    final files = Directory('lib/src/fitness')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      for (final line in f.readAsLinesSync().where(
        (l) =>
            l.trimLeft().startsWith('import') ||
            l.trimLeft().startsWith('export'),
      )) {
        expect(line, isNot(contains('ports/')), reason: f.path);
        expect(
          line,
          isNot(
            matches(
              RegExp(
                r'storage|speicher|database|drift|sqlite|dart:io|dart:ui',
                caseSensitive: false,
              ),
            ),
          ),
          reason: f.path,
        );
      }
    }
  });

  test(
    'alle Varianten von standard(): Methode, Version, Kategorie gesetzt',
    () {
      final all = AlgorithmRegistry.standard().allVariants.toList();
      expect(all.map((v) => v.method).toSet(), {
        'heart-rate-reserve',
        'reserve-zones',
        'edwards-trimp',
      });
      for (final v in all) {
        expect(v.method.trim(), isNotEmpty);
        expect(v.methodVersion, greaterThanOrEqualTo(1));
        expect(AlgorithmCategory.values, contains(v.category));
      }
    },
  );

  test(
    'jedes Ergebnis nennt die erzeugende Variante (verfügbar und nicht)',
    () {
      const p = FitnessParameters.v3();
      final hr = fitHeartRate(fitDense(0, 59, 150));
      final mv = fitMovement([fitSpan(0, 60)]);
      const full = HeartRateBasis(maxBpm: 200, restingBpm: 50);
      const none = HeartRateBasis();
      final reg = AlgorithmRegistry.standard();
      final results = <(AlgorithmVariant, FitnessResult<Object?>)>[];
      for (final b in [full, none]) {
        final hrr = reg.active(heartRateReserveFamily);
        results.add((hrr, hrr.relativeLoad(b, 150, p)));
        final z = reg.active(reserveZonesFamily);
        results.add((
          z,
          z.timeInZones(basis: b, heartRate: hr, movement: mv, p: p),
        ));
        final l = reg.active(loadModelFamily);
        results.add((
          l,
          l.compute(basis: b, heartRate: hr, movement: mv, p: p),
        ));
      }
      expect(
        results.whereType<(AlgorithmVariant, FitnessAvailable)>(),
        isNotEmpty,
      );
      expect(results.where((r) => r.$2 is FitnessUnavailable), hasLength(3));
      expect(results.where((r) => r.$2 is FitnessAvailable), hasLength(3));
      for (final (v, r) in results) {
        expect(r.method, v.method);
        expect(r.methodVersion, v.methodVersion);
        expect(r.parameterVersion, p.parameterVersion);
      }
    },
  );
}
