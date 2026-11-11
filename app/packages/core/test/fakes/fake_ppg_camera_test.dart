import 'package:core/core.dart';
import 'package:test/test.dart';

PpgFrame _frame(double t) => PpgFrame(
  t: t,
  r: 200,
  g: 40,
  r16: List<double>.filled(16, 200),
  g16: List<double>.filled(16, 40),
);

void main() {
  test(
    'Torch ist nur an, solange der Strom läuft; Abbestellen schaltet aus',
    () async {
      final cam = FakePpgCamera();
      final sub = cam.start().listen((_) {});
      await pumpEvents();
      expect(cam.torchOn, isTrue);
      await sub.cancel();
      expect(cam.torchOn, isFalse);
    },
  );

  test('stop beendet den Strom und schaltet Torch aus', () async {
    final cam = FakePpgCamera();
    var done = false;
    cam.start().listen((_) {}, onDone: () => done = true);
    await pumpEvents();
    await cam.stop();
    await pumpEvents();
    expect(cam.torchOn, isFalse);
    expect(done, isTrue);
  });

  test(
    'Abbruch mit Grund (Hintergrund): Ereignis, Torch aus, Strom endet',
    () async {
      final cam = FakePpgCamera();
      final events = <PpgCameraEvent>[];
      var done = false;
      cam.start().listen(events.add, onDone: () => done = true);
      await pumpEvents();
      cam.emitFrame(_frame(0));
      await cam.abort(PpgCameraStopReason.background);
      await pumpEvents();
      expect(cam.torchOn, isFalse);
      expect(done, isTrue);
      expect(
        (events.last as PpgCameraStopped).reason,
        PpgCameraStopReason.background,
      );
      expect(events.whereType<PpgCameraFrame>(), hasLength(1));
    },
  );

  test(
    'ohne Kamera, Blitz oder Recht: Ergebnis mit Grund, Torch bleibt aus',
    () async {
      for (final (a, r) in [
        (PpgCameraAvailability.noCamera, PpgCameraStopReason.noCamera),
        (PpgCameraAvailability.noFlash, PpgCameraStopReason.noFlash),
        (
          PpgCameraAvailability.permissionDenied,
          PpgCameraStopReason.permissionDenied,
        ),
      ]) {
        final cam = FakePpgCamera(a);
        final events = await cam.start().toList();
        expect((events.single as PpgCameraStopped).reason, r);
        expect(cam.torchOn, isFalse);
      }
    },
  );

  test('Rechteanfrage ändert die Verfügbarkeit', () async {
    final cam = FakePpgCamera(PpgCameraAvailability.permissionDenied)
      ..afterPermissionRequest = PpgCameraAvailability.available;
    expect(await cam.availability(), PpgCameraAvailability.permissionDenied);
    expect(await cam.requestPermission(), PpgCameraAvailability.available);
    expect(cam.permissionRequests, 1);
  });
}

Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
