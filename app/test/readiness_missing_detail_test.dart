import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/readiness/readiness_card.dart';
import 'package:running_app/features/readiness/readiness_detail_screen.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

// Fehlende Faktoren der Erholung (FR-0111, PAR-164K): Grund und Weg zum
// Nachholen je Faktor, „Schlaf angeben“ an der zählenden Morgenmessung des
// Ortstags, Sperre ohne Entwicklermodus (K62). Fake-Speicher und feste Uhr;
// heute ist Samstag, der 14.11.2026, 10 Uhr Ortszeit (UTC+1, im
// Morgenfenster 4–11), außerhalb des Fensters 14 bzw. 3 Uhr. Nur erfundene
// Werte.

const _offset = Duration(hours: 1);

/// Morgenmessung [daysAgo] Tage vor heute um [hour]:[minute] Uhr Ortszeit
/// mit Gerät [model] und Schlafstufe [band].
MorningMeasurement _morning(
  int daysAgo, {
  int hour = 7,
  int minute = 0,
  String model = 'Modell',
  SleepBand? band,
}) => MorningMeasurement(
  measuredAt: DateTime.utc(
    2026,
    11,
    14 - daysAgo,
    hour,
    minute,
  ).subtract(_offset),
  utcOffset: _offset,
  posture: RestingPosture.lying,
  deviceManufacturer: 'Hersteller',
  deviceModel: model,
  sleepBand: band,
  method: 'ppg',
  methodVersion: 1,
  quality: PpgQuality.good,
  restingHrBpm: 56.0 + daysAgo % 4,
  rmssdMs: 40.0 + daysAgo % 6,
  timingNoiseMs: 10,
  cameraIntervalsMs: const [],
  beforeValidation: true,
  outsideWindow: false,
);

class _Env {
  _Env(this.session, this.clock);

  final StorageSession session;
  final FakeClock clock;

  MorningStore get morning => (session as MorningStorage).morning;

  late final ReadinessService service = ReadinessService(
    session: session,
    clock: clock,
  );

  ReadinessActions actions({bool startMorning = true}) => ReadinessActions(
    reload: service.load,
    startMorning: startMorning ? (_) async {} : null,
    saveSleep: (entry, band) => saveReadinessSleep(morning, entry, band),
  );
}

