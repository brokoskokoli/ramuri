import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const p = FitnessParameters.v5();
const model = HighHeartRateTime();
const plan = PlanParameters();

FitnessResult<HighHeartRateTimeResult> run({
  HeartRateBasis basis = const HeartRateBasis(maxBpm: 190),
  required List<TimeSpan> moving,
  required List<RawHeartRate> hrs,
  List<HeartRateGap> gaps = const [],
}) => model.compute(
  basis: basis,
  heartRate: fitHeartRate(hrs, gaps: gaps),
  movement: fitMovement(moving),
  p: p,
);

HighHeartRateTimeResult value(FitnessResult<HighHeartRateTimeResult> r) =>
    (r as FitnessAvailable<HighHeartRateTimeResult>).value;

UnavailableReason reason(FitnessResult<HighHeartRateTimeResult> r) =>
    (r as FitnessUnavailable<HighHeartRateTimeResult>).reason;

/// [above] Sekunden bei 160 bpm (84 % von 190), danach 20 min bei 120 bpm.
FitnessResult<HighHeartRateTimeResult> withAbove(int above) => run(
  moving: [fitSpan(0, above + 1200)],
  hrs: [...fitDense(0, above - 1, 160), ...fitDense(above, above + 1199, 120)],
);

void main() {
  test('PAR-058: 9 min ≥ 80 % HFmax nicht intensiv, 10 min intensiv', () {
    final nine = value(withAbove(9 * 60));
    final ten = value(withAbove(10 * 60));
    expect(nine.minutes, 9);
    expect(ten.minutes, 10);
    expect(plan.completedIntensive(highHrMinutes: nine.minutes), isFalse);
    expect(plan.completedIntensive(highHrMinutes: ten.minutes), isTrue);
  });

  test('Grenze 80 % inklusiv: HFmax 190, 152 bpm zählt, 151 nicht', () {
    final at = run(moving: [fitSpan(0, 60)], hrs: fitDense(0, 59, 152));
    final below = run(moving: [fitSpan(0, 60)], hrs: fitDense(0, 59, 151));
    expect(value(at).minutes, 1);
    expect(value(below).minutes, 0);
    expect(value(below).incomplete, isFalse);
  });

  test('Pulslücke (PAR-010) zählt nicht, der Wert wird vorläufig', () {
    // 12 min Bewegung bei 160 bpm, aber 3 min davon ohne Puls.
    final r = run(
      moving: [fitSpan(0, 720)],
      hrs: [...fitDense(0, 299, 160), ...fitDense(480, 719, 160)],
      gaps: [fitGap(300, 480)],
    );
    final v = value(r);
    expect(v.minutes, 9);
    expect(v.incomplete, isTrue);
    expect(plan.completedIntensive(highHrMinutes: v.minutes), isFalse);
  });

  test('Pause zählt nicht', () {
    // Puls läuft in der Pause (300..480) weiter, zählt aber nicht.
    final r = run(
      moving: [fitSpan(0, 300), fitSpan(480, 720)],
      hrs: fitDense(0, 719, 160),
    );
    expect(value(r).minutes, 9);
  });

  test('ohne HFmax nicht verfügbar (missingMaxHeartRate)', () {
    final r = run(
      basis: const HeartRateBasis(restingBpm: 50),
      moving: [fitSpan(0, 60)],
      hrs: fitDense(0, 59, 160),
    );
    expect(reason(r), UnavailableReason.missingMaxHeartRate);
    expect(r.method, HighHeartRateTime.methodId);
  });

  test('HFmax nicht über HFRuhe (PAR-018) nicht verfügbar', () {
    final r = run(
      basis: const HeartRateBasis(maxBpm: 60, restingBpm: 60),
      moving: [fitSpan(0, 60)],
      hrs: fitDense(0, 59, 160),
    );
    expect(reason(r), UnavailableReason.maxNotAboveResting);
  });

  test('ohne Puls nicht verfügbar (noHeartRate), nie 0', () {
    final r = run(moving: [fitSpan(0, 600)], hrs: const []);
    expect(reason(r), UnavailableReason.noHeartRate);
  });

  test('Ergebnis nennt Methode, Version, Kategorie, Parameterversion', () {
    final r = withAbove(60);
    expect(r.method, 'high-hr-time');
    expect(r.methodVersion, 1);
    expect(r.parameterVersion, p.parameterVersion);
    expect(model.category, AlgorithmCategory.heuristic);
  });
}
