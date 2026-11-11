import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/app_shell.dart';
import 'package:running_app/features/statistics/progress_header.dart';
import 'package:running_app/features/statistics/statistics_screen.dart';
import 'package:running_app/features/statistics/statistics_view_state.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show openHistory, seedRun, started;
import 'statistics_test.dart' show calc, choose, openStats;

/// Fortschritt als Seite (WP15 Teil B): Wochenbalken gegen die Wochenstatistik,
/// alle bisherigen Kennzahlen, Zustand beim Tab-Wechsel über die echte
/// `AppShell`.

const ProfileRecord _profile = ProfileRecord(
  maxHeartRateBpm: 190,
  restingHeartRateBpm: 60,
);

String plain(String k) {
  final t = key(k).evaluate().single.widget as Text;
  return t.textSpan?.toPlainText() ?? t.data!;
}

String barsLabel(WidgetTester tester) =>
    tester.getSemantics(key('progress_week_bars')).label;

Future<void> openToday(WidgetTester tester) async {
  await tester.tap(key('home_today'));
  await tester.pumpAndSettle();
}

ScrollPosition position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: key('stat_list'), matching: find.byType(Scrollable)),
    )
    .position;

/// Zahl vor " km" oder " mi".
String distanceOf(String text) =>
    RegExp(r'[\d,.]+ (km|mi)').firstMatch(text)!.group(0)!;

/// Ein beendeter Lauf ohne jede Rohdatenzeile: Strecke nicht lesbar.
Future<int> seedRunWithoutDistance(StorageSession s, DateTime start) async {
  final run = await s.runs.create(startedAt: start);
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(const Duration(minutes: 10)),
    endedUtcOffset: Duration.zero,
  );
  return run.id;
}

