import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/app_shell.dart';
import 'package:running_app/features/home/data_changes.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/features/statistics/prediction_card.dart';
import 'package:running_app/features/statistics/prediction_controller.dart';
import 'package:running_app/features/statistics/progress_header.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart' show Device;
import 'history_summary_test.dart' show key, seedRun, started;
import 'statistics_test.dart' show openStats;

/// Karte „Prognose“ auf Fortschritt (WP20 Teil C): Anzeige je Stufe, Eintragen,
/// Löschen, Vorschlag bestätigen und ablehnen, Layout.

final DateTime _now = DateTime.utc(2026, 6, 10, 12);

PredictionStore _store(Device d) => (d.session as PredictionStorage).prediction;

Future<int> addRef(
  Device d,
  ReferenceKind kind,
  double meters,
  double seconds, {
  int daysAgo = 20,
  String? runId,
}) {
  final n = d.clock.now().toLocal();
  return _store(d).addReference(
    ReferencePerformance(
      kind: kind,
      distanceMeters: meters,
      seconds: seconds,
      date: DateTime(n.year, n.month, n.day - daysAgo),
      createdAt: d.clock.now(),
      runId: runId,
    ),
  );
}

Future<Device> boot(WidgetTester tester) async {
  final d = await started(tester);
  d.clock.set(_now);
  return d;
}

DateTime _at(int daysAgo, [int hour = 8]) =>
    DateTime.utc(2026, 6, 10, hour).subtract(Duration(days: daysAgo));

/// Je rollender Woche der letzten [weeks] zwei kurze Läufe.
Future<void> regularRuns(Device d, {int weeks = 8}) async {
  for (var w = 0; w < weeks; w++) {
    await seedRun(d.session, _at(7 * w + 1));
    await seedRun(d.session, _at(7 * w + 3));
  }
}

