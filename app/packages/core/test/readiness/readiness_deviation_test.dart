import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

final today = DateTime.utc(2026, 11, 14);
DateTime back(int n) => today.subtract(Duration(days: n));

/// Reihe aus [ref] (Tage heute-1 bis heute-n, in dieser Reihenfolge) und
/// [now] (heute, null = fehlt). Synthetische Werte.
Map<DateTime, double> series(List<double> ref, double? now) => {
  for (var i = 0; i < ref.length; i++) back(i + 1): ref[i],
  today: ?now,
};

List<double> alternating(double a, double b, [int n = 28]) => [
  for (var i = 0; i < n; i++) i.isOdd ? a : b,
];

DeviationResult hrv(Map<DateTime, double> s, {bool camera = false}) =>
    deviationForSeries(
      byDay: s,
      today: today,
      factor: ReadinessFactor.hrv,
      source: camera ? ReadinessSource.camera : ReadinessSource.healthConnect,
      rules: camera ? DeviationRules.cameraHrv : DeviationRules.hrv,
    );

DeviationResult rhr(Map<DateTime, double> s, {bool camera = false}) =>
    deviationForSeries(
      byDay: s,
      today: today,
      factor: ReadinessFactor.restingHeartRate,
      source: camera ? ReadinessSource.camera : ReadinessSource.healthConnect,
      rules: camera
          ? DeviationRules.cameraRestingHeartRate
          : DeviationRules.restingHeartRate,
    );

