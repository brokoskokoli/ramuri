import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_view.dart' show formatClock;
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart'
    show key, seedRun, showAllRuns, started, text;

/// Verlauf nach Verlauf.dc.html (WP16 D, FR-0040, FR-0212).
///
/// Heute ist Mittwoch, der 17. Juni 2026 (Wochenbeginn Montag).
final DateTime _now = DateTime.utc(2026, 6, 17, 12);

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: key('history_range'), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Sechs Läufe: zwei in dieser Woche, einer in der letzten, einer weiter vorn
/// im Monat, einer im Vormonat, einer im Vorjahr.
Future<Map<String, int>> _seed(Device d) async {
  final s = d.session;
  return {
    'a': await seedRun(s, DateTime.utc(2026, 6, 16, 8)),
    'b': await seedRun(
      s,
      DateTime.utc(2026, 6, 15, 8),
      minutes: 20,
      speed: 2.5,
      bpm: null,
    ),
    'c': await seedRun(s, DateTime.utc(2026, 6, 10, 8), minutes: 30),
    'd': await seedRun(s, DateTime.utc(2026, 6, 2, 8), minutes: 5),
    'e': await seedRun(s, DateTime.utc(2026, 5, 28, 8), minutes: 15),
    'f': await seedRun(s, DateTime.utc(2025, 11, 20, 8), minutes: 25),
  };
}

String _km(double? meters) =>
    '${(meters! / 1000).toStringAsFixed(2).replaceAll('.', ',')} km';

Future<Device> _start(WidgetTester tester) async {
  final d = await started(tester);
  d.clock.set(_now);
  return d;
}

Future<HistoryTotals> _expected(Device d, HistoryRange range) async {
  final overviews = await RunOverviewService(
    session: d.session,
    clock: d.clock,
  ).load();
  return historyTotals(range, '2026-06-17', [
    for (final o in overviews) o.toFigures(),
  ]);
}

/// Zahl der Zeilen eines Absatzes (Höhe geteilt durch die Zeilenhöhe).
int _lines(RenderParagraph p) =>
    (p.size.height / p.getFullHeightForCaret(const TextPosition(offset: 0)))
        .round();

