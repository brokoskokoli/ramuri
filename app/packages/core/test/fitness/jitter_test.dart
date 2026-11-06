import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/support.dart';

// Befund 1 (Review 2): Zeitstempel-Jitter ohne fehlende Werte darf weder
// `incomplete` setzen noch Punkte kosten. Alles über den echten
// RunPreprocessor, 1800 s, 3 m/s, Puls 150 bei HFmax 200 (Gewicht 3, also
// 90 Punkte), fester Seed.

const trimp = EdwardsTrimp();
const p = FitnessParameters.v4();
const basis = HeartRateBasis(maxBpm: 200, restingBpm: 50);
const until = 1800;

RunPreprocessing jittered(
  int jitterMs, {
  Set<int> drop = const {},
  int seed = 7,
}) {
  final rnd = Random(seed);
  final r = RunPreprocessor(start: t0);
  for (var s = 0; s <= until; s++) {
    r.addPosition(pos(s, 3.0 * s));
    if (drop.contains(s)) continue;
    final j = jitterMs == 0 ? 0 : rnd.nextInt(2 * jitterMs + 1) - jitterMs;
    final ms = (s * 1000 + j).clamp(0, until * 1000);
    r.addHeartRate(
      RawHeartRate(
        time: t0.add(Duration(milliseconds: ms)),
        source: 'x',
        bpm: 150,
      ),
    );
  }
  return r.result(at: at(until));
}

FitnessResult<TrimpResult> load(RunPreprocessing x) => trimp.compute(
  basis: basis,
  heartRate: x.heartRate,
  movement: x.movement,
  p: p,
);

SectionQuality quality(RunPreprocessing x) => SectionQuality.assess(
  from: at(0),
  to: at(until),
  heartRate: x.heartRate,
  position: x.position,
  settlingIntervals: const [],
  parameters: x.parameters,
);

TrimpResult value(FitnessResult<TrimpResult> r) =>
    (r as FitnessAvailable<TrimpResult>).value;

void main() {
  for (final j in [0, 1, 50, 100, 200]) {
    test('Jitter ±$j ms ohne Aussetzer: vollständig, 90,0 Punkte', () {
      final x = jittered(j);
      final v = value(load(x));
      expect(v.incomplete, isFalse);
      expect(v.points, 90.0);
      expect(v.coverage, 1.0);
      final q = quality(x);
      expect(q.missingHeartRateShare, 0.0);
      expect(q.meetsHeartRateGapRule, isTrue);
    });
  }

  test('Jitter ±490 ms: festgehalten, Abstände bis 1,98 s', () {
    // Abstand ab 1,5 Takten zählt als Aussetzer (Δt − Takt fehlt). Gemessen
    // mit Seed 7: Abdeckung 92,9 %, 83,6 Punkte, unvollständig; SectionQuality
    // 7,1 % fehlend, die 5-%-Regel greift hier.
    final x = jittered(490);
    final v = value(load(x));
    expect(v.coverage, closeTo(0.929, 0.005));
    expect(v.incomplete, isTrue);
    expect(quality(x).missingHeartRateShare, closeTo(0.071, 0.005));
  });

  test('ein ausgefallener Wert im 1-Hz-Raster kostet genau einen Takt', () {
    final x = jittered(0, drop: {100});
    final v = value(load(x));
    expect(v.movingMicros - v.coveredMicros, 1000000);
    expect(v.incomplete, isTrue);
    expect(quality(x).missingHeartRateShare, closeTo(1 / until, 1e-9));
  });

  test('Jitter ±200 ms plus ein Aussetzer: ein Takt (±Jitter) fehlt', () {
    final x = jittered(200, drop: {100});
    final v = value(load(x));
    final lost = v.movingMicros - v.coveredMicros;
    expect(lost, inInclusiveRange(600000, 1400000));
  });
}
