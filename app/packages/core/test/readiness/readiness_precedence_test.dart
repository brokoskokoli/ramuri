import 'package:core/core.dart';
import 'package:test/test.dart';

DeviationResult res(
  ReadinessSource source, {
  double? z,
  ReadinessFactor factor = ReadinessFactor.hrv,
  MorningSeriesKey? key,
  int refN = 20,
}) => DeviationResult(
  factor: factor,
  source: source,
  origin: source == ReadinessSource.healthConnect ? 'app.a' : null,
  cameraSeries: key,
  z: z,
  reason: z == null ? NoDeviationReason.noValueToday : null,
  referenceCount: refN,
);

const lyingKey = MorningSeriesKey(RestingPosture.lying, 'H', 'M1');
const sittingKey = MorningSeriesKey(RestingPosture.sitting, 'H', 'M1');

FactorEvaluation choose(
  DeviationResult? hc,
  List<DeviationResult> cam, {
  bool released = true,
}) => chooseFactor(
  factor: ReadinessFactor.hrv,
  healthConnect: hc,
  camera: cam,
  cameraReleased: released,
);

void main() {
  final hcOk = res(ReadinessSource.healthConnect, z: -1.2);
  final hcNo = res(ReadinessSource.healthConnect);
  final camOk = res(ReadinessSource.camera, z: 0.3, key: lyingKey);
  final camNo = res(ReadinessSource.camera, key: lyingKey);

  test('Vorrang: Health Connect mit z vor Kamera mit z', () {
    final e = choose(hcOk, [camOk]);
    expect(identical(e.chosen, hcOk), isTrue);
    expect(e.others, [camOk]);
  });

  test('Health Connect ohne z: Kamera mit z zählt, wenn freigegeben', () {
    final e = choose(hcNo, [camOk]);
    expect(identical(e.chosen, camOk), isTrue);
    expect(e.others, [hcNo]);
  });

  test('Kamera nicht freigegeben: keine Reihe zählt, beide nur Tatsache', () {
    final e = choose(hcNo, [camOk], released: false);
    expect(e.chosen, isNull);
    expect(e.others.length, 2);
  });

  test('Freigabe ändert den Vorrang von Health Connect nicht', () {
    expect(
      identical(choose(hcOk, [camOk], released: false).chosen, hcOk),
      isTrue,
    );
  });

  test('weder Health Connect noch Kamera mit z: nichts zählt', () {
    final e = choose(hcNo, [camNo]);
    expect(e.chosen, isNull);
    expect(e.others.length, 2);
    expect(choose(null, const []).chosen, isNull);
  });

  test('keine Mittelung: die Wahl ist genau eine der Reihen', () {
    final e = choose(hcOk, [camOk]);
    expect(e.chosen!.z, -1.2);
  });

  test(
    'mehrere Kamerareihen: liegend vor sitzend, auch bei kleinerer Referenz',
    () {
      final sit = res(ReadinessSource.camera, z: 1, key: sittingKey, refN: 28);
      final lie = res(ReadinessSource.camera, z: 2, key: lyingKey, refN: 15);
      expect(choose(null, [sit, lie]).chosen!.z, 2);
      expect(choose(null, [lie, sit]).chosen!.z, 2);
    },
  );

  test('gleiche Haltung: mehr Referenzwerte zuerst', () {
    const k2 = MorningSeriesKey(RestingPosture.lying, 'H', 'M0');
    final a = res(ReadinessSource.camera, z: 1, key: lyingKey, refN: 16);
    final b = res(ReadinessSource.camera, z: 2, key: k2, refN: 20);
    expect(choose(null, [a, b]).chosen!.z, 2);
  });

  test('Kamerareihe ohne z wird übergangen, die nächste zählt', () {
    final sit = res(ReadinessSource.camera, z: 1, key: sittingKey);
    expect(choose(null, [camNo, sit]).chosen!.z, 1);
  });

  test('andere Faktoren werden ignoriert', () {
    final other = res(
      ReadinessSource.camera,
      z: 5,
      key: lyingKey,
      factor: ReadinessFactor.restingHeartRate,
    );
    expect(choose(null, [other]).chosen, isNull);
  });
}
