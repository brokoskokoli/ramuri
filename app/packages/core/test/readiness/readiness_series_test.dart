import 'package:core/core.dart';
import 'package:test/test.dart';

import 'readiness_helpers.dart';

void main() {
  group('Health Connect je Quell-App (PAR-189, FR-0115)', () {
    test('Ruhepuls: eine Quelle liefert z mit ihren eigenen Werten', () {
      final r = hcRhr(rhrSamples('app.a', wave(55)));
      expect(r.origin, 'app.a');
      expect(r.source, ReadinessSource.healthConnect);
      expect(r.z, isNotNull);
      expect(r.referenceCount, 28);
    });

    test(
      'Quellwechsel ohne Mischen: längste Reihe zählt, andere gehen nicht ein',
      () {
        final a = rhrSamples('app.a', wave(55, from: 0)); // 29 Tage
        final b = rhrSamples(
          'app.b',
          wave(80, from: 12),
        ); // 17 Tage, andere Lage
        final both = hcRhr([...a, ...b]);
        final onlyA = hcRhr(a);
        expect(both.origin, 'app.a');
        expect(both.z, onlyA.z);
        expect(both.referenceCount, onlyA.referenceCount);
      },
    );

    test(
      'längere Quelle ohne Wert heute: kein z, kein Ausweichen auf die kürzere',
      () {
        final longNoToday = rhrSamples(
          'app.a',
          wave(55, to: 28),
        ); // 28 Tage, heute fehlt
        final shortToday = rhrSamples(
          'app.b',
          wave(55, from: 20),
        ); // 9 Tage mit heute
        final r = hcRhr([...longNoToday, ...shortToday]);
        expect(r.origin, 'app.a');
        expect(r.z, isNull);
        expect(r.reason, NoDeviationReason.noValueToday);
      },
    );

    test(
      'Ruhepuls: Werte für Tatsachen (7-Tage-Mittel, Median, heute), ganze bpm',
      () {
        final r = hcRhr(rhrSamples('app.a', wave(55)));
        final v = [for (var i = 0; i < 29; i++) 55 + (i % 5) * 2.0];
        final win = v.sublist(22);
        final ref = v.sublist(0, 28)..sort();
        expect(r.todayValue, v[28]);
        expect(r.windowMean, (win.reduce((a, b) => a + b) / 7).roundToDouble());
        expect(r.referenceMedian, ((ref[13] + ref[14]) / 2).roundToDouble());
        expect(r.todayIsFallback, isFalse);
      },
    );

    test(
      'HRV: Ersatzwert aus 60 min nach dem Schlaf markiert den Tag (PAR-160)',
      () {
        final samples = <HealthSample>[];
        final sessions = <SleepSession>[];
        for (var i = 1; i < 29; i++) {
          sessions.add(sleep('app.a', i));
          // heute: Wert erst nach Schlafende (Ersatzfenster), sonst im Schlaf
          samples.add(
            i == 28
                ? HealthSample(
                    time: at(i, 6).add(const Duration(minutes: 30)),
                    value: 44,
                    origin: 'app.a',
                  )
                : hrvSample('app.a', i, 40 + (i % 6) * 3),
          );
        }
        final r = healthConnectHrvDeviation(
          processing: p,
          samples: samples,
          sessions: sessions,
          days: days,
        );
        expect(r.z, isNotNull);
        expect(r.todayIsFallback, isTrue);
        expect(r.todayValue, 44);
      },
    );

    test('keine Quelle: kein z', () {
      expect(hcRhr(const []).reason, NoDeviationReason.noSeries);
    });

    test('HRV aus der Hauptschlafphase je Quelle, z auf ln', () {
      final samples = <HealthSample>[];
      final sessions = <SleepSession>[];
      for (var i = 1; i < 29; i++) {
        sessions.add(sleep('app.a', i));
        samples.add(hrvSample('app.a', i, 40 + (i % 6) * 3));
        samples.add(hrvSample('app.b', i, 90 + (i % 3))); // andere Quelle
      }
      final r = healthConnectHrvDeviation(
        processing: p,
        samples: samples,
        sessions: sessions,
        days: days,
      );
      expect(r.z, isNotNull);
      expect(r.origin, isNotNull);
      final r2 = healthConnectHrvDeviation(
        processing: p,
        samples: [
          for (final s in samples)
            if (s.origin == r.origin) s,
        ],
        sessions: sessions,
        days: days,
      );
      expect(r2.z, r.z);
    });
  });

  group('Kamera je Haltung und Gerät (PAR-160K bis PAR-162K)', () {
    List<MorningMeasurement> lying({
      int from = 0,
      int to = 29,
      String model = 'M1',
    }) => [
      for (var i = from; i < to; i++)
        morning(
          dayIdx: i,
          hr: 55 + (i % 5) * 2,
          rmssd: 40 + (i % 6) * 3,
          model: model,
        ),
    ];

    DeviationResult pick(
      List<DeviationResult> r,
      ReadinessFactor f, {
      RestingPosture posture = RestingPosture.lying,
      String model = 'M1',
    }) => r.singleWhere(
      (x) =>
          x.factor == f &&
          x.cameraSeries!.posture == posture &&
          x.cameraSeries!.model == model,
    );

    test('liegende Reihe liefert z für Ruhepuls und HRV', () {
      final r = cameraDeviations(lying(), today: todayKey);
      expect(pick(r, ReadinessFactor.hrv).z, isNotNull);
      expect(pick(r, ReadinessFactor.restingHeartRate).z, isNotNull);
      expect(r.every((x) => x.source == ReadinessSource.camera), isTrue);
    });

    test('Haltungen und Geräte bleiben getrennt, ohne Mischen', () {
      final base = lying();
      final noise = [
        for (var i = 0; i < 29; i++)
          morning(
            dayIdx: i,
            hr: 90 + (i % 3).toDouble(),
            rmssd: 150 - (i % 4).toDouble(),
            posture: RestingPosture.sitting,
          ),
        for (var i = 0; i < 29; i++)
          morning(dayIdx: i, hr: 100 + (i % 2).toDouble(), model: 'M2'),
      ];
      final alone = cameraDeviations(base, today: todayKey);
      final mixed = cameraDeviations([...base, ...noise], today: todayKey);
      for (final f in ReadinessFactor.values) {
        expect(pick(mixed, f).z, pick(alone, f).z);
      }
      expect(mixed.length, 6); // 3 Reihen x 2 Faktoren
    });

    test('außerhalb des Morgenfensters zählt nicht', () {
      final all = [
        for (var i = 0; i < 29; i++)
          morning(dayIdx: i, hr: 55 + (i % 5) * 2, outside: i == 28),
      ];
      final r = cameraDeviations(all, today: todayKey);
      expect(
        pick(r, ReadinessFactor.restingHeartRate).reason,
        NoDeviationReason.noValueToday,
      );
    });

    test('RMSSD nur bei Qualität gut und Zeitrauschen unter der Grenze', () {
      List<MorningMeasurement> mk({
        PpgQuality q = PpgQuality.good,
        double? noise = 10,
      }) => [
        for (var i = 0; i < 29; i++)
          morning(
            dayIdx: i,
            hr: 55 + (i % 5) * 2,
            rmssd: 40 + (i % 6) * 3,
            quality: i == 28 ? q : PpgQuality.good,
            noise: i == 28 ? noise : 10,
          ),
      ];
      DeviationResult hrvOf(List<MorningMeasurement> m) =>
          pick(cameraDeviations(m, today: todayKey), ReadinessFactor.hrv);
      expect(hrvOf(mk()).z, isNotNull);
      expect(hrvOf(mk(noise: morningRmssdTimingNoiseLimitMs)).z, isNotNull);
      expect(hrvOf(mk(noise: morningRmssdTimingNoiseLimitMs + 0.1)).z, isNull);
      expect(hrvOf(mk(noise: null)).z, isNull);
      expect(hrvOf(mk(q: PpgQuality.limited)).z, isNull);
      // Der Ruhepuls zählt bei „eingeschränkt“ weiter.
      expect(
        pick(
          cameraDeviations(mk(q: PpgQuality.limited), today: todayKey),
          ReadinessFactor.restingHeartRate,
        ).z,
        isNotNull,
      );
    });

    test(
      'zwei Messungen derselben Reihe am selben Tag: nur die erste zählt (K65)',
      () {
        final base = lying();
        final first = cameraDeviations(base, today: todayKey);
        // Zweite Messung heute, andere Werte, später am Morgen.
        final second = morning(dayIdx: 28, hr: 90, rmssd: 150, hour: 8);
        final both = cameraDeviations([...base, second], today: todayKey);
        for (final f in ReadinessFactor.values) {
          expect(pick(both, f).z, pick(first, f).z);
          expect(pick(both, f).todayValue, pick(first, f).todayValue);
        }
        // Erste eingeschränkt, zweite gut: RMSSD heute fehlt, Ruhepuls aus der ersten.
        final limited = [
          for (final m in base)
            if (m.measuredAt != DateTime(2026, 11, 14, 7).toUtc()) m,
          morning(dayIdx: 28, hr: 61, quality: PpgQuality.limited),
          morning(dayIdx: 28, hr: 90, rmssd: 150, hour: 8),
        ];
        final r = cameraDeviations(limited, today: todayKey);
        expect(
          pick(r, ReadinessFactor.hrv).reason,
          NoDeviationReason.noValueToday,
        );
        expect(pick(r, ReadinessFactor.restingHeartRate).todayValue, 61);
      },
    );

    test('„vor der Validierung gemessen“ ändert nichts (K62 Punkt 6)', () {
      List<MorningMeasurement> mk(bool before) => [
        for (var i = 0; i < 29; i++)
          morning(dayIdx: i, hr: 55 + (i % 5) * 2, before: before),
      ];
      final a = cameraDeviations(mk(false), today: todayKey);
      final b = cameraDeviations(mk(true), today: todayKey);
      expect([for (final x in a) x.z], [for (final x in b) x.z]);
    });

    test('Hinweis wenige Messungen: 4 Werte in 7 Tagen', () {
      final all = [
        for (var i = 0; i < 29; i++)
          if (i < 22 || i == 24 || i == 26 || i == 27 || i == 28)
            morning(dayIdx: i, hr: 55 + (i % 5) * 2),
      ];
      final r = pick(
        cameraDeviations(all, today: todayKey),
        ReadinessFactor.restingHeartRate,
      );
      expect(r.windowCount, 4);
      expect(r.fewMeasurements, isTrue);
      expect(r.z, isNotNull);
    });

    test('Referenzwert läuft nicht aus anderem Tag-Schlüssel (Ortstag)', () {
      // Sanity: der Schlüssel entspricht dem Ortstag der Messung.
      final m = morning(dayIdx: 28);
      expect(morningLocalDay(m), todayKey);
    });
  });
}
