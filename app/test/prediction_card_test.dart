import 'dart:async';
import 'dart:math' as math;

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
  StorageSession? session,
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
                session: session ?? d.session,
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

/// Speicher, dessen Ablehnen und Neuladen der Test anhalten kann.
class _GatedStore implements PredictionStore {
  _GatedStore(this._inner);
  final PredictionStore _inner;

  /// Hält `rejectSuggestion` an, bis es fertig ist.
  Completer<void>? holdReject;

  /// Hält das Lesen der abgelehnten Läufe an (erster Schritt des Neuladens).
  Completer<void>? holdReload;

  @override
  Future<void> rejectSuggestion(int runId) async {
    await holdReject?.future;
    await _inner.rejectSuggestion(runId);
  }

  @override
  Future<Set<int>> rejectedSuggestions() async {
    await holdReload?.future;
    return _inner.rejectedSuggestions();
  }

  @override
  Future<int> addReference(ReferencePerformance reference) =>
      _inner.addReference(reference);
  @override
  Future<void> deleteReference(int id) => _inner.deleteReference(id);
  @override
  Future<List<StoredReference>> references() => _inner.references();
  @override
  Future<ReferencePerformance?> activeReference() => _inner.activeReference();
}

class _GatedSession implements StorageSession, PredictionStorage {
  _GatedSession(this._inner)
    : prediction = _GatedStore((_inner as PredictionStorage).prediction);
  final StorageSession _inner;
  @override
  final _GatedStore prediction;

  @override
  RunStore get runs => _inner.runs;
  @override
  RunMarkerStore get markers => _inner.markers;
  @override
  RawDataStore get rawData => _inner.rawData;
  @override
  PreprocessingStore get preprocessing => _inner.preprocessing;
  @override
  RatedSectionStore get sections => _inner.sections;
  @override
  ComputedValueStore get values => _inner.values;
  @override
  ProfileStore get profile => _inner.profile;
  @override
  SettingsStore get settings => _inner.settings;
  @override
  KnownDeviceStore get devices => _inner.devices;
  @override
  ConsentStore get consents => _inner.consents;
  @override
  RunSubjectiveStore get subjective => _inner.subjective;
  @override
  ManualTrainingStore get manualTrainings => _inner.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => _inner.deleteRun(runId);
  @override
  Future<void> deleteAll() => _inner.deleteAll();
  @override
  Future<void> close() => _inner.close();
}

TextButton _buttonOf(String k) =>
    find
            .descendant(of: key(k), matching: find.byType(TextButton))
            .evaluate()
            .single
            .widget
        as TextButton;