Future<void> pumpCard(
  WidgetTester tester,
  Device d, {
  String locale = 'de',
  double width = 411,
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool vo2 = false,
  DataChanges? changes,
  DistanceUnit unit = DistanceUnit.kilometers,
}) async {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final settings = await AppSettings.load(d.session.settings, d.clock);
  if (unit == DistanceUnit.miles) await settings.setDistanceUnit(unit);
  final holder = AppSettingsHolder()..attach(settings);
  await tester.pumpWidget(
    OffloadScope(
      offload: inlineOffload,
      child: AppSettingsScope(
        holder: holder,
        child: MaterialApp(
          theme: brightness == Brightness.light
              ? RamuriTheme.light
              : RamuriTheme.dark,
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PredictionCard(
                session: d.session,
                clock: d.clock,
                hasVo2maxEstimate: vo2,
                changes: changes,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String txt(String k) {
  final t = key(k).evaluate().single.widget as Text;
  return t.textSpan?.toPlainText() ?? t.data!;
}

/// Alle Texte der Karte, zusammengefügt.
String cardText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: key('prediction_card'), matching: find.byType(Text)),
    )
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');

Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

void main() {
  group('Anzeige je Stufe', () {
    testWidgets('ohne Referenz: Grund statt Zeit, Kopf als allgemeine '
        'Schätzung', (tester) async {
      final d = await boot(tester);
      await pumpCard(tester, d);
      expect(txt('prediction_subtitle'), contains('unabhängig von einem Ziel'));
      expect(
        txt('prediction_reason'),
        'Nicht bestimmbar: Es ist keine Referenzleistung eingetragen.',
      );
      expect(txt('prediction_reference'), 'Keine Referenz eingetragen.');
      for (var i = 0; i < 4; i++) {
        expect(txt('prediction_value_$i'), 'nicht bestimmbar');
      }
      final all = cardText(tester);
      expect(all, isNot(contains('≈')));
      expect(all, isNot(contains('%')));
      expect(key('prediction_test_hint'), findsNothing);
    });

    testWidgets('VO₂max allein: keine Zeit, nur der Grund', (tester) async {
      final d = await boot(tester);
      await pumpCard(tester, d, vo2: true);
      expect(txt('prediction_reason'), contains('VO₂max'));
      for (var i = 0; i < 4; i++) {
        expect(txt('prediction_value_$i'), 'nicht bestimmbar');
      }
      expect(cardText(tester), isNot(contains('≈')));
    });

    testWidgets('vorläufig: Zeiten auf die Minute, Stufe mit Grund, Referenz '
        'sichtbar', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      await pumpCard(tester, d);
      expect(txt('prediction_value_0'), '≈ 24 min');
      expect(txt('prediction_value_1'), '≈ 50 min');
      expect(txt('prediction_value_2'), '≈ 1 h 50 min');
      expect(txt('prediction_value_3'), '≈ 3 h 50 min');
      for (var i = 0; i < 4; i++) {
        expect(txt('prediction_level_$i'), startsWith('vorläufig: '));
      }
      expect(txt('prediction_level_1'), contains('regelmäßige Läufe'));
      expect(
        txt('prediction_reference'),
        'Grundlage: Wettkampfzeit, 10,00 km in 50:00, 31. Mai 2026',
      );
      expect(key('prediction_reason'), findsNothing);
    });

    testWidgets('ausreichend: regelmäßig gelaufen, Marathon bleibt vorläufig', (
      tester,
    ) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000);
      await regularRuns(d);
      await pumpCard(tester, d);
      for (var i = 0; i < 3; i++) {
        expect(txt('prediction_level_$i'), startsWith('ausreichend: '));
      }
      expect(txt('prediction_level_1'), contains('längste Einheit'));
      expect(txt('prediction_level_3'), startsWith('vorläufig: '));
    });

    testWidgets('gut: Wettkampfzeit, regelmäßig, lange Einheit; der Marathon '
        'nie über vorläufig', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000);
      await regularRuns(d);
      await seedRun(d.session, _at(5, 9), minutes: 70);
      await pumpCard(tester, d);
      for (var i = 0; i < 3; i++) {
        expect(txt('prediction_level_$i'), startsWith('gut: '));
      }
      expect(txt('prediction_level_3'), startsWith('vorläufig: '));
    });

    testWidgets('Marathon: auch bei bester Datenlage vorläufig, Grund '
        'Marathon', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 21097.5, 6600, daysAgo: 10);
      await regularRuns(d);
      await seedRun(d.session, _at(5, 9), minutes: 130);
      await pumpCard(tester, d);
      expect(txt('prediction_level_2'), startsWith('gut: '));
      expect(
        txt('prediction_level_3'),
        'vorläufig: Der Marathon bleibt immer vorläufig.',
      );
      expect(txt('prediction_value_3'), startsWith('≈ 3 h'));
    });

    testWidgets('Testzeit statt Wettkampf: höchstens ausreichend', (
      tester,
    ) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.test, 10000, 3000);
      await regularRuns(d);
      await seedRun(d.session, _at(5, 9), minutes: 70);
      await pumpCard(tester, d);
      expect(txt('prediction_level_1'), startsWith('ausreichend: '));
      expect(txt('prediction_level_1'), contains('Testzeit'));
    });

    testWidgets('Referenz zu alt: Grund statt Zeit', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 200);
      await pumpCard(tester, d);
      expect(txt('prediction_reason'), contains('zu alt'));
      expect(cardText(tester), isNot(contains('≈')));
      // Die Referenz bleibt sichtbar und löschbar.
      expect(key('prediction_delete'), findsOneWidget);
    });

    testWidgets('Meilen-Einstellung: Distanzen und Referenz in mi', (
      tester,
    ) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      await pumpCard(tester, d, unit: DistanceUnit.miles);
      expect(txt('prediction_label_0'), '5 km (3,11 mi)');
      expect(txt('prediction_label_2'), 'Halbmarathon (13,11 mi)');
      expect(txt('prediction_reference'), contains('6,21 mi'));
    });

    testWidgets('englisch', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      await pumpCard(tester, d, locale: 'en');
      expect(txt('prediction_value_3'), '≈ 3 h 50 min');
      expect(txt('prediction_level_0'), startsWith('provisional: '));
      expect(txt('prediction_reference'), startsWith('Based on: race time'));
    });
  });

  group('Testhinweis', () {
    testWidgets('ohne Referenz, regelmäßig gelaufen: Hinweis', (tester) async {
      final d = await boot(tester);
      for (var i = 1; i <= 12; i++) {
        await seedRun(d.session, _at(2 * i));
      }
      await seedRun(d.session, _at(3, 9), minutes: 31);
      await pumpCard(tester, d);
      expect(txt('prediction_test_hint'), contains('5-km-Test'));
      expect(key('prediction_reason'), findsOneWidget);
    });

    testWidgets('ohne Referenz, zu wenig gelaufen: nur der Grund', (
      tester,
    ) async {
      final d = await boot(tester);
      for (var i = 1; i <= 5; i++) {
        await seedRun(d.session, _at(2 * i));
      }
      await seedRun(d.session, _at(3, 9), minutes: 31);
      await pumpCard(tester, d);
      expect(key('prediction_test_hint'), findsNothing);
      expect(key('prediction_reason'), findsOneWidget);
      // Eintragen bleibt immer möglich.
      expect(key('prediction_add'), findsOneWidget);
    });
  });

  group('Referenz eintragen und löschen', () {
    testWidgets('Testzeit 10 km eintragen, Karte lädt neu, Änderung gemeldet', (
      tester,
    ) async {
      final d = await boot(tester);
      final changes = DataChanges();
      addTearDown(changes.dispose);
      await pumpCard(tester, d, changes: changes);
      await tapKey(tester, 'prediction_add');
      await tapKey(tester, 'prediction_form_kind_test');
      await tapKey(tester, 'prediction_form_distance_tenKilometers');
      await tester.enterText(key('prediction_form_minutes'), '52');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      expect(key('prediction_form'), findsNothing);

      final stored = await _store(d).references();
      expect(stored, hasLength(1));
      final r = stored.single.reference;
      expect(r.kind, ReferenceKind.test);
      expect(r.distanceMeters, 10000);
      expect(r.seconds, 3120);
      expect(changes.revision, 1);
      expect(txt('prediction_reference'), contains('Testzeit, 10,00 km in'));
      expect(txt('prediction_value_1'), '≈ 52 min');
    });

    testWidgets('freie Distanz in Kilometern mit Komma', (tester) async {
      final d = await boot(tester);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_add');
      await tapKey(tester, 'prediction_form_distance_other');
      await tester.enterText(key('prediction_form_distance_field'), '10,5');
      await tester.enterText(key('prediction_form_hours'), '1');
      await tester.enterText(key('prediction_form_seconds'), '30');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      final r = (await _store(d).references()).single.reference;
      expect(r.kind, ReferenceKind.race);
      expect(r.distanceMeters, 10500);
      expect(r.seconds, 3630);
    });

    testWidgets('freie Distanz in Meilen wird in Meter umgerechnet', (
      tester,
    ) async {
      final d = await boot(tester);
      await pumpCard(tester, d, unit: DistanceUnit.miles);
      await tapKey(tester, 'prediction_add');
      await tapKey(tester, 'prediction_form_distance_other');
      await tester.enterText(key('prediction_form_distance_field'), '6.2');
      await tester.enterText(key('prediction_form_minutes'), '50');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      final r = (await _store(d).references()).single.reference;
      expect(r.distanceMeters, closeTo(6.2 * 1609.344, 0.01));
    });

    testWidgets('ungültig: Fehlertext, nichts gespeichert', (tester) async {
      final d = await boot(tester);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_add');
      // Keine Zeit.
      await tapKey(tester, 'prediction_form_save');
      expect(
        txt('prediction_form_error'),
        'Die Zeit muss größer als null sein.',
      );
      // Zu kurze Distanz.
      await tapKey(tester, 'prediction_form_distance_other');
      await tester.enterText(key('prediction_form_distance_field'), '2');
      await tester.enterText(key('prediction_form_minutes'), '10');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      expect(txt('prediction_form_error'), contains('mindestens 3,00 km'));
      // Keine Zahl.
      await tester.enterText(key('prediction_form_distance_field'), 'abc');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      expect(txt('prediction_form_error'), contains('als Zahl'));
      expect(key('prediction_form'), findsOneWidget);
      expect(await _store(d).references(), isEmpty);
      await tapKey(tester, 'prediction_form_cancel');
      expect(await _store(d).references(), isEmpty);
    });

    testWidgets('Löschen nach Rückfrage; Abbrechen löscht nichts', (
      tester,
    ) async {
      final d = await boot(tester);
      final changes = DataChanges();
      addTearDown(changes.dispose);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      await pumpCard(tester, d, changes: changes);
      await tapKey(tester, 'prediction_delete');
      await tapKey(tester, 'prediction_delete_cancel');
      expect(await _store(d).references(), hasLength(1));
      expect(changes.revision, 0);

      await tapKey(tester, 'prediction_delete');
      await tapKey(tester, 'prediction_delete_confirm');
      expect(await _store(d).references(), isEmpty);
      expect(changes.revision, 1);
      expect(txt('prediction_reference'), 'Keine Referenz eingetragen.');
      expect(key('prediction_delete'), findsNothing);
      expect(cardText(tester), isNot(contains('≈')));
    });
  });

  group('Vorschlag (FR-0131)', () {
    /// Referenz 10 km in 60:00; ein 20-min-Lauf mit 3,5 m/s (4,2 km) ist per
    /// Riegel schneller als erwartet.
    Future<(Device, int)> withFastRun(
      WidgetTester tester, {
      int daysAgo = 3,
      int refDaysAgo = 20,
    }) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3600, daysAgo: refDaysAgo);
      final id = await seedRun(
        d.session,
        _at(daysAgo),
        minutes: 20,
        speed: 3.5,
      );
      return (d, id);
    }

    testWidgets('wird angezeigt, aber nie von allein übernommen', (
      tester,
    ) async {
      final (d, _) = await withFastRun(tester);
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsOneWidget);
      expect(txt('prediction_suggestion_text'), contains('könnte eine neue'));
      // Auch nach einem erneuten Laden bleibt nur die eingetragene Referenz.
      final refs = await _store(d).references();
      expect(refs, hasLength(1));
      expect(refs.single.reference.kind, ReferenceKind.race);
    });

    testWidgets('bestätigen: bestätigter Lauf mit Lauf-ID, Vorschlag weg', (
      tester,
    ) async {
      final (d, id) = await withFastRun(tester);
      final changes = DataChanges();
      addTearDown(changes.dispose);
      await pumpCard(tester, d, changes: changes);
      await tapKey(tester, 'prediction_suggestion_accept');
      final active = (await _store(d).references()).first.reference;
      expect(active.kind, ReferenceKind.confirmedRun);
      expect(active.runId, '$id');
      expect(active.distanceMeters, closeTo(4200, 60));
      expect(active.seconds, closeTo(1200, 5));
      expect(changes.revision, 1);
      expect(key('prediction_suggestion'), findsNothing);
      expect(txt('prediction_reference'), contains('bestätigter Lauf'));
      // Ein bestätigter Lauf als Referenz: höchstens vorläufig.
      expect(txt('prediction_level_1'), startsWith('vorläufig: '));
    });

    testWidgets('ablehnen: keine Referenz, derselbe Lauf kommt nicht wieder', (
      tester,
    ) async {
      final (d, id) = await withFastRun(tester);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_suggestion_reject');
      expect(key('prediction_suggestion'), findsNothing);
      expect(await _store(d).rejectedSuggestions(), {id});
      expect(await _store(d).references(), hasLength(1));
      // Neu aufgebaut: weiter kein Vorschlag.
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
    });

    testWidgets('Lauf älter als 182 Tage wird nicht mehr vorgeschlagen', (
      tester,
    ) async {
      final (d, _) = await withFastRun(tester, daysAgo: 200, refDaysAgo: 250);
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
    });
  });

  group('Erklärung (FR-0053)', () {
    testWidgets('Zeitpunkt, Zeitraum, Messungen, Quellen, Methode, Version, '
        'Stufe', (tester) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      await regularRuns(d, weeks: 2);
      await pumpCard(tester, d, vo2: true);
      await tapKey(tester, 'prediction_explain');
      expect(key('prediction_explain_dialog'), findsOneWidget);
      expect(txt('prediction_explain_calculated'), contains('2026'));
      expect(
        txt('prediction_explain_period'),
        '31. Mai 2026 bis 10. Juni 2026',
      );
      expect(txt('prediction_explain_count'), '5');
      expect(
        txt('prediction_explain_sources'),
        'Eingetragene Zeit, Laufverlauf der letzten Wochen, '
        'VO₂max-Schätzung (nur Hinweis, keine Zeit)',
      );
      expect(txt('prediction_explain_method'), 'riegel-prediction, Version 1');
      expect(txt('prediction_explain_level'), 'vorläufig');
      await tapKey(tester, 'prediction_explain_close');
      expect(key('prediction_explain_dialog'), findsNothing);
    });
  });

  group('Layout', () {
    for (final (width, scale, brightness) in [
      (320.0, 1.3, Brightness.light),
      (320.0, 1.3, Brightness.dark),
      (411.0, 1.0, Brightness.dark),
    ]) {
      testWidgets('Breite $width, Schrift $scale, $brightness: kein Überlauf, '
          '48 dp', (tester) async {
        final d = await boot(tester);
        await addRef(d, ReferenceKind.race, 10000, 3600);
        await seedRun(d.session, _at(3), minutes: 20, speed: 3.5);
        await pumpCard(
          tester,
          d,
          width: width,
          scale: scale,
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
        for (final k in [
          'prediction_add',
          'prediction_delete',
          'prediction_explain',
          'prediction_suggestion_accept',
          'prediction_suggestion_reject',
        ]) {
          expect(
            tester.getSize(key(k)).height,
            greaterThanOrEqualTo(48),
            reason: k,
          );
        }
        // Formular und Erklärung ebenfalls.
        await tapKey(tester, 'prediction_add');
        await tapKey(tester, 'prediction_form_distance_other');
        await tapKey(tester, 'prediction_form_save');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'prediction_form_cancel');
        await tapKey(tester, 'prediction_explain');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'prediction_explain_close');
        // Nicht bestimmbar (ohne Referenz) ebenfalls.
        await tapKey(tester, 'prediction_delete');
        await tapKey(tester, 'prediction_delete_confirm');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Fortschritt', () {
    testWidgets('genau eine Karte, zwischen VO₂max und Effizienz; Eintragen '
        'baut die Seite neu auf', (tester) async {
      final d = await boot(tester);
      await seedRun(d.session, _at(2));
      await openStats(d, tester);
      expect(key('prediction_card'), findsOneWidget);
      final vo2 = tester.getTopLeft(find.byType(Vo2ProgressCard)).dy;
      final pred = tester.getTopLeft(key('prediction_card')).dy;
      final eff = tester.getTopLeft(find.byType(EfficiencyCard)).dy;
      expect(vo2, lessThan(pred));
      expect(pred, lessThan(eff));
      expect(find.byType(AppShell), findsOneWidget);

      await tapKey(tester, 'prediction_add');
      await tapKey(tester, 'prediction_form_distance_tenKilometers');
      await tester.enterText(key('prediction_form_minutes'), '50');
      await tester.pump();
      await tapKey(tester, 'prediction_form_save');
      expect(txt('prediction_value_1'), '≈ 50 min');
      expect(key('prediction_card'), findsOneWidget);
    });
  });

  group('Ladezeit', () {
    testWidgets('100 Läufe der letzten 182 Tage (inline, Fake-Speicher)', (
      tester,
    ) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3600, daysAgo: 30);
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await seedRun(
            d.session,
            _at(1 + (i * 175) ~/ 100),
            minutes: 20,
            speed: 3.5,
          );
        }
        final sw = Stopwatch()..start();
        final c = PredictionController(
          session: d.session,
          clock: d.clock,
          hasVo2maxEstimate: false,
        );
        while (c.state.phase == PredictionPhase.loading) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        sw.stop();
        // ignore: avoid_print
        print('LADEZEIT 100 Läufe: ${sw.elapsedMilliseconds} ms');
        expect(c.state.phase, PredictionPhase.ready);
        expect(sw.elapsed, lessThan(const Duration(seconds: 60)));
        c.dispose();
      });
    });
  });
}
