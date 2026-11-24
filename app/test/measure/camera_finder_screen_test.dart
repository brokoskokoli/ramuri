import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/features/measure/camera_finder_screen.dart';

import '../helpers/widget_helpers.dart';

// Seite „Kamera finden“ (FR-0220, PAR-227, PAR-228) mit der Debug-Quelle: Standardkamera
// „kein Finger“, zweite „Finger“, dritte nicht nutzbar. Erfundene Kameras und Zahlen.

const _std = PpgCameraRef('0');
const _second = PpgCameraRef('0', '2');
const _noFlash = PpgCameraRef('1');

typedef _S = ({
  DebugTestPpgCamera cam,
  PpgCameraChoiceStore choice,
  SettingsDeveloperModeStore dev,
  List<PpgCameraRef?> results,
});

Future<_S> _setup() async {
  final session = await FakeStorage().open(Uint8List(32));
  final clock = FakeClock(DateTime.utc(2026, 11, 24));
  // Feste Wanduhr: je Takt (0,1 s) genau ein Bild je Kamera.
  final cam = DebugTestPpgCamera(wallClock: () => Duration.zero)
    ..setScenario(_std, DebugPpgScenario.noFinger)
    ..setScenario(_second, DebugPpgScenario.goodPulse);
  return (
    cam: cam,
    choice: SettingsPpgCameraChoiceStore(session.settings, clock),
    dev: SettingsDeveloperModeStore(session.settings, clock),
    results: <PpgCameraRef?>[],
  );
}

