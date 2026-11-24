import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  test('Sperre mit Sensorzeit; ohne Zeit t == null (ältere Gegenseite)', () {
    final withT = MethodChannelPpgCamera.parse({
      'type': 'locked',
      't': 26.5,
    }) as PpgCameraExposureLocked;
    expect(withT.t, 26.5);
    final withoutT = MethodChannelPpgCamera.parse({
      'type': 'locked',
    }) as PpgCameraExposureLocked;
    expect(withoutT.t, isNull);
    // Unbrauchbare Zeit: die Sperre bleibt, nur ohne Zeit.
    for (final bad in <Object?>['26.5', double.nan, double.infinity, -1]) {
      final e = MethodChannelPpgCamera.parse({
        'type': 'locked',
        't': bad,
      }) as PpgCameraExposureLocked;
      expect(e.t, isNull, reason: '$bad');
    }
  });

  test('Neu-Einschwingen mit Sensorzeit; ohne gültige Zeit ignoriert', () {
    final e = MethodChannelPpgCamera.parse({'type': 'relocking', 't': 24});
    expect(e, isA<PpgCameraRelocking>());
    expect((e! as PpgCameraRelocking).t, 24.0);
    for (final bad in <Object?>[null, '24', double.nan, -0.5]) {
      expect(
        MethodChannelPpgCamera.parse({'type': 'relocking', 't': bad}),
        isNull,
        reason: '$bad',
      );
    }
    expect(MethodChannelPpgCamera.parse({'type': 'relocking'}), isNull);
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
    'Bildrate: ganze Zahl 1 bis 240, sonst null, Eintrag bleibt gültig',
    () async {
      Map<String, Object?> cam(String id, [Object? fps = _absent]) => {
        'cameraId': id,
        'isDefault': false,
        'usable': true,
        if (!identical(fps, _absent)) 'frameRate': fps,
      };
      cameraList = [
        cam('0', 60),
        cam('1'),
        cam('2', 0),
        cam('3', -30),
        cam('4', 30.5),
        cam('5', '60'),
        cam('6', 1),
        cam('7', 240),
        cam('8', 241),
        cam('9', null),
      ];
      final list = await MethodChannelPpgCamera().cameras();
      expect(list.map((c) => c.ref.cameraId).toList(), [
        for (var i = 0; i < 10; i++) '$i',
      ]);
      expect(list.map((c) => c.frameRate).toList(), [
        60,
        null,
        null,
        null,
        null,
        null,
        1,
        240,
        null,
        null,
      ]);
      expect(list.every((c) => c.usable), isTrue);
    },
  );

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

  test('Schalter und ISP-Werte gehen als Start-Argumente an Kotlin, started meldet die gesetzten', () async {
    final out = <PpgCameraEvent>[];
    final sub = MethodChannelPpgCamera()
        .start(
          diagnostics: const {
            PpgCameraDiagnostic.shadingOff,
            PpgCameraDiagnostic.noiseReductionOff,
            PpgCameraDiagnostic.awbFixed,
          },
          ispFrames: true,
        )
        .listen(out.add);
    await pumpEventQueue();
    expect(listenArgs, {
      'diagnostics': ['noise_reduction_off', 'awb_fixed', 'shading_off'],
      'ispFrames': true,
    });
    sink!.add({
      'type': 'started',
      'fps': 60,
      'cameraId': '0',
      'diagnostics': ['awb_fixed', 'shading_off', 'unbekannt'],
      'awbVariant': 'lock',
    });
    sink!.add({'type': 'started', 'fps': 60, 'cameraId': '0'});
    await pumpEventQueue();
    final started = out.cast<PpgCameraStarted>();
    expect(started[0].diagnostics, {
      PpgCameraDiagnostic.awbFixed,
      PpgCameraDiagnostic.shadingOff,
    });
    expect(started[0].awbVariant, PpgAwbVariant.lock);
    expect(started[1].diagnostics, isEmpty);
    expect(started[1].awbVariant, isNull);
    await sub.cancel();
    expect(
      MethodChannelPpgCamera.startArguments(
        camera: const PpgCameraRef('2'),
        ispFrames: true,
      ),
      {'cameraId': '2', 'physicalCameraId': null, 'ispFrames': true},
    );
  });

  test('Bild mit 19 ISP-Werten, einzelnen fehlenden und ohne ISP-Werte', () {
    final full = Float64List.fromList([for (var k = 0; k < 19; k++) k + 0.5]);
    final a = MethodChannelPpgCamera.parse({
      ..._frame(0.1),
      'isp': full,
    }) as PpgCameraFrame;
    expect(a.isp, [for (var k = 0; k < 19; k++) k + 0.5]);
    final gaps = Float64List.fromList(full)
      ..[4] = double.nan
      ..[18] = double.nan;
    final b = MethodChannelPpgCamera.parse({
      ..._frame(0.2),
      'isp': gaps,
    }) as PpgCameraFrame;
    expect(b.isp![4].isNaN, isTrue);
    expect(b.isp![18].isNaN, isTrue);
    expect(b.isp![5], 5.5);
    final nulls = [for (var k = 0; k < 19; k++) k == 3 ? null : k];
    final c = MethodChannelPpgCamera.parse({
      ..._frame(0.3),
      'isp': nulls,
    }) as PpgCameraFrame;
    expect(c.isp![3].isNaN, isTrue);
    expect(c.isp![2], 2.0);
    final none = MethodChannelPpgCamera.parse(_frame(0.4)) as PpgCameraFrame;
    expect(none.isp, isNull);
    expect(none.frame.t, 0.4);
    final short = MethodChannelPpgCamera.parse({
      ..._frame(0.5),
      'isp': full.sublist(1),
    }) as PpgCameraFrame;
    expect(short.isp, isNull, reason: 'nicht 19 Werte: nicht gemeldet');
  });

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

  group('Kamerasuche', () {
    const previewChannel = EventChannel(ppgCameraPreviewChannelName);
    StreamController<Object?>? psink;
    Object? pargs;
    var pcancelled = 0;

    setUp(() {
      pcancelled = 0;
      pargs = null;
      messenger.setMockStreamHandler(
        previewChannel,
        MockStreamHandler.inline(
          onListen: (arguments, e) {
            pargs = arguments;
            psink = StreamController<Object?>(sync: true)
              ..stream.listen(
                e.success,
                onError: (Object x) {
                  final c = x is PlatformException ? x.code : 'error';
                  e.error(code: c);
                },
                onDone: e.endOfStream,
              );
          },
          onCancel: (arguments) => pcancelled++,
        ),
      );
    });

    tearDown(() => messenger.setMockStreamHandler(previewChannel, null));

    test('Kanalname steht in PpgCameraPreview.kt', () {
      final kt = File(
        '../../android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgCameraPreview.kt',
      ).readAsStringSync();
      expect(kt, contains('"$ppgCameraPreviewChannelName"'));
    });

    test('Kameras gehen als Argument, Ereignisse kommen an', () async {
      final out = <PpgPreviewEvent>[];
      final sub = MethodChannelPpgCamera()
          .preview(const [PpgCameraRef('0'), PpgCameraRef('0', '2')])
          .listen(out.add);
      await pumpEventQueue();
      expect(pargs, {
        'cameras': [
          {'cameraId': '0', 'physicalCameraId': null},
          {'cameraId': '0', 'physicalCameraId': '2'},
        ],
      });
      psink!
        ..add({
          'type': 'started',
          'mode': 'alternating',
          'textures': [
            {'cameraId': '0', 'physicalCameraId': null, 'textureId': 7},
            {'cameraId': '0', 'physicalCameraId': '2', 'textureId': -1},
          ],
        })
        ..add({'type': 'turn', 'cameraId': '0', 'physicalCameraId': '2'})
        ..add({
          'type': 'frame',
          'cameraId': '0',
          'physicalCameraId': '2',
          't': 1.25,
          'r': 200.0,
          'g': 40.0,
          'exposureNs': 10000000,
          'iso': 400,
        })
        ..add({
          'type': 'failed',
          'cameraId': '0',
          'physicalCameraId': null,
          'reason': 'busy',
        });
      await pumpEventQueue();
      final started = out[0] as PpgPreviewStarted;
      expect(started.mode, PpgPreviewMode.alternating);
      expect(started.textures, {const PpgCameraRef('0'): 7});
      expect((out[1] as PpgPreviewTurn).camera, const PpgCameraRef('0', '2'));
      final f = out[2] as PpgPreviewFrame;
      expect(f.camera, const PpgCameraRef('0', '2'));
      expect(
        [f.t, f.r, f.g, f.exposureNs, f.iso],
        [1.25, 200, 40, 10000000, 400],
      );
      final failed = out[3] as PpgPreviewCameraFailed;
      expect(failed.camera, const PpgCameraRef('0'));
      expect(failed.reason, PpgCameraStopReason.busy);
      await sub.cancel();
      expect(pcancelled, 1);
    });

    test('Bild ohne Belichtungsangaben: null; Unpassendes entfällt', () {
      final f = MethodChannelPpgCamera.parsePreview({
        'type': 'frame',
        'cameraId': '0',
        't': 0.5,
        'r': 10,
        'g': 5,
        'exposureNs': 0,
      }) as PpgPreviewFrame;
      expect(f.exposureNs, isNull);
      expect(f.iso, isNull);
      for (final bad in <Object?>[
        null,
        'x',
        {'type': 'frame', 'cameraId': '0', 't': 0.5, 'r': 10},
        {'type': 'frame', 't': 0.5, 'r': 10, 'g': 5},
        {'type': 'frame', 'cameraId': '0', 't': -1, 'r': 10, 'g': 5},
        {'type': 'started', 'mode': 'x'},
        {'type': 'turn'},
        {'type': 'failed', 'reason': 'busy'},
        {'type': 'unbekannt'},
      ]) {
        expect(
          MethodChannelPpgCamera.parsePreview(bad),
          isNull,
          reason: '$bad',
        );
      }
    });

    test('Ende mit Grund und Fehler des Kanals beenden den Strom', () async {
      final out = <PpgPreviewEvent>[];
      var done = false;
      MethodChannelPpgCamera()
          .preview(const [PpgCameraRef('0')])
          .listen(out.add, onDone: () => done = true);
      await pumpEventQueue();
      psink!.add({'type': 'stopped', 'reason': 'background'});
      await pumpEventQueue();
      expect(
        (out.single as PpgPreviewStopped).reason,
        PpgCameraStopReason.background,
      );
      expect(done, isTrue);

      out.clear();
      done = false;
      MethodChannelPpgCamera()
          .preview(const [PpgCameraRef('0')])
          .listen(out.add, onDone: () => done = true);
      await pumpEventQueue();
      psink!.addError(PlatformException(code: 'disconnected'));
      await pumpEventQueue();
      expect(
        (out.single as PpgPreviewStopped).reason,
        PpgCameraStopReason.disconnected,
      );
      expect(done, isTrue);
    });

    test('stop beendet die Vorschau (Abbestellen in Kotlin)', () async {
      final c = MethodChannelPpgCamera();
      var done = false;
      c
          .preview(const [PpgCameraRef('0')])
          .listen((_) {}, onDone: () => done = true);
      await pumpEventQueue();
      await c.stop();
      await pumpEventQueue();
      expect(pcancelled, 1);
      expect(done, isTrue);
    });
  });
}

const Object _absent = Object();
