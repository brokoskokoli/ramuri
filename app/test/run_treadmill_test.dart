import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/run/run_ports.dart';

final _t0 = DateTime.utc(2030, 3, 1, 10);

/// Sitzung mit steuerbarem Rohdatenspeicher und Laufspeicher (nur Fehlerwege).
class _FaultySession implements StorageSession {
  _FaultySession(this.s);
  final StorageSession s;
  Object? appendError; // wird beim nächsten append geworfen (solange gesetzt)
  Object? getError; // wird beim nächsten runs.get geworfen (einmalig)
  @override
  RawDataStore get rawData => _Raw(this);
  @override
  RunStore get runs => _Runs(this);
  @override
  SettingsStore get settings => s.settings;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  RunSubjectiveStore get subjective => s.subjective;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _Raw implements RawDataStore {
  _Raw(this.f);
  final _FaultySession f;
  @override
  Future<void> append(int runId, RawBatch batch) {
    final e = f.appendError;
    if (e != null) return Future.error(e);
    return f.s.rawData.append(runId, batch);
  }

  @override
  Future<StoredRawData> read(int runId) => f.s.rawData.read(runId);
}

class _Runs implements RunStore {
  _Runs(this.f);
  final _FaultySession f;
  @override
  Future<StoredRun?> get(int id) {
    final e = f.getError;
    f.getError = null;
    if (e != null) return Future.error(e);
    return f.s.runs.get(id);
  }

  @override
  Future<StoredRun> create({
    required DateTime startedAt,
    RunMode mode = RunMode.gps,
  }) => f.s.runs.create(startedAt: startedAt, mode: mode);
  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) => f.s.runs.setState(
    runId,
    state,
    endedAt: endedAt,
    endedUtcOffset: endedUtcOffset,
  );
  @override
  Future<List<StoredRun>> list() => f.s.runs.list();
  @override
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to) =>
      f.s.runs.finishedBetween(from, to);
  @override
  Future<List<StoredRun>> unfinished() => f.s.runs.unfinished();
}

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

    test('Speicherfehler beim Ändern: Sitzung hat sie (true); andere Ausnahme: false', () async {
      final w = await _world();
      final fs = _FaultySession(w.session);
      final c = RunController(
        clock: w.clock,
        storage: fs,
        location: w.location,
        service: w.service,
        mode: RunMode.treadmill,
        startBeltSpeedMetersPerSecond: 2,
        tickEvery: const Duration(hours: 1),
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.phase, RecordingPhase.running);
      w.clock.advance(const Duration(seconds: 10));
      fs.appendError = const StorageException(StorageFailure.failed);
      expect(await c.setBeltSpeed(3), isTrue);
      expect(c.snapshot.beltSpeedMetersPerSecond, 3);
      fs.appendError = StateError('unerwartet');
      expect(await c.setBeltSpeed(4), isFalse);
    });

    test(
      'Fortsetzen: nicht lesbare Laufart bricht ab, kein GPS-Dienst',
      () async {
        final w = await _world();
        final a = _belt(w);
        await a.start();
        final id = (await w.session.runs.unfinished()).single.id;
        a.dispose();
        final fs = _FaultySession(w.session)
          ..getError = const StorageException(StorageFailure.failed);
        final w2 = FakeRecordingServicePort();
        final b = RunController(
          clock: w.clock,
          storage: fs,
          location: w.location,
          service: w2,
          resumeRunId: id,
          tickEvery: const Duration(hours: 1),
        );
        addTearDown(b.dispose);
        await b.start();
        expect(b.startFailed, isTrue);
        expect(w2.startModes, isEmpty);
        expect(w.location.hasListeners, isFalse);
        expect(b.phase, RecordingPhase.idle);
      },
    );

    test(
      'Erste Einstellung nicht speicherbar: Lauf läuft, Fehler sichtbar',
      () async {
        final w = await _world();
        final fs = _FaultySession(w.session)
          ..appendError = const StorageException(StorageFailure.failed);
        final c = RunController(
          clock: w.clock,
          storage: fs,
          location: w.location,
          service: w.service,
          mode: RunMode.treadmill,
          startBeltSpeedMetersPerSecond: 2,
          tickEvery: const Duration(hours: 1),
        );
        addTearDown(c.dispose);
        await c.start();
        expect(c.startFailed, isFalse);
        expect(c.phase, RecordingPhase.running);
        expect(c.writeFailure, StorageFailure.failed);
        expect(w.service.startModes, [RecordingServiceMode.treadmill]);
        // Erholt sich der Speicher, geht die Bedienung weiter.
        fs.appendError = null;
        expect(await c.setBeltSpeed(3), isTrue);
        final run = (await w.session.runs.unfinished()).single;
        final rows = (await w.session.rawData.read(run.id)).beltSettings;
        expect(rows.map((r) => r.value.speedMetersPerSecond), [2, 3]);
      },
    );
  });
}
