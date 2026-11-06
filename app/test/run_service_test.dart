import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/method_channel_recording_service.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';

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
    Object? error;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      calls.clear();
      error = null;
    });

    void mock({Object? answer}) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
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
        'android/app/src/main/kotlin/io/github/brokoskokoli/running_app/RecordingServiceState.kt',
      ).readAsStringSync();
      expect(kt, contains('"$recordingServiceChannelName"'));
      for (final m in ['start', 'stop', 'isRunning']) {
        expect(kt, contains('"$m"'));
      }
    });
  });

  group('Quelltext des Dienstes (ADR-0005 Punkt 6, Wake Lock)', () {
    const dir =
        'android/app/src/main/kotlin/io/github/brokoskokoli/running_app';
    final service = File('$dir/RecordingService.kt').readAsStringSync();
    final lifecycle = File('$dir/RecordingLifecycle.kt').readAsStringSync();
    final state = File('$dir/RecordingServiceState.kt').readAsStringSync();

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

    test('Standortrecht wird vor startForegroundService geprüft', () {
      final check = state.indexOf('RecordingLifecycle.mayStart(');
      final start = state.indexOf('startForegroundService(');
      expect(check, isNonNegative);
      expect(start, greaterThan(check));
      expect(state, contains('Manifest.permission.ACCESS_FINE_LOCATION'));
      // Bei Ablehnung: Fehler start_failed und zurück, ohne Dienst.
      final denied = state.substring(check, start);
      expect(denied, contains('"start_failed"'));
      expect(denied, contains('return'));
    });

    test('kein stopService vor dem Vordergrund', () {
      // Nur bei laufendem Dienst; Timeout und Stopp im Start werden vorgemerkt.
      expect(RegExp('stopService').allMatches(state), hasLength(1));
      expect(state, contains('else if (running)'));
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
        'WAKE_LOCK',
        'POST_NOTIFICATIONS',
      ]) {
        expect(manifest, contains('android.permission.$p"'));
      }
      expect(
        manifest,
        contains('android:foregroundServiceType="location|connectedDevice"'),
      );
    });

    test('kein Neustart, keine Hintergrund-Standortberechtigung', () {
      expect(manifest, isNot(contains('BOOT_COMPLETED')));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    });
  });
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
  Future<CommandResult> start() async => throw StateError('kein Speicher');
}
