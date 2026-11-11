import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:running_app/features/measure/resting_measure_launcher.dart';
import 'package:running_app/features/measure/resting_measure_screen.dart';
import 'package:running_app/features/profile/profile_screen.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/features/setup/setup_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'measure_support.dart';

// Alle Werte synthetisch. Die Auswertung ist gescriptet; geprüft werden die
// Einstiege (Profil, Einrichtung) und was nach der Messung im Formular steht.

class _Spy extends RecalculationService {
  _Spy(StorageSession session, Clock clock)
    : super(
        session: session,
        clock: clock,
        calculation: ValueCalculationService(session: session, clock: clock),
      );

  int basisChanged = 0;

  /// Angebot, das [profileChanged] liefert (Stellvertreter für Läufe, die
  /// neu gerechnet werden könnten).
  RecalculationOffer? offerOnChange;

  @override
  Future<RecalculationOffer?> profileChanged({
    required ProfileRecord before,
    required ProfileRecord after,
  }) async =>
      offerOnChange ?? await super.profileChanged(before: before, after: after);

  @override
  Future<RecalculationOffer?> loadBasisChanged() {
    basisChanged++;
    final o = offerOnChange;
    return o != null ? Future.value(o) : super.loadBasisChanged();
  }

  @override
  Future<RecalculationOffer?> pendingOffer() {
    final o = offerOnChange;
    return o != null ? Future.value(o) : super.pendingOffer();
  }
}

Future<PpgMeasurement> _good(List<PpgFrame> f, PpgWindow w) async =>
    const PpgMeasurement(
      quality: PpgQuality.good,
      reasons: [],
      bpm: 52.4,
      rmssdMs: 40,
    );

class _Env {
  _Env._(this.session, this.clock, this.spy, this.recalc, this.cam);

  final StorageSession session;
  final FakeClock clock;
  final _Spy spy;
  final RecalculationController recalc;
  final HoldingCamera cam;

  static Future<_Env> make() async {
    final session = await FakeStorage().open(testKey);
    await session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    final clock = FakeClock(DateTime.utc(2026, 11, 10, 12));
    final spy = _Spy(session, clock);
    return _Env._(
      session,
      clock,
      spy,
      RecalculationController(spy),
      HoldingCamera(),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget Function(_Env) home, {
    bool withCamera = true,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(recalc.dispose);
    final app = MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: RamuriTheme.light,
      home: home(this),
    );
    await tester.pumpWidget(
      withCamera
          ? PpgCameraScope(camera: cam, evaluate: _good, child: app)
          : app,
    );
    await tester.pumpAndSettle();
  }
}

Widget _profile(_Env e) =>
    ProfileScreen(session: e.session, clock: e.clock, recalculation: e.recalc);

Widget _setup(_Env e) => SetupScreen(
  session: e.session,
  clock: e.clock,
  onFinished: () async {},
  serialize: e.recalc.exclusive,
);

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

/// Lässt eine Rückmeldung (SnackBar) ablaufen, bevor der Test den Baum abbaut.
Future<void> _expireSnackBar(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

bool _hasFocus(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('profile_resting')))
    .focusNode!
    .hasFocus;

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('profile_resting')))
    .controller!
    .text;

/// Sofort messen und bis zum Ergebnis Bilder einspielen.
Future<void> _measureUntilResult(WidgetTester tester, _Env e) async {
  await tapKey(tester, 'measure_mode_now');
  await tapKey(tester, 'measure_start');
  var t = 0.0;
  var k = 0;
  while (t <= 66.5) {
    e.cam.emitFrame(
      PpgFrame(
        t: t,
        r: 200,
        g: 40,
        r16: List.filled(16, 200),
        g16: List.filled(16, 40),
      ),
    );
    t += 0.5;
    if (++k % 10 == 0) await tester.pump();
  }
  await settle(tester);
}

