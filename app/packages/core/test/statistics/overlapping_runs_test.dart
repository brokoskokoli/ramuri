import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/overlapping_runs.dart';

/// Verlauf, Zeitraumstatistik und Einordnung mit zwei Läufen, die sich nach
/// einem Rücksprung der Wanduhr überlappen (ADR-0005 Punkt 7): B beginnt und
/// endet vor dem Ende von A. Reihenfolge nach Ende bleibt die Ordnung.
void main() {
  late OverlappingRuns o;
  late List<RunFigures> figures;
  late RunFigures a;
  late RunFigures b;
  const today = '2030-01-16';

  setUp(() async {
    o = await recordOverlappingRuns();
    final overviews = await RunOverviewService(
      session: o.session,
      clock: o.clock,
    ).load();
    figures = [for (final v in overviews) v.toFigures()];
    a = figures.singleWhere((f) => f.runId == o.a);
    b = figures.singleWhere((f) => f.runId == o.b);
  });

  test('Verlauf enthält beide Läufe, Reihenfolge nach Ende', () {
    expect(figures.map((f) => f.runId).toSet(), {o.a, o.b});
    expect(a.day, today);
    expect(b.day, today);
    final weeks = groupByWeek<RunFigures>(
      figures,
      today,
      dayOf: (f) => f.day,
      endedAtOf: (f) => f.endedAt,
    );
    expect(weeks.single.kind, WeekGroupKind.thisWeek);
    // Neuester zuerst nach Ende: A endet nach B, obwohl B später startete.
    expect(weeks.single.items.map((f) => f.runId), [o.a, o.b]);
    for (final r in HistoryRange.values) {
      expect(historyTotals(r, today, figures).runCount, 2, reason: '$r');
    }
  });

  test('Zeitraumstatistik zählt beide Läufe genau einmal', () {
    final s = computePeriodStatistics(StatisticsPeriod.weekOf(today), figures);
    expect(s.runCount, 2);
    expect(s.distanceMeters.runsWithValue, 2);
    expect(s.distanceMeters.value, a.distanceMeters! + b.distanceMeters!);
    expect(s.movingTime.value, a.movingTime! + b.movingTime!);
    // Zeiten aus der Sitzungszeit: A 20 min trotz Sprung, B 3 min.
    expect(a.totalTime, const Duration(minutes: 20));
    expect(b.totalTime, const Duration(minutes: 3));
    expect(s.totalTime.value, const Duration(minutes: 23));
  });

  test('Einordnung: Vorläufe nach Ende, ohne Ausnahme', () {
    // B endet vor A: B hat keinen Vorlauf, A hat B als Vorlauf.
    final cb = classifyRun(b, figures);
    expect(cb.isAvailable, isFalse);
    expect(cb.unavailable, ClassificationUnavailable.tooFewPreviousRuns);
    expect(cb.comparedRuns, 0);
    final ca = classifyRun(a, figures);
    expect(ca.isAvailable, isTrue);
    expect(ca.comparedRuns, 1);
    expect(ca.referenceSecondsPerKm, b.averagePaceSecondsPerKm);
  });

  test('Fitnessübersicht: beide Läufe gezählt, neuester nach Ende', () async {
    final fo = await FitnessOverviewService(session: o.session)
        .load(await o.session.runs.list());
    expect(fo.readFailed, isFalse);
    // Noch ohne berechnete Laufwerte: beide stehen aus, keiner fehlt.
    expect(fo.pendingRuns, 2);
    expect(fo.day, today);
  });
}
