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
    hrCount: 100,
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
    hrCount: 300,
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
      final odd = figures(6, '2030-01-03', zonesSec: [1, 2, 3]);
      final s = computePeriodStatistics(week, [a, odd]);
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
}