/// Startseite mit Knopf, der die Kamerasuche öffnet (wie die Entwicklereinstellungen).
Future<void> _open(
  WidgetTester tester,
  _S s, {
  String locale = 'de',
  bool dev = true,
  CameraFinderPurpose purpose = CameraFinderPurpose.developer,
}) async {
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(locale),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () async {
              final r = await Navigator.of(context).push<PpgCameraRef>(
                MaterialPageRoute(
                  builder: (_) => CameraFinderScreen(
                    camera: s.cam,
                    choice: s.choice,
                    developerMode: dev,
                    allowManual:
                        dev && purpose == CameraFinderPurpose.developer,
                    purpose: purpose,
                  ),
                ),
              );
              s.results.add(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // Letzter Takt der Debug-Quelle läuft nach dem Abbestellen aus.
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _tile(PpgCameraRef ref) => find.byKey(CameraFinderScreen.tileKey(ref));

/// Bild einer Kachel (oben in der Kachel, nie unter den Knöpfen).
Finder _image(PpgCameraRef ref) =>
    find.descendant(of: _tile(ref), matching: find.byType(AspectRatio));

void main() {
  testWidgets(
    'zwei Bilder, zweite Kamera „Finger erkannt“ und „Empfohlen“, Bildrate je Kamera; '
    'Übernehmen setzt das Suchergebnis, danach misst die zweite Kamera',
    (tester) async {
      final s = await _setup();
      await _open(tester, s);
      expect(find.text('Kamera finden'), findsOneWidget);
      expect(
        find.text(
          'Lege den Finger über Blitz und Kamera, wie bei der Messung.',
        ),
        findsOneWidget,
      );
      expect(s.cam.previewOn, isTrue);
      expect(s.cam.torchOn, isTrue);
      expect(s.cam.previewRequests.single, [_std, _second]);
      expect(_tile(_std), findsOneWidget);
      expect(_tile(_second), findsOneWidget);
      expect(_tile(_noFlash), findsNothing);
      expect(
        find.descendant(of: _tile(_std), matching: find.text('60 Bilder/s')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tile(_second), matching: find.text('30 Bilder/s')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _tile(_second),
          matching: find.text('Finger erkannt'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _tile(_std), matching: find.text('Kein Finger')),
        findsOneWidget,
      );
      expect(find.byKey(CameraFinderScreen.recommendedKey(_second)), findsOne);
      expect(find.byKey(CameraFinderScreen.recommendedKey(_std)), findsNothing);
      expect(find.text('Kameras werden nacheinander gezeigt'), findsNothing);
      // Entwicklermodus: Zahlen je Bild.
      expect(
        tester
            .widget<Text>(find.byKey(CameraFinderScreen.numbersKey(_second)))
            .data,
        'R/G 5,00 · 8,3 ms · ISO 100 · Licht 24.000',
      );
      await tester.tap(find.byKey(const Key('camera_finder_apply')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(s.results, [_second]);
      expect(await s.choice.readAuto(), _second);
      expect(await s.choice.readManual(), isNull);
      expect(s.cam.previewOn, isFalse);
      expect(s.cam.torchOn, isFalse);
      // Messung ohne Entwicklermodus und ohne Wahl von Hand: zweite Kamera.
      expect(
        await choosePpgCamera(
          camera: s.cam,
          developerMode: s.dev.read,
          choice: s.choice,
        ),
        _second,
      );
    },
  );

  testWidgets('englisch: Bildrate, Licht, Empfehlung', (tester) async {
    final s = await _setup();
    await _open(tester, s, locale: 'en');
    expect(find.text('Find camera'), findsOneWidget);
    expect(
      find.descendant(of: _tile(_std), matching: find.text('60 fps')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _tile(_second), matching: find.text('30 fps')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tile(_second),
        matching: find.text('Finger detected'),
      ),
      findsOneWidget,
    );
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Light'), findsNWidgets(2));
    await _close(tester);
  });

  testWidgets('Tipp auf die Standardkamera überstimmt die Empfehlung; '
      '„Als feste Wahl setzen“ setzt die Wahl von Hand', (tester) async {
    final s = await _setup();
    await _open(tester, s);
    await tester.tap(_image(_std));
    await tester.pump();
    expect(find.byKey(CameraFinderScreen.selectedKey(_std)), findsOne);
    await tester.tap(find.byKey(const Key('camera_finder_manual')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.results, [_std]);
    expect(await s.choice.readManual(), _std);
    expect(await s.choice.readAuto(), isNull);
    await s.dev.set(true);
    expect(
      await choosePpgCamera(
        camera: s.cam,
        developerMode: s.dev.read,
        choice: s.choice,
      ),
      _std,
    );
  });

  testWidgets('ohne Entwicklermodus keine Zahlen und keine feste Wahl', (
    tester,
  ) async {
    final s = await _setup();
    await _open(tester, s, dev: false);
    expect(find.byKey(CameraFinderScreen.numbersKey(_second)), findsNothing);
    expect(find.byKey(const Key('camera_finder_manual')), findsNothing);
    expect(find.textContaining('Bilder/s'), findsNothing);
    await _close(tester);
  });

  for (final (purpose, label) in [
    (CameraFinderPurpose.settings, 'Übernehmen'),
    (CameraFinderPurpose.measurement, 'Weiter'),
  ]) {
    testWidgets(
      'für Nutzer (${purpose.name}): Erklärung, „$label“, keine Zahlen '
      'und keine Bildrate; Tipp übernimmt die Kamera',
      (tester) async {
        final s = await _setup();
        await _open(tester, s, dev: false, purpose: purpose);
        expect(
          find.text(
            'Dein Handy hat mehrere Kameras. Lege den Finger über Blitz und '
            'Kamera – die beleuchtete Kamera ist markiert.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(CameraFinderScreen.numbersKey(_second)),
          findsNothing,
        );
        expect(find.textContaining('Bilder/s'), findsNothing);
        expect(find.byKey(const Key('camera_finder_manual')), findsNothing);
        expect(find.byKey(const Key('camera_finder_default')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('camera_finder_apply')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
        await tester.tap(_image(_std));
        await tester.pump();
        await tester.tap(find.byKey(const Key('camera_finder_apply')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 200));
        expect(s.results, [_std]);
        expect(await s.choice.readAuto(), _std);
        expect(await s.choice.readManual(), isNull);
        expect(s.cam.torchOn, isFalse);
      },
    );
  }

  testWidgets('für Nutzer ohne Empfehlung und ohne Tipp: „Standardkamera '
      'verwenden“; nach Tipp wieder „Weiter“', (tester) async {
    final s = await _setup();
    s.cam.setScenario(_second, DebugPpgScenario.noFinger);
    await _open(
      tester,
      s,
      dev: false,
      purpose: CameraFinderPurpose.measurement,
    );
    expect(find.byKey(const Key('camera_finder_apply')), findsNothing);
    expect(find.text('Standardkamera verwenden'), findsOneWidget);
    await tester.tap(_image(_second));
    await tester.pump();
    expect(find.byKey(const Key('camera_finder_default')), findsNothing);
    expect(find.text('Weiter'), findsOneWidget);
    await tester.tap(find.byKey(const Key('camera_finder_apply')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.results, [_second]);
    expect(await s.choice.readAuto(), _second);
    expect(s.cam.torchOn, isFalse);
  });

  testWidgets('für Nutzer ohne Empfehlung: „Standardkamera verwenden“ '
      'speichert die Standardkamera', (tester) async {
    final s = await _setup();
    s.cam.setScenario(_second, DebugPpgScenario.noFinger);
    await _open(
      tester,
      s,
      dev: false,
      purpose: CameraFinderPurpose.measurement,
    );
    await tester.tap(find.byKey(const Key('camera_finder_default')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(s.results, [_std]);
    expect(await s.choice.readAuto(), _std);
    expect(s.cam.torchOn, isFalse);
  });

  for (final (purpose, shown) in [
    (CameraFinderPurpose.measurement, true),
    (CameraFinderPurpose.settings, true),
    (CameraFinderPurpose.developer, false),
  ]) {
    testWidgets('nach Ende der Vorschau (${purpose.name}): '
        '„Standardkamera verwenden“ ${shown ? 'angeboten' : 'fehlt'}', (
      tester,
    ) async {
      final session = await FakeStorage().open(Uint8List(32));
      final clock = FakeClock(DateTime.utc(2026, 11, 24));
      final choice = SettingsPpgCameraChoiceStore(session.settings, clock);
      final cam = FakePpgCamera()
        ..cameraList = const [
          PpgCameraInfo(ref: _std, isDefault: true, frameRate: 60),
          PpgCameraInfo(ref: _second, frameRate: 30),
        ];
      final results = <PpgCameraRef?>[];
      await tester.pumpWidget(
        localizedApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () async => results.add(
                  await Navigator.of(context).push<PpgCameraRef>(
                    MaterialPageRoute(
                      builder: (_) => CameraFinderScreen(
                        camera: cam,
                        choice: choice,
                        purpose: purpose,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await cam.abortPreview(PpgCameraStopReason.busy);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('camera_finder_stopped')), findsOneWidget);
      expect(
        find.byKey(const Key('camera_finder_default')),
        shown ? findsOneWidget : findsNothing,
      );
      expect(find.byKey(const Key('camera_finder_apply')), findsNothing);
      if (!shown) return;
      await tester.tap(find.byKey(const Key('camera_finder_default')));
      await tester.pumpAndSettle();
      expect(results, [_std]);
      expect(await choice.readAuto(), _std);
    });
  }

  testWidgets(
    'Zurück: Vorschau gestoppt, Taschenlampe aus, nichts gespeichert',
    (tester) async {
      final s = await _setup();
      await _open(tester, s);
      await tester.tap(_image(_second));
      await tester.pump();
      await _close(tester);
      expect(s.results, [null]);
      expect(s.cam.previewOn, isFalse);
      expect(s.cam.torchOn, isFalse);
      expect(await s.choice.readAuto(), isNull);
      expect(await s.choice.readManual(), isNull);
    },
  );

  testWidgets(
    'Hintergrund: Vorschau gestoppt, Taschenlampe aus; zurück: läuft neu',
    (tester) async {
      final s = await _setup();
      await _open(tester, s);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(s.cam.previewOn, isFalse);
      expect(s.cam.torchOn, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(s.cam.previewRequests, hasLength(2));
      expect(s.cam.previewOn, isTrue);
      expect(find.byKey(CameraFinderScreen.recommendedKey(_second)), findsOne);
      await _close(tester);
      expect(s.cam.torchOn, isFalse);
      expect(await s.choice.readAuto(), isNull);
    },
  );

  testWidgets(
    'Wechselbetrieb: Hinweis, Bilder stehen, Empfehlung nach einem vollen '
    'Durchgang',
    (tester) async {
      final s = await _setup();
      s.cam.previewAlternating = true;
      await _open(tester, s);
      expect(find.text('Kameras werden nacheinander gezeigt'), findsOneWidget);
      // Bis 1,5 s ist nur die Standardkamera dran, danach bis 3,0 s die zweite.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(
        find.byKey(CameraFinderScreen.recommendedKey(_second)),
        findsNothing,
      );
      expect(
        find.descendant(of: _tile(_std), matching: find.text('Kein Finger')),
        findsOneWidget,
      );
      final grey = tester.widget<ColoredBox>(
        find
            .descendant(of: _tile(_std), matching: find.byType(ColoredBox))
            .first,
      );
      await tester.pump(const Duration(milliseconds: 900));
      // Zweite Kamera hat Finger, aber noch kein voller Durchgang.
      expect(
        find.descendant(
          of: _tile(_second),
          matching: find.text('Finger erkannt'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(CameraFinderScreen.recommendedKey(_second)),
        findsNothing,
      );
      // Das Bild der Standardkamera steht, solange die zweite dran ist.
      final still = tester.widget<ColoredBox>(
        find
            .descendant(of: _tile(_std), matching: find.byType(ColoredBox))
            .first,
      );
      expect(still.color, grey.color);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(CameraFinderScreen.recommendedKey(_second)), findsOne);
      await _close(tester);
      expect(s.cam.torchOn, isFalse);
    },
  );

  testWidgets('nur eine nutzbare Kamera: Hinweis, keine Vorschau', (
    tester,
  ) async {
    final session = await FakeStorage().open(Uint8List(32));
    final clock = FakeClock(DateTime.utc(2026, 11, 24));
    final cam = FakePpgCamera()
      ..cameraList = const [
        PpgCameraInfo(ref: _std, isDefault: true, frameRate: 60),
        PpgCameraInfo(ref: _noFlash, unusable: PpgCameraUnusable.noFlash),
      ];
    await tester.pumpWidget(
      localizedApp(
        home: CameraFinderScreen(
          camera: cam,
          choice: SettingsPpgCameraChoiceStore(session.settings, clock),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Nur eine Kamera, keine Auswahl nötig'), findsOneWidget);
    expect(cam.previewWith, isEmpty);
    expect(find.byKey(const Key('camera_finder_apply')), findsNothing);
  });

  testWidgets('ohne Empfehlung und ohne Tipp ist Übernehmen gesperrt', (
    tester,
  ) async {
    final s = await _setup();
    s.cam.setScenario(_second, DebugPpgScenario.noFinger);
    await _open(tester, s);
    final apply = tester.widget<FilledButton>(
      find.byKey(const Key('camera_finder_apply')),
    );
    expect(apply.onPressed, isNull);
    await tester.tap(_image(_std));
    await tester.pump();
    final after = tester.widget<FilledButton>(
      find.byKey(const Key('camera_finder_apply')),
    );
    expect(after.onPressed, isNotNull);
    await _close(tester);
    expect(await s.choice.readAuto(), isNull);
  });
}
