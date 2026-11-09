import 'package:core/core.dart';
import 'package:test/test.dart';

LoadProfileResolution res(
  LoadProfile profile, {
  int? max = 190,
  int? rest,
  LoadCoefficients? c,
}) => resolveLoadProfile(
  requested: profile,
  basis: HeartRateBasis(maxBpm: max, restingBpm: rest),
  coefficients: c,
  fitness: const FitnessParameters.v4(),
);

void main() {
  test('Edwards ist ohne Ruhepuls und Koeffizienten anwendbar', () {
    final r = res(LoadProfile.edwards);
    expect(r.applicable, isTrue);
    expect(r.model, isA<EdwardsTrimp>());
  });

  test('Banister mit Ruhepuls und Koeffizienten: anwendbar', () {
    final r = res(LoadProfile.banister, rest: 50, c: LoadCoefficients.female);
    expect(r.applicable, isTrue);
    expect(r.model!.method, BanisterTrimp.methodIdFemale);
  });

  test('Banister ohne Ruhepuls: nicht anwendbar, kein Wechsel auf Edwards', () {
    final r = res(LoadProfile.banister, c: LoadCoefficients.male);
    expect(r.applicable, isFalse);
    expect(r.model, isNull);
    expect(r.profile, LoadProfile.banister);
    expect(r.issues, [LoadProfileIssue.missingRestingHeartRate]);
  });

  test('Banister ohne Koeffizienten: nicht anwendbar', () {
    final r = res(LoadProfile.banister, rest: 50);
    expect(r.applicable, isFalse);
    expect(r.issues, [LoadProfileIssue.missingCoefficients]);
  });

  test('Banister ohne beides: beide Gründe; Ruhepuls 0 zählt als fehlend', () {
    final r = res(LoadProfile.banister, rest: 0);
    expect(r.issues, [
      LoadProfileIssue.missingRestingHeartRate,
      LoadProfileIssue.missingCoefficients,
    ]);
  });

  test('Banister nur mit berechenbarem r (PAR-018, PAR-019)', () {
    const c = LoadCoefficients.male;
    // HFR 190 - 145 = 45 < 50 (PAR-019).
    var r = res(LoadProfile.banister, rest: 145, c: c);
    expect(r.applicable, isFalse);
    expect(r.model, isNull);
    expect(r.issues, [LoadProfileIssue.heartRateReserveUnusable]);
    // HFmax nicht über dem Ruhepuls (PAR-018).
    r = res(LoadProfile.banister, max: 60, rest: 70, c: c);
    expect(r.issues, [LoadProfileIssue.heartRateReserveUnusable]);
    // HFmax fehlt.
    r = res(LoadProfile.banister, max: null, rest: 50, c: c);
    expect(r.issues, [LoadProfileIssue.heartRateReserveUnusable]);
    // Genau an der Grenze: HFR 50 ist brauchbar.
    r = res(LoadProfile.banister, rest: 140, c: c);
    expect(r.applicable, isTrue);
    // Edwards bleibt davon unberührt.
    expect(res(LoadProfile.edwards, rest: 145).applicable, isTrue);
  });

  test('Speicherwert: unbekannt -> Edwards', () {
    expect(LoadProfile.fromStorage('banister'), LoadProfile.banister);
    expect(LoadProfile.fromStorage('edwards'), LoadProfile.edwards);
    expect(LoadProfile.fromStorage(null), LoadProfile.edwards);
    expect(LoadProfile.fromStorage('zzz'), LoadProfile.edwards);
  });
}
