import 'package:core/core.dart';
import 'package:test/test.dart';

const p = FitnessParameters.v3();
const reserve = HeartRateReserve();

double r(int max, int rest, int hf) {
  final res = reserve.relativeLoad(
    HeartRateBasis(maxBpm: max, restingBpm: rest),
    hf,
    p,
  );
  return (res as FitnessAvailable<double>).value;
}

UnavailableReason? reasonOf(int? max, int? rest) {
  final res = reserve.relativeLoad(
    HeartRateBasis(maxBpm: max, restingBpm: rest),
    120,
    p,
  );
  return res is FitnessUnavailable<double> ? res.reason : null;
}

void main() {
  test('Referenzwert aus docs/quality/testing.md: 190/60/151 ergibt 0,70', () {
    expect(r(190, 60, 151), 0.7);
  });

  test('Ergebnis nennt Methode, Versionen und Schätzung von HFmax', () {
    final res = reserve.relativeLoad(
      const HeartRateBasis(maxBpm: 190, restingBpm: 60, maxIsEstimated: true),
      151,
      p,
    );
    expect(res.method, 'heart-rate-reserve');
    expect(res.methodVersion, 1);
    expect(res.parameterVersion, p.parameterVersion);
    expect(res.maxIsEstimated, isTrue);
    expect(reserve.category, AlgorithmCategory.established);
  });

  test('fehlender Wert ist nicht verfügbar mit Grund, nie 0 (FR-0060)', () {
    expect(reasonOf(null, 60), UnavailableReason.missingMaxHeartRate);
    expect(reasonOf(190, null), UnavailableReason.missingRestingHeartRate);
    expect(reasonOf(null, null), UnavailableReason.missingMaxHeartRate);
  });

  test('PAR-018: HFmax gleich HFRuhe und darunter', () {
    expect(reasonOf(60, 60), UnavailableReason.maxNotAboveResting);
    expect(reasonOf(59, 60), UnavailableReason.maxNotAboveResting);
    expect(reasonOf(40, 60), UnavailableReason.maxNotAboveResting);
  });

  test('PAR-019: HFR 49 nicht verfügbar, 50 verfügbar, 1 nicht verfügbar', () {
    expect(reasonOf(109, 60), UnavailableReason.reserveTooSmall);
    expect(reasonOf(110, 60), isNull);
    expect(reasonOf(61, 60), UnavailableReason.reserveTooSmall);
  });

  test('r wird nicht geklemmt', () {
    expect(r(190, 60, 200), greaterThan(1));
    expect(r(190, 60, 40), lessThan(0));
  });

  test('78/130 ist exakt 0,6 (eine Division)', () {
    expect(r(190, 60, 138), 0.6);
  });
}
