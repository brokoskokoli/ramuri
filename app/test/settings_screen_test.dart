import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/camera_finder_screen.dart';
import 'package:running_app/features/settings/ppg_camera_measure_section.dart';

import 'app_harness.dart';

// Abschnitt „Kamera-Messung“ der Einstellungen (FR-0220) mit der Debug-Quelle: Standardkamera
// „kein Finger“ (5,4 mm), zweite „Finger“ (2,2 mm). Erfundene Kameras und Zahlen.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');

typedef _S = ({
  PpgCamera cam,
  StorageSession session,
  PpgCameraChoiceStore choice,
  FakeClock clock,
});

Future<_S> _setup(PpgCamera cam) async {
  final session = await FakeStorage().open(Uint8List(32));
  final clock = FakeClock(DateTime.utc(2026, 11, 24));
  return (
    cam: cam,
    session: session,
    choice: SettingsPpgCameraChoiceStore(session.settings, clock),
    clock: clock,
  );
}

DebugTestPpgCamera _debugCam({bool finger = true}) =>
    // Feste Wanduhr: je Takt (0,1 s) genau ein Bild je Kamera.
    DebugTestPpgCamera(wallClock: () => Duration.zero)
      ..setScenario(_std, DebugPpgScenario.noFinger)
      ..setScenario(
        _second,
        finger ? DebugPpgScenario.goodPulse : DebugPpgScenario.noFinger,
      );

Future<void> _pump(WidgetTester tester, _S s, String locale) async {
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(locale),
      home: Scaffold(
        body: ListView(
          children: [
            PpgCameraMeasureSection(
              camera: s.cam,
              settings: s.session.settings,
              clock: s.clock,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

String _current(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('settings_ppg_camera_current')))
    .data!;

/// Öffnet „Kamera suchen“, wartet auf die Empfehlung und tippt den Hauptknopf.
Future<void> _search(WidgetTester tester, Key button) async {
  await tester.tap(find.byKey(const Key('settings_ppg_camera_find')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(CameraFinderScreen), findsOneWidget);
  await tester.tap(find.byKey(button));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // Letzter Takt der Debug-Quelle läuft nach dem Abbestellen aus.
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final (locale, before, after, title, find0) in [
    (
      'de',
      'Standardkamera · 5,4 mm',
      'Kamera 0/2 · 2,2 mm',
      'Kamera-Messung',
      'Kamera suchen',
    ),
    (
      'en',
      'Default camera · 5.4 mm',
      'Camera 0/2 · 2.2 mm',
      'Camera measurement',
      'Find camera',
    ),
  ]) {
    testWidgets(
      '$locale: zeigt die geltende Kamera; „Kamera suchen“ ändert sie ohne Messung',
      (tester) async {
        final cam = _debugCam();
        final s = await _setup(cam);
        await _pump(tester, s, locale);
        expect(find.byKey(const Key('settings_ppg_camera')), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(find.text(find0), findsOneWidget);
        expect(_current(tester), before);

        await _search(tester, const Key('camera_finder_apply'));
        expect(find.byType(CameraFinderScreen), findsNothing);
        expect(await s.choice.readAuto(), _second);
        expect(_current(tester), after);
        // Keine Messung: keine Aufnahme gestartet, Taschenlampe aus.
        expect(cam.startedCameras, isEmpty);
        expect(cam.torchOn, isFalse);
        expect(cam.previewOn, isFalse);
        await _end(tester);
      },
    );
  }

  testWidgets('Suche öffnet die Seite für Nutzer: Erklärung, „Übernehmen“, '
      'keine Zahlen je Kamera', (tester) async {
    final cam = _debugCam();
    final s = await _setup(cam);
    await _pump(tester, s, 'de');
    await tester.tap(find.byKey(const Key('settings_ppg_camera_find')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text(
        'Dein Handy hat mehrere Kameras. Lege den Finger über Blitz und '
        'Kamera – die beleuchtete Kamera ist markiert.',
      ),
      findsOneWidget,
    );
    expect(find.text('Übernehmen'), findsOneWidget);
    expect(find.text('Weiter'), findsNothing);
    expect(find.byKey(CameraFinderScreen.numbersKey(_second)), findsNothing);
    expect(find.text('30 Bilder/s'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(await s.choice.readAuto(), isNull);
    expect(_current(tester), 'Standardkamera · 5,4 mm');
    await _end(tester);
  });

  testWidgets('ohne Empfehlung: „Standardkamera verwenden“ setzt die '
      'Standardkamera als Suchergebnis', (tester) async {
    final cam = _debugCam(finger: false);
    final s = await _setup(cam);
    await s.choice.setAuto(_second);
    await _pump(tester, s, 'de');
    expect(_current(tester), 'Kamera 0/2 · 2,2 mm');
    await _search(tester, const Key('camera_finder_default'));
    expect(await s.choice.readAuto(), _std);
    expect(_current(tester), 'Standardkamera · 5,4 mm');
    expect(cam.startedCameras, isEmpty);
    await _end(tester);
  });

  testWidgets('nur eine nutzbare Kamera: kein Abschnitt', (tester) async {
    final cam = FakePpgCamera()
      ..cameraList = const [
        PpgCameraInfo(ref: _std, isDefault: true, frameRate: 60),
        PpgCameraInfo(
          ref: PpgCameraRef('1'),
          unusable: PpgCameraUnusable.noFlash,
        ),
      ];
    final s = await _setup(cam);
    await _pump(tester, s, 'de');
    expect(find.byKey(const Key('settings_ppg_camera')), findsNothing);
    expect(find.text('Kamera-Messung'), findsNothing);
  });

  testWidgets('Kameraliste nicht lesbar: kein Abschnitt', (tester) async {
    final cam = _BrokenList();
    final s = await _setup(cam);
    await _pump(tester, s, 'de');
    expect(find.byKey(const Key('settings_ppg_camera')), findsNothing);
  });

  testWidgets('Einstellungen der App zeigen den Abschnitt mit Kamera', (
    tester,
  ) async {
    final d = Device()..ppgCamera = _debugCam();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_ppg_camera_current')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Kamera-Messung'), findsOneWidget);
    expect(_current(tester), 'Standardkamera · 5,4 mm');
  });

  testWidgets('Einstellungen der App ohne Kamera: kein Abschnitt', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await openOverview(tester);
    await tester.tap(find.byKey(const Key('home_settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings_ppg_camera')), findsNothing);
  });
}

class _BrokenList extends FakePpgCamera {
  @override
  Future<List<PpgCameraInfo>> cameras() async => throw StateError('kaputt');
}
