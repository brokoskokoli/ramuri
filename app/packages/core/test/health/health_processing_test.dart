import 'package:core/core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 11, 14, 8);
const hp = HealthProcessing();

DateTime h(double hoursAgo) =>
    now.subtract(Duration(minutes: (hoursAgo * 60).round()));

SleepSession sess(
  String o,
  double startAgo,
  double endAgo, [
  List<SleepStage> st = const [],
]) => SleepSession(origin: o, start: h(startAgo), end: h(endAgo), stages: st);

SleepStage stage(SleepStageKind k, double startAgo, double endAgo) =>
    SleepStage(kind: k, start: h(startAgo), end: h(endAgo));

HealthSample smp(String o, double minutesAfterEpoch, double v) => HealthSample(
  time: DateTime.utc(
    2026,
    11,
    14,
  ).add(Duration(minutes: minutesAfterEpoch.round())),
  value: v,
  origin: o,
);

void main() {
  group('Hauptschlafphase PAR-164', () {
    test('längste Sitzung einer Quelle, Nickerchen zählt nicht', () {
      final m = hp.mainSleep([
        sess('a', 9, 2), // 7 h
        sess('a', 5, 4), // Nickerchen
        sess('a', 8, 3), // 5 h
      ], now);
      expect(m!.duration, const Duration(hours: 7));
    });
    test('Grenze 3 h einschließlich, 2:59 nicht', () {
      expect(hp.mainSleep([sess('a', 5, 2)], now), isNotNull);
      expect(
        hp.mainSleep([
          SleepSession(
            origin: 'a',
            start: h(5),
            end: h(2).subtract(const Duration(minutes: 1)),
          ),
        ], now),
        isNull,
      );
    });
    test('Ende 16 h her einschließlich, 16 h 1 min nicht; Zukunft nicht', () {
      expect(hp.mainSleep([sess('a', 24, 16)], now), isNotNull);
      expect(
        hp.mainSleep([
          SleepSession(
            origin: 'a',
            start: h(24),
            end: h(16).subtract(const Duration(minutes: 1)),
          ),
        ], now),
        isNull,
      );
      expect(hp.mainSleep([sess('a', 3, -1)], now), isNull);
    });
    test('mehrere Quellen: mit Phasen vor längerer ohne Phasen', () {
      final withStages = sess('b', 8, 2, [
        stage(SleepStageKind.light, 8, 2),
      ]); // 6 h
      final longer = sess('a', 10, 1); // 9 h, ohne Phasen
      expect(hp.mainSleep([longer, withStages], now)!.origin, 'b');
    });
    test('mehrere Quellen ohne Phasen: die längste', () {
      expect(
        hp.mainSleep([sess('a', 8, 2), sess('b', 9, 2)], now)!.origin,
        'b',
      );
    });
    test('keine Sitzung', () => expect(hp.mainSleep([], now), isNull));
  });

  group('Schlafzeit PAR-166', () {
    test('Summe der Schlafphasen, Wach zählt nicht, Effizienz', () {
      // 8 h Sitzung: 6 h Schlaf, 2 h wach, volle Abdeckung -> 75 %
      final s = sess('a', 10, 2, [
        stage(SleepStageKind.light, 10, 7),
        stage(SleepStageKind.awake, 7, 5),
        stage(SleepStageKind.deep, 5, 3),
        stage(SleepStageKind.rem, 3, 2),
      ]);
      final r = hp.sleepSummary(s);
      expect(r.sleepDuration, const Duration(hours: 6));
      expect(r.efficiencyPercent, closeTo(75, 1e-9));
      expect(r.isEstimate, isFalse);
      expect(r.method.method, 'sleep-summary');
      expect(r.method.parameterVersion, 4);
    });
    test('ohne Phasen: Sitzungsdauer, Schätzung, keine Effizienz', () {
      final r = hp.sleepSummary(sess('a', 9, 2));
      expect(r.sleepDuration, const Duration(hours: 7));
      expect(r.isEstimate, isTrue);
      expect(r.efficiencyPercent, isNull);
    });
    test('Abdeckung 89 % Schätzung, 90 % nicht', () {
      // 10 h Sitzung: 8,9 h bzw. 9,0 h Phasen
      SleepSession cov(double hours) =>
          sess('a', 12, 2, [stage(SleepStageKind.light, 12, 12 - hours)]);
      expect(hp.sleepSummary(cov(8.9)).isEstimate, isTrue);
      final r = hp.sleepSummary(cov(9));
      expect(r.isEstimate, isFalse);
      expect(r.efficiencyPercent, closeTo(90, 1e-9));
    });
    test('Phasen außerhalb der Sitzung werden zugeschnitten', () {
      final s = sess('a', 8, 2, [stage(SleepStageKind.light, 20, 0)]);
      expect(hp.sleepSummary(s).efficiencyPercent, closeTo(100, 1e-9));
    });
    test('Teilskala: Knicke und Kappung', () {
      expect(hp.efficiencyScore(95), 80);
      expect(hp.efficiencyScore(100), 80);
      expect(hp.efficiencyScore(90), 75);
      expect(hp.efficiencyScore(85), 70);
      expect(hp.efficiencyScore(80), 45);
      expect(hp.efficiencyScore(60), 0);
    });
  });

  group('HRV PAR-160', () {
    // Hauptschlafphase 00:00 bis 06:00 am 2026-11-14 (Minuten ab 00:00).
    final main = SleepSession(
      origin: 's',
      start: DateTime.utc(2026, 11, 14),
      end: DateTime.utc(2026, 11, 14, 6),
    );
    test('Median je Quell-App, getrennte Reihen', () {
      final r = hp.hrvDaily([
        smp('a', 60, 30),
        smp('a', 120, 50),
        smp('a', 180, 40),
        smp('b', 60, 80),
        smp('b', 120, 100),
      ], main);
      expect(r['a']!.value, 40);
      expect(r['b']!.value, 90);
      expect(r['a']!.isFallback, isFalse);
      expect(r['a']!.method.method, 'hrv-rmssd-night');
    });
    test(
      'Eintrag außerhalb der Schlafphase zählt nicht, solange es innen gibt',
      () {
        final r = hp.hrvDaily([smp('a', 60, 30), smp('a', 400, 150)], main);
        expect(r['a']!.value, 30);
        expect(r['a']!.sampleCount, 1);
      },
    );
    test('Rückfall: nur Einträge der 60 min danach, markiert', () {
      final r = hp.hrvDaily([smp('a', 380, 45), smp('a', 500, 99)], main);
      expect(r['a']!.value, 45);
      expect(r['a']!.isFallback, isTrue);
    });
    test(
      'Rückfallgrenze: 60 min einschließlich, 61 nicht; Ende gehört zur Phase',
      () {
        expect(hp.hrvDaily([smp('a', 420, 45)], main)['a']!.isFallback, isTrue);
        expect(hp.hrvDaily([smp('a', 421, 45)], main), isEmpty);
        final atEnd = hp.hrvDaily([smp('a', 360, 45)], main)['a']!;
        expect(atEnd.isFallback, isFalse);
      },
    );
    test('vor dem Beginn kein Eintrag', () {
      expect(hp.hrvDaily([smp('a', -10, 45)], main), isEmpty);
    });
    test('Wertebereich 1–200 einschließlich', () {
      final r = hp.hrvDaily([
        smp('a', 10, 0.9),
        smp('a', 20, 200.1),
        smp('a', 30, 1),
        smp('a', 40, 200),
      ], main);
      expect(r['a']!.sampleCount, 2);
      expect(r['a']!.value, 100.5);
    });
    test('ungültiger Eintrag im Schlaf zählt nicht, Rückfall greift', () {
      final r = hp.hrvDaily([smp('a', 10, 500), smp('a', 380, 40)], main);
      expect(r['a']!.isFallback, isTrue);
    });
    test('ohne Schlafsitzung kein Wert', () {
      expect(hp.hrvDaily([smp('a', 10, 40)], null), isEmpty);
    });
  });

  group('Ruhepuls PAR-017', () {
    final from = DateTime.utc(2026, 11, 14);
    final to = DateTime.utc(2026, 11, 15);
    test('Median je Quelle, Grenzen 30 und 120 gültig', () {
      final r = hp.restingHeartRateDaily(
        [
          smp('a', 10, 29.9),
          smp('a', 20, 30),
          smp('a', 30, 120),
          smp('a', 40, 120.1),
          smp('b', 10, 55),
          smp('b', 20, 57),
          smp('b', 30, 56),
        ],
        from,
        to,
      );
      expect(r['a']!.value, 75);
      expect(r['a']!.sampleCount, 2);
      expect(r['b']!.value, 56);
      expect(r['b']!.method.method, 'resting-hr-day');
    });
    test('nur ungültige Werte: keine Quelle; Zeitraum halboffen', () {
      expect(hp.restingHeartRateDaily([smp('a', 10, 20)], from, to), isEmpty);
      expect(hp.restingHeartRateDaily([smp('a', 1440, 55)], from, to), isEmpty);
      expect(hp.restingHeartRateDaily([smp('a', 0, 55)], from, to), isNotEmpty);
    });
  });

  group('Quellenauswahl PAR-189', () {
    test('die mit den meisten gültigen Einträgen, ungültige zählen nicht', () {
      final s = [
        smp('a', 1, 50),
        smp('a', 2, 51),
        smp('b', 1, 50),
        smp('b', 2, 500),
        smp('b', 3, 500),
        smp('b', 4, 500),
      ];
      expect(hp.selectHrvSource(s), 'a');
    });
    test('Gleichstand: kleinerer Name; leer: null', () {
      expect(hp.selectHrvSource([smp('b', 1, 50), smp('a', 1, 50)]), 'a');
      expect(hp.selectHrvSource([]), isNull);
      expect(hp.selectRestingHeartRateSource([smp('a', 1, 10)]), isNull);
    });
    test('Ruhepuls nutzt den Bereich 30–120', () {
      final s = [smp('a', 1, 150), smp('a', 2, 150), smp('b', 1, 60)];
      expect(hp.selectRestingHeartRateSource(s), 'b');
      expect(hp.selectHrvSource(s), 'a');
    });
  });
}
