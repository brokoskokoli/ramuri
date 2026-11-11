import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
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
_world() async => (
  clock: FakeClock(_t0),
  session: await FakeStorage().open(Uint8List(32)),
  location: FakeLocationSource(),
  service: FakeRecordingServicePort(),
);

RunController _belt(
  ({
    FakeClock clock,
    StorageSession session,
    FakeLocationSource location,
    FakeRecordingServicePort service,
  })
  w, {
  double? speed = 2,
}) => RunController(
  clock: w.clock,
  storage: w.session,
  location: w.location,
  service: w.service,
  mode: RunMode.treadmill,
  startBeltSpeedMetersPerSecond: speed,
  startInclinePercent: 1,
  tickEvery: const Duration(hours: 1),
);

void main() {
  group('RunController im Laufbandmodus (FR-0196, K57)', () {
    test(
      'Start: Dienst im Laufbandmodus, kein Standort, Lauf als Bandlauf',
      () async {
        final w = await _world();
        final c = _belt(w);
        addTearDown(c.dispose);
        await c.start();
        expect(w.service.startModes, [RecordingServiceMode.treadmill]);
        expect(c.phase, RecordingPhase.running);
        expect(c.startDenied, isNull);
        expect(w.location.hasListeners, isFalse); // keine Standortquelle
        final run = (await w.session.runs.unfinished()).single;
        expect(run.mode, RunMode.treadmill);
      },
    );

    test(
      'ohne ACTIVITY_RECOGNITION: eigener Grund, kein Lauf, kein Fehlerzustand',
      () async {
        final w = await _world();
        w.service.activityRecognitionGranted = false;
        final c = _belt(w);
        addTearDown(c.dispose);
        await c.start();
        expect(c.startDenied, RecordingStartDeniedReason.activityRecognition);
        expect(c.serviceFailed, isFalse);
        expect(c.startFailed, isFalse);
        expect(c.phase, RecordingPhase.idle);
        expect(await w.session.runs.list(), isEmpty);
        // nach Erteilen des Rechts startet derselbe Controller
        w.service.activityRecognitionGranted = true;
        await c.start();
        expect(c.startDenied, isNull);
        expect(c.phase, RecordingPhase.running);
      },
    );

    test('ohne Startgeschwindigkeit: startFailed, kein Lauf, Dienst wieder gestoppt', () async {
      final w = await _world();
      final c = _belt(w, speed: null);
      addTearDown(c.dispose);
      await c.start();
      expect(c.startFailed, isTrue);
      expect(await w.session.runs.list(), isEmpty);
      expect(w.service.running, isFalse);
    });

    test(
      'setBeltSpeed/setIncline wirken ab jetzt und werden gespeichert',
      () async {
        final w = await _world();
        final c = _belt(w);
        addTearDown(c.dispose);
        await c.start();
        w.clock.advance(const Duration(seconds: 100));
        expect(await c.setBeltSpeed(4), isTrue);
        expect(await c.setIncline(3), isTrue);
        expect(await c.setBeltSpeed(-1), isFalse);
        w.clock.advance(const Duration(seconds: 50));
        await c.pause(); // aktualisiert den Stand
        expect(c.snapshot.distanceMeters, closeTo(400, 1e-6));
        expect(c.snapshot.beltSpeedMetersPerSecond, 4);
        expect(c.snapshot.inclinePercent, 3);
        final id = (await w.session.runs.unfinished()).single.id;
        final rows = (await w.session.rawData.read(id)).beltSettings;
        expect(rows.length, 3);
      },
    );

    test(
      'GPS-Controller: Standort und Dienst wie bisher, setBeltSpeed lehnt ab',
      () async {
        final w = await _world();
        final c = RunController(
          clock: w.clock,
          storage: w.session,
          location: w.location,
          service: w.service,
          tickEvery: const Duration(hours: 1),
        );
        addTearDown(c.dispose);
        await c.start();
        expect(w.service.startModes, [RecordingServiceMode.gps]);
        expect(w.location.hasListeners, isTrue);
        expect(await c.setBeltSpeed(2), isFalse);
      },
    );

    test('Fortsetzen eines Bandlaufs: gespeicherte Art gilt, Dienst im Laufbandmodus', () async {
      final w = await _world();
      final a = _belt(w);
      await a.start();
      final id = (await w.session.runs.unfinished()).single.id;
      w.clock.advance(const Duration(seconds: 60));
      await a.setBeltSpeed(3);
      a.dispose();
      w.clock.advance(const Duration(seconds: 600));
      final w2 = FakeRecordingServicePort();
      final b = RunController(
        clock: w.clock,
        storage: w.session,
        location: w.location,
        service: w2,
        resumeRunId: id,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(b.dispose);
      await b.start();
      expect(w2.startModes, [RecordingServiceMode.treadmill]);
      expect(b.runMode, RunMode.treadmill);
      expect(b.snapshot.beltSpeedMetersPerSecond, 3);
      expect(
        b.snapshot.distanceMeters,
        closeTo(120, 1e-6),
      ); // bis zur Einstellung belegt
    });
  });
}