void main() {
  group('Kilometer pro Woche', () {
    testWidgets('acht Wochen, gleiche Werte wie die Wochenstatistik, leere '
        'Woche als 0', (tester) async {
      final handle = tester.ensureSemantics();
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12)); // Mittwoch, KW 23
      // KW 23 (zwei Läufe), KW 22, KW 20, KW 17 (außerhalb: KW 16 beginnt
      // am 13. April), KW 15 gehört nicht mehr zu den acht Wochen.
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 6, 3, 8), minutes: 20);
      await seedRun(d.session, DateTime.utc(2026, 5, 27, 8), minutes: 15);
      await seedRun(d.session, DateTime.utc(2026, 5, 13, 8), minutes: 5);
      await seedRun(d.session, DateTime.utc(2026, 4, 22, 8), minutes: 25);
      await seedRun(d.session, DateTime.utc(2026, 4, 8, 8), minutes: 30);
      await openStats(d, tester);

      expect(find.byType(AppBar), findsNothing);
      expect(plain('progress_title'), 'Fortschritt');
      expect(plain('progress_week_title'), 'Kilometer pro Woche');
      expect(plain('progress_week_first'), 'KW 16');
      expect(
        tester.getSemantics(key('progress_title')).flagsCollection.isHeader,
        isTrue,
      );

      final label = barsLabel(tester);
      // Von der aktuellen Woche rückwärts: die Wochenwahl liefert die Summe.
      final heights = <double>[];
      String? week22;
      for (var back = 0; back < 8; back++) {
        final week = 23 - back;
        final runs = plain('stat_runs_value');
        final expected = runs == '0'
            ? '0,00 km'
            : distanceOf(plain('stat_distance_value'));
        final entry = back == 0
            ? 'KW $week (diese Woche, bisher): $expected'
            : 'KW $week: $expected';
        expect(label, contains(entry), reason: 'Woche $week');
        if (week == 22) week22 = expected;
        heights.add(tester.getSize(key('week_bar_${7 - back}')).height);
        expect(
          runs == '0',
          // KW 21, 19, 18, 16 haben keinen Lauf.
          {21, 19, 18, 16}.contains(week),
          reason: 'Woche $week',
        );
        await tester.tap(key('stat_prev'));
        await tester.pumpAndSettle();
      }
      // Leere Wochen nur als Nulllinie, volle Wochen höher.
      for (final (i, h) in heights.indexed) {
        final week = 23 - i;
        if ({21, 19, 18, 16}.contains(week)) {
          expect(h, ramuriWeekBarMinHeight, reason: 'leere Woche $week');
        } else {
          expect(h, greaterThan(ramuriWeekBarMinHeight), reason: 'Woche $week');
        }
      }
      // Genau acht Balken; KW 15 fehlt.
      expect(key('week_bar_7'), findsOneWidget);
      expect(label, isNot(contains('KW 15')));
      expect(label, contains('KW 16: 0,00 km'));
      // Fuß: letzte volle Woche (KW 22) mit ihrem Wert.
      expect(week22, isNot('0,00 km'));
      expect(plain('progress_week_last'), 'letzte: $week22');
      handle.dispose();
    });

    testWidgets('Meilen-Einstellung: Meilen in Überschrift und Werten', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = await started(tester);
      await d.session.settings.set(
        SettingKeys.distanceUnit,
        'mi',
        at: d.clock.now(),
      );
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 27, 8));
      await openStats(d, tester);
      expect(plain('progress_week_title'), 'Meilen pro Woche');
      final label = barsLabel(tester);
      expect(label, contains(' mi'));
      expect(label, isNot(contains(' km')));
      expect(plain('progress_week_last'), contains(' mi'));
      // Wert der Woche = Wochenstatistik (ebenfalls in Meilen).
      expect(label, contains(distanceOf(plain('stat_distance_value'))));
      handle.dispose();
    });

    testWidgets('Woche mit nur teilweise lesbaren Läufen: Hinweis; ohne '
        'lesbare Strecke: nicht verfügbar, nie 0', (tester) async {
      final handle = tester.ensureSemantics();
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      // KW 23: ein Lauf mit, einer ohne Strecke. KW 22: nur ohne Strecke.
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRunWithoutDistance(d.session, DateTime.utc(2026, 6, 2, 8));
      await seedRunWithoutDistance(d.session, DateTime.utc(2026, 5, 27, 8));
      await openStats(d, tester);
      final notes = find.descendant(
        of: key('progress_week_notes'),
        matching: find.byType(Text),
      );
      final texts = [for (final e in notes.evaluate()) (e.widget as Text).data];
      expect(texts, contains('KW 22: nicht verfügbar (keine Strecke gelesen)'));
      expect(texts, contains('KW 23: Aus 1 von 2 Läufen'));
      final label = barsLabel(tester);
      expect(label, contains('KW 22: nicht verfügbar (keine Strecke gelesen)'));
      expect(label, contains('KW 23 (diese Woche, bisher): '));
      expect(label, contains('(Aus 1 von 2 Läufen)'));
      expect(label, isNot(contains('KW 22: 0,00')));
      // Weg, den die Balken zeichnen: nicht verfügbar ist keine Nulllinie in
      // Balkenfarbe, sondern ein Strich in der Linienfarbe.
      final bar = tester.widget<Container>(key('week_bar_6'));
      expect(
        (bar.decoration! as BoxDecoration).color,
        RamuriColors.light.outlineStrong,
      );
      handle.dispose();
    });
  });

  group('VO₂max-Karte in der App', () {
    for (final (locale, stage, link) in [
      ('de', 'Qualitätsstufe: ausreichend', 'Wie wird das berechnet?'),
      ('en', 'Quality level: sufficient', 'How is this calculated?'),
    ]) {
      testWidgets('$locale: Stufentext der Karte = Erklärungsseite, Link '
          'öffnet die Erklärung', (tester) async {
        final d = await started(tester, locale: locale);
        d.clock.set(DateTime.utc(2026, 6, 3, 12));
        await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
        await d.session.values.createOriginals(
          const ValueOwner.day('2026-06-01'),
          [
            ComputedValue(
              key: vo2maxLongTermValueKey,
              value: 45.0,
              unit: 'ml/kg/min',
              computedAt: d.clock.now(),
              dataFrom: DateTime.utc(2026, 5, 1),
              dataTo: DateTime.utc(2026, 6, 1),
              measurementCount: 4,
              sources: const ['strap'],
              method: 'm',
              methodVersion: 1,
              parameterVersion: 1,
              quality: ValueQuality.sufficient,
            ),
          ],
        );
        await openStats(d, tester);
        expect(plain('progress_vo2_basis'), endsWith(stage));
        expect(find.text(link), findsOneWidget);
        expect(find.textContaining('±'), findsNothing);
        await tester.ensureVisible(key('progress_vo2_explain'));
        await tester.pumpAndSettle();
        await tester.tap(key('progress_vo2_explain'));
        await tester.pumpAndSettle();
        expect(key('expl_body'), findsOneWidget);
        expect(plain('expl_a5'), stage);
      });
    }
  });

  group('alle bisherigen Kennzahlen bleiben (FR-0043, FR-0057)', () {
    // Stand 5adab5c: die Schlüssel aus statistics_screen.dart,
    // statistics_view.dart und fitness_section.dart, die in den Lagen unten
    // (Woche mit Werten, `perScenario`) sichtbar sind. Nur in anderen Tests
    // stehen `stat_failed`, `stat_retry` (load_failure_test),
    // `stat_fitness_failed` (progress_cards_test) und `stat_vo2_zero_weight`
    // (statistics_test). Zeilen `id` haben dazu `id_value`.
    const rows = [
      'stat_runs',
      'stat_days',
      'stat_distance',
      'stat_moving',
      'stat_total',
      'stat_avg_pace',
      'stat_best_pace',
      'stat_laps',
      'stat_avg_hr',
      'stat_max_hr',
      'stat_trimp',
      'stat_delta_runs',
      'stat_delta_distance',
      'stat_delta_moving',
      'stat_vo2_run',
      'stat_vo2_current',
      'stat_efficiency',
    ];
    const others = [
      'stat_list',
      'stat_kind_week',
      'stat_kind_month',
      'stat_kind_custom',
      'stat_kind_run',
      'stat_prev',
      'stat_next',
      'stat_period_label',
      'stat_zones',
      'stat_compare',
      'stat_fitness',
      'stat_vo2_note',
      'stat_vo2_trend',
      'stat_vo2_trend_note',
      'stat_efficiency_note',
      'stat_explain_vo2_run',
      'stat_explain_vo2_current',
      'stat_explain_efficiency',
    ];
    // Je in einer eigenen Lage sichtbar.
    const perScenario = {
      'custom': ['stat_from', 'stat_to', 'stat_compare_only'],
      'run': ['stat_run_pick', 'stat_compare_only'],
      'pending': ['stat_pending', 'stat_vo2_trend_none'],
      'empty': ['stat_no_runs_at_all'],
    };

    Set<String> visible(Iterable<String> candidates) => {
      for (final c in candidates)
        if (key(c).evaluate().isNotEmpty) c,
    };

    testWidgets('Woche mit Lauf, Werten und Verlauf', (tester) async {
      final d = await started(tester);
      await d.session.profile.save(_profile);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 1, 8),
        minutes: 30,
      );
      await seedRun(d.session, DateTime.utc(2026, 5, 27, 8));
      await calc(d, id);
      await openStats(d, tester);
      final expected = {
        for (final r in rows) ...[r, '${r}_value'],
        ...others,
      };
      final missing = expected.difference(visible(expected));
      expect(missing, isEmpty);
      expect(
        visible(['stat_vo2_trend_${'2026-06-01'}']),
        isNotEmpty,
        reason: 'Verlaufszeile des Tages',
      );
    });

    testWidgets('freier Zeitraum, einzelner Lauf, ausstehende Berechnung, '
        'keine Läufe', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await openStats(d, tester);
      await choose(tester, 'custom');
      expect(visible(perScenario['custom']!), perScenario['custom']!.toSet());
      await choose(tester, 'run');
      expect(visible(perScenario['run']!), perScenario['run']!.toSet());
      expect(visible(perScenario['pending']!), perScenario['pending']!.toSet());
      await d.session.deleteRun(1);
      await openToday(tester);
      await openStats(d, tester);
      await choose(tester, 'run');
      expect(visible(perScenario['empty']!), perScenario['empty']!.toSet());
    });
  });

  group('Zustand beim Tab-Wechsel (AppShell)', () {
    testWidgets('Zeitraumart und Anker bleiben, Daten sind frisch', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 20, 8));
      await openStats(d, tester);
      await choose(tester, 'month');
      await tester.tap(key('stat_prev'));
      await tester.pumpAndSettle();
      expect(plain('stat_period_label'), 'Mai 2026');
      expect(plain('stat_runs_value'), '1');

      await openHistory(d, tester);
      // Zwischenzeitlich kommt ein Lauf im Mai dazu: nach dem Wechsel sichtbar.
      await seedRun(d.session, DateTime.utc(2026, 5, 22, 8));
      await openStats(d, tester);
      expect(plain('stat_period_label'), 'Mai 2026');
      expect(plain('stat_runs_value'), '2');

      await openToday(tester);
      await openStats(d, tester);
      expect(plain('stat_period_label'), 'Mai 2026');
    });

    testWidgets('ohne Wahl folgt der Zeitraum der Uhr (Wochenkarte und '
        'Balken), mit Wahl bleibt er', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12)); // KW 23
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 6, 19, 8)); // KW 25
      await openStats(d, tester);
      final first = plain('stat_period_label');
      await openHistory(d, tester);
      d.clock.set(DateTime.utc(2026, 6, 20, 12)); // KW 25
      await openStats(d, tester);
      expect(plain('stat_period_label'), isNot(first));
      expect(plain('stat_runs_value'), '1');
      expect(plain('progress_week_last'), isNotEmpty);

      // Mit Wahl (eine Woche zurück) bleibt der Zeitraum über Uhr und Tab.
      await tester.tap(key('stat_prev'));
      await tester.pumpAndSettle();
      final chosen = plain('stat_period_label');
      await openHistory(d, tester);
      d.clock.set(DateTime.utc(2026, 7, 8, 12));
      await openStats(d, tester);
      expect(plain('stat_period_label'), chosen);
    });

    testWidgets('freier Zeitraum ohne Wahl folgt der Uhr', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 10, 12));
      await openStats(d, tester);
      await choose(tester, 'custom');
      String from() =>
          ((key('stat_from').evaluate().single.widget as OutlinedButton).child!
                  as Text)
              .data!;
      final before = from();
      await openHistory(d, tester);
      d.clock.set(DateTime.utc(2026, 6, 20, 12));
      await openStats(d, tester);
      expect(from(), isNot(before));
    });

    group('freier Zeitraum: jede Wahl legt beide Enden fest', () {
      String label(String k) =>
          ((key(k).evaluate().single.widget as OutlinedButton).child! as Text)
              .data!
              .split(': ')
              .last;

      Future<void> pickDay(WidgetTester tester, String k, int day) async {
        await tester.tap(key(k));
        await tester.pumpAndSettle();
        await tester.tap(find.text('$day').last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      Future<Device> open(WidgetTester tester) async {
        final d = await started(tester);
        d.clock.set(DateTime.utc(2026, 6, 10, 12)); // von 4. bis 10. Juni
        await openStats(d, tester);
        await choose(tester, 'custom');
        return d;
      }

      for (final (name, later) in [
        ('Uhr vor', DateTime.utc(2026, 6, 20, 12)),
        ('Uhr zurück', DateTime.utc(2026, 6, 5, 12)),
      ]) {
        testWidgets('nur „bis“ gewählt, $name: Enden bleiben, kein Absturz', (
          tester,
        ) async {
          final d = await open(tester);
          final from = label('stat_from');
          await pickDay(tester, 'stat_to', 10);
          final to = label('stat_to');
          await openHistory(d, tester);
          d.clock.set(later);
          await openStats(d, tester);
          expect(tester.takeException(), isNull);
          expect(label('stat_from'), from);
          expect(label('stat_to'), to);
        });

        testWidgets('nur „von“ gewählt, $name: Enden bleiben, kein Absturz', (
          tester,
        ) async {
          final d = await open(tester);
          final to = label('stat_to');
          await pickDay(tester, 'stat_from', 8);
          final from = label('stat_from');
          await openHistory(d, tester);
          d.clock.set(later);
          await openStats(d, tester);
          expect(tester.takeException(), isNull);
          expect(label('stat_from'), from);
          expect(label('stat_to'), to);
        });
      }

      testWidgets('„bis“ vor „von“ gewählt: „von“ zieht mit, keine Ausnahme', (
        tester,
      ) async {
        await open(tester);
        await pickDay(tester, 'stat_to', 2);
        expect(tester.takeException(), isNull);
        expect(label('stat_from'), contains('2. Juni'));
        expect(label('stat_to'), contains('2. Juni'));
      });

      testWidgets('„von“ nach „bis“ gewählt: „bis“ zieht mit, keine Ausnahme', (
        tester,
      ) async {
        await open(tester);
        await pickDay(tester, 'stat_from', 15);
        expect(tester.takeException(), isNull);
        expect(label('stat_from'), contains('15. Juni'));
        expect(label('stat_to'), contains('15. Juni'));
      });

      for (final (name, k) in [('von', 'stat_from'), ('bis', 'stat_to')]) {
        testWidgets('Dialog „$name“ abgebrochen, Uhr vor: beide Enden folgen '
            'weiter der Uhr', (tester) async {
          final d = await open(tester);
          final from = label('stat_from');
          final to = label('stat_to');
          await tester.tap(key(k));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Abbrechen'));
          await tester.pumpAndSettle();
          expect(label('stat_from'), from);
          expect(label('stat_to'), to);
          await openHistory(d, tester);
          d.clock.set(DateTime.utc(2026, 6, 20, 12));
          await openStats(d, tester);
          expect(tester.takeException(), isNull);
          expect(label('stat_from'), isNot(from));
          expect(label('stat_to'), contains('20. Juni'));
        });
      }
    });

    testWidgets('Datenmeldung (changes.revision): Zeitraum und Lage bleiben, '
        'Läufe frisch', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 20, 8));
      await openStats(d, tester);
      await choose(tester, 'month');
      await tester.tap(key('stat_prev'));
      await tester.pumpAndSettle();
      // Erst jetzt schmal: Die Chips lägen sonst unter der Navigationsleiste.
      tester.view.physicalSize = const Size(411, 914);
      await tester.pumpAndSettle();
      await tester.drag(key('stat_list'), const Offset(0, -500));
      await tester.pumpAndSettle();
      final offset = position(tester).pixels;
      expect(offset, greaterThan(300));
      expect(plain('stat_runs_value'), '1');

      await seedRun(d.session, DateTime.utc(2026, 5, 22, 8));
      final shell = tester.widget<AppShell>(find.byType(AppShell));
      final before = shell.changes.revision;
      shell.changes.changed();
      await tester.pumpAndSettle();
      expect(shell.changes.revision, before + 1);
      expect(plain('stat_period_label'), 'Mai 2026');
      expect(plain('stat_runs_value'), '2');
      expect(position(tester).pixels, closeTo(offset, 0.5));
    });

    testWidgets('freier Zeitraum bleibt', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 10, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 2, 8));
      await openStats(d, tester);
      await choose(tester, 'custom');
      final before =
          (key('stat_from').evaluate().single.widget as OutlinedButton).child!;
      await openHistory(d, tester);
      await openStats(d, tester);
      expect(key('stat_from'), findsOneWidget);
      expect(
        ((key('stat_from').evaluate().single.widget as OutlinedButton).child!
                as Text)
            .data,
        (before as Text).data,
      );
    });

    testWidgets('Scrollposition bleibt', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      tester.view.physicalSize = const Size(411, 914);
      await openStats(d, tester);
      await tester.drag(key('stat_list'), const Offset(0, -700));
      await tester.pumpAndSettle();
      final offset = position(tester).pixels;
      expect(offset, greaterThan(500));
      await openHistory(d, tester);
      await openStats(d, tester);
      expect(position(tester).pixels, closeTo(offset, 0.5));
    });

    Future<void> shortFirstFrame(
      WidgetTester tester, {
      required bool userScrolls,
    }) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      // Zwölf Wochenwerte des Verlaufs machen die Seite lang; sie gehören
      // keinem Datenzeitraum und fallen mit dem Lauf weg.
      for (var w = 0; w < 12; w++) {
        final day = isoDay(DateTime.utc(2026, 3, 16 + 7 * w));
        await d.session.values.createOriginals(ValueOwner.day(day), [
          ComputedValue(
            key: vo2maxLongTermValueKey,
            value: 40.0 + w,
            unit: 'u',
            computedAt: d.clock.now(),
            measurementCount: 1,
            sources: const ['strap'],
            method: 'm',
            methodVersion: 1,
            parameterVersion: 1,
            quality: ValueQuality.good,
          ),
        ]);
      }
      tester.view.physicalSize = const Size(411, 914);
      await openStats(d, tester);
      await tester.drag(key('stat_list'), const Offset(0, -9000));
      await tester.pumpAndSettle();
      await tester.drag(key('stat_list'), const Offset(0, 390));
      await tester.pumpAndSettle();
      // 390 statt 300: Mit dem Lauf nennt die Karte dessen unbewertete Einheit
      // (eine Zeile mehr); ohne ihn ist die Seite etwas kürzer. Die Position
      // muss zwischen dem ersten Bild und dem geladenen Ende liegen.
      final before = position(tester).pixels;
      expect(before, greaterThan(500));
      await openHistory(d, tester);
      await d.session.deleteRun(id);
      // Das erste Bild nach dem Öffnen: die Karte Belastung zeigt noch
      // „wird berechnet“; der Scrollbereich klemmt die gemerkte Position auf
      // sein Ende.
      await tester.tap(key('home_statistics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final first = position(tester);
      final clamped = first.maxScrollExtent;
      expect(clamped, lessThan(before), reason: 'erstes Bild kürzer');
      expect(first.pixels, clamped, reason: 'aufs Ende des ersten Bilds');
      double? userEnd;
      if (userScrolls) {
        // Der Nutzer scrollt, solange die Karte noch lädt.
        await tester.drag(key('stat_list'), const Offset(0, 40));
        userEnd = position(tester).pixels;
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final pos = position(tester);
      if (userScrolls) {
        // Das Wiederherstellen überschreibt die Eingabe nicht.
        expect(userEnd, lessThan(clamped));
        expect(pos.pixels, userEnd);
        return;
      }
      // Die Karte lädt danach und macht die Seite länger: die gemerkte
      // Position wird exakt wieder angesteuert (nicht am geklemmten Wert).
      expect(pos.maxScrollExtent, greaterThan(clamped));
      expect(pos.maxScrollExtent, greaterThan(before));
      expect(pos.pixels, before);
    }

    testWidgets(
      'Scrollposition hinter dem kürzeren ersten Bild: nach dem Laden '
      'der Karte exakt wieder da, keine Ausnahme',
      (tester) => shortFirstFrame(tester, userScrolls: false),
    );

    testWidgets(
      'Scrollen des Nutzers während die Karte lädt wird nicht überschrieben',
      (tester) => shortFirstFrame(tester, userScrolls: true),
    );

    testWidgets('gemerkter Lauf inzwischen gelöscht: neuester Lauf, kein '
        'Absturz', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final older = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      final newer = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 3, 8),
        minutes: 20,
      );
      await openStats(d, tester);
      await choose(tester, 'run');
      await tester.tap(key('stat_run_pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownMenuItem<int>).last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<int>>(key('stat_run_pick')).value,
        older,
      );
      await openHistory(d, tester);
      await d.session.deleteRun(older);
      await openStats(d, tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<DropdownButton<int>>(key('stat_run_pick')).value,
        newer,
      );
      expect(plain('stat_runs_value'), '1');
    });

    testWidgets('StatisticsScreen mit und ohne Zustandsobjekt', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final older = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      final newer = await seedRun(d.session, DateTime.utc(2026, 6, 3, 8));
      tester.view.physicalSize = const Size(411, 914);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> open(StatisticsViewState? state) async {
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => StatisticsScreen(
              session: d.session,
              clock: d.clock,
              viewState: state,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> close() async {
        nav.pop();
        await tester.pumpAndSettle();
      }

      // Ohne Objekt: arbeitet für sich, ein zweiter Aufbau beginnt neu.
      await open(null);
      await choose(tester, 'month');
      expect(plain('stat_period_label'), 'Juni 2026');
      await close();
      await open(null);
      expect(plain('stat_period_label'), contains('1.'));
      await close();

      // Mit Objekt: gemerkter Lauf (hier ein nie vergebener) und eine
      // Scrollposition weit hinter dem Inhalt; beides wird abgefangen, und die
      // Seite schreibt ihre Wahl ins Objekt.
      final state = StatisticsViewState()
        ..kind = StatisticsKind.run
        ..runId = 987654
        ..scrollOffset = 100000;
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => StatisticsScreen(
            session: d.session,
            clock: d.clock,
            viewState: state,
          ),
        ),
      );
      // Das erste Bild mit Inhalt: Die Position liegt schon auf dem Ende,
      // sie läuft nicht erst von dahinter zurück.
      for (var i = 0; i < 200 && key('stat_list').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(position(tester).pixels, position(tester).maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<DropdownButton<int>>(key('stat_run_pick')).value,
        newer,
      );
      final pos = position(tester);
      expect(pos.pixels, pos.maxScrollExtent);
      expect(older, isNot(newer));
      await tester.ensureVisible(key('stat_run_pick'));
      await tester.pumpAndSettle();
      await tester.tap(key('stat_run_pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownMenuItem<int>).last);
      await tester.pumpAndSettle();
      expect(state.runId, older);
      expect(state.scrollOffset, closeTo(position(tester).pixels, 0.5));
      await tester.ensureVisible(key('stat_kind_week'));
      await tester.pumpAndSettle();
      await choose(tester, 'week');
      expect(state.kind, StatisticsKind.week);
    });
  });

  group('hell und dunkel', () {
    for (final b in Brightness.values) {
      testWidgets('${b.name}: Seite ohne Ausnahme, Karten in Themefarben', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final d = await started(tester);
        await d.session.profile.save(_profile);
        d.clock.set(DateTime.utc(2026, 6, 3, 12));
        final id = await seedRun(
          d.session,
          DateTime.utc(2026, 6, 1, 8),
          minutes: 30,
        );
        await calc(d, id);
        tester.view.physicalSize = const Size(411, 914);
        await openStats(d, tester);
        final colors = b == Brightness.light
            ? RamuriColors.light
            : RamuriColors.night;
        Color? cardColor(Finder card) => tester
            .widget<Material>(
              find.descendant(of: card, matching: find.byType(Material)).first,
            )
            .color;
        expect(cardColor(find.byType(WeekDistanceCard)), colors.surface);
        expect(cardColor(find.byType(Vo2ProgressCard)), colors.panel);
        expect(cardColor(find.byType(EfficiencyCard)), colors.surface);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