/// Seite mit dem Einstieg und der Ausgabe des Ausgangs.
class _Launch extends StatelessWidget {
  const _Launch(this.e, this.onOutcome);
  final _Env e;
  final void Function(RestingMeasureOutcome) onOutcome;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      key: const Key('launch'),
      onPressed: () async {
        final launch = restingMeasureLauncher(
          camera: e.cam,
          profile: ProfileService(
            e.session.profile,
            e.clock,
            settings: e.session.settings,
          ),
          settings: e.session.settings,
          clock: e.clock,
          evaluate: _good,
        );
        onOutcome(await launch(context));
      },
      child: const Text('los'),
    ),
  );
}

void main() {
  for (final entry in <(String, Widget Function(_Env))>[
    ('Profil', _profile),
    ('Einrichtung', _setup),
  ]) {
    final name = entry.$1;
    final home = entry.$2;

    group('Einstieg $name', () {
      testWidgets('genau ein Knopf, öffnet die Messung', (tester) async {
        final e = await _Env.make();
        await e.pump(tester, home);
        expect(
          find.byKey(const Key('profile_resting_measure')),
          findsOneWidget,
        );
        expect(find.text('Mit der Kamera messen'), findsOneWidget);
        await tapKey(tester, 'profile_resting_measure');
        expect(find.byKey(const Key('measure_start')), findsOneWidget);
        expect(find.text('Ruhepuls messen'), findsWidgets);
      });

      testWidgets('nach Übernahme steht der neue Wert im Feld', (tester) async {
        final e = await _Env.make();
        await e.pump(tester, home);
        expect(_fieldText(tester), '60');
        await tapKey(tester, 'profile_resting_measure');
        await _measureUntilResult(tester, e);
        await tapKey(tester, 'measure_adopt');
        expect(find.byKey(const Key('measure_start')), findsNothing);
        expect(_fieldText(tester), '52');
        expect((await e.session.profile.read()).restingHeartRateBpm, 52);
        expect(_hasFocus(tester), isFalse);
        await _expireSnackBar(tester);
      });

      testWidgets('Verwerfen lässt das Feld unverändert', (tester) async {
        final e = await _Env.make();
        await e.pump(tester, home);
        await tapKey(tester, 'profile_resting_measure');
        await _measureUntilResult(tester, e);
        await tapKey(tester, 'measure_discard');
        expect(find.byKey(const Key('profile_resting')), findsOneWidget);
        expect(_fieldText(tester), '60');
        expect((await e.session.profile.read()).restingHeartRateBpm, 60);
      });

      testWidgets('Verwerfen nach Eingabe im Feld: Fokus bleibt weg', (
        tester,
      ) async {
        final e = await _Env.make();
        await e.pump(tester, home);
        // Wie im Gerätetest: Wert von Hand getippt, danach die Messung.
        await tester.tap(find.byKey(const Key('profile_resting')));
        await tester.pump();
        expect(_hasFocus(tester), isTrue);
        await tapKey(tester, 'profile_resting_measure');
        await _measureUntilResult(tester, e);
        await tapKey(tester, 'measure_discard');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile_resting')), findsOneWidget);
        expect(_hasFocus(tester), isFalse);
      });

      testWidgets('ohne Kamera: Selbst eintragen führt zum Feld', (
        tester,
      ) async {
        final e = await _Env.make();
        e.cam.availabilityState = PpgCameraAvailability.noCamera;
        await e.pump(tester, home);
        await tapKey(tester, 'profile_resting_measure');
        await tapKey(tester, 'measure_mode_now');
        await tapKey(tester, 'measure_start');
        expect(find.byKey(const Key('measure_manual')), findsOneWidget);
        await tapKey(tester, 'measure_manual');
        expect(find.byKey(const Key('profile_resting')), findsOneWidget);
        final field = tester.widget<TextField>(
          find.byKey(const Key('profile_resting')),
        );
        expect(field.focusNode!.hasFocus, isTrue);
        await tester.enterText(find.byKey(const Key('profile_resting')), '58');
        expect(_fieldText(tester), '58');
      });

      testWidgets('ohne Kamera-Scope kein Knopf, Feld bleibt', (tester) async {
        final e = await _Env.make();
        await e.pump(tester, home, withCamera: false);
        expect(find.byKey(const Key('profile_resting_measure')), findsNothing);
        expect(find.byKey(const Key('profile_resting')), findsOneWidget);
      });
    });
  }

  group('Zurück des Systems', () {
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('Einstieg: Seite schließt als verworfen', (tester) async {
      final e = await _Env.make();
      RestingMeasureOutcome? got;
      await e.pump(tester, (e) => _Launch(e, (o) => got = o));
      await tapKey(tester, 'launch');
      expect(find.byKey(const Key('measure_start')), findsOneWidget);
      await back(tester);
      expect(find.byKey(const Key('measure_start')), findsNothing);
      expect(got, RestingMeasureOutcome.discarded);
      expect(find.byKey(const Key('launch')), findsOneWidget);
    });

    testWidgets('Ergebnis: nichts übernommen, verworfen', (tester) async {
      final e = await _Env.make();
      RestingMeasureOutcome? got;
      await e.pump(tester, (e) => _Launch(e, (o) => got = o));
      await tapKey(tester, 'launch');
      await _measureUntilResult(tester, e);
      expect(find.byKey(const Key('measure_adopt')), findsOneWidget);
      await back(tester);
      expect(find.byKey(const Key('measure_adopt')), findsNothing);
      expect(got, RestingMeasureOutcome.discarded);
      expect(find.byKey(const Key('launch')), findsOneWidget);
      expect((await e.session.profile.read()).restingHeartRateBpm, 60);
    });

    testWidgets('Kein Wert: Seite schließt als verworfen', (tester) async {
      final e = await _Env.make();
      e.cam.availabilityState = PpgCameraAvailability.noCamera;
      RestingMeasureOutcome? got;
      await e.pump(tester, (e) => _Launch(e, (o) => got = o));
      await tapKey(tester, 'launch');
      await tapKey(tester, 'measure_mode_now');
      await tapKey(tester, 'measure_start');
      expect(find.byKey(const Key('measure_manual')), findsOneWidget);
      await back(tester);
      expect(find.byKey(const Key('measure_manual')), findsNothing);
      expect(got, RestingMeasureOutcome.discarded);
      expect(find.byKey(const Key('launch')), findsOneWidget);
    });

    testWidgets('im Profil: Feld bleibt, Wert nicht geändert', (tester) async {
      final e = await _Env.make();
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await _measureUntilResult(tester, e);
      await back(tester);
      expect(find.byKey(const Key('profile_resting')), findsOneWidget);
      expect(_fieldText(tester), '60');
      expect((await e.session.profile.read()).restingHeartRateBpm, 60);
      expect(_hasFocus(tester), isFalse);
    });
  });

  testWidgets('Profil: Übernahme meldet die Grundlage der Zonen neu', (
    tester,
  ) async {
    final e = await _Env.make();
    await e.pump(tester, _profile);
    await tapKey(tester, 'profile_resting_measure');
    await _measureUntilResult(tester, e);
    await tapKey(tester, 'measure_adopt');
    expect(e.spy.basisChanged, 1);
    await _expireSnackBar(tester);
  });

  group('Rückmeldung und Fokus im Profil', () {
    testWidgets('Übernahme: Profil gespeichert wie beim manuellen Speichern', (
      tester,
    ) async {
      final e = await _Env.make();
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await _measureUntilResult(tester, e);
      await tapKey(tester, 'measure_adopt');
      await tester.pumpAndSettle();
      expect(find.text('Profil gespeichert.'), findsOneWidget);
      expect(find.textContaining('Neuberechnung ist möglich'), findsNothing);
      await _expireSnackBar(tester);
    });

    testWidgets('Übernahme mit Angebot: Neuberechnung wird genannt', (
      tester,
    ) async {
      final e = await _Env.make();
      e.spy.offerOnChange = RecalculationOffer(
        causes: {RecalculationCause.heartRateBasis},
        runIds: [1],
      );
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await _measureUntilResult(tester, e);
      await tapKey(tester, 'measure_adopt');
      await tester.pumpAndSettle();
      expect(find.textContaining('Profil gespeichert.'), findsOneWidget);
      expect(find.textContaining('Neuberechnung ist möglich'), findsOneWidget);
      await _expireSnackBar(tester);
    });

    testWidgets('Verwerfen: keine Rückmeldung', (tester) async {
      final e = await _Env.make();
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await _measureUntilResult(tester, e);
      await tapKey(tester, 'measure_discard');
      await tester.pumpAndSettle();
      expect(find.text('Profil gespeichert.'), findsNothing);
    });

    testWidgets('Schließen bei Kein Wert: kein Fokus aufs Feld', (
      tester,
    ) async {
      final e = await _Env.make();
      e.cam.availabilityState = PpgCameraAvailability.noCamera;
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await tapKey(tester, 'measure_mode_now');
      await tapKey(tester, 'measure_start');
      await tapKey(tester, 'measure_close');
      expect(find.byKey(const Key('measure_manual')), findsNothing);
      expect(_hasFocus(tester), isFalse);
    });

    testWidgets('Zurück-Pfeil auf dem Einstieg: kein Fokus aufs Feld', (
      tester,
    ) async {
      final e = await _Env.make();
      await e.pump(tester, _profile);
      await tapKey(tester, 'profile_resting_measure');
      await tapKey(tester, 'measure_back');
      await settle(tester);
      expect(find.byKey(const Key('measure_start')), findsNothing);
      expect(_hasFocus(tester), isFalse);
    });
  });

  group('Seite wird mitten in der Messung aus dem Baum genommen', () {
    Future<RestingMeasureController> openHost(
      WidgetTester tester,
      _Env e,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: RamuriTheme.light,
          home: RestingMeasureHost(
            camera: e.cam,
            profile: ProfileService(
              e.session.profile,
              e.clock,
              settings: e.session.settings,
            ),
            settings: e.session.settings,
            clock: e.clock,
            evaluate: _good,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapKey(tester, 'measure_mode_now');
      return tester
          .widget<RestingMeasureScreen>(find.byType(RestingMeasureScreen))
          .controller;
    }

    Future<void> removeHost(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    }

    testWidgets(
      'während der Messung: Kamera gestoppt, Controller freigegeben',
      (tester) async {
        final e = await _Env.make();
        final c = await openHost(tester, e);
        await tapKey(tester, 'measure_start');
        for (var i = 0; i < 6; i++) {
          e.cam.emitFrame(
            PpgFrame(
              t: i * 0.5,
              r: 200,
              g: 40,
              r16: List.filled(16, 200),
              g16: List.filled(16, 40),
            ),
          );
        }
        await settle(tester);
        expect(c.phase, RestingMeasurePhase.measuring);
        expect(e.cam.torchOn, isTrue);
        await removeHost(tester);
        expect(e.cam.torchOn, isFalse);
        expect(e.cam.stopCount, greaterThan(0));
        expect(() => c.addListener(() {}), throwsFlutterError);
      },
    );

    testWidgets(
      'beim Starten (Rechteanfrage offen): Kamera startet nicht mehr',
      (tester) async {
        final e = await _Env.make();
        final hold = Completer<PpgCameraAvailability>();
        e.cam.hold = hold;
        final c = await openHost(tester, e);
        await tapKey(tester, 'measure_start');
        expect(c.phase, RestingMeasurePhase.starting);
        await removeHost(tester);
        hold.complete(PpgCameraAvailability.available);
        await settle(tester);
        expect(e.cam.startCount, 0);
        expect(e.cam.torchOn, isFalse);
        expect(() => c.addListener(() {}), throwsFlutterError);
      },
    );
  });
}
