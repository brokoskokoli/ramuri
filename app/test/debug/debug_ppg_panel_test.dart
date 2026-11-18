import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_ppg_panel.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:running_app/features/measure/resting_measure_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

/// Prüft, dass Mitte und die vier Kantenmitten (je 2 dp nach innen) des
/// Widgets hinter [finder] einen Treffer auf dieses Widget ergeben, also
/// nichts darüber liegt (Kantenmitten statt Ecken: runde Knöpfe).
void expectFullyTappable(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  final r = tester.getRect(finder).deflate(2);
  for (final p in [
    r.center,
    r.centerLeft,
    r.centerRight,
    r.topCenter,
    r.bottomCenter,
  ]) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, p, tester.view.viewId);
    expect(
      result.path.any((e) => identical(e.target, box)),
      isTrue,
      reason: 'Punkt $p von ${finder.describeMatch(Plurality.one)} verdeckt',
    );
  }
}

void main() {
  testWidgets(
    'zugeklappt verdeckt das Feld bei 360 dp keinen Knopf der Messseite',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cam = DebugTestPpgCamera();
      final c = RestingMeasureController(
        camera: cam,
        clock: FakeClock(DateTime.utc(2026, 11, 10, 12, 0)),
        evaluate: (frames, window) async => const PpgMeasurement(
          quality: PpgQuality.unusable,
          reasons: [PpgQualityReason.insufficientData],
        ),
        autoTick: false,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        DebugPpgPanel(
          camera: cam,
          child: MaterialApp(
            theme: RamuriTheme.light,
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RestingMeasureScreen(
              controller: c,
              soundOn: ValueNotifier(true),
              onClose: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Haupt-Knopf über die ganze Breite und der Plus-Knopf am rechten Rand.
      for (final k in ['measure_start', 'measure_minutes_plus']) {
        final f = find.byKey(Key(k));
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        expect(f.hitTestable(), findsOneWidget, reason: k);
        expectFullyTappable(tester, f);
        // Der Knopf reicht nah an den rechten Rand, liegt aber nicht unter dem Feld.
        expect(
          tester.getRect(f).right,
          lessThanOrEqualTo(360 - DebugPpgPanel.collapsedWidth),
        );
      }
      // Zugeklappt sichtbar und bedienbar bleibt das Feld selbst.
      expect(find.text('PPG').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('Zeitraffer bleibt über Navigation und Zuklappen erhalten', (
    tester,
  ) async {
    final cam = DebugTestPpgCamera();
    await tester.pumpWidget(
      DebugPpgPanel(
        camera: cam,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: TextButton(
                      key: const Key('back'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('zurück'),
                    ),
                  ),
                ),
              ),
              child: const Text('weiter'),
            ),
          ),
        ),
      ),
    );
    // Beim Einschalten ist der Zustand schon am zugeklappten Knopf sichtbar.
    expect(find.text('PPG'), findsOneWidget);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    await tester.tap(find.textContaining('PPG Zeitraffer'));
    await tester.pump();
    expect(cam.speed, 30);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    expect(find.text('PPG x30'), findsOneWidget);

    await tester.tap(find.text('weiter'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('back')), findsOneWidget);
    expect(cam.speed, 30);
    expect(find.text('PPG x30'), findsOneWidget);
    await tester.tap(find.byKey(const Key('back')));
    await tester.pumpAndSettle();
    expect(cam.speed, 30);
    await tester.tap(find.textContaining(RegExp(r'^PPG( x30| x)?$')));
    await tester.pump();
    expect(find.text('PPG Zeitraffer an'), findsOneWidget);
  });

  testWidgets('Kachel einer Kamera setzt das Szenario nur für diese Kamera', (
    tester,
  ) async {
    final cam = DebugTestPpgCamera();
    await tester.pumpWidget(
      DebugPpgPanel(
        camera: cam,
        child: const MaterialApp(home: SizedBox()),
      ),
    );
    await tester.tap(find.text('PPG'));
    await tester.pump();
    expect(find.text('PPG Kamera 0'), findsOneWidget);
    expect(find.text('PPG Kamera 0/2'), findsOneWidget);
    expect(find.text('PPG Kamera 1'), findsOneWidget);
    // Vorgabe: Standardkamera.
    await tester.tap(find.text('PPG weakSignal'));
    await tester.pump();
    expect(cam.scenario, DebugPpgScenario.weakSignal);
    expect(
      cam.scenarioOf(const PpgCameraRef('0', '2')),
      DebugPpgScenario.goodPulse,
    );

    await tester.tap(find.text('PPG Kamera 0/2'));
    await tester.pump();
    await tester.tap(find.text('PPG busy'));
    await tester.pump();
    expect(cam.scenarioOf(const PpgCameraRef('0', '2')), DebugPpgScenario.busy);
    expect(cam.scenario, DebugPpgScenario.weakSignal);
    expect(cam.scenarioOf(const PpgCameraRef('1')), DebugPpgScenario.goodPulse);
  });
}