bool _enabled(String k) => _buttonOf(k).onPressed != null;

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

  group('Ältere Referenzen (Befund 3)', () {
    testWidgets(
      'Liste mit Löschen je Eintrag; Rückfrage nennt die danach geltende',
      (tester) async {
        final d = await boot(tester);
        final oldest = await addRef(
          d,
          ReferenceKind.test,
          5000,
          1500,
          daysAgo: 60,
        );
        final middle = await addRef(
          d,
          ReferenceKind.race,
          10000,
          3300,
          daysAgo: 40,
        );
        final active = await addRef(
          d,
          ReferenceKind.race,
          21097.5,
          7200,
          daysAgo: 10,
        );
        await pumpCard(tester, d);
        expect(txt('prediction_others'), 'Weitere gespeicherte Referenzen: 2');
        expect(key('prediction_other_$middle'), findsOneWidget);
        expect(key('prediction_other_$oldest'), findsOneWidget);
        // Die geltende Referenz steht nicht zusätzlich in der Liste.
        expect(key('prediction_other_$active'), findsNothing);

        // Eine ältere löschen: die geltende bleibt, die Rückfrage nennt sie.
        await tapKey(tester, 'prediction_other_delete_$oldest');
        expect(
          txt('prediction_delete_body'),
          contains('Danach gilt: Wettkampfzeit, 21,10 km'),
        );
        await tapKey(tester, 'prediction_delete_confirm');
        expect(await _store(d).references(), hasLength(2));
        expect(txt('prediction_others'), 'Weitere gespeicherte Referenzen: 1');

        // Die geltende löschen: die Rückfrage nennt die nächstältere.
        await tapKey(tester, 'prediction_delete');
        expect(
          txt('prediction_delete_body'),
          contains('Danach gilt: Wettkampfzeit, 10,00 km'),
        );
        await tapKey(tester, 'prediction_delete_confirm');
        expect(key('prediction_others'), findsNothing);
        expect(txt('prediction_reference'), contains('10,00 km'));

        // Die letzte löschen: kein Verweis auf eine weitere.
        await tapKey(tester, 'prediction_delete');
        expect(txt('prediction_delete_body'), contains('keine Referenz mehr'));
      },
    );
  });

  group('Vorschlag (FR-0131)', () {
    /// Lauf mit RPE 8, gleichmäßig, 20 min bei 3 m/s (3,6 km).
    Future<int> hardRun(Device d, int daysAgo, {int? rpe = 8}) async {
      final id = await seedRun(d.session, _at(daysAgo), minutes: 20);
      if (rpe != null) {
        await d.session.subjective.save(id, RunSubjective(rpe: rpe));
      }
      return id;
    }

    testWidgets(
      'Zweig 1 ohne Referenz: RPE 8 und gleichmäßig wird vorgeschlagen',
      (tester) async {
        final d = await boot(tester);
        await hardRun(d, 3);
        await pumpCard(tester, d);
        expect(key('prediction_suggestion'), findsOneWidget);
        expect(await _store(d).references(), isEmpty);
      },
    );

    testWidgets('ohne RPE oder mit RPE 7 kein Vorschlag', (tester) async {
      final d = await boot(tester);
      await hardRun(d, 3, rpe: null);
      await hardRun(d, 5, rpe: 7);
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
    });

    testWidgets('bestätigter Lauf älter als die Referenz kommt nicht wieder', (
      tester,
    ) async {
      final d = await boot(tester);
      await addRef(d, ReferenceKind.race, 10000, 3000, daysAgo: 10);
      final id = await hardRun(d, 40);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_suggestion_accept');
      final refs = await _store(d).references();
      expect(refs, hasLength(2));
      expect(refs.first.reference.kind, ReferenceKind.race); // jüngere gilt
      expect(refs.last.reference.runId, '$id');
      expect(key('prediction_suggestion'), findsNothing);
      // Karte neu aufbauen (neuer State, lädt neu): es bleibt dabei, und es
      // entsteht keine Doppelzeile.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
      expect(await _store(d).references(), hasLength(2));
    });

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

    testWidgets('Referenz aus bestätigtem Lauf löschen: der Lauf wird nicht '
        'wieder vorgeschlagen', (tester) async {
      final (d, id) = await withFastRun(tester);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_suggestion_accept');
      final stored = (await _store(d).references()).first;
      expect(stored.reference.runId, '$id');
      await _store(d).deleteReference(stored.id);
      expect(await _store(d).references(), hasLength(1)); // Altbestand bleibt
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
    });

    testWidgets('Zweig 2: bestätigter Lauf kommt nach neuerem Wettkampf am '
        'selben Tag nicht wieder', (tester) async {
      final (d, id) = await withFastRun(tester);
      await pumpCard(tester, d);
      await tapKey(tester, 'prediction_suggestion_accept');
      expect((await _store(d).references()).first.reference.runId, '$id');
      // Wettkampf am selben Tag wie der Lauf, später angelegt: er gilt jetzt.
      // Der Lauf schlägt ihn per Riegel (10 km in 60:00), wäre also ohne die
      // Sperre für gespeicherte Läufe wieder ein Vorschlag (Zweig 2).
      await addRef(d, ReferenceKind.race, 10000, 3600, daysAgo: 3);
      expect(
        (await _store(d).references()).first.reference.kind,
        ReferenceKind.race,
      );
      // Karte neu aufbauen, damit sie wirklich neu lädt.
      await tester.pumpWidget(const SizedBox());
      await pumpCard(tester, d);
      expect(key('prediction_suggestion'), findsNothing);
    });

    testWidgets('Doppeltippen: die zweite Änderung wird abgewiesen, solange '
        'die erste läuft', (tester) async {
      final (d, _) = await withFastRun(tester);
      final c = PredictionController(
        session: d.session,
        clock: d.clock,
        hasVo2maxEstimate: false,
      );
      addTearDown(c.dispose);
      await tester.pumpAndSettle();
      final s = c.state.suggestion!;
      final results = await Future.wait([
        c.acceptSuggestion(s),
        c.acceptSuggestion(s),
      ]);
      expect(results, [true, false]);
      expect(await _store(d).references(), hasLength(2)); // Wettkampf + Lauf
      // Danach ist die nächste Änderung wieder möglich.
      expect(await c.deleteActive(), isTrue);
    });

    testWidgets('Soll 2: nach einer fehlschlagenden Aktion wird die nächste '
        'Änderung wieder angenommen', (tester) async {
      final (d, _) = await withFastRun(tester);
      final c = PredictionController(
        session: d.session,
        clock: d.clock,
        hasVo2maxEstimate: false,
      );
      addTearDown(c.dispose);
      await tester.pumpAndSettle();
      expect(await c.deleteReference(9999), isFalse); // unbekannte Kennung
      expect(c.busy, isFalse);
      expect(await c.deleteActive(), isTrue);
    });

    testWidgets('Soll 3: die Sperre hält bis das Neuladen fertig ist', (
      tester,
    ) async {
      final (d, _) = await withFastRun(tester);
      final g = _GatedSession(d.session);
      final c = PredictionController(
        session: g,
        clock: d.clock,
        hasVo2maxEstimate: false,
      );
      addTearDown(c.dispose);
      await tester.pumpAndSettle();
      final s = c.state.suggestion!;
      g.prediction.holdReload = Completer<void>();
      final first = c.rejectSuggestion(s);
      await tester.pump();
      // Gespeichert, das Neuladen hängt: noch gesperrt, alter Vorschlag da.
      expect(c.busy, isTrue);
      expect(c.state.suggestion, isNotNull);
      expect(await c.rejectSuggestion(s), isFalse);
      g.prediction.holdReload!.complete();
      expect(await first, isTrue);
      expect(c.busy, isFalse);
      expect(c.state.suggestion, isNull);
      expect(await _store(d).rejectedSuggestions(), hasLength(1));
    });

    testWidgets('Soll 1: Knöpfe sind während einer Änderung gesperrt, kein '
        'falscher Hinweis', (tester) async {
      final (d, _) = await withFastRun(tester);
      final g = _GatedSession(d.session);
      await pumpCard(tester, d, session: g);
      expect(_enabled('prediction_suggestion_accept'), isTrue);
      g.prediction.holdReject = Completer<void>();
      await tester.ensureVisible(key('prediction_suggestion_reject'));
      await tester.tap(key('prediction_suggestion_reject'));
      await tester.pump();
      for (final k in [
        'prediction_suggestion_accept',
        'prediction_suggestion_reject',
        'prediction_add',
        'prediction_delete',
      ]) {
        expect(_enabled(k), isFalse, reason: k);
      }
      // Ein Tippen auf den gesperrten Knopf tut nichts und warnt nicht.
      await tester.tap(
        key('prediction_suggestion_accept'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      g.prediction.holdReject!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(key('prediction_suggestion'), findsNothing);
      expect(_enabled('prediction_add'), isTrue);
      expect(await _store(d).references(), hasLength(1)); // nicht übernommen
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

  group('Kontrast der Kartenknöpfe', () {
    double lum(Color c) {
      double f(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    double ratio(Color a, Color b) {
      final l1 = lum(a), l2 = lum(b);
      return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
    }

    for (final brightness in Brightness.values) {
      testWidgets('$brightness: Vordergrund gegen Kartenfläche >= 4,5:1', (
        tester,
      ) async {
        final d = await boot(tester);
        await addRef(d, ReferenceKind.race, 10000, 3600);
        await seedRun(d.session, _at(3), minutes: 20, speed: 3.5);
        await pumpCard(tester, d, brightness: brightness);
        final c = RamuriColors.of(tester.element(find.byType(PredictionCard)));
        for (final k in [
          'prediction_add',
          'prediction_delete',
          'prediction_explain',
          'prediction_suggestion_accept',
          'prediction_suggestion_reject',
        ]) {
          final text = find.descendant(of: key(k), matching: find.byType(Text));
          final fg = DefaultTextStyle.of(tester.element(text.first))
              .style
              .color!;
          expect(ratio(fg, c.surface), greaterThanOrEqualTo(4.5), reason: k);
        }
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
          final id = await seedRun(
            d.session,
            _at(1 + (i * 175) ~/ 100),
            minutes: 20,
            speed: 3.5,
          );
          // Ungünstigster Fall: alle Läufe mit RPE 8, jeder wird abgespielt.
          await d.session.subjective.save(id, RunSubjective(rpe: 8));
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
