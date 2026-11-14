import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/method_channel_recording_service.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';
import 'package:running_app/features/sensors/run_heart_rate.dart';
import 'package:running_app/features/sensors/sensor_manager.dart';

final _t0 = DateTime.utc(2030, 3, 1, 10);

Future<
  ({
    FakeClock clock,
    StorageSession session,
    FakeLocationSource location,
    FakeRecordingServicePort service,
  })
>
_world({Object? startError}) async => (
  clock: FakeClock(_t0),
  session: await FakeStorage().open(Uint8List(32)),
  location: FakeLocationSource(),
  service: FakeRecordingServicePort(startError: startError),
);

RunController _controller(
  ({
    FakeClock clock,
    StorageSession session,
    FakeLocationSource location,
    FakeRecordingServicePort service,
  })
  w,
) => RunController(
  clock: w.clock,
  storage: w.session,
  location: w.location,
  service: w.service,
  tickEvery: const Duration(hours: 1),
);

/// Pulsquelle eines Laufs aus der Sensorverwaltung, Gerät 's' verbunden.
RunHeartRate _hrRun(FakeClock clock) {
  final run = SensorManager(
    sensor: FakeHeartRateSensor(),
    clock: clock,
  ).beginRun();
  run.handle(const HeartRateConnected('s'));
  return run;
}

