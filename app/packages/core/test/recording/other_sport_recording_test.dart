import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Werte, keine echten Pulsreihen (SEC-0001 bis SEC-0010).
final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

Duration s(int n) => Duration(seconds: n);
Duration m(int n) => Duration(minutes: n);

void main() {
  group('Andere Sportart in der Sitzung (FR-0221, PAR-232)', () {
    late FakeClock clock;
    late RecordingSession ses;
    setUp(() {
      clock = FakeClock(t0);
      ses = RecordingSession(clock: clock);
    });

    test('Start nur mit Sportart, Sportart nur bei sport', () {
      expect(ses.start(mode: RunMode.sport), CommandResult.rejected);
      expect(
        ses.start(mode: RunMode.gps, sport: OtherSport.rope),
        CommandResult.rejected,
      );
      expect(
        ses.start(mode: RunMode.treadmill, sport: OtherSport.rope),
        CommandResult.rejected,
      );
      expect(ses.phase, RecordingPhase.idle);
      expect(
        ses.start(mode: RunMode.sport, sport: OtherSport.cycling),
        CommandResult.ok,
      );
      final snap = ses.snapshot();
      expect(snap.mode, RunMode.sport);
      expect(snap.sport, OtherSport.cycling);
      expect(ses.sport, OtherSport.cycling);
    });

    test('30 min mit 5 min Pause-Taste ergeben 25 min Bewegungszeit', () {
      ses.start(mode: RunMode.sport, sport: OtherSport.rope);
      clock.advance(m(10));
      expect(ses.pause(), CommandResult.ok);
      clock.advance(m(5));
      expect(ses.resume(), CommandResult.ok);
      clock.advance(m(15));
      ses.finish();
      final snap = ses.snapshot();
      expect(snap.totalTime, m(30));
      expect(snap.movingTime, m(25));
      expect(snap.distanceMeters, isNull);
    });

    test('ohne Pause 30 min; Puls auf der Stelle ohne Position', () {
      ses.start(mode: RunMode.sport, sport: OtherSport.rowing);
      for (var i = 0; i < 30; i++) {
        clock.advance(m(1));
        expect(
          ses.addHeartRate(HeartRateReading('hr', clock.now(), 140)),
          Intake.processed,
        );
      }
      final snap = ses.snapshot();
      expect(snap.movingTime, m(30));
      expect(snap.heartRateBpm, 140);
      expect(snap.distanceMeters, isNull);
    });

    test('Pausen zwischen Runden ohne Pause-Taste zählen mit', () {
      ses.start(mode: RunMode.sport, sport: OtherSport.rope);
      clock.advance(m(2));
      ses.lap(); // Runde 1
      clock.advance(m(3)); // Erholung zwischen den Runden, ohne Pause-Taste
      ses.lap();
      clock.advance(m(2));
      ses.lap();
      final snap = ses.snapshot();
      expect(snap.movingTime, m(7));
      expect(snap.laps.map((l) => l.movingTime), [m(2), m(3), m(2)]);
    });

    test('keine Autopause, keine GPS-Lücke, Positionen werden ignoriert', () {
      ses.setAutoPause(true);
      ses.start(mode: RunMode.sport, sport: OtherSport.other);
      expect(ses.autoPauseEnabled, isFalse);
      clock.advance(s(120));
      ses.tick();
      expect(
        ses.addPosition(
          LocationSample(time: clock.now(), latitude: 1, longitude: 1),
        ),
        Intake.ignoredNotActive,
      );
      final snap = ses.snapshot();
      expect(snap.positionLost, isFalse);
      expect(snap.standstillDetected, isFalse);
      expect(snap.gaps, isEmpty);
      expect(snap.phase, RecordingPhase.running);
      expect(snap.movingTime, s(120));
      expect(snap.distanceMeters, isNull);
    });

    test('Band-Befehle werden abgelehnt', () {
      ses.start(mode: RunMode.sport, sport: OtherSport.rope);
      expect(ses.setBeltSpeed(2), CommandResult.rejected);
      expect(ses.beltHeartbeat(), CommandResult.rejected);
      expect(ses.beltSettings, isEmpty);
    });
  });

  group('activeTimeWithoutPauses (PAR-232)', () {
    test('überlappende und überstehende Pausen zählen einmal', () {
      expect(
        activeTimeWithoutPauses(
          start: t0,
          end: t0.add(m(30)),
          pauses: [
            (t0.add(m(5)), t0.add(m(10))),
            (t0.add(m(8)), t0.add(m(12))),
            (t0.subtract(m(5)), t0.add(m(1))),
            (t0.add(m(29)), t0.add(m(40))),
          ],
        ),
        m(30 - 7 - 1 - 1),
      );
    });

    test('Ende vor dem Start ergibt 0', () {
      expect(
        activeTimeWithoutPauses(
          start: t0,
          end: t0.subtract(m(1)),
          pauses: const [],
        ),
        Duration.zero,
      );
    });
  });

  group('Andere Sportart im Recorder: Speichern und Wiederanlauf', () {
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
      'Start speichert Art und Sportart; falsche Kombination legt nichts an',
      () async {
        final rec = make();
        expect(await rec.start(mode: RunMode.sport), CommandResult.rejected);
        expect(await rec.start(sport: OtherSport.rope), CommandResult.rejected);
        expect(await store.runs.list(), isEmpty);
        expect(
          await rec.start(mode: RunMode.sport, sport: OtherSport.rowing),
          CommandResult.ok,
        );
        final run = await store.runs.get(rec.runId!);
        expect(run!.mode, RunMode.sport);
        expect(run.sport, OtherSport.rowing);
      },
    );

    test('keine Kadenz und keine Splits: Schritte werden nicht angenommen, '
        'nichts in raw_steps (FR-0221)', () async {
      final rec = make();
      await rec.start(mode: RunMode.sport, sport: OtherSport.rope);
      for (var i = 0; i < 20; i++) {
        clock.advance(m(1));
        expect(rec.addSteps(150), Intake.ignoredNotActive);
        rec.addHeartRate(HeartRateReading('hr', clock.now(), 150));
        rec.tick();
      }
      expect(computeKilometerSplits(rec.preprocessing()!).splits, isEmpty);
      await rec.finish();
      await rec.flush();
      expect(rec.addSteps(150), Intake.ignoredFinished);
      final raw = await store.rawData.read(rec.runId!);
      expect(raw.steps, isEmpty);
      expect(raw.heartRates, isNotEmpty);
    });

    for (final sport in OtherSport.values) {
      test('Wiederanlauf nach Prozessende setzt ${sport.wire} fort', () async {
        final a = make();
        await a.start(mode: RunMode.sport, sport: sport);
        clock.advance(m(5));
        a.addHeartRate(HeartRateReading('hr', clock.now(), 150));
        await a.pause();
        clock.advance(m(2));
        await a.resume();
        clock.advance(m(3));
        a.addHeartRate(HeartRateReading('hr', clock.now(), 155));
        await a.lap(); // belegt bis hier (10 min)
        clock.advance(m(4)); // Prozessende: nichts belegt
        final b = make();
        expect(await b.restore(a.runId!), CommandResult.ok);
        var snap = b.snapshot();
        expect(snap.mode, RunMode.sport);
        expect(snap.sport, sport);
        expect(b.snapshot().distanceMeters, isNull);
        // Pause (2 min) und Unterbrechung (4 min) zählen nicht.
        expect(snap.movingTime, m(8));
        clock.advance(m(1));
        snap = b.snapshot();
        expect(snap.movingTime, m(9));
        await b.finish();
        final run = await store.runs.get(a.runId!);
        expect(run!.state, RunState.finished);
        expect(run.mode, RunMode.sport);
        expect(run.sport, sport);
      });
    }

    test(
      'Wanduhr zurück vor dem Prozessende: Bewegungszeit nie negativ',
      () async {
        final a = make();
        await a.start(mode: RunMode.sport, sport: OtherSport.rope);
        clock.advance(m(10));
        a.addHeartRate(HeartRateReading('hr', clock.now(), 150));
        await a.lap();
        clock.set(t0.add(m(2))); // Uhr springt zurück, dann Prozessende
        final b = make();
        expect(await b.restore(a.runId!), CommandResult.ok);
        final snap = b.snapshot();
        expect(snap.sport, OtherSport.rope);
        expect(snap.movingTime, m(10));
      },
    );
  });
}
