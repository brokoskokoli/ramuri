import 'dart:async';
import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _frame(double t) => {
  'type': 'frame',
  't': t,
  'r': 200.0,
  'g': 40.0,
  'r16': List<double>.filled(16, 200),
  'g16': List<double>.filled(16, 40),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const method = MethodChannel(ppgCameraChannelName);
  const events = EventChannel(ppgCameraStreamChannelName);
  const perms = MethodChannel(permissionChannelName);

  String availability = 'available';
  String afterRequest = 'available';
  final calls = <String>[];
  StreamController<Object?>? sink;
  var cancelled = 0;
  Object? listenArgs = 'nie';
  Object? cameraList;
  // Nachbildung von Kotlin: torchOn wie in der Hardware, onCancel schaltet aus.
  var torchOn = false;

  setUp(() {
    availability = 'available';
    afterRequest = 'available';
    calls.clear();
    cancelled = 0;
    listenArgs = 'nie';
    cameraList = null;
    torchOn = false;
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add('ppg:${call.method}');
      if (call.method == 'availability') return availability;
      if (call.method == 'cameras') return cameraList;
      if (call.method == 'stop') torchOn = false;
      return null;
    });
    messenger.setMockMethodCallHandler(perms, (call) async {
      calls.add('perm:${call.method}');
      return call.method == 'requestCamera' ? afterRequest : null;
    });
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, e) {
          listenArgs = arguments;
          torchOn = true;
          sink = StreamController<Object?>(sync: true)
            ..stream.listen(
              e.success,
              onError: (Object x) {
                final c = x is PlatformException ? x.code : 'error';
                e.error(code: c);
              },
              onDone: e.endOfStream,
            );
        },
        onCancel: (arguments) {
          cancelled++;
          torchOn = false;
        },
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockMethodCallHandler(perms, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('Kanalnamen stimmen mit PpgCamera.kt überein', () {
    final kt = File(
      '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgCamera.kt',
    ).readAsStringSync();
    expect(kt, contains('"$ppgCameraChannelName"'));
    expect(kt, contains('"$ppgCameraStreamChannelName"'));
  });

  test('Verfügbarkeit aus den Kotlin-Zuständen', () async {
    final c = MethodChannelPpgCamera();
    expect(await c.availability(), PpgCameraAvailability.available);
    for (final (s, a) in [
      ('permission_denied', PpgCameraAvailability.permissionDenied),
      ('no_flash', PpgCameraAvailability.noFlash),
      ('no_camera', PpgCameraAvailability.noCamera),
      ('unbekannt', PpgCameraAvailability.noCamera),
    ]) {
      availability = s;
      expect(await c.availability(), a, reason: s);
    }
  });

  test(
    'Rechteanfrage geht über den Rechte-Kanal, nicht über den Kamera-Kanal',
    () async {
      final c = MethodChannelPpgCamera();
      availability = 'permission_denied';
      afterRequest = 'available';
      expect(await c.requestPermission(), PpgCameraAvailability.available);
      expect(calls, ['perm:requestCamera']);
    },
  );

  test('ohne Plattform ist die Kamera nicht verfügbar, kein Fehler', () async {
    messenger.setMockMethodCallHandler(method, null);
    expect(
      await MethodChannelPpgCamera().availability(),
      PpgCameraAvailability.noCamera,
    );
  });

  test('Bilder, Start und Sperre kommen als Ereignisse an', () async {
    final out = <PpgCameraEvent>[];
    final sub = MethodChannelPpgCamera().start().listen(out.add);
    await pumpEventQueue();
    sink!
      ..add({'type': 'started', 'fps': 60, 'cameraId': '0'})
      ..add(_frame(0.5))
      ..add({'type': 'locked'});
    await pumpEventQueue();
    expect((out[0] as PpgCameraStarted).fps, 60);
    expect((out[0] as PpgCameraStarted).camera, const PpgCameraRef('0'));
    final f = (out[1] as PpgCameraFrame).frame;
    expect(f.t, 0.5);
    expect(f.r16, hasLength(16));
    expect(out[2], isA<PpgCameraExposureLocked>());
    await sub.cancel();
  });

  test('Kameraliste aus Kotlin, ohne Rechteanfrage', () async {
    cameraList = [
      {
        'cameraId': '0',
        'physicalCameraId': null,
        'focalLength': 4.25,
        'isDefault': true,
        'usable': true,
      },
      {
        'cameraId': '0',
        'physicalCameraId': '3',
        'focalLength': null,
        'isDefault': false,
        'usable': false,
        'reason': 'no_flash',
      },
      {
        'cameraId': '1',
        'physicalCameraId': null,
        'focalLength': 2.0,
        'isDefault': false,
        'usable': false,
        'reason': 'frame_rate',
      },
      {'cameraId': '2', 'isDefault': false, 'usable': false, 'reason': 'error'},
      // Unpassend: entfällt.
      {'cameraId': '', 'isDefault': false, 'usable': true},
      {'cameraId': '5', 'isDefault': false},
      {
        'cameraId': '5',
        'physicalCameraId': 7,
        'isDefault': false,
        'usable': true,
      },
      'Text',
    ];
    final list = await MethodChannelPpgCamera().cameras();
    expect(calls, ['ppg:cameras']);
    expect(list.map((c) => c.ref).toList(), const [
      PpgCameraRef('0'),
      PpgCameraRef('0', '3'),
      PpgCameraRef('1'),
      PpgCameraRef('2'),
    ]);
    expect(list[0].focalLengthMm, 4.25);
    expect(list[0].isDefault, isTrue);
    expect(list[0].usable, isTrue);
    expect(list[1].focalLengthMm, isNull);
    expect(list[1].unusable, PpgCameraUnusable.noFlash);
    expect(list[2].unusable, PpgCameraUnusable.frameRate);
    expect(list[3].unusable, PpgCameraUnusable.other);
  });

  test(
    'Kameraliste ohne Plattform oder bei Fehler: leer, kein Fehler',
    () async {
      messenger.setMockMethodCallHandler(method, null);
      expect(await MethodChannelPpgCamera().cameras(), isEmpty);
      messenger.setMockMethodCallHandler(
        method,
        (call) async => throw PlatformException(code: 'error'),
      );
      expect(await MethodChannelPpgCamera().cameras(), isEmpty);
    },
  );

  test('ohne Angabe startet die Standardkamera (kein Argument)', () async {
    final sub = MethodChannelPpgCamera().start().listen((_) {});
    await pumpEventQueue();
    expect(listenArgs, isNull);
    await sub.cancel();
  });

  test(
    'angegebene Kamera geht an Kotlin, started nennt die geöffnete',
    () async {
      final out = <PpgCameraEvent>[];
      final sub = MethodChannelPpgCamera()
          .start(camera: const PpgCameraRef('0', '3'))
          .listen(out.add);
      await pumpEventQueue();
      expect(listenArgs, {'cameraId': '0', 'physicalCameraId': '3'});
      sink!.add({
        'type': 'started',
        'fps': 30,
        'cameraId': '0',
        'physicalCameraId': '3',
      });
      await pumpEventQueue();
      expect(
        (out.single as PpgCameraStarted).camera,
        const PpgCameraRef('0', '3'),
      );
      await sub.cancel();
    },
  );

  test('unbekannte oder unbrauchbare Kamera: Strom endet mit Grund', () async {
    for (final (code, reason) in [
      ('no_camera', PpgCameraStopReason.noCamera),
      ('no_flash', PpgCameraStopReason.noFlash),
      ('frame_rate', PpgCameraStopReason.frameRate),
      ('error', PpgCameraStopReason.error),
    ]) {
      final out = <PpgCameraEvent>[];
      var done = false;
      MethodChannelPpgCamera()
          .start(camera: const PpgCameraRef('9'))
          .listen(out.add, onDone: () => done = true);
      await pumpEventQueue();
      sink!.add({'type': 'stopped', 'reason': code});
      await pumpEventQueue();
      expect((out.single as PpgCameraStopped).reason, reason, reason: code);
      expect(done, isTrue);
    }
  });

  test('started ohne Kamera ist unpassend und entfällt', () {
    expect(
      MethodChannelPpgCamera.parse({'type': 'started', 'fps': 60}),
      isNull,
    );
  });

  test('Kamera-Angaben kommen an, Fehlendes und Unpassendes bleibt null', () {
    final d = MethodChannelPpgCamera.parse({
      'type': 'details',
      'exposureNs': 8333333,
      'iso': 100,
      'timestampSource': 'realtime',
      'skewNs': 20000000,
      'torch': 1,
      'saturated': 0.02,
    }) as PpgCameraDetails;
    expect(d.exposureTimeNs, 8333333);
    expect(d.iso, 100);
    expect(d.timestampSource, CameraTimestampSource.realtime);
    expect(d.rollingShutterSkewNs, 20000000);
    expect(d.torchStrength, 1);
    expect(d.saturatedFraction, 0.02);
    final e = MethodChannelPpgCamera.parse({
      'type': 'details',
      'iso': 'viel',
      'timestampSource': 'x',
      'saturated': 1.5,
    }) as PpgCameraDetails;
    expect(e.exposureTimeNs, isNull);
    expect(e.iso, isNull);
    expect(e.timestampSource, isNull);
    expect(e.saturatedFraction, isNull);
  });

  test('unpassende Nachrichten entfallen', () async {
    final out = <PpgCameraEvent>[];
    final sub = MethodChannelPpgCamera().start().listen(out.add);
    await pumpEventQueue();
    sink!
      ..add('Text')
      ..add({'type': 'frame', 't': 1.0})
      ..add({
        'type': 'frame',
        ..._frame(1)..['r16'] = <double>[1, 2],
      })
      ..add({'type': 'xyz'});
    await pumpEventQueue();
    expect(out, isEmpty);
    await sub.cancel();
  });

  test('Abbestellen schaltet die Kamera ab (Torch aus)', () async {
    final sub = MethodChannelPpgCamera().start().listen((_) {});
    await pumpEventQueue();
    expect(torchOn, isTrue);
    await sub.cancel();
    expect(cancelled, 1);
    expect(torchOn, isFalse);
  });

  test('stop beendet den Strom und ruft stop in Kotlin', () async {
    final c = MethodChannelPpgCamera();
    var done = false;
    c.start().listen((_) {}, onDone: () => done = true);
    await pumpEventQueue();
    await c.stop();
    await pumpEventQueue();
    expect(calls, contains('ppg:stop'));
    expect(cancelled, 1);
    expect(torchOn, isFalse);
    expect(done, isTrue);
  });

  test(
    'Abbruch von Kotlin (Hintergrund): Ereignis mit Grund, dann Ende',
    () async {
      final out = <PpgCameraEvent>[];
      var done = false;
      MethodChannelPpgCamera().start().listen(
        out.add,
        onDone: () => done = true,
      );
      await pumpEventQueue();
      sink!.add({'type': 'stopped', 'reason': 'background'});
      await pumpEventQueue();
      expect(
        (out.single as PpgCameraStopped).reason,
        PpgCameraStopReason.background,
      );
      expect(done, isTrue);
    },
  );

  test('Fehlergründe aus Kotlin werden zugeordnet', () async {
    for (final (s, r) in [
      ('permission_denied', PpgCameraStopReason.permissionDenied),
      ('no_camera', PpgCameraStopReason.noCamera),
      ('no_flash', PpgCameraStopReason.noFlash),
      ('busy', PpgCameraStopReason.busy),
      ('disconnected', PpgCameraStopReason.disconnected),
      ('frame_rate', PpgCameraStopReason.frameRate),
      ('error', PpgCameraStopReason.error),
      ('irgendwas', PpgCameraStopReason.error),
    ]) {
      final out = <PpgCameraEvent>[];
      final sub = MethodChannelPpgCamera().start().listen(out.add);
      await pumpEventQueue();
      sink!.add({'type': 'stopped', 'reason': s});
      await pumpEventQueue();
      expect((out.single as PpgCameraStopped).reason, r, reason: s);
      await sub.cancel();
    }
  });

  test('Fehler auf dem Kanal: Ereignis, Strom endet, kein Absturz', () async {
    final out = <PpgCameraEvent>[];
    var done = false;
    MethodChannelPpgCamera().start().listen(out.add, onDone: () => done = true);
    await pumpEventQueue();
    sink!.addError(PlatformException(code: 'busy'));
    await pumpEventQueue();
    expect((out.single as PpgCameraStopped).reason, PpgCameraStopReason.busy);
    expect(done, isTrue);
  });
}