void main() {
  group('robustZ (FR-0113)', () {
    test('X = {48,50,52}, x = 50 ergibt z = 0', () {
      final z = robustZ(reference: [48, 50, 52], x: 50, k: 1, madMin: 0.001);
      expect(z, 0);
    });

    test('X = {48,50,52}, k = 4, x = 51 ergibt z = 0,67', () {
      final z = robustZ(reference: [48, 50, 52], x: 51, k: 4, madMin: 0.001);
      expect(z, closeTo(0.6745, 0.0005));
      expect(z!.toStringAsFixed(2), '0.67');
    });

    test('MAD = 0 ergibt kein z (FR-0114)', () {
      expect(
        robustZ(reference: [50, 50, 50, 50], x: 55, k: 3, madMin: 0),
        isNull,
      );
    });

    test('MAD genau auf der Grenze zählt, darunter nicht', () {
      // Referenz {49, 51, 49, 51}: Median 50, MAD 1.
      final r = <double>[49, 51, 49, 51];
      expect(robustZ(reference: r, x: 52, k: 1, madMin: 1), isNotNull);
      expect(robustZ(reference: r, x: 52, k: 1, madMin: 1.0001), isNull);
    });
  });

  group('deviationForSeries (PAR-161, PAR-162)', () {
    test('HRV: z auf ln(RMSSD) aus dem 7-Tage-Mittel mit Nenner durch √k', () {
      final ref = alternating(50, 53);
      final r = hrv(series(ref, 60));
      // Fenster: heute 60, heute-1..-6 abwechselnd 50 (i ungerade -> Tag -1: 50).
      final win = <double>[
        60,
        for (var i = 1; i < 7; i++) ref[i - 1],
      ].map(math.log).toList();
      final x = win.reduce((a, b) => a + b) / 7;
      final lr = ref.map(math.log).toList()..sort();
      final med = (lr[13] + lr[14]) / 2;
      final mad = (math.log(53) - math.log(50)) / 2;
      expect(r.z, closeTo((x - med) / (1.4826 * mad / math.sqrt(7)), 1e-9));
      expect(r.windowCount, 7);
      expect(r.referenceCount, 28);
      expect(r.fewMeasurements, isFalse);
    });

    test(
      'Ruhepuls: Vorzeichen umgedreht, niedriger als üblich ist positiv',
      () {
        final ref = alternating(60, 62);
        final low = rhr(series(ref, 55));
        final high = rhr(series(ref, 70));
        expect(low.z, greaterThan(0));
        expect(high.z, lessThan(0));
        // Tag -1: 60, -2: 62, ... -6: 62; Fenster mit heute 55, k = 7.
        final x = (55 + 60 + 62 + 60 + 62 + 60 + 62) / 7;
        expect(low.z, closeTo(-(x - 61) / (1.4826 * 1.0 / math.sqrt(7)), 1e-9));
      },
    );

    test('z = 0 bleibt 0 (kein -0 durch die Umkehr)', () {
      final ref = alternating(60, 62);
      final r = rhr(series(ref, 61 * 7 - (60 + 62 + 60 + 62 + 60 + 62)));
      expect(r.z, 0);
      expect(r.z!.isNegative, isFalse);
    });

    test('heute fehlt: kein z', () {
      final r = hrv(series(alternating(50, 53), null));
      expect(r.z, isNull);
      expect(r.reason, NoDeviationReason.noValueToday);
    });

    test('leere Reihe: kein z', () {
      expect(hrv({}).reason, NoDeviationReason.noSeries);
    });

    test('weniger als 14 Referenzwerte: kein z, 14 genügen', () {
      final r13 = hrv({
        for (var i = 1; i <= 13; i++) back(i): i.isOdd ? 50.0 : 53.0,
        today: 55,
      });
      expect(r13.z, isNull);
      expect(r13.reason, NoDeviationReason.tooFewReference);
      expect(r13.referenceCount, 13);
      final r14 = hrv({
        for (var i = 1; i <= 14; i++) back(i): i.isOdd ? 50.0 : 53.0,
        today: 55,
      });
      expect(r14.z, isNotNull);
    });

    test(
      'Referenz zählt nur die 28 Tage vor heute, nicht heute, nicht älter',
      () {
        final r = hrv({
          for (var i = 1; i <= 28; i++) back(i): i.isOdd ? 50.0 : 53.0,
          back(29): 120, // zu alt
          back(40): 120,
          today: 55,
        });
        expect(r.referenceCount, 28);
      },
    );

    test('weniger als 3 Werte in 7 Tagen: kein z', () {
      // Werte nur heute und vor 3 Tagen im Fenster, Rest älter als 7 Tage.
      final s = <DateTime, double>{
        for (var i = 8; i <= 28; i++) back(i): 50.0 + (i % 4) * 2,
        back(3): 51,
        today: 55,
      };
      final r = hrv(s);
      expect(r.z, isNull);
      expect(r.reason, NoDeviationReason.tooFewInWindow);
      expect(r.windowCount, 2);
      // Mit einem dritten Wert entsteht z.
      expect(hrv({...s, back(5): 52}).windowCount, 3);
      expect(hrv({...s, back(5): 52}).z, isNotNull);
    });

    test('MAD unter der Grenze: kein z (HRV 0,02 auf ln)', () {
      final tiny = hrv(series(alternating(50, 50.4), 60));
      expect(tiny.z, isNull);
      expect(tiny.reason, NoDeviationReason.madTooSmall);
      expect(hrv(series(List.filled(28, 50), 60)).z, isNull);
      // ln(53) - ln(50) = 0,058, halbe Spanne 0,029 > 0,02.
      expect(hrv(series(alternating(50, 53), 60)).z, isNotNull);
    });

    test(
      'Ruhepuls-MAD: Health Connect 1 bpm, Kamera 0,5 bpm (PAR-162, 162K)',
      () {
        final s = series(alternating(60, 61), 58); // MAD 0,5
        expect(rhr(s).z, isNull);
        expect(rhr(s).reason, NoDeviationReason.madTooSmall);
        expect(rhr(s, camera: true).z, isNotNull);
        // MAD 0,2: auch die Kamera sperrt.
        expect(rhr(series(alternating(60, 60.4), 58), camera: true).z, isNull);
      },
    );

    test('Hinweis wenige Messungen nur bei der Kamera, unter 5 in 7 Tagen', () {
      Map<DateTime, double> withWindow(int k) => {
        for (var i = 8; i <= 28; i++) back(i): 50.0 + (i % 4) * 2,
        for (var i = 1; i < k; i++) back(i): 51 + i.toDouble(),
        today: 55,
      };
      expect(hrv(withWindow(3), camera: true).fewMeasurements, isTrue);
      expect(hrv(withWindow(4), camera: true).fewMeasurements, isTrue);
      expect(hrv(withWindow(5), camera: true).fewMeasurements, isFalse);
      expect(hrv(withWindow(7), camera: true).fewMeasurements, isFalse);
      expect(hrv(withWindow(3)).fewMeasurements, isFalse);
      // Der Hinweis hindert das z nicht.
      expect(hrv(withWindow(3), camera: true).z, isNotNull);
    });

    test('toString enthält keine Werte', () {
      final r = hrv(series(alternating(50, 53), 61.37));
      expect(r.toString(), isNot(contains('61')));
      expect(r.toString(), isNot(contains(r.z!.toString())));
    });

    test('byDay trägt die Tageswerte der Reihe (Verlauf, Lücken bleiben)', () {
      final s = series(alternating(50, 53), 61);
      s.remove(back(5));
      final ok = hrv(s);
      expect(ok.byDay, s);
      expect(ok.byDay.containsKey(back(5)), isFalse);
      // Auch ohne z (heute fehlt): die Werte sind da.
      final none = hrv(series(alternating(50, 53), null));
      expect(none.hasZ, isFalse);
      expect(none.byDay.length, 28);
      expect(none.byDay.containsKey(today), isFalse);
    });

    test(
      'sourceSpanDays kommt aus der Reihe: erster Wert vor 20 Tagen = 20',
      () {
        final r = hrv(series(alternating(50, 53, 20), 61));
        expect(r.hasZ, isTrue);
        expect(r.sourceSpanDays, 20);
      },
    );

    test('sourceSpanDays: erster Wert vor 28 und vor 16 Tagen (PAR-150)', () {
      expect(hrv(series(alternating(50, 53), 61)).sourceSpanDays, 28);
      expect(hrv(series(alternating(50, 53, 16), 61)).sourceSpanDays, 16);
    });
  });
}
