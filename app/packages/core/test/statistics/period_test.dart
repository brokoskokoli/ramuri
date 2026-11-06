import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('Zeitraum (FR-0044)', () {
    test('Kalenderwoche Montag bis Sonntag', () {
      // 2030-01-02 ist ein Mittwoch.
      final p = StatisticsPeriod.weekOf('2030-01-02');
      expect(p.kind, PeriodKind.week);
      expect([p.firstDay, p.lastDay], ['2029-12-31', '2030-01-06']);
    });

    test('Woche über den Jahreswechsel enthält beide Jahre', () {
      final p = StatisticsPeriod.weekOf('2029-12-31');
      expect(p.contains(id: 1, day: '2029-12-31'), isTrue);
      expect(p.contains(id: 2, day: '2030-01-01'), isTrue);
      expect(p.contains(id: 3, day: '2030-01-07'), isFalse);
      expect(p.contains(id: 4, day: '2029-12-30'), isFalse);
    });

    test('Wochenbeginn einstellbar (Sonntag)', () {
      final p = StatisticsPeriod.weekOf(
        '2030-01-02',
        parameters: const StatisticsParameters(firstDayOfWeek: DateTime.sunday),
      );
      expect([p.firstDay, p.lastDay], ['2029-12-30', '2030-01-05']);
      // Ist der Tag selbst der erste Tag, beginnt die Woche dort.
      expect(
        StatisticsPeriod.weekOf(
          '2029-12-30',
          parameters: const StatisticsParameters(
            firstDayOfWeek: DateTime.sunday,
          ),
        ).firstDay,
        '2029-12-30',
      );
      // Die Vorwoche behält den Wochenbeginn (Befund 4).
      final before = p.previous()!;
      expect([before.firstDay, before.lastDay], ['2029-12-23', '2029-12-29']);
      expect(before.firstDayOfWeek, DateTime.sunday);
    });

    test('Monate: Februar normal und im Schaltjahr, Dezember', () {
      expect(StatisticsPeriod.monthOf('2030-02-14').lastDay, '2030-02-28');
      expect(StatisticsPeriod.monthOf('2032-02-14').lastDay, '2032-02-29');
      final dec = StatisticsPeriod.monthOf('2029-12-15');
      expect([dec.firstDay, dec.lastDay], ['2029-12-01', '2029-12-31']);
    });

    test('freier Zeitraum über den Jahreswechsel, Grenzen eingeschlossen', () {
      final p = StatisticsPeriod.custom(from: '2029-12-20', to: '2030-01-10');
      expect(p.contains(id: 1, day: '2029-12-20'), isTrue);
      expect(p.contains(id: 1, day: '2030-01-10'), isTrue);
      expect(p.contains(id: 1, day: '2029-12-19'), isFalse);
      expect(p.contains(id: 1, day: '2030-01-11'), isFalse);
      // Ein Tag als Zeitraum ist erlaubt.
      expect(
        () => StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-01'),
        returnsNormally,
      );
    });

    test('ungültige Eingaben werden abgelehnt', () {
      expect(
        () => StatisticsPeriod.custom(from: '2030-01-02', to: '2030-01-01'),
        throwsArgumentError,
      );
      for (final bad in ['2030-02-30', '2030-1-1', '', '2030-13-01']) {
        expect(() => StatisticsPeriod.monthOf(bad), throwsArgumentError);
      }
    });

    test('einzelner Lauf gehört über die Id, nicht über den Tag', () {
      const p = StatisticsPeriod.singleRun(5);
      expect(p.contains(id: 5, day: '2030-01-01'), isTrue);
      expect(p.contains(id: 6, day: '2030-01-01'), isFalse);
    });

    test('Vorgänger: Woche, Monat über Jahreswechsel; sonst keiner', () {
      final w = StatisticsPeriod.weekOf('2030-01-02').previous()!;
      expect([w.firstDay, w.lastDay], ['2029-12-24', '2029-12-30']);
      final m = StatisticsPeriod.monthOf('2030-01-15').previous()!;
      expect([m.firstDay, m.lastDay], ['2029-12-01', '2029-12-31']);
      expect(const StatisticsPeriod.singleRun(1).previous(), isNull);
      expect(
        StatisticsPeriod.custom(
          from: '2030-01-01',
          to: '2030-01-02',
        ).previous(),
        isNull,
      );
    });
  });
}
