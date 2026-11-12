import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);
const kmh10 = 10 / 3.6;

Duration s(int n) => Duration(seconds: n);

void main() {
  group('Laufbandmodus in der Sitzung (FR-0196, K57)', () {
    late FakeClock clock;
    late RecordingSession ses;
    setUp(() {
      clock = FakeClock(t0);
      ses = RecordingSession(clock: clock);
    });

    test('Start ohne Geschwindigkeit oder mit unzulässiger wird abgelehnt', () {
      expect(ses.start(mode: RunMode.treadmill), CommandResult.rejected);
      expect(
        ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: -1),
        CommandResult.rejected,
      );
      expect(ses.phase, RecordingPhase.idle);
    });

    test(
      'Strecke = Geschwindigkeit mal Zeit, Wechsel wirkt erst ab Zeitpunkt',
      () {
        ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
        clock.advance(s(100)); // 200 m
        expect(ses.snapshot().distanceMeters, closeTo(200, 1e-9));
        ses.setBeltSpeed(4);
        expect(
          ses.snapshot().distanceMeters,
          closeTo(200, 1e-9),
        ); // nicht rückwirkend
        clock.advance(s(50)); // + 200 m
        final snap = ses.snapshot();
        expect(snap.distanceMeters, closeTo(400, 1e-9));
        expect(snap.movingTime, s(150));
        expect(snap.totalTime, s(150));
        expect(snap.mode, RunMode.treadmill);
        expect(snap.beltSpeedMetersPerSecond, 4);
      },
    );

    test('Geschwindigkeit 0 ist Stillstand ohne Bewegungszeit und Strecke', () {
      ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 3);
      clock.advance(s(10));
      ses.setBeltSpeed(0);
      clock.advance(s(60));
      ses.setBeltSpeed(3);
      clock.advance(s(10));
      final snap = ses.snapshot();
      expect(snap.distanceMeters, closeTo(60, 1e-9));
      expect(snap.movingTime, s(20));
      expect(snap.totalTime, s(80));
      expect(snap.phase, RecordingPhase.running);
    });

    test(
      'Pause zählt nicht; Änderung in der Pause gilt ab ihrem Zeitpunkt',
      () {
        ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
        clock.advance(s(10)); // 20 m
        ses.pause();
        clock.advance(s(30));
        ses.setBeltSpeed(5); // in der Pause
        clock.advance(s(30));
        var snap = ses.snapshot();
        expect(snap.distanceMeters, closeTo(20, 1e-9));
        expect(snap.movingTime, s(10));
        ses.resume();
        clock.advance(s(10)); // + 50 m
        snap = ses.snapshot();
        expect(snap.distanceMeters, closeTo(70, 1e-9));
        expect(snap.movingTime, s(20));
        expect(snap.totalTime, s(80));
      },
    );

    test('keine Autopause, keine GPS-Lücke, Positionen werden ignoriert', () {
      ses.setAutoPause(true);
      ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 3);
      expect(ses.autoPauseEnabled, isFalse);
      clock.advance(s(120));
      ses.tick();
      final i = ses.addPosition(
        LocationSample(time: clock.now(), latitude: 1, longitude: 1),
      );
      expect(i, Intake.ignoredNotActive);
      final snap = ses.snapshot();
      expect(snap.positionLost, isFalse);
      expect(snap.gaps, isEmpty);
      expect(snap.phase, RecordingPhase.running);
      expect(snap.distanceMeters, closeTo(360, 1e-9));
    });

    test(
      'Steigung als Einstellung; unveränderte Werte erzeugen keine Zeile',
      () {
        ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
        clock.advance(s(5));
        expect(ses.setIncline(2.5), CommandResult.ok);
        expect(ses.setIncline(2.5), CommandResult.ok);
        expect(ses.setBeltSpeed(2), CommandResult.ok);
        expect(ses.setIncline(-1), CommandResult.rejected);
        expect(ses.beltSettings.length, 2);
        expect(ses.beltSettings.last.inclinePercent, 2.5);
        expect(ses.beltSettings.last.speedMetersPerSecond, 2);
        expect(ses.beltSettings.last.offset, s(5));
        ses.setBeltSpeed(3); // Steigung bleibt
        expect(ses.snapshot().inclinePercent, 2.5);
      },
    );

    test('Ende friert Strecke ein; danach keine Änderung mehr', () {
      ses.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
      clock.advance(s(10));
      ses.finish();
      clock.advance(s(10));
      expect(ses.snapshot().distanceMeters, closeTo(20, 1e-9));
      expect(ses.setBeltSpeed(9), CommandResult.rejected);
    });

    test('GPS-Lauf: keine Laufbandfunktionen, Strecke aus Positionen', () {
      ses.start();
      expect(ses.setBeltSpeed(2), CommandResult.rejected);
      expect(ses.setIncline(1), CommandResult.rejected);
      clock.advance(s(30));
      expect(ses.snapshot().distanceMeters, isNull);
      for (var i = 0; i < 20; i++) {
        clock.advance(s(1));
        expect(
          ses.addPosition(
            LocationSample(
              time: clock.now(),
              latitude: 10 + 3.0 * i / 111195,
              longitude: 20,
              accuracyMeters: 5,
            ),
          ),
          Intake.processed,
        );
      }
      expect(ses.snapshot().distanceMeters, closeTo(57, 3));
      expect(ses.autoPauseEnabled, isFalse);
      ses.setAutoPause(true);
      expect(ses.autoPauseEnabled, isTrue);
      expect(ses.snapshot().mode, RunMode.gps);
      expect(ses.snapshot().beltSpeedMetersPerSecond, isNull);
    });
  });

  group('Laufband im Recorder: Speichern und Wiederanlauf (FR-0193)', () {
    late FakeClock clock;
    late StorageSession store;
    RunRecorder make() => RunRecorder(
      clock: clock,
      runs: store.runs,
      rawData: store.rawData,
      markers: store.markers,
    );
    setUp(() async {
      clock = FakeClock(t0);
      store = await FakeStorage().open(Uint8List(32));
    });

    test(
      'Start legt Art und erste Einstellung an, Änderungen werden gespeichert',
      () async {
        final rec = make();
        expect(
          await rec.start(mode: RunMode.treadmill),
          CommandResult.rejected,
        );
        expect(
          await store.runs.list(),
          isEmpty,
        ); // kein Lauf ohne Geschwindigkeit
        await rec.start(
          mode: RunMode.treadmill,
          beltSpeedMetersPerSecond: 2,
          inclinePercent: 1,
        );
        clock.advance(s(10));
        await rec.setBeltSpeed(3);
        clock.advance(s(10));
        await rec.setIncline(null);
        final run = await store.runs.get(rec.runId!);
        expect(run!.mode, RunMode.treadmill);
        final belts = (await store.rawData.read(rec.runId!)).beltSettings;
        expect(belts.map((b) => b.value), [
          const BeltSetting(
            offset: Duration.zero,
            speedMetersPerSecond: 2,
            inclinePercent: 1,
          ),
          const BeltSetting(
            offset: Duration(seconds: 10),
            speedMetersPerSecond: 3,
            inclinePercent: 1,
          ),
          const BeltSetting(
            offset: Duration(seconds: 20),
            speedMetersPerSecond: 3,
          ),
        ]);
      },
    );

    test(
      'Wiederanlauf stellt Modus, Geschwindigkeit, Steigung, Strecke her',
      () async {
        final a = make();
        await a.start(
          mode: RunMode.treadmill,
          beltSpeedMetersPerSecond: 2,
          inclinePercent: 1.5,
        );
        clock.advance(s(100)); // 200 m
        await a.setBeltSpeed(4); // ab 100 s
        clock.advance(s(50)); // + 200 m, belegt bis hier durch Runde
        await a.lap();
        clock.advance(s(600)); // Absturz: nichts belegt
        final b = make();
        expect(await b.restore(a.runId!), CommandResult.ok);
        var snap = b.snapshot();
        expect(snap.mode, RunMode.treadmill);
        expect(snap.beltSpeedMetersPerSecond, 4);
        expect(snap.inclinePercent, 1.5);
        expect(snap.distanceMeters, closeTo(400, 1e-9));
        expect(snap.movingTime, s(150));
        clock.advance(s(10)); // läuft mit 4 m/s weiter
        snap = b.snapshot();
        expect(snap.distanceMeters, closeTo(440, 1e-9));
        // Wiederhergestelltes wird nicht doppelt gespeichert.
        await b.setBeltSpeed(5);
        final belts = (await store.rawData.read(a.runId!)).beltSettings;
        expect(belts.length, 3);
      },
    );

    test('letzter belegter Zeitpunkt zählt die Einstellungen (Absturz ohne Punkte)', () async {
      final a = make();
      await a.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
      clock.advance(s(100));
      await a.setBeltSpeed(3); // einziger Beleg nach dem Start
      clock.advance(s(600));
      final run = (await store.runs.get(a.runId!))!;
      final last = lastRecordedTime(
        run,
        await store.rawData.read(a.runId!),
        await store.markers.gaps(a.runId!),
        await store.markers.laps(a.runId!),
      );
      expect(last, t0.add(s(100)));
    });

    test(
      'Wiederanlauf ohne gespeicherte Einstellung: Band bleibt bedienbar',
      () async {
        final a = make();
        await a.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
        final id = a.runId!;
        // Die erste Einstellung kam nie in der DB an.
        final raw = await store.rawData.read(id);
        expect(raw.beltSettings.length, 1);
        await store.deleteRun(id);
        final run = await store.runs.create(
          startedAt: t0,
          mode: RunMode.treadmill,
        );
        clock.advance(s(100));
        final b = make();
        expect(await b.restore(run.id), CommandResult.ok);
        expect(await b.setBeltSpeed(3), CommandResult.ok);
        clock.advance(s(10));
        expect(b.snapshot().distanceMeters, closeTo(30, 1e-9));
        expect(await b.setIncline(2), CommandResult.ok);
        final belts = (await store.rawData.read(run.id)).beltSettings;
        expect(belts.map((x) => x.value.speedMetersPerSecond), [3, 3]);
      },
    );

    test(
      'Start meldet ok erst nach dem Speichern der ersten Einstellung',
      () async {
        final failing = _FailAppend(store.rawData);
        final rec = RunRecorder(
          clock: clock,
          runs: store.runs,
          rawData: failing,
          markers: store.markers,
        );
        failing.fail = true;
        await expectLater(
          rec.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2),
          throwsA(isA<StorageException>()),
        );
        failing.fail = false;
        final ok = RunRecorder(
          clock: clock,
          runs: store.runs,
          rawData: failing,
          markers: store.markers,
        );
        await ok.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
        // Sofort nach dem Rückgabewert steht die Zeile in der DB.
        expect((await store.rawData.read(ok.runId!)).beltSettings.length, 1);
      },
    );

    test('Lebenszeichen: Absturz 5 min nach der letzten Änderung behält die Strecke', () async {
      final a = make();
      await a.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
      clock.advance(s(10));
      await a.setBeltSpeed(3); // letzte echte Änderung bei 10 s
      for (var i = 0; i < 10; i++) {
        clock.advance(s(30));
        a.tick();
        await a.flush();
      }
      // Absturz bei 310 s (300 s nach der Änderung), danach 20 s bis zum Ende.
      clock.advance(s(20));
      final id = a.runId!;
      final raw = await store.rawData.read(id);
      expect(raw.beltSettings.length, 2 + 10); // Anhängen, kein Ändern
      final last = lastRecordedTime(
        (await store.runs.get(id))!,
        raw,
        await store.markers.gaps(id),
        await store.markers.laps(id),
      );
      expect(last, t0.add(s(310)));
      final b = make();
      await b.restore(id);
      // 10 s mit 2 m/s + 300 s mit 3 m/s, Integral unverändert.
      expect(b.snapshot().distanceMeters, closeTo(20 + 900, 1e-9));
    });

    test('Ohne Lebenszeichen-Intervall und im GPS-Lauf keine Zeile', () async {
      final a = make();
      await a.start(mode: RunMode.treadmill, beltSpeedMetersPerSecond: 2);
      clock.advance(beltHeartbeatInterval - s(1));
      a.tick();
      await a.flush();
      expect((await store.rawData.read(a.runId!)).beltSettings.length, 1);
      final g = make();
      await g.start();
      clock.advance(s(100));
      g.tick();
      await g.flush();
      expect((await store.rawData.read(g.runId!)).beltSettings, isEmpty);
    });

    test('GPS-Lauf bleibt gps und ohne Einstellungen', () async {
      final rec = make();
      await rec.start();
      expect((await store.runs.get(rec.runId!))!.mode, RunMode.gps);
      expect(await rec.setBeltSpeed(2), CommandResult.rejected);
      expect((await store.rawData.read(rec.runId!)).beltSettings, isEmpty);
    });
  });
}

class _FailAppend implements RawDataStore {
  _FailAppend(this.inner);
  final RawDataStore inner;
  bool fail = false;
  @override
  Future<void> append(int runId, RawBatch batch) => fail
      ? Future.error(const StorageException(StorageFailure.failed))
      : inner.append(runId, batch);
  @override
  Future<StoredRawData> read(int runId) => inner.read(runId);
}
