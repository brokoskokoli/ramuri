import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // Heute: Mittwoch 2030-01-16 (Woche 01-14..01-20).
  const today = '2030-01-16';
  final runs = [
    figures(1, '2029-06-10', km: 8, movingSec: 2700, hrAvg: 150, hrSec: 2700),
    figures(2, '2029-12-31', km: 5, movingSec: 1800, paceSec: 1790),
    figures(3, '2030-01-02', km: 10, movingSec: 3300, paceSec: 3300),
    figures(4, '2030-01-09', km: 4, movingSec: 1500, hour: 7),
    figures(5, '2030-01-09', km: 6, movingSec: 2100, hour: 18),
    figures(6, '2030-01-15', km: 7, movingSec: 2400),
    figures(7, '2030-01-16', movingSec: 600), // ohne Strecke
  ];

  test('Zeiträume: Woche, Monat, Jahr, Alle', () {
    String span(HistoryRange r) {
      final p = historyPeriod(r, today, runs: runs);
      return '${p.firstDay}..${p.lastDay}';
    }

    expect(span(HistoryRange.week), '2030-01-14..2030-01-20');
    expect(span(HistoryRange.month), '2030-01-01..2030-01-31');
    expect(span(HistoryRange.year), '2030-01-01..2030-12-31');
    expect(span(HistoryRange.all), '2029-06-10..2030-01-16');
  });

  test('Alle reicht bis zum letzten Lauftag, auch nach heute', () {
    // Ein Lauf nach „heute“ (Uhr zurückgestellt, Zeitzone): er gehört dazu.
    final withFuture = [
      ...runs,
      figures(8, '2030-01-20', km: 3, movingSec: 900),
    ];
    final p = historyPeriod(HistoryRange.all, today, runs: withFuture);
    expect(p.lastDay, '2030-01-20');
    final t = historyTotals(HistoryRange.all, today, withFuture);
    expect(t.runCount, 8);
    expect(t.runCount, withFuture.length);
  });

  test('FR-0212: Summen gleich der Statistik für denselben Zeitraum', () {
    for (final r in HistoryRange.values) {
      final t = historyTotals(r, today, runs);
      final s = computePeriodStatistics(t.period, runs);
      expect(t.distanceMeters, s.distanceMeters.value, reason: '$r');
      expect(t.movingTime, s.movingTime.value, reason: '$r');
      expect(t.totalTime, s.totalTime.value, reason: '$r');
      expect(t.runCount, s.runCount, reason: '$r');
    }
    // Zahlen von Hand: Monat Januar 2030 = Läufe 3..7.
    final m = historyTotals(HistoryRange.month, today, runs);
    expect(m.runCount, 5);
    expect(m.distanceMeters, 27000);
    expect(
      m.movingTime,
      const Duration(seconds: 3300 + 1500 + 2100 + 2400 + 600),
    );
    // Woche: Läufe 6, 7.
    final w = historyTotals(HistoryRange.week, today, runs);
    expect(w.runCount, 2);
    expect(w.distanceMeters, 7000);
    // Alle: sieben Läufe.
    expect(historyTotals(HistoryRange.all, today, runs).runCount, 7);
    expect(historyTotals(HistoryRange.year, today, runs).runCount, 5);
  });

  test('ohne Läufe: Anzahl 0, Strecke und Zeit null statt 0', () {
    final t = historyTotals(HistoryRange.week, today, const []);
    expect(t.runCount, 0);
    expect(t.distanceMeters, isNull);
    expect(t.movingTime, isNull);
    final all = historyTotals(HistoryRange.all, today, const []);
    expect(all.period.firstDay, today);
  });

  test('Gruppen nach Wochen: Diese, Letzte, danach mit Datum', () {
    final groups = groupByWeek<RunFigures>(
      runs,
      today,
      dayOf: (r) => r.day,
      endedAtOf: (r) => r.endedAt,
    );
    expect(
      [for (final g in groups) g.kind],
      [
        WeekGroupKind.thisWeek,
        WeekGroupKind.lastWeek,
        WeekGroupKind.dated,
        WeekGroupKind.dated,
      ],
    );
    expect(
      [for (final g in groups) g.week.firstDay],
      ['2030-01-14', '2030-01-07', '2029-12-31', '2029-06-04'],
    );
    // Neuester Lauf zuerst, auch bei gleichem Tag.
    expect(
      [
        for (final g in groups) [for (final r in g.items) r.runId],
      ],
      [
        [7, 6],
        [5, 4],
        [3, 2],
        [1],
      ],
    );
    // Jede Woche zählt wie die Wochenstatistik.
    for (final g in groups) {
      final s = computePeriodStatistics(g.week, runs);
      expect(g.items.length, s.runCount);
    }
  });

  test('ohne Einträge keine Gruppen', () {
    expect(
      groupByWeek<RunFigures>(
        const [],
        today,
        dayOf: (r) => r.day,
        endedAtOf: (r) => r.endedAt,
      ),
      isEmpty,
    );
  });
}
