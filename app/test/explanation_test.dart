import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:running_app/features/transparency/value_explanation_screen.dart';

import 'app_harness.dart';
import 'history_summary_test.dart'
    show key, openHistory, seedRun, started, text;
import 'statistics_test.dart' show calc, openStats;

const ProfileRecord _profile = ProfileRecord(
  maxHeartRateBpm: 190,
  restingHeartRateBpm: 60,
);

/// Lauf mit Wert; öffnet die Erklärung des Laufwerts aus der Statistik.
Future<Device> seeded(
  WidgetTester tester, {
  ProfileRecord? profile = _profile,
  int? bpm = 150,
  String? deviceName,
  bool knownDevice = true,
  String locale = 'de',
}) async {
  final d = await started(tester, locale: locale);
  if (profile != null) await d.session.profile.save(profile);
  if (knownDevice) {
    await d.session.devices.upsert(
      'strap',
      displayName: deviceName,
      at: DateTime.utc(2026, 5, 1),
    );
  }
  d.clock.set(DateTime.utc(2026, 6, 3, 12));
  final id = await seedRun(
    d.session,
    DateTime.utc(2026, 6, 1, 8),
    minutes: 30,
    bpm: bpm,
  );
  await calc(d, id);
  return d;
}

Future<void> openRunDetail(Device d, WidgetTester tester, int id) async {
  await openHistory(d, tester);
  await tester.tap(key('history_run_$id'));
  await tester.pumpAndSettle();
}

Future<int> firstRunId(Device d) async =>
    (await d.session.runs.list()).first.id;

Future<void> explainFromStats(WidgetTester tester, String id) async {
  await tester.ensureVisible(key(id));
  await tester.pumpAndSettle();
  await tester.tap(key(id));
  await tester.pumpAndSettle();
}

String bodyText(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(of: key('expl_body'), matching: find.byType(Text)),
    )
    .map((t) => t.data ?? '')
    .join('\n');