void main() {
  group('RunController und Dienst (WP08)', () {
    test('Start startet den Dienst genau einmal', () async {
      final w = await _world();
      final c = _controller(w);
      addTearDown(c.dispose);
      await c.start();
      expect(w.service.startCalls, 1);
      expect(w.service.running, isTrue);
      expect(c.serviceFailed, isFalse);
      expect(c.phase, RecordingPhase.running);
    });

    test('Fortsetzen eines inzwischen beendeten Laufs: abgelehnt, kein Dienst, '
        'startFailed', () async {
      final w = await _world();
      final run = await w.session.runs.create(startedAt: _t0);
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: _t0.add(const Duration(minutes: 1)),
      );
      final c = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: w.service,
        tickEvery: const Duration(hours: 1),
        resumeRunId: run.id,
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.startFailed, isTrue);
      expect(w.service.startCalls, 0);
      expect(w.service.running, isFalse);
      expect(w.location.hasListeners, isFalse);
    });

    test('Ende stoppt den Dienst', () async {
      final w = await _world();
      final c = _controller(w);
      addTearDown(c.dispose);
      await c.start();
      w.clock.advance(const Duration(minutes: 1));
      await c.finish();
      expect(w.service.running, isFalse);
      expect(w.service.stopCalls, 1);
    });

    test('dispose stoppt den Dienst auch ohne Ende', () async {
      final w = await _world();
      final c = _controller(w);
      await c.start();
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(w.service.running, isFalse);
      expect(w.service.stopCalls, 1);
    });

    test(
      'Fehler beim Dienststart: Lauf läuft weiter und wird gemeldet',
      () async {
        final w = await _world(startError: StateError('abgelehnt'));
        final c = _controller(w);
        addTearDown(c.dispose);
        await c.start();
        expect(c.serviceFailed, isTrue);
        expect(c.phase, RecordingPhase.running);
        expect(c.startFailed, isFalse);
        // Der Lauf nimmt weiter Punkte an.
        for (var i = 1; i <= 3; i++) {
          w.clock.advance(const Duration(seconds: 1));
          w.location.emit(
            LocationSample(
              time: w.clock.now(),
              latitude: 50 + i * 0.000027,
              longitude: 8,
              accuracyMeters: 5,
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
        await c.pause();
        expect(c.hasFix, isTrue);
        expect(w.service.running, isFalse);
      },
    );

    test(
      'Ende während des Dienststarts: Dienst wird nachträglich gestoppt',
      () async {
        final w = await _world();
        final gate = Completer<void>();
        w.service.startGate = gate.future;
        final c = _controller(w);
        final starting = c.start();
        await Future<void>.delayed(Duration.zero);
        c.dispose();
        gate.complete();
        await starting;
        await Future<void>.delayed(Duration.zero);
        expect(w.service.running, isFalse);
      },
    );

    test('Scheitert das Anlegen des Laufs, startet kein Dienst', () async {
      final w = await _world();
      final failing = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: w.service,
        tickEvery: const Duration(hours: 1),
        recorder: _FailingStart(w),
      );
      addTearDown(failing.dispose);
      await failing.start();
      expect(failing.startFailed, isTrue);
      expect(w.service.startCalls, 0);
    });

    test('ohne Dienst läuft alles wie bisher', () async {
      final w = await _world();
      final c = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.serviceFailed, isFalse);
      await c.finish();
      expect(c.phase, RecordingPhase.finished);
    });
  });

  group('MethodChannelRecordingService', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(recordingServiceChannelName);
    final calls = <String>[];
    final args = <Object?>[];
    Object? error;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      calls.clear();
      args.clear();
      error = null;
    });

    void mock({Object? answer}) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          args.add(call.arguments);
          if (error != null) throw error!;
          return answer;
        });

    test('start, stop, isRunning rufen die Kotlin-Methoden', () async {
      mock(answer: true);
      final s = MethodChannelRecordingService();
      await s.start();
      await s.stop();
      expect(await s.isRunning(), isTrue);
      expect(calls, ['start', 'stop', 'isRunning']);
    });

    test('start nennt die Laufart, Vorgabe gps', () async {
      mock();
      final s = MethodChannelRecordingService();
      await s.start();
      await s.start(mode: RecordingServiceMode.treadmill);
      expect(args, [
        {'mode': 'gps'},
        {'mode': 'treadmill'},
      ]);
    });

    test(
      'Laufband ohne ACTIVITY_RECOGNITION: eigener Grund, kein Systemfehler',
      () async {
        // Form wie Kotlin sie sendet (channelErrorArgs: Detail in message und details).
        error = PlatformException(
          code: 'start_denied',
          message: 'activity_recognition',
          details: 'activity_recognition',
        );
        mock();
        await expectLater(
          MethodChannelRecordingService().start(
            mode: RecordingServiceMode.treadmill,
          ),
          throwsA(
            isA<RecordingStartDenied>().having(
              (e) => e.reason,
              'reason',
              RecordingStartDeniedReason.activityRecognition,
            ),
          ),
        );
      },
    );

    test(
      'anderer Startfehler bleibt PlatformException (auch im Laufband)',
      () async {
        error = PlatformException(
          code: 'start_failed',
          details: 'SecurityException',
        );
        mock();
        await expectLater(
          MethodChannelRecordingService().start(
            mode: RecordingServiceMode.treadmill,
          ),
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('Fehler des Dienststarts erreicht den Aufrufer', () async {
      error = PlatformException(code: 'start_failed', message: 'x');
      mock();
      expect(
        MethodChannelRecordingService().start(),
        throwsA(isA<PlatformException>()),
      );
    });

    test('Kanalname und Methoden stehen auch in Kotlin', () {
      final kt = File(
        'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/RecordingServiceState.kt',
      ).readAsStringSync();
      expect(kt, contains('"$recordingServiceChannelName"'));
      for (final m in ['start', 'stop', 'isRunning', 'updateType']) {
        expect(kt, contains('"$m"'));
      }
    });
  });

  group('Sensor im Lauf (WP08 C, ADR-0006 Punkt 4)', () {
    test('erster Pulswert zieht den Diensttyp nach, nur einmal', () async {
      final w = await _world();
      final hr = _hrRun(w.clock);
      final c = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: w.service,
        sensors: hr,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      expect(w.service.updateTypeCalls, 0);
      hr.handle(HeartRateReading('s', w.clock.now(), 120));
      hr.handle(HeartRateReading('s', w.clock.now(), 121));
      await Future<void>.delayed(Duration.zero);
      expect(w.service.updateTypeCalls, 1);
    });

    test('Fehler beim Nachziehen stört den Lauf nicht', () async {
      final w = await _world();
      final service = _ThrowingUpdate();
      final hr = _hrRun(w.clock);
      final c = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: service,
        sensors: hr,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      hr.handle(HeartRateReading('s', w.clock.now(), 120));
      await Future<void>.delayed(Duration.zero);
      expect(c.phase, RecordingPhase.running);
      expect(c.heartRateSourceSeen, isTrue);
    });

    test('RR (FR-0213): nur die aktive Quelle, Herkunft je Paket, Wechsel '
        'trennt die Pakete', () async {
      final w = await _world();
      final hr = _hrRun(w.clock);
      hr.handle(const HeartRateConnected('t'));
      final c = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: w.service,
        sensors: hr,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      HeartRateReading rd(String id, int bpm, List<int> rr) =>
          HeartRateReading(id, w.clock.now(), bpm, rrIntervals: rr);
      hr.handle(rd('s', 120, const [800, 810]));
      hr.handle(rd('t', 121, const [500])); // nicht aktiv: nicht gespeichert
      hr.handle(rd('s', 122, const []));
      expect(hr.select('t'), isTrue);
      hr.handle(rd('t', 123, const [700]));
      await Future<void>.delayed(Duration.zero);
      await c.finish();
      final raw = await w.session.rawData.read(c.runId!);
      final rr = raw.rrPackets.map((p) => p.value).toList();
      expect(rr.map((p) => p.source), ['s', 't']);
      expect(rr.map((p) => p.intervals), [
        [800, 810],
        [700],
      ]);
      expect(raw.heartRates.map((h) => h.value.source), ['s', 's', 't']);
    });
  });

  group('Quelltext des Dienstes (ADR-0005 Punkt 6, Wake Lock)', () {
    const dir = 'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri';
    final service = File('$dir/RecordingService.kt').readAsStringSync();
    final lifecycle = File('$dir/RecordingLifecycle.kt').readAsStringSync();
    final stateSource = File('$dir/RecordingServiceState.kt')
        .readAsStringSync();
    final state = stateSource;

    test('START_NOT_STICKY, kein onTaskRemoved', () {
      expect(service, contains('return RecordingLifecycle.START_MODE'));
      expect(
        lifecycle,
        contains('const val START_MODE: Int = Service.START_NOT_STICKY'),
      );
      expect(service + lifecycle, isNot(contains('START_STICKY')));
      expect(service, isNot(contains('onTaskRemoved')));
    });

    test('onDestroy gibt den Lock frei', () {
      expect(service, contains('lifecycle?.onDestroy()'));
      expect(lifecycle, matches(RegExp(r'fun onDestroy\(\) = stop\(\)')));
    });

    test(
      'Standortrecht geht in den Controller (Entscheidung per JVM-Test)',
      () {
        expect(state, contains('Manifest.permission.ACCESS_FINE_LOCATION'));
        expect(state, contains('controller.start('));
      },
    );

    test('connectedDevice nur hinter BLUETOOTH_CONNECT', () {
      // Der Typ entsteht allein in startType(bluetoothConnectGranted, mode) ...
      expect(
        lifecycle,
        contains(
          'fun startType(bluetoothConnectGranted: Boolean, mode: RecordingMode = RecordingMode.GPS): Int',
        ),
      );
      final body = lifecycle.substring(
        lifecycle.indexOf('fun startType('),
        lifecycle.indexOf('fun hasConnectedDevice'),
      );
      expect(
        body,
        matches(
          RegExp(
            r'return if \(bluetoothConnectGranted\) base or ServiceInfo\.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE else base',
          ),
        ),
      );
      // Basistyp: location im GPS-Lauf, health nur im Laufbandlauf (ADR-0005 Nachtrag WP25).
      expect(
        body,
        matches(
          RegExp(
            r'RecordingMode\.GPS -> ServiceInfo\.FOREGROUND_SERVICE_TYPE_LOCATION\s*'
            r'RecordingMode\.TREADMILL -> ServiceInfo\.FOREGROUND_SERVICE_TYPE_HEALTH',
          ),
        ),
      );
      // ... start und Nachziehen fragen das Recht ab, der Dienst liest es am System.
      expect(lifecycle, contains('startType(bluetoothConnectGranted(), mode)'));
      expect(
        service,
        contains(
          'checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==',
        ),
      );
      // health nur an der einen Stelle im Laufbandzweig von startType (K57).
      expect(
        'FOREGROUND_SERVICE_TYPE_HEALTH'.allMatches(
          service + lifecycle + state,
        ),
        hasLength(1),
      );
    });

    test('Verdrahtung: Standortrecht und Timeout gehen an den Controller', () {
      // Die Entscheidungen testet die JVM; hier nur, dass State sie genau so ruft.
      expect(state, contains('Runnable { controller.onTimeout() }'));
      expect(
        RegExp(
          r'controller\.start\(\s*result,\s*'
          r'context\.checkSelfPermission\(Manifest\.permission\.ACCESS_FINE_LOCATION\) ==\s*'
          r'PackageManager\.PERMISSION_GRANTED,\s*mode,\s*'
          r'context\.checkSelfPermission\(Manifest\.permission\.ACTIVITY_RECOGNITION\) ==\s*'
          r'PackageManager\.PERMISSION_GRANTED,\s*\)',
        ).hasMatch(state),
        isTrue,
      );
    });

    test(
      'Verdrahtung: Fehlerantwort trägt das Detail in message und details',
      () {
        // Dart liest details; die Form prüft der JVM-Test, hier der Aufruf.
        final controller = _code(
          File('$dir/RecordingServiceController.kt').readAsStringSync(),
        );
        final state = _code(stateSource);
        expect(controller, contains('= Triple(code, detail, detail)'));
        expect(
          state,
          contains(
            'val (c, message, details) = channelErrorArgs(code, detail)',
          ),
        );
        expect(state, contains('result.error(c, message, details)'));
        expect(state, isNot(contains('result.error(code, detail, null)')));
      },
    );

    test('Verdrahtung: Bandmodus-Argument erreicht die Rechteabfrage', () {
      final main = _code(File('$dir/MainActivity.kt').readAsStringSync());
      expect(main, contains('call.argument<Boolean>("treadmill") == true'));
      expect(
        main,
        contains(
          'StepSensor.shouldAsk(StepSensor.hasSensor(this), '
          'StepSensor.granted(this), treadmill)',
        ),
      );
    });

    test('kein stopService vor dem Vordergrund', () {
      // Nur bei laufendem Dienst (Entscheidung per JVM-Test des Controllers).
      final controller = File('$dir/RecordingServiceController.kt')
          .readAsStringSync();
      // Genau ein Aufruf je Datei: im State die Wirkung, im Controller die Entscheidung.
      int count(String text, String what) => what.allMatches(text).length;
      expect(
        count(state, 'stopService'),
        2,
        reason: 'override und c.stopService',
      );
      expect(count(state, 'c.stopService('), 1);
      expect(count(controller, 'fx.stopService()'), 1);
      expect(controller, contains('else if (running)'));
      expect(service, contains('takeStopRequest()'));
    });
  });

  group('Manifest (ADR-0005 Punkt 2 und 6)', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    test('Rechte und Diensttypen', () {
      for (final p in [
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_LOCATION',
        'FOREGROUND_SERVICE_CONNECTED_DEVICE',
        'WAKE_LOCK',
        'FOREGROUND_SERVICE_HEALTH',
        'POST_NOTIFICATIONS',
      ]) {
        expect(manifest, contains('android.permission.$p"'));
      }
      expect(
        manifest,
        contains(
          'android:foregroundServiceType="location|connectedDevice|health"',
        ),
      );
    });

    test('kein Neustart, keine Hintergrund-Standortberechtigung', () {
      // ADR-0005 Punkt 6 mit Nachtrag WP22 (Maintainer 2026-11-10): Die
      // Aufzeichnung startet nie nach dem Neustart. BOOT_COMPLETED empfängt
      // nur genau ein nicht exportierter Empfänger der Erinnerungen
      // (FR-0174); er stellt Wecker und startet keinen Dienst. Das Gate
      // prüft dasselbe am gemergten Manifest des Release-APK.
      // Genau zweimal: das Recht und die Aktion im Filter des Empfängers,
      // nirgends sonst (kein Dienst, keine Activity mit Boot-Filter).
      expect(
        RegExp('BOOT_COMPLETED').allMatches(manifest).length,
        2,
        reason: 'BOOT_COMPLETED nur als Recht und im Erinnerungs-Empfänger',
      );
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>',
        ),
      );
      final receivers = RegExp(r'<receiver\b[\s\S]*?</receiver>')
          .allMatches(manifest)
          .map((m) => m[0]!)
          .toList();
      expect(receivers, hasLength(1));
      // Auch selbstschließende Empfänger zählen: genau einer im Manifest.
      expect(RegExp(r'<receiver\b').allMatches(manifest).length, 1);
      final receiver = receivers.single;
      expect(receiver, contains('android:name=".TrainingReminderReceiver"'));
      expect(receiver, contains('android:exported="false"'));
      expect(receiver, contains('android.intent.action.BOOT_COMPLETED'));
      // Nur inexakte Wecker (Auflage zum Boot-Empfänger).
      expect(manifest, isNot(contains('SCHEDULE_EXACT_ALARM')));
      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    });

    test('Boot-Empfänger plant nur Wecker: kein Dienst, keine Aufzeichnung, '
        'keine Datenbank', () {
      const kt = 'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri';
      final receiver = File('$kt/TrainingReminderReceiver.kt')
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/|//.*'), '');
      // Der Empfänger ruft nur TrainingReminders.fire (Neustart, Wecker) und
      // MorningReminder.fire (nur dessen Wecker, WP33 Teil D) auf.
      expect(
        RegExp(r'\b[A-Za-z_]+\.[a-z][A-Za-z_]*\(')
            .allMatches(receiver)
            .map((m) => m[0])
            .toSet(),
        {'TrainingReminders.fire(', 'MorningReminder.fire('},
      );
      for (final f in [
        'TrainingReminderReceiver.kt',
        'TrainingReminders.kt',
        'MorningReminder.kt',
      ]) {
        final src = File('$kt/$f').readAsStringSync();
        for (final banned in [
          'RecordingService',
          'RecordingLifecycle',
          'startService',
          'startForegroundService',
          'startActivity',
          'bindService',
          'FlutterEngine',
          'WorkManager',
          'JobScheduler',
          'SQLite',
          'sqlite',
          'Database',
          'setExact',
          'setAlarmClock',
        ]) {
          expect(src, isNot(contains(banned)), reason: '$f: $banned');
        }
      }
    });
  });
}

/// Dienst, dessen Nachziehen des Typs scheitert.
class _ThrowingUpdate extends FakeRecordingServicePort {
  @override
  Future<bool> updateType() async => throw StateError('abgelehnt');
}

/// Recorder, dessen Start scheitert (Anlegen des Laufs).
class _FailingStart extends RunRecorder {
  _FailingStart(
    ({
      FakeClock clock,
      StorageSession session,
      FakeLocationSource location,
      FakeRecordingServicePort service,
    })
    w,
  ) : super(
        clock: w.clock,
        runs: w.session.runs,
        rawData: w.session.rawData,
        markers: w.session.markers,
      );

  @override
  Future<CommandResult> start({
    RunMode mode = RunMode.gps,
    double? beltSpeedMetersPerSecond,
    double? inclinePercent,
  }) async => throw StateError('kein Speicher');
}

/// Kotlin-Quelltext ohne Kommentare, damit ein auskommentierter Aufruf eine
/// Verdrahtungsprüfung nicht erfüllt (Review 4b).
String _code(String kotlin) => kotlin
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(^|[ \t])//[^\n]*', multiLine: true), '');
