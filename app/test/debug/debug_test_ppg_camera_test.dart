import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';

Future<List<PpgCameraEvent>> _run(DebugTestPpgCamera cam) =>
    cam.start().toList();

List<PpgFrame> _frames(List<PpgCameraEvent> e) => [
  for (final x in e.whereType<PpgCameraFrame>()) x.frame,
];

void main() {
  test('guter Puls: Auswertung findet ca. 70/min, Torch danach aus', () async {
    final cam = DebugTestPpgCamera(speed: 100000);
    final events = await _run(cam);
    expect(events.first, isA<PpgCameraStarted>());
    expect(events.whereType<PpgCameraExposureLocked>(), hasLength(1));
    expect(
      events.whereType<PpgCameraDetails>().first.iso,
      debugCameraDetails.iso,
    );
    expect(events.last, isA<PpgCameraFrame>());
    expect(cam.torchOn, isFalse);
    final m = evaluatePpg(_frames(events));
    expect(m.quality, isNot(PpgQuality.unusable));
    expect(m.bpm, closeTo(60 / 0.85, 2.0));
  });

  test('guter Puls: sendet im Suchmodus bis mindestens zur Höchstdauer der Aufnahme', () async {
    final cam = DebugTestPpgCamera(speed: 100000);
    final frames = _frames(await _run(cam));
    expect(frames.last.t, greaterThanOrEqualTo(ppgSearchMaxRecordSeconds));
  });

  test('ohne Anforderung: keine ISP-Werte, keine Schalter', () async {
    final cam = DebugTestPpgCamera(speed: 100000);
    final events = await _run(cam);
    final started = events.first as PpgCameraStarted;
    expect(started.diagnostics, isEmpty);
    expect(started.awbVariant, isNull);
    expect(
      events.whereType<PpgCameraFrame>().map((f) => f.isp),
      everyElement(isNull),
    );
    expect(cam.startedRequests, hasLength(1));
    expect(cam.startedRequests.single.diagnostics, isEmpty);
    expect(cam.startedRequests.single.ispFrames, isFalse);
  });

  test('mit Anforderung: angeforderte Schalter gesetzt, 19 ISP-Werte je Bild, '
      'Auswertung gleich', () async {
    final plain = _frames(await _run(DebugTestPpgCamera(speed: 100000)));
    final cam = DebugTestPpgCamera(speed: 100000);
    final events = await cam
        .start(
          diagnostics: {
            PpgCameraDiagnostic.noiseReductionOff,
            PpgCameraDiagnostic.awbFixed,
          },
          ispFrames: true,
        )
        .toList();
    final started = events.first as PpgCameraStarted;
    expect(started.diagnostics, {
      PpgCameraDiagnostic.noiseReductionOff,
      PpgCameraDiagnostic.awbFixed,
    });
    expect(started.awbVariant, PpgAwbVariant.matrix);
    final frames = events.whereType<PpgCameraFrame>().toList();
    expect(frames, isNotEmpty);
    for (final f in frames) {
      expect(f.isp, hasLength(ppgIspValueCount));
    }
    final isp = frames.first.isp!;
    expect(isp[7], 0); // Rauschunterdrückung aus
    expect(isp[8], 1); // Kanten unverändert
    expect(isp[5], 0); // AWB OFF
    expect(isp[11], debugCameraDetails.exposureTimeNs);
    // Einzelne Felder „nicht gemeldet“ kommen vor.
    expect(frames.where((f) => f.isp![18].isNaN), isNotEmpty);
    // Bildstatistik und damit die Auswertung wie ohne Anforderung.
    expect(
      frames.map((f) => f.frame.r).toList(),
      plain.map((f) => f.r).toList(),
    );
  });

  test('schlechtes Signal: Auswertung unbrauchbar, kein Wert', () async {
    final cam = DebugTestPpgCamera(
      scenario: DebugPpgScenario.weakSignal,
      speed: 100000,
    );
    final m = evaluatePpg(_frames(await _run(cam)));
    expect(m.quality, PpgQuality.unusable);
    expect(m.hasResult, isFalse);
  });

  test(
    'Szenario noFinger: R/G unter 1,5, Auswertung „kein Finger“ ohne Zahlen',
    () async {
      final cam = DebugTestPpgCamera(
        scenario: DebugPpgScenario.noFinger,
        speed: 100000,
      );
      final frames = _frames(await _run(cam));
      final meanR =
          frames.map((f) => f.r).reduce((a, b) => a + b) / frames.length;
      final meanG =
          frames.map((f) => f.g).reduce((a, b) => a + b) / frames.length;
      expect(meanR / meanG, lessThan(1.5));
      final m = evaluatePpg(frames);
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.hasResult, isFalse);
    },
  );

  test(
    'guter Puls und schwaches Signal haben R/G über 1,5 (Finger erkannt)',
    () async {
      for (final s in [
        DebugPpgScenario.goodPulse,
        DebugPpgScenario.weakSignal,
      ]) {
        final frames = _frames(
          await _run(DebugTestPpgCamera(scenario: s, speed: 100000)),
        );
        expect(
          evaluatePpg(frames).reasons,
          isNot(contains(PpgQualityReason.noFinger)),
        );
      }
    },
  );

  test('Zeitraffer gilt ab dem Start: Umschalten mitten in der Messung ändert nichts', () async {
    var wall = Duration.zero;
    final cam = DebugTestPpgCamera(speed: 1, wallClock: () => wall);
    final sub = cam.start().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cam.speed = 100000; // Panel: gilt erst ab dem nächsten Start
    wall = const Duration(seconds: 1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();
    // Echtzeit: nach 1 s Wanduhr höchstens etwa 30 Bilder, nicht die ganze Messung (ca. 2000).
    expect(cam.framesGenerated, lessThan(100));
  });

  test('Kamera belegt: Abbruch mit Grund, ohne Bilder', () async {
    final events = await _run(
      DebugTestPpgCamera(scenario: DebugPpgScenario.busy),
    );
    expect(
      (events.single as PpgCameraStopped).reason,
      PpgCameraStopReason.busy,
    );
  });

  test(
    'Getrennt mitten in der Messung: Bilder, dann Abbruch, Torch aus',
    () async {
      final cam = DebugTestPpgCamera(
        scenario: DebugPpgScenario.disconnected,
        speed: 100000,
      );
      final events = await _run(cam);
      expect(_frames(events), isNotEmpty);
      expect(
        (events.last as PpgCameraStopped).reason,
        PpgCameraStopReason.disconnected,
      );
      expect(cam.torchOn, isFalse);
    },
  );

  test('Recht verweigert bleibt auch nach der Anfrage verweigert', () async {
    final cam = DebugTestPpgCamera(scenario: DebugPpgScenario.permissionDenied);
    expect(await cam.availability(), PpgCameraAvailability.permissionDenied);
    expect(
      await cam.requestPermission(),
      PpgCameraAvailability.permissionDenied,
    );
    expect(cam.scenario, DebugPpgScenario.permissionDenied);
    expect(await cam.availability(), PpgCameraAvailability.permissionDenied);
    final events = await cam.start().toList();
    expect(events, [isA<PpgCameraStopped>()]);
    expect(
      (events.single as PpgCameraStopped).reason,
      PpgCameraStopReason.permissionDenied,
    );
  });

  test(
    'Recht fehlt bis zur Anfrage, dann erteilt; ohne Kamera nie verfügbar',
    () async {
      final cam = DebugTestPpgCamera(
        scenario: DebugPpgScenario.permissionGrantedOnRequest,
      );
      expect(await cam.availability(), PpgCameraAvailability.permissionDenied);
      expect(await cam.requestPermission(), PpgCameraAvailability.available);
      expect(await cam.availability(), PpgCameraAvailability.available);
      expect(
        await DebugTestPpgCamera(scenario: DebugPpgScenario.noCamera)
            .requestPermission(),
        PpgCameraAvailability.noCamera,
      );
    },
  );

  test(
    'Abbestellen beendet die Aufnahme sofort (Torch aus, keine Bilder mehr)',
    () async {
      final cam = DebugTestPpgCamera(speed: 1000);
      var n = 0;
      final sub = cam.start().listen((e) {
        if (e is PpgCameraFrame) n++;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cam.torchOn, isTrue);
      await sub.cancel();
      expect(cam.torchOn, isFalse);
      final seen = cam.framesGenerated;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cam.framesGenerated, seen);
      expect(n, lessThanOrEqualTo(seen));
    },
  );

  test('main_debug: dieselben Abhängigkeiten nutzen die Fake-Kamera', () {
    final cam = DebugTestPpgCamera();
    expect(
      identical(AppDependencies.create(ppgCamera: cam).ppgCamera, cam),
      isTrue,
    );
  });

  group('Kamerawahl (FR-0220)', () {
    test('cameras() liefert Standard, physische und Kamera ohne Blitz in dieser Reihenfolge', () async {
      final list = await DebugTestPpgCamera().cameras();
      expect(
        [for (final c in list) c.ref],
        [
          const PpgCameraRef('0'),
          const PpgCameraRef('0', '2'),
          const PpgCameraRef('1'),
        ],
      );
      expect([for (final c in list) c.isDefault], [true, false, false]);
      expect([for (final c in list) c.usable], [true, true, false]);
      expect(list[2].unusable, PpgCameraUnusable.noFlash);
      // Bildrate: Standard 60, die übrigen nutzbaren 30, die nicht nutzbare ohne.
      expect([for (final c in list) c.frameRate], [60, 30, null]);
    });

    test('ohne Rückkamera ist die Liste leer', () async {
      final cam = DebugTestPpgCamera(scenario: DebugPpgScenario.noCamera);
      expect(await cam.cameras(), isEmpty);
    });

    test('ohne Angabe startet die Standardkamera', () async {
      final cam = DebugTestPpgCamera(speed: 100000);
      final events = await cam.start().toList();
      expect(
        (events.first as PpgCameraStarted).camera,
        const PpgCameraRef('0'),
      );
      expect(cam.startedCameras, [const PpgCameraRef('0')]);
    });

    test(
      'Szenario je Kamera: zweite Kamera guter Puls, Standard schwach',
      () async {
        final cam = DebugTestPpgCamera(
          scenario: DebugPpgScenario.weakSignal,
          speed: 100000,
        );
        expect(
          cam.scenarioOf(const PpgCameraRef('0', '2')),
          DebugPpgScenario.goodPulse,
        );
        final second = await cam
            .start(camera: const PpgCameraRef('0', '2'))
            .toList();
        expect(
          (second.first as PpgCameraStarted).camera,
          const PpgCameraRef('0', '2'),
        );
        expect(evaluatePpg(_frames(second)).hasResult, isTrue);
        final first = await cam.start(camera: const PpgCameraRef('0')).toList();
        expect(evaluatePpg(_frames(first)).hasResult, isFalse);
        expect(cam.startedCameras, [
          const PpgCameraRef('0', '2'),
          const PpgCameraRef('0'),
        ]);
      },
    );

    test('setScenario gilt nur für die angegebene Kamera', () async {
      final cam = DebugTestPpgCamera(speed: 100000);
      cam.setScenario(const PpgCameraRef('0', '2'), DebugPpgScenario.busy);
      expect(cam.scenario, DebugPpgScenario.goodPulse);
      expect(
        cam.scenarioOf(const PpgCameraRef('0')),
        DebugPpgScenario.goodPulse,
      );
      final events = await cam
          .start(camera: const PpgCameraRef('0', '2'))
          .toList();
      expect(events, hasLength(1));
      expect(
        (events.single as PpgCameraStopped).reason,
        PpgCameraStopReason.busy,
      );
      cam.setScenario(const PpgCameraRef('0'), DebugPpgScenario.weakSignal);
      expect(cam.scenario, DebugPpgScenario.weakSignal);
    });

    test(
      'Kamera ohne Blitz endet mit noFlash, ohne andere Kamera und Torch',
      () async {
        final cam = DebugTestPpgCamera(speed: 100000);
        final events = await cam
            .start(camera: const PpgCameraRef('1'))
            .toList();
        expect(events, hasLength(1));
        expect(
          (events.single as PpgCameraStopped).reason,
          PpgCameraStopReason.noFlash,
        );
        expect(cam.startedCameras, isEmpty);
        expect(cam.torchOn, isFalse);
      },
    );

    test('unbekannte Kamera endet mit noCamera, ohne andere Kamera', () async {
      final cam = DebugTestPpgCamera(speed: 100000);
      final events = await cam.start(camera: const PpgCameraRef('7')).toList();
      expect(events, hasLength(1));
      expect(
        (events.single as PpgCameraStopped).reason,
        PpgCameraStopReason.noCamera,
      );
      expect(cam.startedCameras, isEmpty);
    });
  });
}