void main() {
  group('Erklärung eines berechneten Werts (FR-0059, ACC-06)', () {
    testWidgets(
      'alle sechs Fragen sind aus den gespeicherten Daten beantwortet',
      (tester) async {
        final d = await seeded(tester, deviceName: 'Brustgurt');
        await openStats(d, tester);
        await explainFromStats(tester, 'stat_explain_vo2_run');
        for (final q in [
          'Aus welchen Daten wurde der Wert berechnet?',
          'Wie alt sind diese Daten?',
          'Wie viele geeignete Messungen gingen ein?',
          'Welche Methode wurde verwendet?',
          'Wie verlässlich ist das Ergebnis?',
          'Direkt gemessen oder geschätzt?',
        ]) {
          expect(find.text(q), findsOneWidget, reason: q);
        }
        final stored = (await d.session.values.read(
          ValueOwner.run(await firstRunId(d)),
        )).firstWhere((p) => p.current.key == vo2maxRunValueKey).current;
        // 1 Daten: Quellen, Datenbasis, Herzfrequenzbasis-Schnappschuss.
        expect(
          text('expl_source_0_gps'),
          'Standort des Telefons (GPS), 1801 Werte',
        );
        expect(
          text('expl_source_1_strap'),
          'Pulssensor „Brustgurt“ (Kennung strap), 1801 Werte',
        );
        expect(text('expl_data_basis'), 'Datenbasis: Standort (GPS) und Puls');
        expect(text('expl_basis_max'), 'HFmax 190 bpm');
        expect(text('expl_basis_rest'), 'Ruhepuls 60 bpm');
        // 2 Alter: Zeitraum der Daten und Berechnungszeitpunkt.
        expect(text('expl_a2'), startsWith('Daten vom '));
        expect(text('expl_a2'), contains('Berechnet am '));
        // 3 Anzahl wie gespeichert, dazu die bewerteten Abschnitte.
        expect(
          text('expl_a3'),
          stored.measurementCount == 1
              ? '1 verwertbarer Abschnitt'
              : '${stored.measurementCount} verwertbare Abschnitte',
        );
        expect(find.text('Bewertete Abschnitte'), findsOneWidget);
        expect(find.textContaining('Ab Minute '), findsWidgets);
        // 4 Methode samt Versionen wie gespeichert.
        expect(
          text('expl_a4'),
          '${stored.method}, Version ${stored.methodVersion}, '
          'Parameterversion ${stored.parameterVersion}',
        );
        // 5 Stufe ohne Genauigkeitsangabe, 6 geschätzt.
        expect(text('expl_a5'), startsWith('Qualitätsstufe: '));
        expect(text('expl_a5_note'), contains('keine Angabe zur Genauigkeit'));
        expect(text('expl_a6'), startsWith('Geschätzt'));
        expect(text('expl_estimate'), 'Schätzung, keine Messung');
        expect(key('expl_reason'), findsNothing);
      },
    );

    testWidgets(
      'Zonenzeiten und TRIMP: Pulswerte als Grundlage, keine Schätzung',
      (tester) async {
        final d = await seeded(tester);
        final id = await firstRunId(d);
        await openRunDetail(d, tester, id);
        await explainFromStats(tester, 'sum_explain_trimp');
        expect(text('expl_a3'), matches(RegExp(r'^\d+ verwendete Pulswerte$')));
        expect(text('expl_a6'), contains('nichts über Ermüdung'));
        expect(key('expl_estimate'), findsNothing);
        expect(text('expl_basis_max'), 'HFmax 190 bpm');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        await explainFromStats(tester, 'sum_explain_zones');
        expect(text('expl_a6'), contains('Näherung'));
        expect(text('expl_a6'), contains('keine gemessenen Schwellen'));
      },
    );

    testWidgets('Einordnung und VO₂max sind aus Zusammenfassung erreichbar', (
      tester,
    ) async {
      final d = await seeded(tester);
      await seedRun(d.session, DateTime.utc(2026, 5, 30, 8), minutes: 10);
      final ids = [for (final r in await d.session.runs.list()) r.id]..sort();
      await openRunDetail(d, tester, ids.first);
      await explainFromStats(tester, 'sum_explain_class');
      expect(text('expl_class_data'), contains('Referenz'));
      expect(text('expl_class_method'), contains('keine Schätzung'));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await explainFromStats(tester, 'sum_explain_vo2max');
      expect(key('expl_a4'), findsOneWidget);
    });
  });

  group('Fehlender Wert und Datenbasis (FR-0055, FR-0059)', () {
    testWidgets(
      'ohne Profilwerte: Grund sichtbar, Hinweis mit Weg zum Profil',
      (tester) async {
        final d = await seeded(tester, profile: null);
        await openStats(d, tester);
        await explainFromStats(tester, 'stat_explain_vo2_run');
        expect(key('expl_reason'), findsOneWidget);
        expect(text('expl_reason'), contains('HFmax im Profil prüfen'));
        expect(
          text('expl_profile_hint'),
          allOf(
            contains('maximale Herzfrequenz'),
            isNot(contains('Ruhepuls')), // nur, was der Grund nennt
            contains('„Profil“'),
            contains('nur GPS'),
          ),
        );
        expect(text('expl_a4'), contains('Version'));
      },
    );

    testWidgets('nur GPS: Grund „kein Puls“, Datenbasis nur GPS', (
      tester,
    ) async {
      final d = await seeded(tester, bpm: null, knownDevice: false);
      await openStats(d, tester);
      await explainFromStats(tester, 'stat_explain_vo2_run');
      expect(text('expl_reason'), contains('Puls'));
      expect(key('expl_needs_hr'), findsOneWidget);
      expect(
        text('expl_data_basis'),
        'Datenbasis: nur Standort (GPS), kein Puls',
      );
      expect(find.byKey(const Key('expl_source_1_strap')), findsNothing);
      expect(key('expl_profile_hint'), findsNothing);
    });

    for (final loc in ['de', 'en']) {
      testWidgets(
        'nicht berechneter Wert ($loc): Grund, keine Berechnungsbehauptung',
        (tester) async {
          final d = await seeded(
            tester,
            bpm: null,
            knownDevice: false,
            locale: loc,
          );
          final id = await firstRunId(d);
          final stored = (await d.session.values.read(ValueOwner.run(id)))
              .firstWhere((p) => p.current.key == trimpRunValueKey)
              .current;
          expect(stored.value, isNull);
          expect(stored.unavailableReason, isNotNull);
          await openRunDetail(d, tester, id);
          await explainFromStats(tester, 'sum_explain_trimp');
          expect(key('expl_reason'), findsOneWidget);
          final all = bodyText(tester);
          final de = loc == 'de';
          for (final claim
              in de
                  ? [
                      'Berechnet am',
                      'Berechnet aus den gemessenen',
                      'berechnet wurde',
                    ]
                  : [
                      'Calculated on',
                      'Calculated from the measured',
                      'was calculated from',
                    ]) {
            expect(all, isNot(contains(claim)), reason: claim);
          }
          expect(
            text('expl_a2'),
            startsWith(
              de ? 'Berechnungsversuch am ' : 'Calculation attempted on ',
            ),
          );
          expect(
            text('expl_a6'),
            startsWith(
              de ? 'Es wurde kein Wert berechnet' : 'No value was calculated',
            ),
          );
          expect(key('expl_estimate'), findsNothing);
          expect(
            find.text(
              de ? 'Welche Daten lagen vor?' : 'Which data was available?',
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('Wert nicht gespeichert: Hinweis statt Erfindung', (
      tester,
    ) async {
      final d = await started(tester);
      d.clock.set(DateTime.utc(2026, 6, 3, 12));
      final id = await seedRun(d.session, DateTime.utc(2026, 6, 1, 8));
      await openRunDetail(d, tester, id);
      await explainFromStats(tester, 'sum_explain_trimp');
      expect(key('expl_not_stored'), findsOneWidget);
      expect(key('expl_a1_sources'), findsNothing);
    });
  });

  group('Quelle je Datensatz (SEC-0005, FR-0020)', () {
    Future<void> openSources(WidgetTester tester, Device d) async {
      final id = await firstRunId(d);
      await openRunDetail(d, tester, id);
      await explainFromStats(tester, 'sum_explain_sources');
    }

    testWidgets('bekanntes Gerät mit Namen', (tester) async {
      final d = await seeded(tester, deviceName: 'Brustgurt');
      await openSources(tester, d);
      expect(text('expl_source_0_gps'), contains('Standort des Telefons'));
      expect(text('expl_source_1_strap'), contains('„Brustgurt“'));
      expect(text('expl_source_1_strap'), contains('Kennung strap'));
      expect(key('expl_gap_note'), findsOneWidget);
    });

    testWidgets('bekanntes Gerät ohne Anzeigenamen', (tester) async {
      final d = await seeded(tester);
      await openSources(tester, d);
      expect(
        text('expl_source_1_strap'),
        startsWith('Pulssensor ohne Anzeigenamen (Kennung strap)'),
      );
    });

    testWidgets('gelöschtes Gerät: ohne Namen, kenntlich, Kennung bleibt', (
      tester,
    ) async {
      final d = await seeded(tester, knownDevice: false);
      await openSources(tester, d);
      expect(
        text('expl_source_1_strap'),
        startsWith('Gelöschter Pulssensor, ohne Namen (Kennung strap)'),
      );
    });

    testWidgets('zwei Geräte in einem Lauf: zwei Abschnitte, Zahl der Werte', (
      tester,
    ) async {
      final d = await started(tester);
      final start = DateTime.utc(2026, 6, 1, 8);
      final run = await d.session.runs.create(startedAt: start);
      await d.session.rawData.append(
        run.id,
        RawBatch(
          heartRates: [
            for (var i = 0; i < 10; i++)
              RawHeartRate(
                time: start.add(Duration(seconds: i)),
                source: 'a',
                bpm: 140,
              ),
            // Lücke von einer Stunde innerhalb eines Abschnitts: keine Dauer
            // „mit Puls“ aus dem Abschnitt ableiten.
            RawHeartRate(
              time: start.add(const Duration(hours: 1)),
              source: 'a',
              bpm: 141,
            ),
            RawHeartRate(
              time: start.add(const Duration(hours: 1, seconds: 1)),
              source: 'b',
              bpm: 142,
            ),
          ],
        ),
      );
      await d.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(hours: 2)),
        endedUtcOffset: Duration.zero,
      );
      await d.session.devices.upsert(
        'a',
        displayName: 'Gurt A',
        at: DateTime.utc(2026, 5, 1),
      );
      await openRunDetail(d, tester, run.id);
      await explainFromStats(tester, 'sum_explain_sources');
      expect(text('expl_source_0_a'), contains('11 Werte'));
      expect(text('expl_source_1_b'), contains('1 Wert'));
      expect(text('expl_source_1_b'), contains('Gelöschter Pulssensor'));
      expect(find.textContaining('Standort des Telefons'), findsNothing);
      // Keine Dauer aus Abschnittsgrenzen.
      expect(bodyText(tester), isNot(contains('Stunde')));
      expect(bodyText(tester), isNot(contains('min')));
    });

    testWidgets('Tageswert: Quellen am Wert, unbekannte Kennung neutral', (
      tester,
    ) async {
      final d = await seeded(tester, knownDevice: false);
      await d.session.values.createOriginals(
        const ValueOwner.day('2026-06-05'),
        [
          ComputedValue(
            key: vo2maxLongTermValueKey,
            value: 44,
            unit: vo2maxUnit,
            computedAt: DateTime.utc(2026, 6, 5),
            dataFrom: DateTime.utc(2026, 5, 1),
            dataTo: DateTime.utc(2026, 6, 5),
            measurementCount: 3,
            sources: const ['gps', 'gone'],
            method: 'm',
            methodVersion: 1,
            parameterVersion: 1,
            quality: ValueQuality.sufficient,
          ),
        ],
      );
      await showExplanationFor(
        tester,
        d,
        vo2maxLongTermValueKey,
        day: '2026-06-05',
      );
      expect(text('expl_source_0_gps'), 'Standort des Telefons (GPS)');
      expect(
        text('expl_source_1_gone'),
        'Quelle nicht mehr bekannt (Kennung gone)',
      );
      expect(text('expl_a3'), '3 verwertbare Läufe');
      expect(text('expl_a5'), 'Qualitätsstufe: ausreichend');
      expect(text('expl_a6'), contains('mehrerer Läufe'));
    });
  });

  group('Nachbesserung Teil D', () {
    Future<Device> twoDevices(WidgetTester tester, List<String> order) async {
      final d = await started(tester);
      final start = DateTime.utc(2026, 6, 1, 8);
      final run = await d.session.runs.create(startedAt: start);
      await d.session.rawData.append(
        run.id,
        RawBatch(
          heartRates: [
            for (var i = 0; i < order.length; i++)
              RawHeartRate(
                time: start.add(Duration(minutes: i)),
                source: order[i],
                bpm: 140,
              ),
          ],
        ),
      );
      await d.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(hours: 1)),
        endedUtcOffset: Duration.zero,
      );
      for (final id in order.toSet()) {
        await d.session.devices.upsert(
          id,
          displayName: 'Gurt $id',
          at: DateTime.utc(2026, 5, 1),
        );
      }
      return d;
    }

    testWidgets('Gerätewechsel A, B, A: Quellenansicht ohne doppelten Key', (
      tester,
    ) async {
      final d = await twoDevices(tester, ['a', 'b', 'a']);
      final id = await firstRunId(d);
      await openRunDetail(d, tester, id);
      await explainFromStats(tester, 'sum_explain_sources');
      expect(tester.takeException(), isNull);
      expect(text('expl_source_0_a'), contains('Gurt a'));
      expect(text('expl_source_1_b'), contains('Gurt b'));
      expect(text('expl_source_2_a'), contains('Gurt a'));
    });

    testWidgets('Gerätewechsel A, B, A: Frage 1 eines Laufwerts', (
      tester,
    ) async {
      final d = await twoDevices(tester, ['a', 'b', 'a']);
      final id = await firstRunId(d);
      await d.session.values.createOriginals(ValueOwner.run(id), [
        ComputedValue(
          key: trimpRunValueKey,
          value: 50,
          unit: 'TRIMP',
          computedAt: DateTime.utc(2026, 6, 2),
          dataFrom: DateTime.utc(2026, 6, 1, 8),
          dataTo: DateTime.utc(2026, 6, 1, 9),
          measurementCount: 3,
          sources: const ['a', 'b'],
          method: 'm',
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.sufficient,
        ),
      ]);
      await openRunDetail(d, tester, id);
      await explainFromStats(tester, 'sum_explain_trimp');
      expect(tester.takeException(), isNull);
      expect(key('expl_source_2_a'), findsOneWidget);
    });

    testWidgets('berechneter TRIMP mit nur HFmax: kein Profil-Hinweis', (
      tester,
    ) async {
      final d = await seeded(
        tester,
        profile: const ProfileRecord(maxHeartRateBpm: 190),
      );
      final id = await firstRunId(d);
      final trimp = (await d.session.values.read(ValueOwner.run(id)))
          .firstWhere((p) => p.current.key == trimpRunValueKey)
          .current;
      expect(trimp.value, isNotNull); // berechnet, nicht „nicht verfügbar“
      await openRunDetail(d, tester, id);
      await explainFromStats(tester, 'sum_explain_trimp');
      expect(key('expl_reason'), findsNothing);
      expect(key('expl_profile_hint'), findsNothing);
      expect(text('expl_basis_rest'), contains('Ruhepuls'));
    });

    testWidgets('Lesefehler: eigener Text, nicht „nichts gespeichert“', (
      tester,
    ) async {
      final d = await started(tester);
      await showExplanationFor(
        tester,
        d,
        trimpRunValueKey,
        runId: 1,
        session: _FailingSession(d.session),
      );
      expect(key('expl_failed'), findsOneWidget);
      expect(key('expl_not_stored'), findsNothing);
    });

    testWidgets('Tageswert ohne Wertzahl: kein Lückenhinweis', (tester) async {
      final d = await seeded(tester, deviceName: 'Brustgurt');
      await d.session.values.createOriginals(
        const ValueOwner.day('2026-06-05'),
        [
          _dayValue(vo2maxLongTermValueKey, ['gps', 'strap']),
        ],
      );
      await showExplanationFor(
        tester,
        d,
        vo2maxLongTermValueKey,
        day: '2026-06-05',
      );
      expect(text('expl_source_1_strap'), contains('Brustgurt'));
      expect(key('expl_gap_note'), findsNothing);
    });

    testWidgets('Effizienz ist als Schätzung gekennzeichnet (CON-0009)', (
      tester,
    ) async {
      final d = await seeded(tester);
      await d.session.values.createOriginals(
        const ValueOwner.day('2026-06-05'),
        [
          _dayValue(aerobicEfficiencyValueKey, ['gps', 'strap']),
        ],
      );
      await showExplanationFor(
        tester,
        d,
        aerobicEfficiencyValueKey,
        day: '2026-06-05',
      );
      expect(text('expl_estimate'), 'Schätzung, keine Messung');
      expect(text('expl_a6'), startsWith('Geschätzt'));
    });

    testWidgets('Frage 2 nennt Datenanfang, Datenende und Berechnung', (
      tester,
    ) async {
      final d = await seeded(tester);
      await d.session.values.createOriginals(
        const ValueOwner.day('2026-06-05'),
        [
          _dayValue(vo2maxLongTermValueKey, ['gps']),
        ],
      );
      await showExplanationFor(
        tester,
        d,
        vo2maxLongTermValueKey,
        day: '2026-06-05',
      );
      final context = tester.element(key('expl_a2'));
      final m = MaterialLocalizations.of(context);
      String date(int mo, int day) =>
          m.formatMediumDate(DateTime.utc(2026, mo, day).toLocal());
      expect(
        text('expl_a2'),
        'Daten vom ${date(5, 1)} bis ${date(6, 4)}. '
        'Berechnet am ${date(6, 5)}.',
      );
    });
  });

  group('Sprache und Bedienung', () {
    testWidgets('Englisch, große Schrift, Überschriften als Header', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final d = await started(tester, locale: 'en');
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
      await tester.scrollUntilVisible(
        key('stat_explain_vo2_run'),
        300,
        scrollable: find.descendant(
          of: key('stat_list'),
          matching: find.byType(Scrollable),
        ),
      );
      await explainFromStats(tester, 'stat_explain_vo2_run');
      expect(tester.takeException(), isNull);
      final q1 = find.text('Which data was the value calculated from?');
      await tester.scrollUntilVisible(
        q1,
        200,
        scrollable: find.descendant(
          of: find.byType(ValueExplanationScreen),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.getSemantics(q1).flagsCollection.isHeader, isTrue);
      await tester.scrollUntilVisible(
        key('expl_a6'),
        200,
        scrollable: find.descendant(
          of: find.byType(ValueExplanationScreen),
          matching: find.byType(Scrollable),
        ),
      );
      expect(text('expl_a6'), startsWith('Estimated'));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });
}

/// Öffnet die Erklärung ohne Umweg über eine Liste (Tageswert).
Future<void> showExplanationFor(
  WidgetTester tester,
  Device d,
  String valueKey, {
  String? day,
  int? runId,
  StorageSession? session,
}) async {
  await tester.tap(key('home_statistics'));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).last);
  // ignore: unawaited_futures
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ValueExplanationScreen(
        session: session ?? d.session,
        valueKey: valueKey,
        day: day,
        runId: runId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tageswert mit festen Daten: Zeitraum 1.5. bis 4.6., berechnet am 5.6.
ComputedValue _dayValue(String key, List<String> sources) => ComputedValue(
  key: key,
  value: 44,
  unit: key == vo2maxLongTermValueKey ? vo2maxUnit : 'x',
  computedAt: DateTime.utc(2026, 6, 5),
  dataFrom: DateTime.utc(2026, 5, 1),
  dataTo: DateTime.utc(2026, 6, 4),
  measurementCount: 3,
  sources: sources,
  method: 'm',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.sufficient,
);

/// Sitzung, deren Werte nicht lesbar sind (Lesefehler des Speichers).
class _FailingSession implements StorageSession {
  _FailingSession(this.inner);
  final StorageSession inner;

  @override
  ComputedValueStore get values =>
      throw const StorageException(StorageFailure.failed);

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
