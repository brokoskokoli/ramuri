// Tageszuordnung von Ruhepuls, HRV und Hauptschlaf (PAR-164) an den Grenzen
// des Ortstags. Läuft in jeder Zeitzone; das Gate führt die Datei zusätzlich
// unter America/Los_Angeles, Pacific/Auckland und UTC aus.
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'time_zone_helpers.dart';

const _p = HealthProcessing();
const _ms = Duration(milliseconds: 1);

HealthSample _s(DateTime t, double v, {String o = 'a'}) =>
    HealthSample(time: t, value: v, origin: o);

SleepSession _sleep(DateTime start, DateTime end, {String o = 'a'}) =>
    SleepSession(origin: o, start: start, end: end);

void main() {
  group('Zeitzone des Prozesses', () {
    test('TZ wirkt: Versätze der Zone wie erwartet', () {
      final tz = processTz;
      final (w, s) = winterSummerOffset(2026);
      final want = knownZones[tz];
      if (want != null) {
        expect((w, s), want, reason: 'TZ=$tz wirkt nicht (Zonendaten?)');
      } else {
        // Andere Zone (oder TZ nicht gesetzt): nur die Selbstkonsistenz.
        expect(zoneHasDst(2026), w != s);
      }
    });

    test('Ortstage: lückenlos, lokale Mitternacht, 23/24/25 h', () {
      final days = localDaysOfYear(2026);
      expect(days, hasLength(365));
      for (var i = 0; i < days.length; i++) {
        final d = days[i];
        final l = d.start.toLocal();
        expect((l.hour, l.minute), (0, 0), reason: '$l');
        if (i > 0) expect(d.start, days[i - 1].end);
        expect(localDayStart(d.start), d.start);
        expect(localDayStart(d.end.subtract(_ms)), d.start);
      }
      final lengths = [
        for (final d in dstDays(2026)) d.end.difference(d.start),
      ];
      // Mit Sommerzeit genau ein kurzer und ein langer Tag, ohne keiner.
      expect(
        lengths..sort(),
        zoneHasDst(2026)
            ? const [Duration(hours: 23), Duration(hours: 25)]
            : isEmpty,
      );
    });
  });

  for (final c in [...localDayCases(2026), ...fixedDstCases]) {
    group(c.label, () {
      final days = [c.prev, c.day, c.next];

      test(
        'Ruhepuls: 00:00 gehört zum Tag, Mitternacht danach zum Folgetag',
        () {
          final v = restingHeartRateDayValues(_p, [
            _s(c.prev.end.subtract(_ms), 70),
            _s(c.day.start, 50),
            _s(c.day.end.subtract(_ms), 52),
            _s(c.day.end, 80),
          ], days);
          expect(v[0]['a']!.value, 70);
          expect(v[1]['a']!.value, 51); // Median aus 50 und 52
          expect(v[1]['a']!.sampleCount, 2);
          expect(v[2]['a']!.value, 80);
        },
      );

      test('HRV: Schlaf über Mitternacht zählt für den Endtag', () {
        final night = _sleep(
          c.day.start.subtract(const Duration(hours: 2)),
          c.day.start.add(const Duration(hours: 6)),
        );
        final samples = [
          _s(c.day.start.subtract(const Duration(hours: 1)), 40),
          _s(c.day.start.add(const Duration(hours: 3)), 44),
        ];
        final v = hrvDayValues(_p, samples, [night], days);
        expect(v[0], isEmpty);
        expect(v[1]['a']!.value, 42);
        expect(v[1]['a']!.isFallback, isFalse);
        expect(v[2], isEmpty);
      });

      test(
        'Hauptschlaf: Ende um 00:00 zählt für den Tag, nicht den Vortag',
        () {
          final s = _sleep(
            c.day.start.subtract(const Duration(hours: 8)),
            c.day.start,
          );
          final samples = [
            _s(c.day.start.subtract(const Duration(hours: 4)), 45),
          ];
          final v = hrvDayValues(_p, samples, [s], days);
          expect(v[0], isEmpty);
          expect(v[1]['a']!.value, 45);
          expect(v[2], isEmpty);
        },
      );

      test('Hauptschlaf: Ende kurz vor Mitternacht gilt bis Mitternacht '
          '(PAR-164), Ende um Mitternacht erst am Folgetag', () {
        final from = c.day.end.subtract(const Duration(hours: 4));
        final samples = [_s(c.day.end.subtract(const Duration(hours: 2)), 46)];
        final late = _sleep(from, c.day.end.subtract(_ms));
        final v = hrvDayValues(_p, samples, [late], days);
        expect(v[1]['a']!.value, 46);
        expect(v[2], isEmpty);
        // Dieselbe Nacht, Ende genau um Mitternacht: Folgetag.
        final atMidnight = _sleep(from, c.day.end);
        final w = hrvDayValues(_p, samples, [atMidnight], days);
        expect(w[1], isEmpty);
        expect(w[2]['a']!.value, 46);
      });

      test('Hauptschlaf: nur Sitzungen ab Beginn des Ortstags, auch an Tagen '
          'mit Zeitumstellung', () {
        final before = _sleep(
          c.day.start.subtract(const Duration(hours: 8)),
          c.day.start.subtract(_ms),
          o: 'a',
        );
        final at = _sleep(
          c.day.start.subtract(const Duration(hours: 4)),
          c.day.start,
          o: 'b',
        );
        final now = c.day.end.subtract(_ms);
        expect(
          _p.mainSleep([before, at], now, dayStart: c.day.start)?.origin,
          'b',
        );
        // Eine Sitzung vom Vortag ist am letzten Moment des Tages verfallen.
        expect(_p.mainSleep([before], now, dayStart: c.day.start), isNull);
      });
    });
  }

  // Ohne dayStart gilt der Ortstag der Zeitzone des Prozesses (localDayStart).
  for (final c in localDayCases(2026)) {
    test('Hauptschlaf ohne dayStart: Ortstag der Zone (${c.label})', () {
      final before = _sleep(
        c.day.start.subtract(const Duration(hours: 9)),
        c.day.start.subtract(_ms),
      );
      final at = _sleep(
        c.day.start.subtract(const Duration(hours: 4)),
        c.day.start,
      );
      final last = c.day.end.subtract(_ms);
      expect(_p.mainSleep([before, at], last), same(at));
      expect(_p.mainSleep([before], last), isNull);
      expect(_p.mainSleep([before], c.day.start.subtract(_ms)), same(before));
      expect(_p.mainSleep([at], c.day.end), isNull);
    });
  }
}
