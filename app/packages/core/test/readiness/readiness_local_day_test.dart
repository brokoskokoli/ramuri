// Ortstag der Readiness (FR-0108, FR-0109): Die Health-Connect-Reihen werden
// nach dem Kalendertag der lokalen Mitternacht geführt, auch an Tagen mit
// Zeitumstellung. Läuft in jeder Zeitzone; das Gate führt die Datei zusätzlich
// unter America/Los_Angeles, Pacific/Auckland und UTC aus.
import 'package:core/core.dart';
import 'package:test/test.dart';

import '../health/time_zone_helpers.dart';

const _p = HealthProcessing();

double _v(int i) => 50 + (i % 5) * 2;

DateTime _key(DayRange d) {
  final l = d.start.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

void main() {
  for (final c in localDayCases(2026)) {
    group('${c.label}:', () {
      final l = c.day.start.toLocal();
      // 28 Tage Referenz plus heute, letzter Tag ist der Ortstag des Falls.
      final days = localDayRanges(DateTime(l.year, l.month, l.day - 28), 29);

      test('Tage enden mit dem Ortstag des Falls', () {
        expect(days.last.start, c.day.start);
        expect(days.last.end, c.day.end);
        expect(_key(days.last), c.key);
        expect(c.key, DateTime.utc(l.year, l.month, l.day));
      });

      test('Ruhepuls: Wert um 00:00 Ortszeit zählt für den Ortstag', () {
        final samples = [
          for (var i = 0; i < days.length; i++)
            HealthSample(time: days[i].start, value: _v(i), origin: 'a'),
          // Letzter Moment vor Beginn des ersten Tages: zählt nicht.
          HealthSample(
            time: days.first.start.subtract(const Duration(milliseconds: 1)),
            value: 99,
            origin: 'a',
          ),
        ];
        final r = healthConnectRestingHrDeviation(
          processing: _p,
          samples: samples,
          days: days,
        );
        expect(r.reason, isNull);
        expect(r.z, isNotNull);
        expect(r.byDay.keys.toList(), [for (final d in days) _key(d)]);
        expect(r.byDay[c.key], _v(28));
        expect(r.byDay.values, isNot(contains(99)));
      });

      test('HRV: Schlaf über Mitternacht zählt für den Ortstag des Endes', () {
        final sessions = [
          for (final d in days)
            SleepSession(
              origin: 'a',
              start: d.start.subtract(const Duration(hours: 2)),
              end: d.start.add(const Duration(hours: 6)),
            ),
        ];
        final samples = [
          for (var i = 0; i < days.length; i++)
            HealthSample(
              time: days[i].start.add(const Duration(hours: 3)),
              value: _v(i) - 10,
              origin: 'a',
            ),
        ];
        final r = healthConnectHrvDeviation(
          processing: _p,
          samples: samples,
          sessions: sessions,
          days: days,
        );
        expect(r.reason, isNull);
        expect(r.byDay.keys.toList(), [for (final d in days) _key(d)]);
        expect(r.byDay[c.key], _v(28) - 10);
      });
    });
  }
}
