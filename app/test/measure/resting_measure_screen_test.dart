import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:running_app/features/measure/resting_measure_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Alle Werte synthetisch. Die Auswertung ist gescriptet (kein echtes Signal);
// geprüft wird, was die Screens aus dem Zustand des Controllers machen.

/// Gescriptete Auswertung: Zwischenauswertung (`live`) und Endergebnis (`last`).
class Script {
  PpgMeasurement live = const PpgMeasurement(
    quality: PpgQuality.unusable,
    reasons: [PpgQualityReason.insufficientData],
  );
  PpgMeasurement last = const PpgMeasurement(
    quality: PpgQuality.good,
    reasons: [],
    bpm: 61.2,
    rmssdMs: 42.7,
  );

  Future<PpgMeasurement> call(List<PpgFrame> frames, PpgWindow window) async =>
      identical(window, ppgStandardWindow) ? last : live;
}

const goodLive = PpgMeasurement(
  quality: PpgQuality.good,
  reasons: [],
  bpm: 62.4,
  rmssdMs: 42.7,
);

PpgMeasurement unusable(PpgQualityReason r) =>
    PpgMeasurement(quality: PpgQuality.unusable, reasons: [r]);

class Rig {
  Rig._(
    this.cam,
    this.session,
    this.clock,
    this.script,
    this.c,
    this.sound,
    this.store,
  );

  final HoldingCamera cam;
  final StorageSession session;
  final FakeClock clock;
  final Script script;
  final RestingMeasureController c;
  final ValueNotifier<bool> sound;
  final FailingProfileStore store;
  final List<RestingMeasureOutcome> closed = [];
  double _t = 0;

  static Future<Rig> make({ProfileRecord? start}) async {
    final cam = HoldingCamera();
    final session = await FakeStorage().open(testKey);
    final clock = FakeClock(DateTime.utc(2026, 11, 10, 12, 0));
    if (start != null) await session.profile.save(start);
    final script = Script();
    final store = FailingProfileStore(session.profile);
    final c = RestingMeasureController(
      camera: cam,
      profile: ProfileService(store, clock, settings: session.settings),
      settings: session.settings,
      clock: clock,
      evaluate: script.call,
      autoTick: false,
    );
    return Rig._(cam, session, clock, script, c, ValueNotifier(true), store);
  }

