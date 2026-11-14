import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_helpers.dart' as s;

/// Eigenschaft: Reihen werden nie gemischt (FR-0115). Das z einer Reihe hängt
/// nur von ihren eigenen Werten ab, nie von Werten anderer Quell-Apps, Haltungen
/// oder Geräte. Zufallsdaten (synthetisch, Seed fest).
void main() {
  var nonVacuous = 0;
  tearDownAll(() => expect(nonVacuous, greaterThan(100)));
  test('Health Connect: fremde Quellen ändern das z der gewählten nie', () {
    for (var seed = 0; seed < 60; seed++) {
      final rnd = Random(seed);
      List<double?> rows(int from, double base) => [
        for (var i = 0; i < 29; i++)
          i >= from && rnd.nextDouble() < 0.9
              ? base + rnd.nextInt(12).toDouble()
              : null,
      ];
      final a = s.rhrSamples('app.a', rows(0, 50));
      final fromB = 5 + rnd.nextInt(10);
      final b1 = s.rhrSamples('app.b', rows(fromB, 70));
      // Andere Werte derselben Tage der fremden Quelle, kürzer als A.
      final b2 = [
        for (final x in b1)
          HealthSample(time: x.time, value: x.value + 30, origin: x.origin),
      ];
      final r1 = s.hcRhr([...a, ...b1]);
      final r2 = s.hcRhr([...a, ...b2]);
      final alone = s.hcRhr(a);
      if (alone.z != null) nonVacuous++;
      expect(r1.origin, 'app.a', reason: 'seed $seed');
      expect(r1.z, alone.z, reason: 'seed $seed');
      expect(r2.z, alone.z, reason: 'seed $seed');
      expect(r1.referenceCount, alone.referenceCount);
    }
  });

  test('Kamera: Haltung und Gerät ändern das z der anderen Reihe nie', () {
    for (var seed = 0; seed < 60; seed++) {
      final rnd = Random(seed);
      List<MorningMeasurement> series(
        RestingPosture p,
        String model,
        double base,
      ) => [
        for (var i = 0; i < 29; i++)
          if (rnd.nextDouble() < 0.9)
            s.morning(
              dayIdx: i,
              hr: base + rnd.nextInt(12),
              rmssd: base - 10 + rnd.nextInt(20),
              posture: p,
              model: model,
            ),
      ];
      final lying = series(RestingPosture.lying, 'M1', 55);
      final other = [
        ...series(RestingPosture.sitting, 'M1', 80),
        ...series(RestingPosture.lying, 'M2', 90),
      ];
      final alone = cameraDeviations(lying, today: s.todayKey);
      final mixed = cameraDeviations([...lying, ...other], today: s.todayKey);
      for (final r in alone) {
        final m = mixed.singleWhere(
          (x) => x.factor == r.factor && x.cameraSeries == r.cameraSeries,
        );
        if (r.z != null) nonVacuous++;
        expect(m.z, r.z, reason: 'seed $seed');
        expect(m.referenceCount, r.referenceCount);
      }
    }
  });
}
