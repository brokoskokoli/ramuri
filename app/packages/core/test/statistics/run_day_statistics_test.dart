// Statistik, Belastung und Metriken-Export zählen einen Lauf über Mitternacht
// am Ortstag seines Starts (PAR-237, FR-0044, FR-0092). Feste UTC-Zeitpunkte
// mit dem am Lauf gespeicherten Versatz; unabhängig von der Zone des Prozesses.
import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Lauf 23:30–00:40 Ortszeit (+1 h) mit Start am Ortstag [day] (UTC-Mitternacht),
/// sofort berechnet.
Future<int> _midnightRun(RecalcWorld w, DateTime day) async {
  final id = await w.seedRun(
    day.add(const Duration(hours: 22, minutes: 30)),
    minutes: 70,
    utcOffset: const Duration(hours: 1),
  );
  await w.calc().calculateAfterRun(id);
  return id;
}

Future<RunFigures> _figures(RecalcWorld w, int id) async {
  final run = (await w.session.runs.get(id))!;
  final pre = replayRunPreprocessing(
    run: run,
    end: run.endedAt!,
    raw: await w.session.rawData.read(id),
    gaps: await w.session.markers.gaps(id),
    parameters: const PreprocessingParameters.v4(),
  );
  return RunFigures.fromRun(run: run, preprocessing: pre, laps: const []);
}

void main() {
  group('Statistik am Starttag (PAR-237, FR-0044)', () {
    test('Woche: Sonntag 23:30 bis Montag 00:40 zählt zur Woche des Sonntags, '
        'die Folgewoche hat weder Lauf noch Strecke', () async {
      final w = await RecalcWorld.create();
      // 2030-02-24 ist ein Sonntag.
      final f = await _figures(
        w,
        await _midnightRun(w, DateTime.utc(2030, 2, 24)),
      );
      expect(f.day, '2030-02-24');
      final sunday = historyTotals(HistoryRange.week, '2030-02-24', [f]);
      expect(sunday.period.firstDay, '2030-02-18');
      expect(sunday.runCount, 1);
      expect(sunday.distanceMeters, greaterThan(0));
      final monday = historyTotals(HistoryRange.week, '2030-02-25', [f]);
      expect(monday.runCount, 0);
      expect(monday.distanceMeters, isNull);
      // Verlauf: Wochengruppe des Sonntags.
      final groups = groupByWeek(
        [f],
        '2030-02-25',
        dayOf: (x) => x.day,
        endedAtOf: (x) => x.endedAt,
      );
      expect(groups.single.kind, WeekGroupKind.lastWeek);
      expect(groups.single.week.firstDay, '2030-02-18');
    });

    test('Monat: 28.02. 23:30 bis 01.03. 00:40 zählt zum Februar', () async {
      final w = await RecalcWorld.create();
      final f = await _figures(
        w,
        await _midnightRun(w, DateTime.utc(2030, 2, 28)),
      );
      final feb = historyTotals(HistoryRange.month, '2030-02-28', [f]);
      expect(feb.runCount, 1);
      expect(feb.distanceMeters, greaterThan(0));
      final mar = historyTotals(HistoryRange.month, '2030-03-01', [f]);
      expect(mar.runCount, 0);
      expect(mar.distanceMeters, isNull);
    });

    test('Jahr: 31.12. 23:30 bis 01.01. 00:40 zählt zum alten Jahr', () async {
      final w = await RecalcWorld.create();
      final f = await _figures(
        w,
        await _midnightRun(w, DateTime.utc(2029, 12, 31)),
      );
      final old = historyTotals(HistoryRange.year, '2029-12-31', [f]);
      expect(old.runCount, 1);
      expect(old.distanceMeters, greaterThan(0));
      final next = historyTotals(HistoryRange.year, '2030-01-01', [f]);
      expect(next.runCount, 0);
      expect(next.distanceMeters, isNull);
      // Freier Zeitraum (FR-0212): nur der Folgetag enthält ihn nicht.
      expect(
        computePeriodStatistics(
          StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-01'),
          [f],
        ).runCount,
        0,
      );
    });
  });

  test('Belastung: TRIMP-Tageswert und ATL/CTL am Starttag, der Folgetag '
      'ohne TRIMP (FR-0092, PAR-237)', () async {
    final w = await RecalcWorld.create();
    await _midnightRun(w, DateTime.utc(2030, 2, 20));
    w.clock.set(recalcNow);
    final r = await TrainingLoadService(
      session: w.session,
      clock: w.clock,
      calculation: w.calc(),
      recalculation: w.recalc(),
    ).load();
    LoadDay at(DateTime d) => r.series.days.singleWhere((x) => x.day == d);
    final start = at(DateTime.utc(2030, 2, 20));
    expect(start.load, greaterThan(0));
    expect(start.atl, greaterThan(0));
    expect(start.ctl, greaterThan(0));
    expect(at(DateTime.utc(2030, 2, 21)).load, isNull);
  });

  test('Metriken-Export: Spalte day eines Tageswerts ist der Starttag '
      '(docs/contracts/metrics-csv.md, PAR-237)', () async {
    final w = await RecalcWorld.create();
    await _midnightRun(w, DateTime.utc(2030, 2, 20));
    final file = await buildMetricsCsvFile(w.session, now: recalcNow);
    final dayColumn = {
      for (final line in utf8.decode(file.bytes!).split('\r\n').skip(1))
        if (line.isNotEmpty && line.split(',')[1] == 'day') line.split(',')[2],
    };
    expect(dayColumn, {'2030-02-20'});
  });
}
