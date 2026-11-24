import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // Drei Läufe in der Woche 2029-12-31..2030-01-06, einer davor, einer danach.
  final a = figures(
    1,
    '2029-12-31',
    km: 5,
    movingSec: 1800,
    paceSec: 1790,
    best: 340,
    laps: 5,
    hrAvg: 150,
    hrSec: 100,
    hrMax: 170,
    trimp: 60,
    zonesSec: [100, 900, 700, 100, 0],
    belowSec: 50,
  );
  final b = figures(
    2,
    '2030-01-02',
    km: 10,
    movingSec: 3300,
    paceSec: 3300,
    best: 320,
    laps: 10,
    hrAvg: 160,
    hrSec: 300,
    hrMax: 185,
    trimp: 150,
    trimpIncomplete: true,
    zonesSec: [0, 300, 2000, 900, 100],
    belowSec: 20,
  );
  final c = figures(
    3,
    '2030-01-02',
    hour: 18,
    km: 3,
    movingSec: 1000,
    paceSec: 990,
    best: null,
  );
  final before = figures(
    4,
    '2029-12-30',
    km: 8,
    movingSec: 2800,
    paceSec: 2800,
  );
  final after = figures(
    5,
    '2030-01-07',
    km: 12,
    movingSec: 4000,
    paceSec: 4000,
  );
  final all = [after, c, a, before, b];
  final week = StatisticsPeriod.weekOf('2030-01-03');

  group('Summen eines Zeitraums (FR-0043, FR-0044)', () {
    final s = computePeriodStatistics(week, all);

    test('Woche = Summe der Läufe der Woche', () {
      expect(s.runs.map((r) => r.runId), [1, 2, 3]);
      expect(s.runCount, 3);
      expect(s.trainingDays, 2);
      expect(s.distanceMeters.value, 18000);
      expect(s.movingTime.value, const Duration(seconds: 6100));
      expect(s.totalTime.value, const Duration(seconds: 6100 + 180));
      // Summe der Einzelwerte ist die Wochenzahl, unabhängig von der Rechnung.
      expect(
        s.distanceMeters.value,
        s.runs.fold<double>(0, (x, r) => x + r.distanceMeters!),
      );
    });

    test('Durchschnittspace = Strecke / Zeit, nicht Mittel der Paces', () {
      // 6080 s / 18 km.
      expect(s.averagePaceSecondsPerKm.value, closeTo(6080 / 18, 1e-9));
    });

    test('Bestpace = schnellste, Lauf ohne Bestpace zählt nicht als 0', () {
      expect(s.bestPaceSecondsPerKm.value, 320);
      expect(s.bestPaceSecondsPerKm.runsWithValue, 2);
      expect(s.bestPaceSecondsPerKm.isPartial, isTrue);
    });

    test('Puls: gewichtetes Mittel, Maximum; Lauf ohne Puls bleibt außen', () {
      expect(
        s.heartRateAverageBpm.value,
        closeTo((150 * 100 + 160 * 300) / 400, 1e-9),
      );
      expect(s.heartRateMaxBpm.value, 185);
      expect(s.heartRateMaxBpm.runsWithValue, 2);
    });

    test('Zonen und TRIMP summiert, Unvollständigkeit gemeldet', () {
      expect(s.zoneTimes.value!.map((d) => d.inSeconds), [
        100,
        1200,
        2700,
        1000,
        100,
      ]);
      expect(s.belowZone1Time.value, const Duration(seconds: 70));
      expect(s.trimpPoints.value, 210);
      expect(s.trimpIncomplete, isTrue);
      expect(s.lapCount.value, 15);
    });

    test('Zeitraum-Grenzen: Tag davor und danach zählen nicht', () {
      expect(s.runs.any((r) => r.runId == 4 || r.runId == 5), isFalse);
    });

    test('Monat und freier Zeitraum über den Jahreswechsel', () {
      final jan = computePeriodStatistics(
        StatisticsPeriod.monthOf('2030-01-15'),
        all,
      );
      expect(jan.runs.map((r) => r.runId), [2, 3, 5]);
      final span = computePeriodStatistics(
        StatisticsPeriod.custom(from: '2029-12-30', to: '2030-01-02'),
        all,
      );
      expect(span.runs.map((r) => r.runId), [4, 1, 2, 3]);
      expect(span.distanceMeters.value, 26000);
    });

    test('einzelner Lauf entspricht seinen Kennzahlen', () {
      final one = computePeriodStatistics(
        const StatisticsPeriod.singleRun(2),
        all,
      );
      expect(one.runCount, 1);
      expect(one.distanceMeters.value, 10000);
      expect(one.averagePaceSecondsPerKm.value, 330);
      expect(one.bestPaceSecondsPerKm.value, 320);
      expect(one.distanceMeters.isPartial, isFalse);
    });
  });

  group('Fehlendes ist null, nie 0', () {
    test(
      'leerer Zeitraum: Zahl der Läufe 0, alle Kennzahlen nicht verfügbar',
      () {
        final s = computePeriodStatistics(
          StatisticsPeriod.weekOf('2031-06-10'),
          all,
        );
        expect(s.runCount, 0);
        expect(s.trainingDays, 0);
        for (final v in <StatValue<Object>>[
          s.distanceMeters,
          s.movingTime,
          s.totalTime,
          s.averagePaceSecondsPerKm,
          s.bestPaceSecondsPerKm,
          s.lapCount,
          s.heartRateAverageBpm,
          s.heartRateMaxBpm,
          s.zoneTimes,
          s.belowZone1Time,
          s.trimpPoints,
        ]) {
          expect(v.value, isNull);
          expect(v.isAvailable, isFalse);
          expect(v.runsTotal, 0);
        }
        expect(s.trimpIncomplete, isFalse);
      },
    );

    test('Lauf ohne Puls und ohne Strecke: keine 0 in den Summen', () {
      final bare = figures(9, '2030-02-01');
      final s = computePeriodStatistics(
        StatisticsPeriod.monthOf('2030-02-01'),
        [bare],
      );
      expect(s.runCount, 1);
      expect(s.distanceMeters.value, isNull);
      expect(s.heartRateAverageBpm.value, isNull);
      expect(s.heartRateMaxBpm.value, isNull);
      expect(s.trimpPoints.value, isNull);
      expect(s.averagePaceSecondsPerKm.value, isNull);
    });

    test('Strecke 0 ergibt keine Pace', () {
      final s = computePeriodStatistics(
        StatisticsPeriod.monthOf('2030-02-01'),
        [figures(9, '2030-02-01', km: 0, movingSec: 100, paceSec: 100)],
      );
      expect(s.distanceMeters.value, 0); // gemessen 0 m ist ein Wert
      expect(s.averagePaceSecondsPerKm.value, isNull);
    });

    test('doppelte Lauf-Id wird abgelehnt', () {
      expect(() => computePeriodStatistics(week, [a, a]), throwsArgumentError);
    });

    test('abweichende Zonenzahl: Lauf bleibt außen, Teilwert gemeldet', () {
      final odd = figures(6, '2030-01-03', zonesSec: [1, 2, 3], belowSec: 999);
      final s = computePeriodStatistics(week, [a, odd]);
      // Unter Zone 1 nur aus denselben Läufen wie die Zonen.
      expect(s.belowZone1Time.value, const Duration(seconds: 50));
      expect(s.belowZone1Time.runsWithValue, 1);
      expect(s.zoneTimes.value!.length, 5);
      expect(s.zoneTimes.runsWithValue, 1);
      expect(s.zoneTimes.isPartial, isTrue);
    });
  });

  group('Entwicklung: Vergleich mit dem Vorzeitraum', () {
    test('Woche gegen Vorwoche', () {
      final cmp = comparePeriod(week, all)!;
      expect(cmp.previous.period, StatisticsPeriod.weekOf('2029-12-24'));
      expect(cmp.previous.runs.map((r) => r.runId), [4]);
      expect(cmp.distanceDeltaMeters, 18000 - 8000);
      expect(cmp.movingTimeDelta, const Duration(seconds: 6100 - 2800));
      expect(cmp.runCountDelta, 2);
    });

    test(
      'Vorzeitraum leer: Unterschied nicht verfügbar, nicht Differenz zu 0',
      () {
        final cmp = comparePeriod(StatisticsPeriod.weekOf('2030-01-07'), all)!;
        // Vorwoche = die Woche der Läufe 1..3; aktuell Lauf 5.
        expect(cmp.distanceDeltaMeters, 12000 - 18000);
        final none = comparePeriod(StatisticsPeriod.weekOf('2029-06-01'), all)!;
        expect(none.distanceDeltaMeters, isNull);
        expect(none.movingTimeDelta, isNull);
      },
    );

    test('Lauf und freier Zeitraum haben keinen Vergleich', () {
      expect(comparePeriod(const StatisticsPeriod.singleRun(1), all), isNull);
    });
  });

  group('Sporteinheiten (FR-0221, FR-0043)', () {
    // Zwei GPS-Läufe je 5 km in 30 min, eine Sporteinheit 30 min mit TRIMP 40.
    final r1 = figures(
      11,
      '2029-12-31',
      km: 5,
      movingSec: 1800,
      paceSec: 1800,
      best: 350,
      laps: 5,
      hrAvg: 150,
      hrSec: 1800,
      hrMax: 170,
      trimp: 50,
      zonesSec: [600, 1200, 0, 0, 0],
      belowSec: 10,
    );
    final r2 = figures(
      12,
      '2030-01-02',
      km: 5,
      movingSec: 1800,
      paceSec: 1800,
      best: 340,
      laps: 5,
      hrAvg: 160,
      hrSec: 1800,
      hrMax: 175,
      trimp: 60,
      zonesSec: [0, 1800, 0, 0, 0],
      belowSec: 20,
    );
    final sp = figures(
      13,
      '2030-01-04',
      sport: true,
      movingSec: 1800,
      laps: 0,
      hrAvg: 170,
      hrSec: 1800,
      hrMax: 190,
      trimp: 40,
      zonesSec: [0, 0, 1800, 0, 0],
      belowSec: 30,
    );

    test('Umfang und Tempo nur aus Läufen, Puls und TRIMP aus allen', () {
      final s = computePeriodStatistics(week, [sp, r1, r2]);
      expect(s.runCount, 2);
      expect(s.runs.map((r) => r.runId), [11, 12]);
      expect(s.units.map((r) => r.runId), [11, 12, 13]);
      expect(s.trainingDays, 2);
      expect(s.distanceMeters.value, 10000);
      expect(s.distanceMeters.isPartial, isFalse);
      expect(s.distanceMeters.runsTotal, 2);
      expect(s.movingTime.value, const Duration(minutes: 60));
      expect(s.movingTime.isPartial, isFalse);
      expect(s.totalTime.value, const Duration(minutes: 62));
      expect(s.averagePaceSecondsPerKm.value, closeTo(360, 1e-9));
      expect(s.averagePaceSecondsPerKm.runsTotal, 2);
      expect(s.bestPaceSecondsPerKm.value, 340);
      expect(s.lapCount.value, 10);
      expect(s.lapCount.runsTotal, 2);
      expect(s.trimpPoints.value, 150);
      expect(s.trimpPoints.runsTotal, 3);
      expect(s.trimpPoints.isPartial, isFalse);
      expect(s.zoneTimes.value, const [
        Duration(seconds: 600),
        Duration(seconds: 3000),
        Duration(seconds: 1800),
        Duration.zero,
        Duration.zero,
      ]);
      expect(s.zoneTimes.runsTotal, 3);
      expect(s.belowZone1Time.value, const Duration(seconds: 60));
      expect(s.belowZone1Time.runsTotal, 3);
      expect(s.heartRateMaxBpm.value, 190);
      expect(s.heartRateMaxBpm.runsTotal, 3);
      expect(s.heartRateAverageBpm.value, closeTo(160, 1e-9));
      expect(s.heartRateAverageBpm.runsTotal, 3);
    });

    test('Tag nur mit Sporteinheit ist kein Trainingstag', () {
      final s = computePeriodStatistics(week, [r1, sp]);
      expect(s.trainingDays, 1);
    });

    test('Tag mit Lauf und Sporteinheit zählt einmal', () {
      final same = figures(
        14,
        '2029-12-31',
        hour: 18,
        sport: true,
        trimp: 5,
        trimpIncomplete: true,
      );
      final s = computePeriodStatistics(week, [r1, same]);
      expect(s.trainingDays, 1);
      expect(s.runCount, 1);
      expect(s.trimpPoints.value, 55);
      // Unvollständiger Puls der Sporteinheit gilt auch für die Summe.
      expect(s.trimpIncomplete, isTrue);
    });

    test('nur Sporteinheiten: wie ohne Lauf, TRIMP bleibt', () {
      final s = computePeriodStatistics(week, [sp]);
      final none = computePeriodStatistics(week, const []);
      expect(s.runCount, 0);
      expect(s.trainingDays, 0);
      expect(s.distanceMeters.value, none.distanceMeters.value);
      expect(s.distanceMeters.isPartial, isFalse);
      expect(s.movingTime.value, isNull);
      expect(s.averagePaceSecondsPerKm.isAvailable, isFalse);
      expect(s.bestPaceSecondsPerKm.isAvailable, isFalse);
      expect(s.lapCount.value, isNull);
      expect(s.trimpPoints.value, 40);
      expect(s.trimpPoints.isPartial, isFalse);
      expect(s.zoneTimes.value![2], const Duration(seconds: 1800));
    });

    test('Bandlauf zählt als Lauf (FR-0196)', () {
      // Bandlauf: Lauf mit Strecke, ohne Bestpace.
      final belt = figures(
        15,
        '2030-01-03',
        km: 4,
        movingSec: 1500,
        paceSec: 1500,
      );
      final s = computePeriodStatistics(week, [belt, sp]);
      expect(s.runCount, 1);
      expect(s.distanceMeters.value, 4000);
      expect(s.trainingDays, 1);
    });

    test('Vergleich mit der Vorwoche zählt die Sporteinheit nicht', () {
      final next = figures(16, '2030-01-08', sport: true, movingSec: 600);
      final cmp = comparePeriod(StatisticsPeriod.weekOf('2030-01-08'), [
        r1,
        next,
      ])!;
      expect(cmp.runCountDelta, -1);
      expect(cmp.distanceDeltaMeters, isNull);
    });
  });
}
