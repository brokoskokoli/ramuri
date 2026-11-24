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
  test('syntheticIsp: 19 Gleitkommawerte, Linsenzustand nicht gemeldet', () {
    final v = FakePpgCamera.syntheticIsp(1.5);
    expect(v, isA<List<double>>());
    expect(v, hasLength(ppgIspValueCount));
    expect(v[16], 11.5);
    expect(v[18].isNaN, isTrue);
  });

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

  test('Vorgabeliste: eine nutzbare Standardkamera mit 60 Bildern/s', () async {
    final list = await FakePpgCamera().cameras();
    expect(list.single.isDefault, isTrue);
    expect(list.single.usable, isTrue);
    expect(list.single.frameRate, 60);
  });

  group('Kamerawahl', () {
    const second = PpgCameraRef('2', '4');
    FakePpgCamera cam() => FakePpgCamera()
      ..cameraList = const [
        PpgCameraInfo(ref: PpgCameraRef('0'), isDefault: true),
        PpgCameraInfo(ref: second),
        PpgCameraInfo(
          ref: PpgCameraRef('3'),
          unusable: PpgCameraUnusable.frameRate,
        ),
      ];

    test('ohne Angabe: Standardkamera, started nennt sie', () async {
      final c = cam();
      final events = <PpgCameraEvent>[];
      c.start().listen(events.add);
      await pumpEvents();
      expect(
        (events.single as PpgCameraStarted).camera,
        const PpgCameraRef('0'),
      );
      expect(c.startedWith, [null]);
    });

    test('angegebene Kamera: genau diese', () async {
      final c = cam();
      final events = <PpgCameraEvent>[];
      c.start(camera: second).listen(events.add);
      await pumpEvents();
      expect((events.single as PpgCameraStarted).camera, second);
      expect(c.torchOn, isTrue);
    });

    test('unbekannte oder unbrauchbare Kamera: Grund, keine andere', () async {
      for (final (ref, reason) in [
        (const PpgCameraRef('9'), PpgCameraStopReason.noCamera),
        (const PpgCameraRef('3'), PpgCameraStopReason.frameRate),
      ]) {
        final c = cam();
        final events = await c.start(camera: ref).toList();
        expect((events.single as PpgCameraStopped).reason, reason);
        expect(c.torchOn, isFalse);
      }
    });
  });
}

Future<void> pumpEvents() => Future<void>.delayed(Duration.zero);