  Future<void> show(
    WidgetTester tester, {
    required bool dark,
    String lang = 'de',
    double textScale = 1.0,
    bool pushed = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? RamuriTheme.dark : RamuriTheme.light,
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: pushed
            ? const SizedBox()
            : RestingMeasureScreen(
                controller: c,
                soundOn: sound,
                onClose: closed.add,
              ),
      ),
    );
    if (pushed) {
      // Als eigene Route über einer Startseite, damit „Zurück“ beobachtbar ist.
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator))
            .push(
              MaterialPageRoute<void>(
                builder: (_) => RestingMeasureScreen(
                  controller: c,
                  soundOn: sound,
                  onClose: closed.add,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Spielt Bilder bis Sensorzeit [until] ein (alle 0,5 s).
  Future<void> feed(WidgetTester tester, double until) async {
    var k = 0;
    while (_t <= until) {
      cam.emitFrame(
        PpgFrame(
          t: _t,
          r: 200,
          g: 40,
          r16: List.filled(16, 200),
          g16: List.filled(16, 40),
        ),
      );
      _t += 0.5;
      if (++k % 10 == 0) await tester.pump();
    }
    await settle(tester);
  }

  /// Sofort messen und bis [until] Sekunden Bilder einspielen.
  Future<void> measure(WidgetTester tester, double until) async {
    await c.startNow();
    await tester.pump();
    await feed(tester, until);
  }
}

Finder text(String s) => find.text(s);

/// Lässt die asynchronen Schritte des Controllers (Kamera lösen, Auswertung,
/// Profil lesen) durchlaufen.
Future<void> settle(WidgetTester tester) async {
  // Kamera lösen und Profil lesen laufen außerhalb der Testuhr.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

void expectTarget(WidgetTester tester, Finder f) {
  final size = tester.getSize(f);
  expect(size.width, greaterThanOrEqualTo(48), reason: '$f breit');
  expect(size.height, greaterThanOrEqualTo(48), reason: '$f hoch');
}

void expectNoHrv(WidgetTester tester) {
  expect(
    find.textContaining(RegExp('rmssd|hrv', caseSensitive: false)),
    findsNothing,
  );
  expect(find.textContaining('42'), findsNothing);
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';

    group('Einstieg ($mode)', () {
      testWidgets('Inhalt, Haltung, Dauer, Start', (tester) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        expect(text('Ruhepuls messen'), findsOneWidget);
        expect(text('Fingerkuppe locker auflegen'), findsOneWidget);
        expect(
          find.bySemanticsLabel(RegExp('Rückseite des Handys')),
          findsOneWidget,
        );
        expect(text('Kamera'), findsOneWidget);
        expect(text('Blitz'), findsOneWidget);
        expect(text('Erst entspannen'), findsOneWidget);
        expect(text('Ich bin entspannt, sofort messen'), findsOneWidget);
        expect(text('5 min'), findsOneWidget);
        expect(text('Entspannen und messen'), findsOneWidget);
        expect(find.textContaining('Kamera-Berechtigung'), findsOneWidget);
        expectNoHrv(tester);
        for (final k in [
          'measure_back',
          'measure_minutes_minus',
          'measure_minutes_plus',
          'measure_mode_relax',
          'measure_mode_now',
          'measure_start',
        ]) {
          expectTarget(tester, find.byKey(Key(k)));
        }

        await tester.tap(text('Liegend'));
        await tester.pump();
        expect(r.c.posture, RestingPosture.lying);
        await tapKey(tester, 'measure_minutes_plus');
        expect(r.c.restMinutes, 6);
        expect(text('6 min'), findsOneWidget);
        for (var i = 0; i < 20; i++) {
          await tapKey(tester, 'measure_minutes_plus');
        }
        expect(r.c.restMinutes, restingMaxRestMinutes);
        for (var i = 0; i < 20; i++) {
          await tapKey(tester, 'measure_minutes_minus');
        }
        expect(r.c.restMinutes, restingMinRestMinutes);

        // Noch keine Kamera und kein Recht beim Einstieg.
        expect(r.cam.permissionRequests, 0);
        await tapKey(tester, 'measure_start');
        expect(r.c.phase, RestingMeasurePhase.resting);
        expect(r.cam.permissionRequests, 0);
      });

      testWidgets('sofort messen: kein Dauerwähler, Start fragt das Recht', (
        tester,
      ) async {
        final r = await Rig.make();
        r.cam.hold = null;
        await r.show(tester, dark: dark);
        await tapKey(tester, 'measure_mode_now');
        expect(find.byKey(const Key('measure_minutes')), findsNothing);
        expect(text('Messung starten'), findsOneWidget);
        await tapKey(tester, 'measure_start');
        await tester.pump();
        expect(r.cam.permissionRequests, 1);
        expect(r.c.phase, RestingMeasurePhase.measuring);
      });
    });

    group('Ruhephase ($mode)', () {
      testWidgets('Restzeit, Sätze, Ton, Abbrechen, sofort messen', (
        tester,
      ) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        r.c.setPosture(RestingPosture.lying);
        r.c.setRestMinutes(3);
        r.c.startRest();
        await tester.pump();
        expect(text('3:00'), findsOneWidget);
        expect(text('noch von 3:00 min'), findsOneWidget);
        expect(text('Ruhephase · Liegend'), findsOneWidget);
        expect(text('Lass die Schultern sinken.'), findsOneWidget);
        expect(find.textContaining('Ein leiser Ton'), findsOneWidget);
        expect(find.bySemanticsLabel('Noch 3:00 Ruhephase'), findsOneWidget);
        // Kein Atemtempo in der Anleitung.
        expect(
          find.textContaining(RegExp('einatmen|ausatmen|Sekunden|zähl')),
          findsNothing,
        );
        for (final k in [
          'measure_cancel',
          'measure_sound',
          'measure_skip_rest',
        ]) {
          expectTarget(tester, find.byKey(Key(k)));
        }

        r.clock.advance(const Duration(seconds: 62));
        r.c.tick();
        await tester.pump();
        expect(text('1:58'), findsOneWidget);
        expect(text('Lass die Schultern sinken.'), findsNothing);
        expect(text('Gerade gibt es nichts zu erledigen.'), findsOneWidget);

        await tapKey(tester, 'measure_sound');
        expect(r.sound.value, isFalse);
        expect(find.textContaining('vibriert'), findsOneWidget);
        expect(find.textContaining('Ein leiser Ton'), findsNothing);
        expect(find.bySemanticsLabel('Ton aus, einschalten'), findsOneWidget);

        await tapKey(tester, 'measure_skip_rest');
        await tester.pump();
        expect(r.cam.permissionRequests, 1);
        expect(r.c.phase, RestingMeasurePhase.measuring);
      });

      testWidgets('Abbrechen beendet ohne Kamera', (tester) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        r.c.startRest();
        await tester.pump();
        await tapKey(tester, 'measure_cancel');
        await tester.pump();
        expect(r.c.stopCause, RestingStopCause.userCancelled);
        expect(r.closed, [RestingMeasureOutcome.cancelled]);
        expect(r.cam.permissionRequests, 0);
      });
    });

    group('Messung ($mode)', () {
      testWidgets('Einschwingen, guter Puls, Fortschritt', (tester) async {
        final r = await Rig.make();
        r.script.live = goodLive;
        await r.show(tester, dark: dark);
        await r.measure(tester, 2);
        expect(text('Messung · Sitzend'), findsOneWidget);
        expect(text('Einschwingen, Finger ruhig halten'), findsOneWidget);
        expect(text('0 von 60 s'), findsOneWidget);
        expect(text('–'), findsOneWidget);
        expect(text('wird gesucht'), findsOneWidget);

        await r.feed(tester, 30);
        expect(find.byKey(const Key('measure_pulse')), findsOneWidget);
        expect(text('62'), findsOneWidget);
        expect(text('geschätzt'), findsOneWidget);
        expect(text('Signal gut'), findsNWidgets(2)); // Kopf und Hinweis
        expect(text('Ruhig halten'), findsOneWidget);
        expect(text('25 von 60 s'), findsOneWidget);
        expect(text('Pulskurve, letzte 5 s'), findsOneWidget);
        expect(text('Abbrechen'), findsOneWidget);
        expectNoHrv(tester);
        expectTarget(tester, find.byKey(const Key('measure_cancel')));
      });

      final hints = {
        PpgQualityReason.weakSignal: (
          'Signal schwach',
          'Deck Kamera und Blitz',
        ),
        PpgQualityReason.flatSignal: (
          'Kaum Schwankung im Signal',
          'Prüf, ob Kamera und Blitz',
        ),
        PpgQualityReason.tooManyDisturbances: (
          'Signal gestört',
          'Leg Hand und Handy ruhig ab',
        ),
      };
      hints.forEach((reason, texts) {
        testWidgets('Hinweis ${reason.name}: Uhr läuft weiter', (tester) async {
          final r = await Rig.make();
          r.script.live = unusable(reason);
          await r.show(tester, dark: dark);
          await r.measure(tester, 20);
          expect(text(texts.$1), findsWidgets);
          expect(find.textContaining(texts.$2), findsOneWidget);
          expect(text('–'), findsOneWidget);
          expect(
            text('Finger justieren, die Zeit läuft weiter'),
            findsOneWidget,
          );
          expect(text('15 von 60 s'), findsOneWidget);
          await r.feed(tester, 40);
          expect(text('35 von 60 s'), findsOneWidget);
          expect(r.c.phase, RestingMeasurePhase.measuring);
        });
      });

      testWidgets('ohne Meldung der Auswertung kein erfundener Hinweis', (
        tester,
      ) async {
        final r = await Rig.make();
        // Zu wenige Daten: die Auswertung nennt keinen Grund für einen Hinweis.
        await r.show(tester, dark: dark);
        await r.measure(tester, 20);
        expect(text('Finger ruhig halten'), findsOneWidget);
        expect(find.textContaining('zu fest'), findsNothing);
        expect(find.textContaining('verrutscht'), findsNothing);
        expect(find.textContaining('dunkel'), findsNothing);
      });

      testWidgets('Abbrechen', (tester) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        await r.measure(tester, 10);
        await tapKey(tester, 'measure_cancel');
        await tester.pump();
        expect(r.c.stopCause, RestingStopCause.userCancelled);
        expect(r.closed, [RestingMeasureOutcome.cancelled]);
        expect(r.cam.stopCount, greaterThan(0));
      });
    });

    group('Ergebnis ($mode)', () {
      testWidgets('Wert als Schätzung, Angaben, Übernehmen nur per Tipp', (
        tester,
      ) async {
        final r = await Rig.make(
          start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
        );
        await r.show(tester, dark: dark);
        r.c.setPosture(RestingPosture.lying);
        await r.measure(tester, 67);
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(text('Messung fertig'), findsOneWidget);
        expect(find.byKey(const Key('measure_result_bpm')), findsOneWidget);
        expect(text('61'), findsOneWidget);
        expect(text('geschätzt'), findsOneWidget);
        expect(find.byType(EmberDot), findsOneWidget);
        expect(text('gut'), findsOneWidget);
        expect(find.textContaining('zeitweise schwach'), findsNothing);
        expect(text('Liegend'), findsOneWidget);
        expect(find.textContaining('10. Nov'), findsOneWidget);
        expect(text('keine Ruhephase'), findsOneWidget);
        expect(
          find.textContaining('Bisher im Profil: 64, von Hand eingetragen.'),
          findsOneWidget,
        );
        expectNoHrv(tester);
        expectTarget(tester, find.byKey(const Key('measure_adopt')));
        expectTarget(tester, find.byKey(const Key('measure_discard')));
        expectTarget(tester, find.byKey(const Key('measure_close')));

        // Nichts wird von selbst übernommen.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect((await r.session.profile.read()).restingHeartRateBpm, 64);
        expect(r.closed, isEmpty);

        await tapKey(tester, 'measure_adopt');
        await settle(tester);
        expect((await r.session.profile.read()).restingHeartRateBpm, 61);
        expect(r.c.phase, RestingMeasurePhase.adopted);
        expect(r.closed, [RestingMeasureOutcome.adopted]);
      });

      testWidgets('eingeschränkte Qualität', (tester) async {
        final r = await Rig.make();
        r.script.last = const PpgMeasurement(
          quality: PpgQuality.limited,
          reasons: [PpgQualityReason.lowSignalQuality],
          bpm: 58.4,
        );
        await r.show(tester, dark: dark);
        await r.measure(tester, 67);
        expect(text('58'), findsOneWidget);
        expect(text('eingeschränkt'), findsOneWidget);
        expect(find.textContaining('zeitweise schwach'), findsOneWidget);
        expect(find.textContaining('Bisher im Profil'), findsNothing);
      });

      testWidgets('Verwerfen speichert nichts', (tester) async {
        final r = await Rig.make(
          start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
        );
        await r.show(tester, dark: dark);
        await r.measure(tester, 67);
        await tapKey(tester, 'measure_discard');
        await tester.pump();
        expect((await r.session.profile.read()).restingHeartRateBpm, 64);
        expect(r.c.phase, RestingMeasurePhase.discarded);
        expect(r.closed, [RestingMeasureOutcome.discarded]);
      });

      testWidgets('Schließen übernimmt nichts', (tester) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        await r.measure(tester, 67);
        await tapKey(tester, 'measure_close');
        expect((await r.session.profile.read()).restingHeartRateBpm, isNull);
        expect(r.closed, [RestingMeasureOutcome.dismissed]);
        expect(r.c.phase, RestingMeasurePhase.result);
      });
    });

    group('Kein Wert ($mode)', () {
      testWidgets('Ergebnis ohne Wert: Grund, Tipps, Noch einmal', (
        tester,
      ) async {
        final r = await Rig.make();
        r.script.last = unusable(PpgQualityReason.weakSignal);
        await r.show(tester, dark: dark);
        await r.measure(tester, 67);
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(text('Kein Wert diesmal'), findsOneWidget);
        expect(text('Das Signal war zu schwach'), findsOneWidget);
        expect(text('So klappt es eher'), findsOneWidget);
        expect(find.textContaining('Kalte Finger'), findsOneWidget);
        expect(find.byKey(const Key('measure_adopt')), findsNothing);
        expect(find.byKey(const Key('measure_discard')), findsNothing);
        expect(find.byKey(const Key('measure_result_bpm')), findsNothing);
        expect(text('Ins Profil übernehmen'), findsNothing);
        expect(
          find.textContaining('selbst im Profil eintragen'),
          findsOneWidget,
        );
        expectNoHrv(tester);
        expectTarget(tester, find.byKey(const Key('measure_retry')));
        expectTarget(tester, find.byKey(const Key('measure_manual')));
        expectTarget(tester, find.byKey(const Key('measure_close')));

        await tapKey(tester, 'measure_retry');
        await tester.pump();
        expect(r.cam.permissionRequests, 2);
        expect(r.c.phase, RestingMeasurePhase.measuring);
      });

      final reasons = {
        PpgQualityReason.frameGap: 'Die Messung wurde unterbrochen',
        PpgQualityReason.flatSignal: 'Das Signal blieb gleich',
        PpgQualityReason.tooManyDisturbances: 'Das Signal war zu unruhig',
        PpgQualityReason.insufficientData: 'Es kamen zu wenige Daten zusammen',
        PpgQualityReason.analysisFailed: 'Die Auswertung hat nicht geklappt',
      };
      reasons.forEach((reason, title) {
        testWidgets('Grund ${reason.name}', (tester) async {
          final r = await Rig.make();
          r.script.last = unusable(reason);
          await r.show(tester, dark: dark);
          await r.measure(tester, 67);
          expect(text(title), findsOneWidget);
          expect(find.byKey(const Key('measure_adopt')), findsNothing);
        });
      });

      final causes = {
        PpgCameraAvailability.permissionDenied: 'Kamera nicht erlaubt',
        PpgCameraAvailability.noCamera: 'Keine Kamera gefunden',
        PpgCameraAvailability.noFlash: 'Kein Blitz gefunden',
      };
      causes.forEach((availability, title) {
        testWidgets('Abbruch ${availability.name}: kein Noch einmal', (
          tester,
        ) async {
          final r = await Rig.make();
          r.cam.availabilityState = availability;
          await r.show(tester, dark: dark);
          await r.c.startNow();
          await tester.pump();
          await tester.pump();
          expect(text('Kein Wert diesmal'), findsOneWidget);
          expect(text(title), findsOneWidget);
          expect(find.byKey(const Key('measure_retry')), findsNothing);
          expect(find.byKey(const Key('measure_tips')), findsNothing);
          expect(find.textContaining('selbst im Profil'), findsOneWidget);
          expect(r.closed, isEmpty);
        });
      });

      testWidgets('Unterbrechung der Bilder: Grund und Noch einmal', (
        tester,
      ) async {
        final r = await Rig.make();
        await r.show(tester, dark: dark);
        await r.measure(tester, 10);
        r.cam.emitFrame(
          PpgFrame(
            t: 20,
            r: 200,
            g: 40,
            r16: List.filled(16, 200),
            g16: List.filled(16, 40),
          ),
        );
        await settle(tester);
        expect(r.c.stopCause, RestingStopCause.interrupted);
        expect(text('Die Messung wurde unterbrochen'), findsOneWidget);
        expect(find.byKey(const Key('measure_retry')), findsOneWidget);
        expect(find.byKey(const Key('measure_tips')), findsOneWidget);
      });
    });
  }

  group('Übernahme: Fehlerweg und Sperre', () {
    testWidgets(
      'Speichern scheitert: Hinweis, Ergebnis bleibt, nichts übernommen',
      (tester) async {
        final r = await Rig.make(
          start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
        );
        await r.show(tester, dark: false);
        await r.measure(tester, 67);
        expect(find.byKey(const Key('measure_adopt_error')), findsNothing);
        r.store.failSave = true;
        await tapKey(tester, 'measure_adopt');
        expect(
          find.descendant(
            of: find.byKey(const Key('measure_adopt_error')),
            matching: text(
              'Der Wert konnte nicht gespeichert werden. Bitte versuch es noch einmal.',
            ),
          ),
          findsOneWidget,
        );
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(r.closed, isEmpty);
        expect((await r.session.profile.read()).restingHeartRateBpm, 64);
        expect(await RestingHrOrigin.read(r.session.settings), isNull);
        // Erneut möglich.
        r.store.failSave = false;
        await tapKey(tester, 'measure_adopt');
        expect(r.closed, [RestingMeasureOutcome.adopted]);
        expect(find.byKey(const Key('measure_adopt_error')), findsNothing);
      },
    );

    testWidgets(
      'Profil lehnt den Wert ab: eigener Hinweis, nichts gespeichert',
      (tester) async {
        final r = await Rig.make(
          start: const ProfileRecord(
            restingHeartRateBpm: 40,
            maxHeartRateBpm: 55,
            birthYear: 1986,
          ),
        );
        await r.show(tester, dark: false);
        await r.measure(tester, 67);
        await tapKey(tester, 'measure_adopt');
        expect(r.c.adoptRejection, isNotNull);
        expect(
          find.descendant(
            of: find.byKey(const Key('measure_adopt_error')),
            matching: text(
              'Das Profil hat den Wert nicht angenommen. Es wurde nichts gespeichert.',
            ),
          ),
          findsOneWidget,
        );
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(r.closed, isEmpty);
        expect((await r.session.profile.read()).restingHeartRateBpm, 40);
      },
    );

    testWidgets(
      'während der Übernahme: Schließen, Verwerfen und Zurück gesperrt',
      (tester) async {
        final r = await Rig.make(
          start: const ProfileRecord(restingHeartRateBpm: 64, birthYear: 1986),
        );
        await r.show(tester, dark: false, pushed: true);
        await r.measure(tester, 67);
        final hold = Completer<void>();
        r.store.holdSave = hold;
        await tester.tap(find.byKey(const Key('measure_adopt')));
        await settle(tester);
        expect(r.c.adopting, isTrue);

        await tester.tap(find.byKey(const Key('measure_close')));
        await tester.tap(find.byKey(const Key('measure_discard')));
        await tester.pump();
        await tester.binding.handlePopRoute();
        await settle(tester);
        await tester.pump(const Duration(seconds: 1)); // Seitenanimation
        expect(r.closed, isEmpty);
        expect(r.c.phase, RestingMeasurePhase.result);
        expect(find.byKey(const Key('measure_adopt')), findsOneWidget);

        hold.complete();
        await settle(tester);
        expect(r.closed, [RestingMeasureOutcome.adopted]);
        expect((await r.session.profile.read()).restingHeartRateBpm, 61);
      },
    );

    testWidgets(
      'Zurück nach dem Ergebnis (nicht übernehmend) verlässt die Seite',
      (tester) async {
        final r = await Rig.make();
        await r.show(tester, dark: false, pushed: true);
        await r.measure(tester, 67);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('measure_adopt')), findsNothing);
      },
    );
  });

  group('Ruhephase im Hintergrund', () {
    testWidgets('Zeit um, App nicht vorn: Hinweis, Start bei Rückkehr', (
      tester,
    ) async {
      final r = await Rig.make();
      await r.show(tester, dark: false);
      r.c.setRestMinutes(3);
      r.c.startRest();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      r.clock.advance(const Duration(minutes: 3, seconds: 1));
      r.c.tick();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(r.c.waitingForForeground, isTrue);
      expect(
        text('Die Messung beginnt, sobald du wieder in der App bist.'),
        findsOneWidget,
      );
      expect(r.c.phase, RestingMeasurePhase.resting);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(r.c.phase, RestingMeasurePhase.measuring);
    });
  });

  group('Englisch', () {
    testWidgets('Einstieg, Ergebnis und Hinweis erscheinen auf Englisch', (
      tester,
    ) async {
      final r = await Rig.make();
      await r.show(tester, dark: false, lang: 'en');
      expect(text('Measure resting heart rate'), findsOneWidget);
      await r.measure(tester, 67);
      expect(text('Measurement done'), findsOneWidget);
      expect(text('Adopt into profile'), findsOneWidget);
      r.store.failSave = true;
      await tapKey(tester, 'measure_adopt');
      expect(
        text('The value could not be saved. Please try again.'),
        findsOneWidget,
      );
    });
  });

  group('Lebenszyklus', () {
    void lifecycle(WidgetTester tester, AppLifecycleState s) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }

    testWidgets('inactive und hidden brechen nicht ab, paused schon', (
      tester,
    ) async {
      final r = await Rig.make();
      await r.show(tester, dark: false);
      await r.measure(tester, 10);
      lifecycle(tester, AppLifecycleState.inactive);
      await settle(tester);
      lifecycle(tester, AppLifecycleState.hidden);
      await settle(tester);
      expect(r.c.phase, RestingMeasurePhase.measuring);
      expect(text('Messung · Sitzend'), findsOneWidget);
      lifecycle(tester, AppLifecycleState.paused);
      await settle(tester);
      expect(r.c.phase, RestingMeasurePhase.stopped);
      expect(r.c.stopCause, RestingStopCause.background);
      // Im Hintergrund zeichnet die Testumgebung nicht; erst nach der Rückkehr.
      lifecycle(tester, AppLifecycleState.inactive);
      lifecycle(tester, AppLifecycleState.resumed);
      await settle(tester);
      expect(text('Die Messung wurde beendet'), findsOneWidget);
      expect(find.byKey(const Key('measure_retry')), findsOneWidget);
    });

    testWidgets('Rechtedialog (inactive) während der Anfrage bricht nicht ab', (
      tester,
    ) async {
      final r = await Rig.make();
      r.cam.hold = Completer<PpgCameraAvailability>();
      await r.show(tester, dark: false);
      final start = r.c.startNow();
      await tester.pump();
      lifecycle(tester, AppLifecycleState.inactive);
      await tester.pump();
      expect(text('Kamera wird gestartet'), findsOneWidget);
      r.cam.hold!.complete(PpgCameraAvailability.available);
      await start;
      await tester.pump();
      expect(r.c.phase, RestingMeasurePhase.measuring);
    });

    testWidgets('Zurück während der Messung bricht ab', (tester) async {
      final r = await Rig.make();
      await r.show(tester, dark: false);
      await r.measure(tester, 10);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(r.c.stopCause, RestingStopCause.userCancelled);
    });
  });
}
