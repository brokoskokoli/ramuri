import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  @override
  Future<RecalculationOffer?> loadBasisChanged() {
    basisChanged++;
    return super.loadBasisChanged();
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
  });
}
