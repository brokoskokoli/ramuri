import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'history_summary_test.dart'
    show key, openHistory, seedRun, started, text;

const ProfileRecord _profile = ProfileRecord(
  maxHeartRateBpm: 190,
  restingHeartRateBpm: 60,
);

Future<void> openStats(Device d, WidgetTester tester) async {
  await tester.tap(key('home_statistics'));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String kind) async {
  await tester.ensureVisible(key('stat_kind_$kind'));
  await tester.tap(key('stat_kind_$kind'));
  await tester.pumpAndSettle();
}

Future<void> calc(Device d, int runId) => ValueCalculationService(
  session: d.session,
  clock: d.clock,
).calculateAfterRun(runId);

/// Zahl vor " km" aus einem deutschen Text wie `5,40 km`.
double km(String text) => double.parse(
  RegExp(r'([\d,]+) km').firstMatch(text)!.group(1)!.replaceAll(',', '.'),
);

void main() {
  group('Zeiträume (FR-0043, FR-0044)', () {
    testWidgets('Woche: Summe der Läufe in der Historie = Wochenstatistik', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final a = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      final b = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 3, 8),
        minutes: 20,
      );
      // Später im Monat, aber nicht in der Woche; und die Vorwoche (Mittwoch
      // 27. Mai): beide zählen nicht zur Woche.
      await seedRun(d.session, DateTime.utc(2026, 6, 20, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 27, 8));
      await openHistory(d, tester);
      final sum =
          km(text('history_distance_$a')) + km(text('history_distance_$b'));
      await openStats(d, tester);
      expect(text('stat_runs_value'), '2');
      expect(text('stat_days_value'), '2');
      expect(km(text('stat_distance_value')), closeTo(sum, 0.011));
      expect(km(text('stat_distance_value')), closeTo(5.4, 0.02));
      // Entwicklung gegenüber der Vorwoche (1 Lauf, 1,8 km).
      expect(text('stat_delta_runs_value'), '+1');
      expect(text('stat_delta_distance_value'), matches(r'^\+3,[56]\d km$'));
    });

    testWidgets('Woche: vor und zurück, Wochenbeginn Montag', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 31, 22));
      await openStats(d, tester);
      // Montag 1. Juni gehört zu dieser Woche, Sonntag 31. Mai zur vorigen.
      expect(text('stat_runs_value'), '1');
      expect(text('stat_period_label'), contains('1.'));
      await tester.tap(key('stat_prev'));
      await tester.pumpAndSettle();
      expect(text('stat_runs_value'), '1');
      expect(text('stat_period_label'), contains('Mai'));
      await tester.tap(key('stat_next'));
      await tester.pumpAndSettle();
      expect(text('stat_period_label'), contains('Juni'));
    });

    testWidgets('Monat', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 6, 28, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 27, 8));
      await openStats(d, tester);
      await choose(tester, 'month');
      expect(text('stat_period_label'), 'Juni 2026');
      expect(text('stat_runs_value'), '2');
      expect(text('stat_delta_runs_value'), '+1');
      await tester.tap(key('stat_prev'));
      await tester.pumpAndSettle();
      expect(text('stat_period_label'), 'Mai 2026');
      expect(text('stat_runs_value'), '1');
    });

    testWidgets('freier Zeitraum über den Jahreswechsel', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 1, 4, 12));
      await seedRun(d.session, DateTime.utc(2025, 12, 31, 8));
      await seedRun(d.session, DateTime.utc(2026, 1, 2, 8));
      // Außerhalb (vor dem 29. Dezember).
      await seedRun(d.session, DateTime.utc(2025, 12, 20, 8));
      await openStats(d, tester);
      await choose(tester, 'custom');
      expect(text('stat_runs_value'), '2');
      expect(text('stat_days_value'), '2');
      expect(km(text('stat_distance_value')), closeTo(3.6, 0.02));
      expect(find.byKey(const Key('stat_compare_only')), findsOneWidget);
    });

    testWidgets('freier Zeitraum: Beginn per Datumsauswahl', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 10, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 2, 8));
      await seedRun(d.session, DateTime.utc(2026, 6, 8, 8));
      await seedRun(d.session, DateTime.utc(2026, 5, 30, 8));
      await openStats(d, tester);
      await choose(tester, 'custom');
      // Standard: die letzten sieben Tage (4. bis 10. Juni).
      expect(text('stat_runs_value'), '1');
      await tester.tap(key('stat_from'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('2'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(text('stat_runs_value'), '2');
      expect(
        (key('stat_from').evaluate().single.widget as OutlinedButton).child,
        isA<Text>().having((t) => t.data, 'Text', contains('2')),
      );
    });

    testWidgets('einzelner Lauf: Bestpace, Runden, Wechsel des Laufs', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await seedRun(d.session, DateTime.utc(2026, 6, 3, 8), minutes: 20);
      await openStats(d, tester);
      await choose(tester, 'run');
      // Vorgewählt: der neueste Lauf (20 min, 3,6 km).
      expect(text('stat_runs_value'), '1');
      expect(km(text('stat_distance_value')), closeTo(3.6, 0.02));
      expect(text('stat_best_pace_value'), matches(r'^\d+:\d\d min/km$'));
      expect(text('stat_laps_value'), '0');
      await tester.tap(key('stat_run_pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownMenuItem<int>).last);
      await tester.pumpAndSettle();
      expect(km(text('stat_distance_value')), closeTo(1.8, 0.02));
      expect(find.byKey(const Key('stat_compare_only')), findsOneWidget);
    });

    testWidgets('Woche, Monat, frei: Bestpace und Runden aus der Kurzfassung '
        '(schnellster Lauf, Summe der Runden)', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final slowStart = DateTime.utc(2026, 6, 1, 8);
      final fastStart = DateTime.utc(2026, 6, 2, 8);
      final slow = await seedRun(d.session, slowStart);
      final fast = await seedRun(d.session, fastStart, speed: 4.0);
      for (final (id, start, n) in [
        (slow, slowStart, 2),
        (fast, fastStart, 1),
      ]) {
        for (var i = 1; i <= n; i++) {
          await d.session.markers.addLap(
            id,
            StoredLap(
              index: i,
              markedAt: start.add(Duration(minutes: i)),
              lapTime: const Duration(minutes: 1),
            ),
          );
        }
      }
      await openStats(d, tester);
      for (final kind in ['week', 'month', 'custom']) {
        await choose(tester, kind);
        expect(text('stat_runs_value'), '2', reason: kind);
        // 4 m/s = 4:10 min/km, der schnellere der beiden Läufe.
        expect(text('stat_best_pace_value'), '4:10 min/km', reason: kind);
        expect(text('stat_laps_value'), '3', reason: kind);
      }
    });

    testWidgets('ohne Läufe: nicht verfügbar statt 0 km', (tester) async {
      final d = await started(tester);
      await openStats(d, tester);
      expect(text('stat_runs_value'), '0');
      expect(text('stat_distance_value'), contains('keine Läufe im Zeitraum'));
      expect(text('stat_avg_pace_value'), contains('keine Läufe im Zeitraum'));
      expect(text('stat_vo2_run_value'), contains('kein Lauf im Zeitraum'));
      expect(text('stat_vo2_current_value'), contains('nicht verfügbar'));
      await choose(tester, 'run');
      expect(find.byKey(const Key('stat_no_runs_at_all')), findsOneWidget);
    });

    testWidgets('Englisch', (tester) async {
      final d = await started(tester, locale: 'en');
      await openStats(d, tester);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Single run'), findsOneWidget);
      expect(find.textContaining('Week from'), findsOneWidget);
    });
  });

  group('Datenlage (FR-0055)', () {
    testWidgets('Lauf ohne Puls: nicht als 0, Grund sichtbar', (tester) async {
      final d = await started(tester);
      await d.session.profile.save(_profile);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 1, 8),
        bpm: null,
      );
      await calc(d, id);
      await openStats(d, tester);
      expect(text('stat_avg_hr_value'), contains('kein Puls'));
      expect(text('stat_max_hr_value'), contains('kein Puls'));
      expect(text('stat_zones_value'), contains('nicht verfügbar'));
      expect(text('stat_trimp_value'), contains('nicht verfügbar'));
      expect(text('stat_vo2_run_value'), isNot(contains('ml/kg/min')));
      expect(text('stat_vo2_run_value'), contains('kein Puls'));
      expect(key('stat_vo2_trend_none'), findsOneWidget);
      // Die Grundstatistik steht trotzdem.
      expect(km(text('stat_distance_value')), closeTo(1.8, 0.02));
    });

    testWidgets('ohne Profil: Grundstatistik, Hinweis auf das Profil', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await calc(d, id);
      await openStats(d, tester);
      expect(km(text('stat_distance_value')), closeTo(1.8, 0.02));
      expect(text('stat_avg_hr_value'), '150 bpm');
      expect(text('stat_zones_value'), contains('im Profil'));
      expect(text('stat_trimp_value'), contains('im Profil'));
      expect(text('stat_vo2_run_value'), contains('im Profil'));
      expect(text('stat_vo2_run_value'), isNot(contains('ml/kg/min')));
    });

    testWidgets('Lauf ohne gespeicherte Werte: Berechnung steht aus', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await openStats(d, tester);
      expect(text('stat_pending'), contains('noch aus'));
      expect(text('stat_zones_value'), contains('nicht gespeichert'));
      expect(text('stat_vo2_run_value'), contains('nicht verfügbar'));
    });
  });

  group('Fitness (FR-0081, FR-0084, FR-0088, FR-0067)', () {
    Future<Device> withEstimate(WidgetTester tester) async {
      final d = await started(tester);
      await d.session.profile.save(_profile);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 1, 8),
        minutes: 30,
      );
      await calc(d, id);
      await openStats(d, tester);
      return d;
    }

    testWidgets('drei getrennte, benannte Sichten, jede als Schätzung', (
      tester,
    ) async {
      await withEstimate(tester);
      expect(find.text('VO₂max-Schätzung aus einem Lauf'), findsOneWidget);
      // Einmal in der VO₂max-Karte (WP15), einmal in der Fitnessgruppe.
      expect(
        find.text('Aktuelle langfristige VO₂max-Schätzung'),
        findsNWidgets(2),
      );
      expect(find.text('Verlauf der VO₂max-Schätzung'), findsWidgets);
      final estimate = RegExp(r'\d+,\d ml/kg/min \(Schätzung\)');
      expect(
        text('stat_vo2_run_value'),
        matches(RegExp('^Lauf vom .*: ${estimate.pattern}\$')),
      );
      expect(text('stat_vo2_current_value'), startsWith('Stand '));
      expect(text('stat_vo2_current_value'), matches(RegExp(estimate.pattern)));
      final trend = tester.widget<Column>(key('stat_vo2_trend'));
      final rows = trend.children.whereType<Text>().map((t) => t.data!);
      expect(rows.where((t) => estimate.hasMatch(t)), hasLength(1));
      expect(text('stat_vo2_note'), contains('keine Messung'));
    });

    testWidgets('aerobe Effizienz: Wert oder Grund, Abgrenzung zur VO₂max', (
      tester,
    ) async {
      await withEstimate(tester);
      // Ein Lauf reicht für keine Veränderung: Grund statt Wert.
      expect(text('stat_efficiency_value'), contains('nicht verfügbar'));
      expect(
        text('stat_efficiency_note'),
        contains('Keine Messung der VO₂max'),
      );
      expect(
        text('stat_efficiency_note'),
        contains('keine Änderung der VO₂max'),
      );
      // Die Effizienz erscheint nicht als VO₂max-Wert.
      expect(text('stat_efficiency_value'), isNot(contains('ml/kg/min')));
    });

    ComputedValue stored(String key, double? v, String unit, DateTime at) =>
        ComputedValue(
          key: key,
          value: v,
          unit: unit,
          unavailableReason: v == null
              ? UnavailableReason.insufficientData
              : null,
          computedAt: at,
          measurementCount: 1,
          sources: const ['strap'],
          method: 'm',
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.good,
        );

    for (final (value, shown) in [(2.5, '+2,5'), (-3.4, '\u22123,4')]) {
      testWidgets('gespeicherte aerobe Effizienz $shown: Vorzeichen, %, Datum, '
          'keine VO₂max-Einheit', (tester) async {
        final d = await started(tester);
        d.clock.set(DateTime.utc(2026, 6, 3, 12));
        await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
        await d.session.values.createOriginals(
          const ValueOwner.day('2026-06-01'),
          [stored(aerobicEfficiencyValueKey, value, '%', d.clock.now())],
        );
        await openStats(d, tester);
        final eff = text('stat_efficiency_value');
        expect(eff, startsWith('$shown % gegenüber dem Vergleichszeitraum'));
        expect(eff, contains('Schätzung'));
        expect(eff, contains('Stand Mo., 1. Juni 2026'));
        expect(eff, isNot(contains('ml/kg/min')));
      });
    }

    for (final (locale, vo2, eff) in [
      ('de', 'Stand Mo., 3. Juni 2024: 46,0', 'Stand Mo., 3. Juni 2024)'),
      ('en', 'As of Mon, Jun 3, 2024: 46.0', 'as of Mon, Jun 3, 2024)'),
    ]) {
      testWidgets('$locale: Stand der Sektion nennt das Jahr '
          '(FR-0059)', (tester) async {
        final d = await started(tester, locale: locale);
        d.clock.set(DateTime.utc(2024, 6, 4, 12));
        await seedRun(d.session, DateTime.utc(2024, 6, 3, 8));
        await d.session.values.createOriginals(
          const ValueOwner.day('2024-06-03'),
          [
            stored(vo2maxLongTermValueKey, 46.04, 'ml/kg/min', d.clock.now()),
            stored(aerobicEfficiencyValueKey, 2.5, '%', d.clock.now()),
          ],
        );
        await openStats(d, tester);
        expect(text('stat_vo2_current_value'), contains(vo2));
        expect(text('stat_efficiency_value'), contains(eff));
      });
    }

    testWidgets('Sicht 1: der neueste Lauf im Zeitraum, nicht der erste', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 4, 12));
      final older = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      final newer = await seedRun(d.session, DateTime.utc(2026, 6, 3, 8));
      for (final (id, v) in [(older, 41.0), (newer, 47.0)]) {
        await d.session.values.createOriginals(ValueOwner.run(id), [
          stored(vo2maxRunValueKey, v, vo2maxUnit, d.clock.now()),
        ]);
      }
      await openStats(d, tester);
      expect(text('stat_runs_value'), '2');
      expect(
        text('stat_vo2_run_value'),
        'Lauf vom Mi., 3. Juni: 47,0 ml/kg/min (Schätzung)',
      );
    });

    testWidgets('Sicht 3: Verlauf über Wochen aus den Tageswerten, nicht aus '
        'den Laufschätzungen', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 20, 12));
      final id = await seedRun(d.session, DateTime.utc(2026, 6, 18, 8));
      // Eine Laufschätzung, die im Verlauf nicht auftauchen darf.
      await d.session.values.createOriginals(ValueOwner.run(id), [
        stored(vo2maxRunValueKey, 99, vo2maxUnit, d.clock.now()),
      ]);
      // Tageswerte über vier Wochen (Montag 1., 8., 15. Juni; Wochenbeginn
      // Montag): je Woche zählt der letzte Tag mit Wert.
      for (final (day, v) in [
        ('2026-06-01', 40.0),
        ('2026-06-03', 40.5),
        ('2026-06-07', 41.0), // Sonntag, gleiche Woche wie der 1.
        ('2026-06-09', 42.0),
        ('2026-06-16', 43.0),
        ('2026-06-17', null), // nicht bestimmbar: nicht der Wochenwert
      ]) {
        await d.session.values.createOriginals(ValueOwner.day(day), [
          stored(vo2maxLongTermValueKey, v, vo2maxUnit, d.clock.now()),
        ]);
      }
      await openStats(d, tester);
      final rows = tester
          .widget<Column>(key('stat_vo2_trend'))
          .children
          .whereType<Text>()
          .map((t) => t.data!)
          .where((t) => t.contains('ml/kg/min'))
          .toList();
      expect(rows, [
        'So., 7. Juni: 41,0 ml/kg/min (Schätzung)',
        'Di., 9. Juni: 42,0 ml/kg/min (Schätzung)',
        'Di., 16. Juni: 43,0 ml/kg/min (Schätzung)',
      ]);
      // Sicht 1 zeigt die Laufschätzung, der Verlauf nicht.
      expect(text('stat_vo2_run_value'), contains('99,0'));
      expect(rows.where((t) => t.contains('99,0')), isEmpty);
      expect(key('stat_vo2_trend_note'), findsOneWidget);
    });

    testWidgets('Gewicht-0-Abschnitt: Hinweis zur Schätzung', (tester) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await d.session.values.createOriginals(ValueOwner.run(id), [
        ComputedValue(
          key: vo2maxRunValueKey,
          value: 45,
          unit: vo2maxUnit,
          computedAt: d.clock.now(),
          measurementCount: 1,
          sources: const ['strap'],
          method: 'm',
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.good,
          sections: [
            ValueSection(
              start: DateTime.utc(2026, 6, 1, 8),
              end: DateTime.utc(2026, 6, 1, 8, 5),
              weight: 0,
              lateFactor: 0,
              status: SectionStatus.eligible,
              discard: EstimateDiscard.zeroWeight,
            ),
          ],
        ),
      ]);
      await openStats(d, tester);
      expect(
        text('stat_vo2_run_value'),
        endsWith('45,0 ml/kg/min (Schätzung)'),
      );
      expect(key('stat_vo2_zero_weight'), findsOneWidget);
    });

    testWidgets('Einstieg zur Erklärung ist vorhanden', (tester) async {
      await withEstimate(tester);
      for (final id in [
        'stat_explain_vo2_run',
        'stat_explain_vo2_current',
        'stat_explain_efficiency',
      ]) {
        expect(key(id), findsOneWidget);
      }
      // Der Kopf der Seite (Wochenbalken, VO₂max) schiebt die Fitness-Details
      // unter den Rand von 2400 px: erst in Sicht bringen, dann tippen.
      await tester.ensureVisible(key('stat_explain_vo2_current'));
      await tester.pumpAndSettle();
      await tester.tap(key('stat_explain_vo2_current'));
      await tester.pumpAndSettle();
      expect(key('expl_body'), findsOneWidget);
    });

    testWidgets('keine persönlichen Bestzeiten, keine späteren Kennzahlen', (
      tester,
    ) async {
      await withEstimate(tester);
      for (final word in ['Bestzeit', 'Prognose', 'Readiness']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  group('Bedienung', () {
    testWidgets('große Schrift (2,0): alle Zeiträume ohne Überlauf', (
      tester,
    ) async {
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
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openStats(d, tester);
      final scrollable = find.descendant(
        of: key('stat_list'),
        matching: find.byType(Scrollable),
      );
      for (final kind in ['week', 'month', 'custom', 'run']) {
        await tester.scrollUntilVisible(
          key('stat_kind_$kind'),
          -300,
          scrollable: scrollable,
        );
        await choose(tester, kind);
        await tester.scrollUntilVisible(
          key('stat_efficiency_note'),
          300,
          scrollable: scrollable,
        );
        expect(tester.takeException(), isNull, reason: kind);
        expect(key('stat_efficiency_note'), findsOneWidget, reason: kind);
      }
    });

    testWidgets('Semantics: Zeile als Einheit, Überschrift, Schätzung', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = await started(tester);
      await d.session.profile.save(_profile);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(
        d.session,
        DateTime.utc(2026, 6, 1, 8),
        minutes: 30,
      );
      await calc(d, id);
      await openStats(d, tester);
      final row = tester.getSemantics(key('stat_distance'));
      expect(row.label, allOf(contains('Strecke'), contains('km')));
      final vo2 = tester.getSemantics(key('stat_vo2_run'));
      expect(vo2.label, allOf(contains('VO₂max'), contains('Schätzung')));
      expect(
        tester.getSemantics(find.text('Fitness')).flagsCollection.isHeader,
        isTrue,
      );
      handle.dispose();
    });
  });
}
