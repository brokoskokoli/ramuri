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
  // Nachbildung von Kotlin: torchOn wie in der Hardware, onCancel schaltet aus.
  var torchOn = false;

  setUp(() {
    availability = 'available';
    afterRequest = 'available';
    calls.clear();
    cancelled = 0;
    torchOn = false;
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add('ppg:${call.method}');
      if (call.method == 'availability') return availability;
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
      ..add({'type': 'started', 'fps': 60})
      ..add(_frame(0.5))
      ..add({'type': 'locked'});
    await pumpEventQueue();
    expect((out[0] as PpgCameraStarted).fps, 60);
    final f = (out[1] as PpgCameraFrame).frame;
    expect(f.t, 0.5);
    expect(f.r16, hasLength(16));
    expect(out[2], isA<PpgCameraExposureLocked>());
    await sub.cancel();
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