/// Speicher mit Messungen an [history] Tagen vor heute und, mit [today],
/// einer heutigen um 7 Uhr; Entwicklermodus nach [dev]; jetzt um [hour] Uhr
/// Ortszeit.
Future<_Env> _env({
  int history = 9,
  bool today = false,
  bool dev = true,
  int hour = 10,
}) async {
  final session = await FakeStorage().open(Uint8List(32));
  final clock = FakeClock(
    DateTime.utc(2026, 11, 14, hour).subtract(_offset),
    utcOffset: _offset,
  );
  if (dev) await SettingsDeveloperModeStore(session.settings, clock).set(true);
  final morning = (session as MorningStorage).morning;
  for (var i = history; i >= 1; i--) {
    await morning.add(_morning(i));
  }
  if (today) await morning.add(_morning(0));
  return _Env(session, clock);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required String locale,
  required double width,
  required double scale,
}) async {
  tester.view.physicalSize = Size(width, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, 4000),
        textScaler: TextScaler.linear(scale),
      ),
      child: MaterialApp(
        theme: RamuriTheme.light,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder _key(String k) => find.byKey(Key(k));
String _text(String k) => (_key(k).evaluate().single.widget as Text).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final (name, locale, width, scale) in [
    ('de', 'de', 411.0, 1.0),
    ('en, 320 dp, Schrift 2.0', 'en', 320.0, 2.0),
  ]) {
    final de = locale == 'de';
    group('Fehlende Faktoren ($name)', () {
      Future<void> open(
        WidgetTester t,
        ReadinessSnapshot s, {
        ReadinessActions actions = const ReadinessActions(),
      }) => _pump(
        t,
        ReadinessDetailScreen(snapshot: s, actions: actions),
        locale: locale,
        width: width,
        scale: scale,
      );

      testWidgets('ohne Messung heute: Grund und Weg je Faktor', (
        tester,
      ) async {
        final env = (await tester.runAsync(() => _env()))!;
        final s = (await tester.runAsync(env.service.load))!;
        expect(s.sleepEntry, isNull);
        await open(tester, s, actions: env.actions());

        expect(
          _text('readiness_detail_missing_reason_hrv'),
          de ? 'Heute noch keine Messung.' : 'No measurement today yet.',
        );
        expect(_key('readiness_detail_start_morning_hrv'), findsOneWidget);
        expect(
          _key('readiness_detail_start_morning_restingHeartRate'),
          findsOneWidget,
        );
        // Schlaf: Hinweis auf die Morgenmessung und deren Knopf, kein
        // „Schlaf angeben“ ohne heutige Messung.
        expect(
          _text('readiness_detail_missing_reason_sleep'),
          de ? 'Keine Nacht aus Health Connect und keine Angabe.' : isNotEmpty,
        );
        expect(
          _key('readiness_detail_hint_sleep_sleepAtMorning'),
          findsOneWidget,
        );
        expect(_key('readiness_detail_start_morning_sleep'), findsOneWidget);
        expect(_key('readiness_detail_enter_sleep'), findsNothing);
        // Befinden: nur Hinweis.
        expect(
          _key('readiness_detail_hint_wellbeing_wellbeingAfterRun'),
          findsOneWidget,
        );
        expect(
          _text('readiness_detail_hint_wellbeing_wellbeingAfterRun'),
          de
              ? 'Nach dem nächsten Lauf in der Zusammenfassung angeben.'
              : isNotEmpty,
        );
        // Belastung: Grund, kein Knopf.
        expect(_key('readiness_detail_missing_reason_load'), findsOneWidget);
        expect(_key('readiness_detail_start_morning_load'), findsNothing);
        expect(
          find.descendant(
            of: _key('readiness_detail_missing_load'),
            matching: find.byType(TextButton),
          ),
          findsNothing,
        );
      });

      // 11 Uhr Ortszeit ist 10 Uhr UTC: ohne den Versatz des Ortes wäre das
      // Fenster noch offen.
      for (final (hour, today) in [(11, false), (14, false), (3, true)]) {
        testWidgets('außerhalb des Morgenfensters ($hour Uhr): Hinweis statt '
            'Knopf', (tester) async {
          final env = (await tester.runAsync(() => _env(hour: hour)))!;
          final s = (await tester.runAsync(env.service.load))!;
          await open(tester, s, actions: env.actions());
          final expected = switch ((de, today)) {
            (true, false) => 'Die nächste Morgenmessung zählt morgen ab 4 Uhr.',
            (true, true) => 'Die nächste Morgenmessung zählt heute ab 4 Uhr.',
            (false, false) =>
              'Your next morning measurement counts from 4 am tomorrow.',
            (false, true) =>
              'Your next morning measurement counts from 4 am today.',
          };
          for (final id in ['hrv', 'restingHeartRate', 'sleep']) {
            expect(
              _key('readiness_detail_start_morning_$id'),
              findsNothing,
              reason: '$id um $hour',
            );
            expect(
              _text('readiness_detail_hint_${id}_nextMorningWindow'),
              expected,
              reason: '$id um $hour',
            );
          }
          // Schlaf: der Hinweis auf die Morgenmessung bleibt.
          expect(
            _key('readiness_detail_hint_sleep_sleepAtMorning'),
            findsOneWidget,
          );
          expect(
            find.text(
              de ? 'Morgenmessung starten' : 'Start morning measurement',
            ),
            findsNothing,
          );
        });
      }

      testWidgets('Morgenmessung nicht erreichbar: kein Knopf', (tester) async {
        final env = (await tester.runAsync(() => _env()))!;
        final s = (await tester.runAsync(env.service.load))!;
        await open(tester, s, actions: env.actions(startMorning: false));
        expect(_key('readiness_detail_missing_reason_hrv'), findsOneWidget);
        expect(_key('readiness_detail_start_morning_hrv'), findsNothing);
        expect(_key('readiness_detail_start_morning_sleep'), findsNothing);
        expect(
          _key('readiness_detail_hint_sleep_sleepAtMorning'),
          findsOneWidget,
        );
      });

      testWidgets('heutige Messung: Vergleichstage und „Schlaf angeben“', (
        tester,
      ) async {
        final env = (await tester.runAsync(() => _env(today: true)))!;
        final s = (await tester.runAsync(env.service.load))!;
        final id = s.sleepEntry!.measurementId;
        await open(tester, s, actions: env.actions());

        // 9 Tage vorher, heute nicht mitgezählt: 9 von 14, noch 5.
        expect(
          _text('readiness_detail_missing_reason_hrv'),
          de
              ? 'Vergleich aus 9 von 14 Tagen – noch 5 Tage messen.'
              : allOf(contains('9'), contains('14'), contains('5')),
        );
        expect(_key('readiness_detail_start_morning_hrv'), findsNothing);
        expect(_key('readiness_detail_enter_sleep'), findsOneWidget);
        expect(_key('readiness_detail_change_sleep'), findsNothing);

        // Stufe wählen: gespeichert an der ersten Messung des Ortstags,
        // Schlaf zählt danach als Selbstangabe.
        await _tap(tester, 'readiness_detail_enter_sleep');
        expect(_key('readiness_sleep_sheet'), findsOneWidget);
        await _tap(tester, 'readiness_sleep_from7to8');
        await _tap(tester, 'readiness_sleep_done');
        // Neuberechnung über die Fake-Speicher außerhalb des Fake-Async.
        await tester.runAsync(() async {});
        await tester.pumpAndSettle();
        final stored = (await tester.runAsync(env.morning.list))!;
        expect(
          stored.singleWhere((e) => e.id == id).value.sleepBand,
          SleepBand.from7to8,
        );
        expect(_key('readiness_detail_missing_sleep'), findsNothing);
        expect(_key('readiness_detail_enter_sleep'), findsNothing);
        expect(_key('readiness_detail_change_sleep'), findsOneWidget);
        final after = (await tester.runAsync(env.service.load))!;
        expect(
          after.result.factors
              .singleWhere((f) => f.id == ReadinessFactorId.sleep)
              .source,
          ReadinessFactorSource.selfReport,
        );

        // Dieselbe Stufe noch einmal: abgewählt, Schlaf fehlt wieder.
        await _tap(tester, 'readiness_detail_change_sleep');
        await _tap(tester, 'readiness_sleep_from7to8');
        await _tap(tester, 'readiness_sleep_done');
        await tester.runAsync(() async {});
        await tester.pumpAndSettle();
        final cleared = (await tester.runAsync(env.morning.list))!;
        expect(cleared.singleWhere((e) => e.id == id).value.sleepBand, isNull);
        expect(_key('readiness_detail_missing_sleep'), findsOneWidget);
        expect(_key('readiness_detail_enter_sleep'), findsOneWidget);
        expect(_key('readiness_detail_change_sleep'), findsNothing);
      });

      // Zwei Geräte am selben Morgen (PAR-164K): A um 6 Uhr ohne Stufe,
      // B um 6:30 Uhr mit 6–7 h. Gezählt wird die Stufe von B, das Blatt
      // zeigt und ändert sie.
      Future<(_Env, int, int)> twoDevices(
        WidgetTester tester, {
        SleepBand? bandA,
      }) async {
        final env = (await tester.runAsync(() => _env()))!;
        final ids = (await tester.runAsync(() async {
          final a = await env.morning.add(_morning(0, hour: 6, band: bandA));
          final b = await env.morning.add(
            _morning(
              0,
              hour: 6,
              minute: 30,
              model: 'Modell B',
              band: SleepBand.from6to7,
            ),
          );
          return (a, b);
        }))!;
        return (env, ids.$1, ids.$2);
      }

      Future<Map<int, SleepBand?>> bands(WidgetTester t, _Env env) async => {
        for (final e in (await t.runAsync(env.morning.list))!)
          e.id: e.value.sleepBand,
      };

      String sleptAbout(int hours) => de
          ? 'Du hast rund $hours Stunden geschlafen.'
          : 'You slept about '
                '$hours hours.';

      void expectSelected(WidgetTester t, SleepBand b, bool selected) => expect(
        t.getSemantics(_key('readiness_sleep_${b.code}')),
        isSemantics(isChecked: selected),
        reason: b.code,
      );

      testWidgets('zwei Geräte: Blatt zeigt die gezählte Stufe des späteren', (
        tester,
      ) async {
        final (env, a, b) = await twoDevices(tester);
        final s = (await tester.runAsync(env.service.load))!;
        expect(s.sleepEntry!.measurementId, b);
        expect(s.sleepEntry!.band, SleepBand.from6to7);
        final sleep = s.result.factors.singleWhere(
          (f) => f.id == ReadinessFactorId.sleep,
        );
        expect(sleep.source, ReadinessFactorSource.selfReport);
        expect(
          s.result.facts
              .singleWhere((f) => f.kind == ReadinessFactKind.sleepDuration)
              .hours,
          sleepBandHours(SleepBand.from6to7),
        );
        await open(tester, s, actions: env.actions());
        expect(_key('readiness_detail_change_sleep'), findsOneWidget);
        await _tap(tester, 'readiness_detail_change_sleep');
        for (final band in SleepBand.values) {
          expectSelected(tester, band, band == SleepBand.from6to7);
        }
        expect(await bands(tester, env), containsPair(a, null));
      });

      testWidgets('zwei Geräte: Abwählen entfernt die Stufe an allen', (
        tester,
      ) async {
        final (env, a, b) = await twoDevices(tester);
        final s = (await tester.runAsync(env.service.load))!;
        await open(tester, s, actions: env.actions());
        await _tap(tester, 'readiness_detail_change_sleep');
        await _tap(tester, 'readiness_sleep_from6to7');
        await _tap(tester, 'readiness_sleep_done');
        await tester.runAsync(() async {});
        await tester.pumpAndSettle();
        final stored = await bands(tester, env);
        expect(stored[a], isNull);
        expect(stored[b], isNull);
        expect(_key('readiness_detail_missing_sleep'), findsOneWidget);
        expect(_key('readiness_detail_enter_sleep'), findsOneWidget);
        final after = (await tester.runAsync(env.service.load))!;
        expect(after.result.missing, contains(ReadinessFactorId.sleep));
        expect(after.sleepEntry!.measurementId, a);
        expect(after.sleepEntry!.band, isNull);
      });

      // Beide mit Stufe: die frühere zählt; Abwählen darf die spätere nicht
      // nachrücken lassen.
      testWidgets('zwei Geräte mit Stufe: Abwählen entfernt beide', (
        tester,
      ) async {
        final (env, a, b) = await twoDevices(tester, bandA: SleepBand.over8);
        final s = (await tester.runAsync(env.service.load))!;
        expect(s.sleepEntry!.measurementId, a);
        expect(s.sleepEntry!.band, SleepBand.over8);
        // Die Einschätzung zählt dieselbe Stufe wie das Blatt.
        expect(
          s.result.facts
              .singleWhere((f) => f.kind == ReadinessFactKind.sleepDuration)
              .hours,
          sleepBandHours(SleepBand.over8),
        );
        await open(tester, s, actions: env.actions());
        await _tap(tester, 'readiness_detail_change_sleep');
        for (final band in SleepBand.values) {
          expectSelected(tester, band, band == SleepBand.over8);
        }
        await _tap(tester, 'readiness_sleep_over8');
        await _tap(tester, 'readiness_sleep_done');
        await tester.runAsync(() async {});
        await tester.pumpAndSettle();
        final stored = await bands(tester, env);
        expect(stored[a], isNull);
        expect(stored[b], isNull);
        expect(_key('readiness_detail_missing_sleep'), findsOneWidget);
        final after = (await tester.runAsync(env.service.load))!;
        expect(after.result.missing, contains(ReadinessFactorId.sleep));
      });

      testWidgets('zwei Geräte: andere Stufe landet an derselben Messung', (
        tester,
      ) async {
        final (env, a, b) = await twoDevices(tester);
        final s = (await tester.runAsync(env.service.load))!;
        await open(tester, s, actions: env.actions());
        expect(find.textContaining(sleptAbout(7)), findsWidgets);
        await _tap(tester, 'readiness_detail_change_sleep');
        await _tap(tester, 'readiness_sleep_under5');
        await _tap(tester, 'readiness_sleep_done');
        await tester.runAsync(() async {});
        await tester.pumpAndSettle();
        final stored = await bands(tester, env);
        expect(stored[b], SleepBand.under5);
        expect(stored[a], isNull);
        // Detailseite: neue Stufe, die alte nirgends.
        expect(find.textContaining(sleptAbout(5)), findsWidgets);
        expect(find.textContaining(sleptAbout(7)), findsNothing);
        final after = (await tester.runAsync(env.service.load))!;
        expect(after.sleepEntry!.measurementId, b);
        expect(after.sleepEntry!.band, SleepBand.under5);
        // Karte auf „Heute“ aus demselben Stand.
        await _pump(
          tester,
          Scaffold(
            body: ReadinessCard(snapshot: after, onWhereFrom: () {}),
          ),
          locale: locale,
          width: width,
          scale: scale,
        );
        expect(_text('readiness_text'), contains(sleptAbout(5)));
        expect(_text('readiness_text'), isNot(contains(sleptAbout(7))));
      });

      testWidgets(
        'Sperre ohne Entwicklermodus: keine Knöpfe, kein Kamerabezug',
        (tester) async {
          final env = (await tester.runAsync(
            () => _env(today: true, dev: false),
          ))!;
          final s = (await tester.runAsync(env.service.load))!;
          expect(s.result.missing, contains(ReadinessFactorId.hrv));
          expect(s.sleepEntry, isNull);
          await open(tester, s, actions: env.actions());
          expect(_key('readiness_detail_enter_sleep'), findsNothing);
          expect(_key('readiness_detail_change_sleep'), findsNothing);
          expect(find.byType(TextButton), findsNothing);
          // Auch außerhalb des Morgenfensters kein Hinweis auf die nächste
          // Messung.
          final late = (await tester.runAsync(
            () => _env(today: true, dev: false, hour: 14),
          ))!;
          final sl = (await tester.runAsync(late.service.load))!;
          await tester.pumpWidget(const SizedBox());
          await open(tester, sl, actions: late.actions());
          for (final id in sl.result.missing) {
            expect(
              _key('readiness_detail_hint_${id.name}_nextMorningWindow'),
              findsNothing,
            );
          }
          expect(find.byType(TextButton), findsNothing);
          // Neuer Zustand der Seite für den Stand um 10 Uhr.
          await tester.pumpWidget(const SizedBox());
          await open(tester, s, actions: env.actions());
          for (final id in s.result.missing) {
            expect(
              _key('readiness_detail_start_morning_${id.name}'),
              findsNothing,
            );
            final text = _text('readiness_detail_missing_reason_${id.name}');
            for (final word in ['Kamera', 'amera', 'Zeitfenster', 'window']) {
              expect(text, isNot(contains(word)), reason: id.name);
            }
          }
          // Trotz gespeicherter Messung von heute: wie ohne Kamera.
          for (final id in ['hrv', 'restingHeartRate']) {
            expect(
              _text('readiness_detail_missing_reason_$id'),
              de ? 'Noch keine Messung.' : 'No measurement yet.',
            );
          }
          expect(
            _text('readiness_detail_missing_reason_sleep'),
            de
                ? 'Keine Nacht aus Health Connect.'
                : 'No night from Health Connect.',
          );
          expect(
            _key('readiness_detail_hint_sleep_sleepAtMorning'),
            findsNothing,
          );
        },
      );

      testWidgets('Karte und Detailseite nennen denselben HRV-Grund', (
        tester,
      ) async {
        final env = (await tester.runAsync(() => _env(today: true)))!;
        final s = (await tester.runAsync(env.service.load))!;
        expect(s.result.state, ReadinessState.limited);
        await open(tester, s);
        final reason = _text('readiness_detail_missing_reason_hrv');
        final detailFirst = _text('readiness_detail_reason_0');
        await _pump(
          tester,
          Scaffold(
            body: ReadinessCard(snapshot: s, onWhereFrom: () {}),
          ),
          locale: locale,
          width: width,
          scale: scale,
        );
        final prefix = 'HRV (RMSSD): $reason';
        expect(_text('readiness_text'), startsWith(prefix));
        expect(detailFirst, prefix);
      });
    });
  }
}
