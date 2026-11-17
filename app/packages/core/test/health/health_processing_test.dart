import 'package:core/core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 11, 14, 8);
const hp = HealthProcessing();

/// Hauptschlafphase zu [now] mit Tagesbeginn 14.11. 00:00 UTC (unabhängig
/// von der Zeitzone des Systems).
SleepSession? mainAtNow(List<SleepSession> s) =>
    hp.mainSleep(s, now, dayStart: DateTime.utc(2026, 11, 14));

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
      final m = mainAtNow([
        sess('a', 9, 2), // 7 h
        sess('a', 5, 4), // Nickerchen
        sess('a', 8, 3), // 5 h
      ]);
      expect(m!.duration, const Duration(hours: 7));
    });
    test('Grenze 3 h einschließlich, 2:59 nicht', () {
      expect(mainAtNow([sess('a', 5, 2)]), isNotNull);
      expect(
        mainAtNow([
          SleepSession(
            origin: 'a',
            start: h(5),
            end: h(2).subtract(const Duration(minutes: 1)),
          ),
        ]),
        isNull,
      );
    });
    test('gilt bis Mitternacht des Endtags, nicht am Folgetag (feste Uhr)', () {
      // Ortszeit: Ende 07:00 am 14.11., Beginn 23:00 am Vortag.
      final night = SleepSession(
        origin: 'a',
        start: DateTime(2026, 11, 13, 23).toUtc(),
        end: DateTime(2026, 11, 14, 7).toUtc(),
      );
      DateTime local(int d, int h, [int m = 0]) =>
          DateTime(2026, 11, d, h, m).toUtc();
      expect(hp.mainSleep([night], local(14, 7)), isNotNull); // Ende = jetzt
      expect(hp.mainSleep([night], local(14, 12)), isNotNull);
      // 23:59 liegt 16 h 59 min nach dem Ende und zählt noch.
      expect(hp.mainSleep([night], local(14, 23, 59)), isNotNull);
      expect(hp.mainSleep([night], local(15, 0)), isNull);
      expect(hp.mainSleep([night], local(15, 6)), isNull);
      // Vor dem Ende (Zukunft) zählt sie nicht.
      expect(hp.mainSleep([night], local(14, 6, 59)), isNull);
    });
    test('Mitternacht einschließlich: Ende 00:00 zählt für diesen Tag', () {
      final s = SleepSession(
        origin: 'a',
        start: DateTime(2026, 11, 13, 20).toUtc(),
        end: DateTime(2026, 11, 14).toUtc(),
      );
      final at = DateTime(2026, 11, 14, 10).toUtc();
      expect(hp.mainSleep([s], at), isNotNull);
      final before = SleepSession(
        origin: 'a',
        start: s.start,
        end: s.end.subtract(const Duration(minutes: 1)),
      );
      expect(hp.mainSleep([before], at), isNull);
    });
    test('Ende am Vortag zählt nicht, auch wenn weniger als 16 h her', () {
      // Ende 23:30 am Vortag, jetzt 08:00: 8,5 h her, aber anderer Ortstag.
      final s = SleepSession(
        origin: 'a',
        start: DateTime(2026, 11, 13, 19).toUtc(),
        end: DateTime(2026, 11, 13, 23, 30).toUtc(),
      );
      expect(hp.mainSleep([s], DateTime(2026, 11, 14, 8).toUtc()), isNull);
    });
    test('Zeitzone: Mitternacht ist lokal (Versatz +14 h und −10 h)', () {
      // Gleiche UTC-Zeitpunkte, verschiedene Ortstage.
      final s = SleepSession(
        origin: 'a',
        start: DateTime.utc(2026, 11, 13, 2),
        end: DateTime.utc(2026, 11, 13, 9, 30),
      );
      final now = DateTime.utc(2026, 11, 13, 20);
      // UTC+14: Ende 23:30 am 13.11., jetzt 10:00 am 14.11. -> Vortag.
      final plus14 = DateTime.utc(
        2026,
        11,
        14,
      ).subtract(const Duration(hours: 14));
      expect(hp.mainSleep([s], now, dayStart: plus14), isNull);
      // UTC−10: Ende 23:30 am 12.11., jetzt 10:00 am 13.11.; Mitternacht
      // des 13.11. Ortszeit ist 13.11. 10:00 UTC -> Vortag.
      final minus10 = DateTime.utc(2026, 11, 13, 10);
      expect(hp.mainSleep([s], now, dayStart: minus10), isNull);
      // UTC+0: gleicher Tag.
      expect(
        hp.mainSleep([s], now, dayStart: DateTime.utc(2026, 11, 13)),
        isNotNull,
      );
      // UTC+5: Ende 14:30 am 13.11., Mitternacht = 12.11. 19:00 UTC.
      expect(
        hp.mainSleep([s], now, dayStart: DateTime.utc(2026, 11, 12, 19)),
        isNotNull,
      );
    });
    test(
      'Sommerzeitwechsel: Mitternacht vor der Umstellung (Versatz +1 h)',
      () {
        // Europa/Berlin am 29.03.2026: um 01:00 UTC von +1 h auf +2 h. Der
        // Ortstag beginnt 28.03. 23:00 UTC (noch +1 h), nicht 22:00 UTC.
        final dayStart = DateTime.utc(2026, 3, 28, 23);
        final now = DateTime.utc(2026, 3, 29, 20); // 22:00 Ortszeit (+2 h)
        SleepSession endingAt(DateTime end) => SleepSession(
          origin: 'a',
          start: end.subtract(const Duration(hours: 6)),
          end: end,
        );
        // 22:30 UTC = 23:30 Ortszeit am 28.03. -> Vortag.
        expect(
          hp.mainSleep(
            [endingAt(DateTime.utc(2026, 3, 28, 22, 30))],
            now,
            dayStart: dayStart,
          ),
          isNull,
        );
        // 23:30 UTC = 00:30 Ortszeit am 29.03. -> zählt bis Mitternacht.
        expect(
          hp.mainSleep(
            [endingAt(DateTime.utc(2026, 3, 28, 23, 30))],
            now,
            dayStart: dayStart,
          ),
          isNotNull,
        );
        // Der Tag hat 23 h: 21:59 UTC = 23:59 Ortszeit zählt noch.
        expect(
          hp.mainSleep(
            [endingAt(DateTime.utc(2026, 3, 29, 5))],
            DateTime.utc(2026, 3, 29, 21, 59),
            dayStart: dayStart,
          ),
          isNotNull,
        );
      },
    );
    test('mehrere Quellen: mit Phasen vor längerer ohne Phasen', () {
      final withStages = sess('b', 8, 2, [
        stage(SleepStageKind.light, 8, 2),
      ]); // 6 h
      final longer = sess('a', 10, 1); // 9 h, ohne Phasen
      expect(mainAtNow([longer, withStages])!.origin, 'b');
    });
    test('mehrere Quellen ohne Phasen: die längste', () {
      expect(mainAtNow([sess('a', 8, 2), sess('b', 9, 2)])!.origin, 'b');
    });
    test('keine Sitzung', () => expect(mainAtNow([]), isNull));
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
      expect(r.method.methodVersion, 2); // NFR-0001, PAR-164 bis Mitternacht
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
      expect(r['a']!.method.methodVersion, 2);
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
      expect(r['b']!.method.methodVersion, 1);
    });
    test('nur ungültige Werte: keine Quelle; Zeitraum halboffen', () {
      expect(hp.restingHeartRateDaily([smp('a', 10, 20)], from, to), isEmpty);
      expect(hp.restingHeartRateDaily([smp('a', 1440, 55)], from, to), isEmpty);
      expect(hp.restingHeartRateDaily([smp('a', 0, 55)], from, to), isNotEmpty);
    });
  });

  group('Quellenauswahl PAR-189', () {
    Map<String, HealthDailyValue> day(Map<String, int> samplesByOrigin) {
      final main = SleepSession(
        origin: 's',
        start: DateTime.utc(2026, 11, 14),
        end: DateTime.utc(2026, 11, 14, 6),
      );
      return hp.hrvDaily([
        for (final e in samplesByOrigin.entries)
          for (var i = 0; i < e.value; i++) smp(e.key, 10.0 + i, 50),
      ], main);
    }

    test(
      'App mit vielen Messungen in einer Nacht verliert gegen mehr Nächte',
      () {
        final days = [
          day({'a': 50, 'b': 1}),
          day({'b': 1}),
          day({'b': 1}),
        ];
        expect(hp.selectSource(days), 'b');
      },
    );
    test('Zählung: genau die Tage, nicht mehr', () {
      final days = [
        day({'a': 1, 'b': 1}),
        day({'a': 1}),
        day({'a': 1}),
        day({'b': 1}),
      ];
      expect(hp.selectSource(days), 'a');
      // b hat 2, a 3; ein Tag mehr für b ergibt Gleichstand -> Name a,
      // zwei Tage mehr -> b.
      expect(
        hp.selectSource([
          ...days,
          day({'b': 1}),
        ]),
        'a',
      );
      expect(
        hp.selectSource([
          ...days,
          day({'b': 1}),
          day({'b': 1}),
        ]),
        'b',
      );
    });
    test('Gleichstand: kleinerer Name; leer: null', () {
      expect(
        hp.selectSource([
          day({'b': 1, 'a': 1}),
        ]),
        'a',
      );
      expect(hp.selectSource([]), isNull);
      expect(hp.selectSource([const {}]), isNull);
    });
    test('Ruhepuls-Tageswerte gehen genauso', () {
      final from = DateTime.utc(2026, 11, 14);
      final r = hp.restingHeartRateDaily(
        [smp('a', 10, 150), smp('b', 10, 60)],
        from,
        from.add(const Duration(days: 1)),
      );
      expect(hp.selectSource([r]), 'b');
    });
  });
}
