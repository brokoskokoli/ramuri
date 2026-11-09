import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const p = FitnessParameters.v4();
const male = BanisterTrimp(LoadCoefficients.male);
const female = BanisterTrimp(LoadCoefficients.female);

FitnessResult<TrimpResult> run(
  BanisterTrimp m, {
  HeartRateBasis basis = const HeartRateBasis(maxBpm: 200, restingBpm: 40),
  required int bpm,
  int minutes = 30,
  List<HeartRateGap> gaps = const [],
}) => m.compute(
  basis: basis,
  heartRate: fitHeartRate(fitDense(0, minutes * 60 - 1, bpm), gaps: gaps),
  movement: fitMovement([fitSpan(0, minutes * 60)]),
  p: p,
);

double points(FitnessResult<TrimpResult> r) =>
    (r as FitnessAvailable<TrimpResult>).value.points;

void main() {
  test('FR-0197: männlich 30 min, HF 130, HFmax 200, Ruhe 40 (von Hand)', () {
    // r = 90/160 = 0,5625; 0,64 · 0,5625 · e^(1,92·0,5625) = 0,36 · e^1,08
    // = 0,36 · 2,944680 = 1,060085 je Minute; · 30 = 31,8026.
    final r = run(male, bpm: 130);
    expect(points(r), closeTo(31.8026, 1e-3));
    expect(points(r), closeTo(0.36 * math.exp(1.08) * 30, 1e-9));
    expect(r.method, 'banister-trimp-male');
    expect(r.methodVersion, 1);
  });

  test('weiblich nutzt k 0,86 und b 1,67', () {
    // 0,86 · 0,5625 · e^(1,67·0,5625) = 0,48375 · e^0,939375 = 1,23814 je min.
    expect(
      points(run(female, bpm: 130)),
      closeTo(30 * 0.48375 * 2.55866, 5e-2),
    );
    expect(
      points(run(female, bpm: 130)),
      closeTo(30 * 0.86 * 0.5625 * math.exp(1.67 * 0.5625), 1e-9),
    );
    expect(run(female, bpm: 130).method, 'banister-trimp-female');
  });

  test('Koeffizienten als benannte Parameter', () {
    expect(LoadCoefficients.male.k, 0.64);
    expect(LoadCoefficients.male.b, 1.92);
    expect(LoadCoefficients.female.k, 0.86);
    expect(LoadCoefficients.female.b, 1.67);
    expect(LoadCoefficients.fromStorage('male'), LoadCoefficients.male);
    expect(LoadCoefficients.fromStorage('female'), LoadCoefficients.female);
    expect(LoadCoefficients.fromStorage(null), isNull);
    expect(LoadCoefficients.fromStorage('x'), isNull);
  });

  test('Ruhepuls fehlt: nicht verfügbar, kein Wert', () {
    final r = run(male, basis: const HeartRateBasis(maxBpm: 200), bpm: 130);
    expect(r, isA<FitnessUnavailable<TrimpResult>>());
    expect(
      (r as FitnessUnavailable<TrimpResult>).reason,
      UnavailableReason.missingRestingHeartRate,
    );
  });

  test('Pulslücke wie Edwards: nur vorhandene Zeit, als unvollständig', () {
    // Lücke 5 min von 30 -> Abdeckung 25/30 (>= 80 %), unter 100 %.
    final r = run(male, bpm: 130, gaps: [fitGap(600, 900)]);
    final v = (r as FitnessAvailable<TrimpResult>).value;
    expect(v.incomplete, isTrue);
    expect(v.points, closeTo(0.36 * math.exp(1.08) * 25, 1e-6));
  });

  test('Registry führt beide Varianten', () {
    final ms = AlgorithmRegistry.standard()
        .variants(loadModelFamily)
        .map((v) => v.method);
    expect(ms, contains('banister-trimp-male'));
    expect(ms, contains('banister-trimp-female'));
  });
}
