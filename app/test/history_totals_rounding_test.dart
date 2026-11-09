// WP17 B (FR-0212): Die Zeitsumme über der Verlaufsliste ist die Gesamtzeit der Statistik, dieselbe Zeitbasis wie die
// Zeilen (RunFigures.totalTime = RunOverview.totalTime). Die Anzeige schneidet Sekundenbruchteile ab (formatClock,
// inSeconds); die Summe wird erst als Ganzes abgeschnitten. Darum kann sie von der Summe der angezeigten Zeilen
// abweichen, höchstens um (Läufe - 1) Sekunden. Beleg zur Abweichung 18:52 / 18:50 bei sieben Läufen (E2E WP16).
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_view.dart' show formatClock;

import 'history_summary_test.dart' show openHistory, started, text;

void main() {
  test('Zeitsumme = Statistik; Abweichung zur Zeilensumme höchstens Rundung je Zeile', () {
    // Sieben Läufe in einer Woche, jede Gesamtzeit mit 0,3 s Bruchteil.
    // Zeilen 2:40 bis 2:46 (abgeschnitten), Summe der Bruchteile 7 * 0,3 = 2,1 s.
    final totals = [
      for (var i = 0; i < 7; i++)
        Duration(milliseconds: (160 + i) * 1000 + 300),
    ];
    // Die Zeile der Liste zeigt RunOverview.totalTime; die Summe rechnet aus
    // denselben Läufen (toFigures). Die Bewegungszeit ist bewusst kürzer: Wer
    // sie für Zeile oder Summe nähme, fiele hier durch.
    final overviews = [
      for (var i = 0; i < 7; i++)
        RunOverview(
          run: StoredRun(
            id: i + 1,
            state: RunState.finished,
            startedAt: DateTime.utc(2030, 1, 14 + i, 11),
            endedAt: DateTime.utc(2030, 1, 14 + i, 12),
            endedUtcOffset: Duration.zero,
          ),
          distanceMeters: 1000,
          movingTime: totals[i] - const Duration(seconds: 5),
          totalTime: totals[i],
        ),
    ];
    final runs = [for (final o in overviews) o.toFigures()];
    final t = historyTotals(HistoryRange.week, '2030-01-16', runs);
    expect(t.runCount, 7);
    final stat = computePeriodStatistics(t.period, runs);
    // Summe gleich der Statistik, auf der Zeitbasis der Zeilen (Gesamtzeit).
    expect(t.totalTime, stat.totalTime.value);
    final exact = totals.fold(Duration.zero, (a, b) => a + b);
    expect(t.totalTime, exact);
    // Summe angezeigt 19:03, Zeilen addiert 19:01: genau 2 s (7 * 0,3 = 2,1 s).
    final shownSum = t.totalTime!.inSeconds;
    // Zeilen, wie die Liste sie zeigt (formatClock schneidet auf Sekunden).
    final rowsSum = overviews.fold<int>(
      0,
      (a, o) => a + o.totalTime!.inSeconds,
    );
    expect(
      [for (final o in overviews) formatClock(o.totalTime)],
      ['2:40', '2:41', '2:42', '2:43', '2:44', '2:45', '2:46'],
    );
    expect(shownSum - rowsSum, 2);
    expect(
      formatClock(t.totalTime),
      '${shownSum ~/ 60}:${(shownSum % 60).toString().padLeft(2, '0')}',
    );
    // Obergrenze der Rundung: weniger als eine Sekunde je Zeile.
    expect(shownSum - rowsSum, lessThan(runs.length));
    expect(shownSum - rowsSum, greaterThanOrEqualTo(0));
  });

  // WP17 NB1 (Befund 1): Der echte Weg bis zur Oberfläche. Ein Lauf mit
  // Stillstand hat eine Gesamtzeit, die länger ist als die Bewegungszeit;
  // Zeile und Zeitsumme zeigen die Gesamtzeit (FR-0212).
  testWidgets(
    'Lauf mit Stillstand: Zeile und Zeitsumme zeigen die Gesamtzeit',
    (tester) async {
      final d = await started(tester);
      final start = DateTime.utc(2030, 1, 2, 8);
      final run = await d.session.runs.create(startedAt: start);
      // 10 min: 3 min laufen, 3 min stehen (gleiche Position), 4 min laufen.
      const perDegree = earthRadiusMeters * 3.141592653589793 / 180;
      double lat(int s) =>
          10 + (s <= 180 ? s : (s <= 360 ? 180 : s - 180)) * 3.0 / perDegree;
      await d.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 600; s++)
              RawPosition(
                time: start.add(Duration(seconds: s)),
                source: 'gps',
                latitude: lat(s),
                longitude: 20,
                accuracyMeters: 5,
              ),
          ],
        ),
      );
      await d.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(seconds: 600)),
        endedUtcOffset: Duration.zero,
      );
      // Gegenprobe: Die Bewegungszeit ist wirklich kürzer als die Gesamtzeit.
      final summary = (await RunSummaryService(
        session: d.session,
        clock: d.clock,
      ).load(run.id))!;
      expect(
        summary.preprocessing.movement.totalTime,
        const Duration(minutes: 10),
      );
      expect(
        summary.preprocessing.movement.movingTime,
        lessThan(const Duration(minutes: 9)),
      );
      await openHistory(d, tester);
      expect(text('history_time_${run.id}'), '10:00');
      expect(text('history_total_time'), '10:00');
    },
  );
}
