import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // 2030-01-02 ist ein Mittwoch; Woche Mo 2029-12-31 .. So 2030-01-06 (KW 1/2030).
  test('acht Wochen, älteste zuerst, letzte ist die Woche von today', () {
    final s = weeklyDistanceSeries('2030-01-02', const []);
    expect(s, hasLength(8));
    expect(s.last.week, StatisticsPeriod.weekOf('2030-01-02'));
    expect(s.first.week.firstDay, '2029-11-12');
    for (var i = 1; i < s.length; i++) {
      expect(s[i].week.previous(), s[i - 1].week);
      expect(
        s[i - 1].week.lastDay!.compareTo(s[i].week.firstDay!),
        lessThan(0),
      );
    }
  });

  test('Wochen ohne Lauf sind 0 km und nicht ausgelassen', () {
    final s = weeklyDistanceSeries('2030-01-02', [
      figures(1, '2029-12-31', km: 5, movingSec: 1800),
    ]);
    expect(s, hasLength(8));
    expect(s.last.meters, 5000);
    for (final w in s.take(7)) {
      expect(w.hasRuns, isFalse);
      expect(w.meters, 0);
      expect(w.isUnavailable, isFalse);
    }
  });

  test('stimmt mit der Wochenstatistik überein, inklusive isPartial', () {
    final runs = [
      figures(1, '2029-12-31', km: 5, movingSec: 1800),
      figures(2, '2030-01-01', movingSec: 900),
      figures(3, '2029-12-20', km: 8, movingSec: 2400),
    ];
    final s = weeklyDistanceSeries('2030-01-06', runs);
    for (final w in s) {
      final expected = computePeriodStatistics(w.week, runs).distanceMeters;
      expect(w.distance.value, expected.value);
      expect(w.distance.isPartial, expected.isPartial);
      expect(w.distance.runsTotal, expected.runsTotal);
    }
    expect(s.last.distance.isPartial, isTrue);
    expect(s.last.meters, 5000);
    expect(s[5].meters, 8000); // Woche 2029-12-17..23
  });

  test('Läufe ohne lesbare Strecke bleiben "nicht verfügbar", nicht 0', () {
    final s = weeklyDistanceSeries('2030-01-02', [
      figures(1, '2029-12-31', movingSec: 1800),
    ]);
    expect(s.last.hasRuns, isTrue);
    expect(s.last.meters, isNull);
    expect(s.last.isUnavailable, isTrue);
    expect(s[6].meters, 0);
  });

  test('Läufe außerhalb der 8 Wochen zählen nicht', () {
    final s = weeklyDistanceSeries('2030-01-02', [
      figures(1, '2029-11-11', km: 9, movingSec: 1800), // Sonntag davor
      figures(2, '2030-01-07', km: 9, movingSec: 1800), // nächste Woche
    ]);
    expect(s.every((w) => w.meters == 0), isTrue);
  });

  test(
    'Montag und Sonntag sind in derselben Woche, Folgemontag in der nächsten',
    () {
      final runs = [
        figures(1, '2029-12-31', km: 1, movingSec: 600),
        figures(2, '2030-01-06', km: 2, movingSec: 600),
        figures(3, '2030-01-07', km: 4, movingSec: 600),
      ];
      final a = weeklyDistanceSeries('2030-01-06', runs);
      expect(a.last.meters, 3000);
      final b = weeklyDistanceSeries('2030-01-07', runs);
      expect(b.last.meters, 4000);
      expect(b[6].meters, 3000);
    },
  );

  test('ISO-Kalenderwoche über den Jahreswechsel', () {
    final s = weeklyDistanceSeries('2030-01-02', const []);
    expect([for (final w in s) w.isoWeek], [46, 47, 48, 49, 50, 51, 52, 1]);
    expect(s.last.isoWeekYear, 2030);
    expect(s[6].isoWeekYear, 2029);
    // 2027-01-01 (Freitag) gehört zu KW 53/2026.
    final t = weeklyDistanceSeries('2027-01-01', const [], weeks: 2);
    expect([for (final w in t) w.isoWeek], [52, 53]);
    expect(t.last.isoWeekYear, 2026);
    expect(t.last.week.firstDay, '2026-12-28');
    // 2020: KW 53; Woche 2021-01-04 ist KW 1.
    final u = weeklyDistanceSeries('2021-01-04', const [], weeks: 2);
    expect([for (final w in u) w.isoWeek], [53, 1]);
    expect([for (final w in u) w.isoWeekYear], [2020, 2021]);
  });

  test('anderer Wochenbeginn wird beachtet', () {
    const p = StatisticsParameters(firstDayOfWeek: DateTime.sunday);
    final s = weeklyDistanceSeries(
      '2030-01-02',
      [figures(1, '2029-12-30', km: 3, movingSec: 600)],
      parameters: p,
      weeks: 2,
    );
    expect(s.last.week.firstDay, '2029-12-30');
    expect(s.last.meters, 3000);
    expect(s.first.meters, 0);
  });

  test('ISO-Woche bei Wochenbeginn Samstag über den Jahreswechsel', () {
    // Woche Sa 2030-12-28 .. Fr 2031-01-03: Mitte Di 31.12., ISO-Donnerstag
    // 2.1.2031 gehört zu KW 1/2031.
    const p = StatisticsParameters(firstDayOfWeek: DateTime.saturday);
    final s = weeklyDistanceSeries(
      '2031-01-02',
      const [],
      weeks: 1,
      parameters: p,
    );
    expect(s.single.week.firstDay, '2030-12-28');
    expect(s.single.isoWeek, 1);
    expect(s.single.isoWeekYear, 2031);
  });

  test('ungültige Eingaben werfen ArgumentError', () {
    expect(
      () => weeklyDistanceSeries('2030-02-30', const []),
      throwsArgumentError,
    );
    expect(
      () => weeklyDistanceSeries('2030-01-02', const [], weeks: 0),
      throwsArgumentError,
    );
  });
}
