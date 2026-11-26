import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';
import 'snapshot_support.dart';

/// Zwischenstand der Neuberechnung: Vorverarbeitung über den Offload, je Lauf
/// nur die fertigen Werte gehalten, Ergebnis unverändert (NFR-0001).
///
/// `fixtures/snapshot_reference.txt` ist der Zwischenstand desselben
/// Bestands, gerechnet mit der Fassung vor dieser Änderung (Vorverarbeitung
/// im aufrufenden Isolate, jede Analyse samt Vorverarbeitung gehalten).
class _CountingOffload {
  final jobs = <Object>[];
  final runIds = <int>[];

  Future<R> call<A, R>(R Function(A) job, A argument) async {
    jobs.add(job);
    if (argument case (
      run: final StoredRun run,
      end: DateTime _,
      raw: StoredRawData _,
      gaps: List<StoredGap> _,
      parameters: PreprocessingParameters _,
    )) {
      runIds.add(run.id);
    }
    return job(argument);
  }
}

ValueCalculationService _calc(RecalcWorld w, Offload offload) =>
    ValueCalculationService(
      session: w.session,
      clock: w.clock,
      algorithms: AlgorithmRegistry.standard(),
      offload: offload,
    );

void main() {
  final reference = File('test/recalculation/fixtures/snapshot_reference.txt')
      .readAsStringSync();
  // buildSnapshot speichert nichts: ein Bestand für alle Fälle unten.
  late RecalcWorld mixed;
  setUpAll(() async {
    mixed = await RecalcWorld.create();
    await seedMixedRuns(mixed);
  });

  test(
    'Zwischenstand gleich dem vor der Änderung (alle Werte, Inline)',
    () async {
      final w = mixed;
      final s = await _calc(w, inlineOffload).buildSnapshot();
      expect(snapshotDump(s), reference);
    },
  );

  test('Zwischenstand gleich dem vor der Änderung (eigener Isolate)', () async {
    final w = mixed;
    final s = await _calc(w, isolateOffload).buildSnapshot();
    expect(snapshotDump(s), reference);
  });

  test('analyze rechnet die Vorverarbeitung über den Offload', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    final run = (await w.session.runs.get(id))!;
    final offload = _CountingOffload();
    final a = await RunAnalyzer(
      fitness: const FitnessParameters.v5(),
      preprocessing: const PreprocessingParameters.v5(),
      basis: const HeartRateBasis(maxBpm: 190, restingBpm: 60),
      estimator: AlgorithmRegistry.standard().active(vo2maxEstimatorFamily),
      offload: offload.call,
    ).analyze(w.session, run, calculatedAt: recalcNow);
    expect(offload.jobs, [same(replayJob)]);
    expect(offload.runIds, [id]);
    expect(a.preprocessing, isNotNull);
  });

  test('Neuberechnung: jeder Lauf mit Dauer genau einmal über den Offload, '
      'nichts daneben', () async {
    final w = mixed;
    final offload = _CountingOffload();
    await _calc(w, offload.call).buildSnapshot();
    final withDuration = [
      for (final r in await w.session.runs.list())
        if (r.endedAt!.isAfter(r.startedAt)) r.id,
    ];
    expect(offload.runIds..sort(), withDuration..sort());
    expect(offload.jobs.every((j) => identical(j, replayJob)), isTrue);
  });

  test('Zwischenstand hält keine Vorverarbeitung', () async {
    final w = mixed;
    final analyses = RunAnalysisCache();
    await _calc(w, inlineOffload).buildSnapshot(analyses: analyses);
    expect(analyses.length, (await w.session.runs.list()).length);
    expect(analyses.heldPreprocessings, 0);
  });

  test('withoutPreprocessing behält alles außer der Vorverarbeitung', () async {
    final w = await RecalcWorld.create();
    final id = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
    final full =
        await RunAnalyzer(
          fitness: const FitnessParameters.v5(),
          preprocessing: const PreprocessingParameters.v5(),
          basis: const HeartRateBasis(maxBpm: 190, restingBpm: 60),
          estimator: w.calc().vo2maxEstimator,
        ).analyze(
          w.session,
          (await w.session.runs.get(id))!,
          calculatedAt: recalcNow,
        );
    expect(full.preprocessing, isNotNull);
    final slim = full.withoutPreprocessing();
    expect(slim.preprocessing, isNull);
    expect(slim.run, same(full.run));
    expect(slim.selection, same(full.selection));
    expect(slim.estimate, same(full.estimate));
    expect(slim.basis, same(full.basis));
    expect(slim.sources, full.sources);
    expect(slim.belt, same(full.belt));
  });
}
