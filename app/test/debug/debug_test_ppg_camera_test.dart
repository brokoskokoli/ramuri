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
    expect(events.last, isA<PpgCameraFrame>());
    expect(cam.torchOn, isFalse);
    final m = evaluatePpg(_frames(events));
    expect(m.quality, isNot(PpgQuality.unusable));
    expect(m.bpm, closeTo(60 / 0.85, 2.0));
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

  test('Recht fehlt bis zur Anfrage; ohne Kamera nie verfügbar', () async {
    final cam = DebugTestPpgCamera(scenario: DebugPpgScenario.permissionDenied);
    expect(await cam.availability(), PpgCameraAvailability.permissionDenied);
    expect(await cam.requestPermission(), PpgCameraAvailability.available);
    expect(
      await DebugTestPpgCamera(scenario: DebugPpgScenario.noCamera)
          .requestPermission(),
      PpgCameraAvailability.noCamera,
    );
  });

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
}