double _scrolled(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byWidgetPredicate(
              (w) =>
                  w is ListView &&
                  w.key is PageStorageKey<String> &&
                  (w.key! as PageStorageKey<String>).value.startsWith(
                    'history_list',
                  ),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void main() {
  group('Zeitraum und Summen (FR-0212)', () {
    testWidgets('Summen sind die der Statistik für denselben Zeitraum', (
      tester,
    ) async {
      final d = await _start(tester);
      final ids = await _seed(d);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      final counts = {
        HistoryRange.week: 2,
        HistoryRange.month: 4,
        HistoryRange.year: 5,
        HistoryRange.all: 6,
      };
      final labels = {
        HistoryRange.week: 'Woche',
        HistoryRange.month: 'Monat',
        HistoryRange.year: 'Jahr',
        HistoryRange.all: 'Alle',
      };
      for (final range in HistoryRange.values) {
        await _pick(tester, labels[range]!);
        final expected = await _expected(d, range);
        // Die Zahl der Läufe und die Summen kommen aus computePeriodStatistics.
        expect(expected.runCount, counts[range], reason: '$range');
        expect(text('history_total_runs'), '${counts[range]}');
        expect(
          text('history_total_distance'),
          _km(expected.distanceMeters),
          reason: '$range',
        );
        expect(
          text('history_total_time'),
          formatClock(expected.totalTime),
          reason: '$range',
        );
      }
      // Die Wochensumme ist die der Fortschrittsseite.
      await _pick(tester, 'Woche');
      final week = text('history_total_distance');
      await tester.tap(key('home_statistics'));
      await tester.pumpAndSettle();
      expect(text('stat_distance_value'), week);
      expect(text('stat_runs_value'), '2');
      expect(ids.length, 6);
    });

    testWidgets('Läufe außerhalb des Zeitraums stehen nicht in der Liste', (
      tester,
    ) async {
      final d = await _start(tester);
      final ids = await _seed(d);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      // Vorgabe: Monat.
      for (final k in ['a', 'b', 'c', 'd']) {
        expect(key('history_run_${ids[k]}'), findsOneWidget, reason: k);
      }
      for (final k in ['e', 'f']) {
        expect(key('history_run_${ids[k]}'), findsNothing, reason: k);
      }
      await _pick(tester, 'Woche');
      expect(key('history_run_${ids['a']}'), findsOneWidget);
      expect(key('history_run_${ids['c']}'), findsNothing);
      await _pick(tester, 'Alle');
      expect(key('history_run_${ids['f']}'), findsOneWidget);
    });

    testWidgets('leerer Zeitraum: eigene Anzeige statt Nullen', (tester) async {
      final d = await _start(tester);
      await seedRun(d.session, DateTime.utc(2026, 5, 28, 8));
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      // Der Monat hat keinen Lauf, der Verlauf als ganzer aber schon.
      expect(key('history_empty'), findsNothing);
      expect(
        text('history_empty_range'),
        'In diesem Zeitraum gibt es keine Läufe.',
      );
      expect(key('history_total_runs'), findsNothing);
      expect(key('history_total_distance'), findsNothing);
      await _pick(tester, 'Alle');
      expect(key('history_empty_range'), findsNothing);
      expect(text('history_total_runs'), '1');
    });

    testWidgets('leerer Zeitraum mit Läufen anderswo: Knopf führt zu „Alle“', (
      tester,
    ) async {
      final d = await _start(tester);
      final id = await seedRun(d.session, DateTime.utc(2026, 5, 28, 8));
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(key('history_empty_range'), findsOneWidget);
      expect(key('history_run_$id'), findsNothing);
      // Der Umschalter bleibt stehen, der Knopf ist mindestens 48 dp hoch.
      expect(key('history_range'), findsOneWidget);
      expect(find.text('Alle anzeigen'), findsOneWidget);
      expect(
        tester.getSize(key('history_show_all')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(key('history_show_all'));
      await tester.pumpAndSettle();
      expect(key('history_empty_range'), findsNothing);
      expect(key('history_show_all'), findsNothing);
      expect(key('history_run_$id'), findsOneWidget);
      expect(text('history_total_runs'), '1');
    });

    testWidgets('gar keine Läufe: kein Knopf „Alle anzeigen“', (tester) async {
      await _start(tester);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(key('history_empty'), findsOneWidget);
      expect(key('history_show_all'), findsNothing);
      expect(find.text('Alle anzeigen'), findsNothing);
    });

    testWidgets('Läufe ohne Strecke: Summe "nicht verfügbar", nie 0', (
      tester,
    ) async {
      final d = await _start(tester);
      await seedRun(
        d.session,
        DateTime.utc(2026, 6, 16, 8),
        minutes: 0,
        bpm: null,
      );
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(text('history_total_runs'), '1');
      expect(text('history_total_distance'), 'nicht verfügbar');
      expect(find.textContaining(RegExp(r'(^|\s)0[,.]00 km')), findsNothing);
    });

    testWidgets('Meilen: Summe und Zeilen in der Einheit der Einstellungen', (
      tester,
    ) async {
      final d = await started(tester, locale: 'en');
      d.clock.set(_now);
      final a = await seedRun(d.session, DateTime.utc(2026, 6, 16, 8));
      await d.session.settings.set(
        SettingKeys.distanceUnit,
        'mi',
        at: d.clock.now(),
      );
      await openOverview(tester);
      await tester.tap(key('home_settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(text('history_total_distance'), '1.12 mi');
      expect(text('history_distance_$a'), '1.12 mi');
    });
  });

  group('Gruppen nach Wochen (FR-0212)', () {
    testWidgets('Diese Woche, Letzte Woche, danach mit Datum', (tester) async {
      final d = await _start(tester);
      final ids = await _seed(d);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      await _pick(tester, 'Alle');
      Finder heading(String t) => find.text(t.toUpperCase());
      expect(heading('Diese Woche'), findsOneWidget);
      expect(heading('Letzte Woche'), findsOneWidget);
      // Die Woche vom 1. bis 7. Juni, die vom 25. bis 31. Mai, die im November 2025.
      expect(heading('1. Juni – 7. Juni'), findsOneWidget);
      expect(heading('25. Mai – 31. Mai'), findsOneWidget);
      expect(heading('17. Nov. 2025 – 23. Nov. 2025'), findsOneWidget);
      double top(String t) => tester.getTopLeft(heading(t)).dy;
      expect(top('Diese Woche'), lessThan(top('Letzte Woche')));
      expect(top('Letzte Woche'), lessThan(top('1. Juni – 7. Juni')));
      // In einer Gruppe steht der neueste Lauf oben.
      final aY = tester.getTopLeft(key('history_run_${ids['a']}')).dy;
      final bY = tester.getTopLeft(key('history_run_${ids['b']}')).dy;
      expect(aY, lessThan(bY));
      expect(bY, lessThan(top('Letzte Woche')));
    });
  });

  group('Zeitraum und Lage über Tab-Wechsel (WP16 D)', () {
    testWidgets('Zeitraum bleibt, die Liste ist danach aktuell', (
      tester,
    ) async {
      final d = await _start(tester);
      final ids = await _seed(d);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      await _pick(tester, 'Woche');
      expect(key('history_run_${ids['c']}'), findsNothing);

      await tester.tap(key('home_today'));
      await tester.pumpAndSettle();
      // Währenddessen kommt ein Lauf dazu und einer fällt weg.
      final fresh = await seedRun(d.session, DateTime.utc(2026, 6, 17, 7));
      await d.session.deleteRun(ids['b']!);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();

      // Noch „Woche“: der Lauf vom Vormonat fehlt, der Wochenlauf steht da.
      expect(key('history_run_${ids['c']}'), findsNothing);
      expect(key('history_run_${ids['a']}'), findsOneWidget);
      expect(key('history_run_$fresh'), findsOneWidget);
      expect(key('history_run_${ids['b']}'), findsNothing);
      expect(text('history_total_runs'), '2');
    });

    testWidgets('Scrollposition bleibt (je Zeitraum), Zeitraum bleibt', (
      tester,
    ) async {
      final d = await _start(tester);
      tester.view.physicalSize = const Size(411, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var i = 0; i < 12; i++) {
        await seedRun(d.session, DateTime.utc(2026, 6, 1 + i, 8), minutes: 2);
      }
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(_scrolled(tester), 0);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final before = _scrolled(tester);
      expect(before, greaterThan(200));

      await tester.tap(key('home_statistics'));
      await tester.pumpAndSettle();
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(_scrolled(tester), before);

      // Ein anderer Zeitraum beginnt oben und merkt sich seine Lage selbst.
      await tester.drag(find.byType(ListView), Offset(0, before - 70));
      await tester.pumpAndSettle();
      final month = _scrolled(tester);
      expect(month, inInclusiveRange(1, 150));
      await _pick(tester, 'Woche');
      expect(_scrolled(tester), 0);
      await _pick(tester, 'Monat');
      expect(_scrolled(tester), month);
    });
  });

  group('Zeile (FR-0040)', () {
    testWidgets(
      'Strecke, Dauer, Pace, Puls; ohne Puls kein 0; Tipp öffnet Detail',
      (tester) async {
        final d = await _start(tester);
        final ids = await _seed(d);
        await tester.tap(key('home_history'));
        await tester.pumpAndSettle();
        final a = ids['a']!;
        final b = ids['b']!;
        expect(key('history_miniature_$a'), findsOneWidget);
        expect(text('history_distance_$a'), '1,80 km');
        expect(text('history_time_$a'), '10:00');
        expect(text('history_pace_$a'), '5:33 min/km');
        expect(text('history_hr_$a'), 'Ø Puls 150 bpm');
        expect(text('history_hr_$b'), 'Puls: nicht verfügbar');
        expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
        await tester.tap(key('history_run_$a'));
        await tester.pumpAndSettle();
        expect(key('detail_export'), findsOneWidget);
      },
    );

    testWidgets('Löschen: Summen und Liste folgen', (tester) async {
      final d = await _start(tester);
      final ids = await _seed(d);
      await tester.tap(key('home_history'));
      await tester.pumpAndSettle();
      expect(text('history_total_runs'), '4');
      await tester.tap(key('history_delete_${ids['a']}'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lauf löschen').last);
      await tester.pumpAndSettle();
      expect(key('history_run_${ids['a']}'), findsNothing);
      expect(text('history_total_runs'), '3');
      final expected = await _expected(d, HistoryRange.month);
      expect(text('history_total_distance'), _km(expected.distanceMeters));
    });
  });

  group('Schriftfaktor 1,3 auf 360 x 640', () {
    for (final dark in [false, true]) {
      testWidgets(
        '${dark ? 'dunkel' : 'hell'}: keine Überläufe, 48 dp, Einheit ungebrochen',
        (tester) async {
          final d = await _start(tester);
          final ids = await _seed(d);
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          tester.platformDispatcher.platformBrightnessTestValue = dark
              ? Brightness.dark
              : Brightness.light;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await tester.tap(key('home_history'));
          await tester.pumpAndSettle();
          await showAllRuns(tester);
          // Alle Bedienelemente sind mindestens 48 dp groß.
          for (final r in ['Woche', 'Monat', 'Jahr', 'Alle']) {
            final seg = find.ancestor(
              of: find.descendant(
                of: key('history_range'),
                matching: find.text(r),
              ),
              matching: find.byType(InkWell),
            );
            final size = tester.getSize(seg.first);
            expect(
              size.height,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: r,
            );
            expect(
              size.width,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
              reason: r,
            );
            // Die Beschriftung bricht nicht mitten im Wort.
            final label = tester.renderObject<RenderParagraph>(
              find.descendant(of: key('history_range'), matching: find.text(r)),
            );
            expect(_lines(label), 1, reason: r);
            // Die Beschriftung ist ganz zu lesen: weder abgeschnitten noch breiter als ihr Abschnitt.
            expect(label.didExceedMaxLines, isFalse, reason: r);
          }
          for (final id in [ids['a']!, ids['b']!]) {
            await tester.ensureVisible(key('history_run_$id'));
            await tester.pumpAndSettle();
            final del = tester.getSize(key('history_delete_$id'));
            expect(del.height, greaterThanOrEqualTo(RamuriTheme.minTarget));
            expect(del.width, greaterThanOrEqualTo(RamuriTheme.minTarget));
            expect(
              tester.getSize(key('history_run_$id')).height,
              greaterThanOrEqualTo(RamuriTheme.minTarget),
            );
            // Die Einheit der Pace steht auf einer Zeile, nie am "/" getrennt.
            final pace = tester.renderObject<RenderParagraph>(
              key('history_pace_$id'),
            );
            expect(_lines(pace), 1);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
