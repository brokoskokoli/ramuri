import 'package:core/core.dart';
import 'package:test/test.dart';

LoadProfileResolution res(
  LoadProfile profile, {
  int? rest,
  LoadCoefficients? c,
}) => resolveLoadProfile(
  requested: profile,
  basis: HeartRateBasis(maxBpm: 190, restingBpm: rest),
  coefficients: c,
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

  test('Speicherwert: unbekannt -> Edwards', () {
    expect(LoadProfile.fromStorage('banister'), LoadProfile.banister);
    expect(LoadProfile.fromStorage('edwards'), LoadProfile.edwards);
    expect(LoadProfile.fromStorage(null), LoadProfile.edwards);
    expect(LoadProfile.fromStorage('zzz'), LoadProfile.edwards);
  });
}
