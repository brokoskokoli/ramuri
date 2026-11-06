import 'package:core/core.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

LocationSample fix(num sec, num north, {double? alt, int? ageMs}) =>
    LocationSample(
      ageMs: ageMs,
      time: t0.add(Duration(milliseconds: (sec * 1000).round())),
      // Erfundener Nullpunkt; 1 Grad Breite ~ 111195 m.
      latitude: 10 + north / 111195,
      longitude: 20,
      accuracyMeters: 5,
      altitudeMeters: alt,
    );

class _CountingClock implements Clock {
  _CountingClock(this.inner);
  final FakeClock inner;
  int reads = 0;
  @override
  DateTime now() {
    reads++;
    return inner.now();
  }
}

class Rig {
  Rig({bool autoPause = false}) : clock = FakeClock(t0) {
    s = RecordingSession(clock: clock, autoPause: autoPause);
  }
  final FakeClock clock;
  late final RecordingSession s;
  double north = 0;

  /// Läuft [seconds] mit [speed] m/s, ein Punkt je Sekunde; die Uhr folgt.
  void move(int seconds, double speed) {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      north += speed;
      s.addPosition(fix(clock.now().difference(t0).inSeconds, north));
    }
  }

  void wait(int seconds) => clock.advance(Duration(seconds: seconds));
}

void main() {
  group('Übergänge (FR-0028)', () {
    test('Standardwerte: idle, Autopause aus', () {
      final r = Rig();
      expect(r.s.phase, RecordingPhase.idle);
      expect(r.s.autoPauseEnabled, isFalse);
      final snap = r.s.snapshot();
      expect(snap.totalTime, isNull);
      expect(snap.distanceMeters, isNull);
    });

    test('Gültiger Ablauf start, pause, resume, finish', () {
      final r = Rig();
      expect(r.s.start(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.running);
      expect(r.s.pause(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.paused);
      expect(r.s.resume(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.running);
      expect(r.s.finish(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.finished);
      expect(r.s.events.map((e) => e.kind), [
        RecordingEventKind.started,
        RecordingEventKind.manualPaused,
        RecordingEventKind.resumed,
        RecordingEventKind.finished,
      ]);
    });

    test('Ungültig vor dem Start: pause, resume, lap, finish', () {
      final r = Rig();
      expect(r.s.pause(), CommandResult.rejected);
      expect(r.s.resume(), CommandResult.rejected);
      expect(r.s.lap(), CommandResult.rejected);
      expect(r.s.finish(), CommandResult.rejected);
      expect(r.s.phase, RecordingPhase.idle);
      expect(r.s.events, isEmpty);
    });

    test('Ungültig: zweites Start, doppeltes Pause, Resume ohne Pause', () {
      final r = Rig()..s.start();
      expect(r.s.start(), CommandResult.rejected);
      expect(r.s.resume(), CommandResult.rejected);
      r.s.pause();
      expect(r.s.pause(), CommandResult.rejected);
      expect(r.s.start(), CommandResult.rejected);
      expect(r.s.events.length, 2);
    });

    test('Zweites Beenden ändert nichts; nach dem Ende alles abgelehnt', () {
      final r = Rig()..s.start();
      r.wait(30);
      expect(r.s.finish(), CommandResult.ok);
      final total = r.s.snapshot().totalTime;
      r.wait(100);
      expect(r.s.finish(), CommandResult.rejected);
      expect(r.s.pause(), CommandResult.rejected);
      expect(r.s.resume(), CommandResult.rejected);
      expect(r.s.lap(), CommandResult.rejected);
      expect(r.s.start(), CommandResult.rejected);
      expect(r.s.snapshot().totalTime, total);
      expect(r.s.snapshot().endedAt, t0.add(const Duration(seconds: 30)));
      expect(
        r.s.events.where((e) => e.kind == RecordingEventKind.finished),
        hasLength(1),
      );
    });

    test('Beenden aus der Pause: Pause bis zum Ende zählt zur Gesamtzeit', () {
      final r = Rig()..s.start();
      r.move(20, 3);
      r.s.pause();
      r.wait(40);
      r.s.finish();
      final snap = r.s.snapshot();
      expect(snap.totalTime, const Duration(seconds: 60));
      expect(snap.movingTime, const Duration(seconds: 20));
      expect(snap.gaps.single.kind, RunGapKind.manualPause);
      expect(snap.gaps.single.end, snap.endedAt);
    });
  });

  group('Gesamt- und Bewegungszeit', () {
    test('Pausenzeit zählt nur zur Gesamtzeit', () {
      final r = Rig()..s.start();
      r.move(30, 3);
      r.s.pause();
      r.wait(60);
      r.s.resume();
      r.move(30, 3);
      final snap = r.s.snapshot();
      expect(snap.totalTime, const Duration(seconds: 120));
      expect(snap.movingTime, const Duration(seconds: 60));
    });

    test(
      'Stillstand ab 10 s zählt nicht zur Bewegungszeit, auch ohne Autopause',
      () {
        final r = Rig()..s.start();
        r.move(30, 3);
        r.move(30, 0);
        r.move(30, 3);
        final snap = r.s.snapshot();
        expect(r.s.autoPauseEnabled, isFalse);
        expect(snap.phase, RecordingPhase.running);
        expect(snap.totalTime, const Duration(seconds: 90));
        // 30 + ~10 s Haltedauer bis zur Erkennung + 3 s Fortsetzen: Rest ist Pause.
        expect(snap.movingTime! < const Duration(seconds: 80), isTrue);
        expect(snap.movingTime! > const Duration(seconds: 55), isTrue);
      },
    );
  });

  group('Autopause (FR-0029)', () {
    test('An: pausiert nach 10 s Stillstand, setzt nach 3 s Bewegung fort', () {
      final r = Rig(autoPause: true)..s.start();
      r.move(20, 3);
      r.move(9, 0);
      expect(r.s.phase, RecordingPhase.running, reason: 'unter 10 s');
      r.move(3, 0);
      expect(r.s.phase, RecordingPhase.autoPaused);
      r.move(2, 3);
      expect(r.s.phase, RecordingPhase.autoPaused, reason: 'unter 3 s');
      r.move(3, 3);
      expect(r.s.phase, RecordingPhase.running);
      expect(
        r.s.events
            .map((e) => e.kind)
            .where(
              (k) =>
                  k == RecordingEventKind.autoPauseStarted ||
                  k == RecordingEventKind.autoPauseEnded,
            ),
        [
          RecordingEventKind.autoPauseStarted,
          RecordingEventKind.autoPauseEnded,
        ],
      );
    });

    test('Aus (Standard): derselbe Stillstand pausiert nicht', () {
      final r = Rig()..s.start();
      r.move(20, 3);
      r.move(60, 0);
      expect(r.s.phase, RecordingPhase.running);
      expect(r.s.snapshot().standstillDetected, isTrue);
      expect(
        r.s.events.any((e) => e.kind == RecordingEventKind.autoPauseStarted),
        isFalse,
      );
    });

    test('Einschalten und Ausschalten mitten in der erkannten Pause', () {
      final r = Rig()..s.start();
      r.move(20, 3);
      r.move(20, 0);
      r.s.setAutoPause(true);
      expect(r.s.phase, RecordingPhase.autoPaused);
      r.s.setAutoPause(false);
      expect(r.s.phase, RecordingPhase.running);
    });

    test('Manuelle Pause in der erkannten Pause; Resume geht nach running', () {
      final r = Rig(autoPause: true)..s.start();
      r.move(20, 3);
      r.move(20, 0);
      expect(r.s.phase, RecordingPhase.autoPaused);
      expect(r.s.pause(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.paused);
      expect(r.s.resume(), CommandResult.ok);
      expect(r.s.phase, RecordingPhase.running);
      // Bewegung nach dem Fortsetzen wird wieder erkannt (Stand-Erkennung lebt).
      r.move(10, 3);
      r.move(20, 0);
      expect(r.s.phase, RecordingPhase.autoPaused);
    });

    test('GPS-Lücke im Stand löst keine Autopause aus (PAR-004)', () {
      final r = Rig(autoPause: true)..s.start();
      r.move(20, 3);
      r.wait(60); // keine Punkte
      r.s.tick();
      expect(r.s.phase, RecordingPhase.running);
      expect(r.s.snapshot().positionLost, isTrue);
      // Danach ein einzelner Punkt am selben Ort: Lücke, kein Stillstand-Segment.
      r.s.addPosition(fix(r.clock.now().difference(t0).inSeconds, r.north));
      expect(r.s.phase, RecordingPhase.running);
      expect(r.s.snapshot().standstillDetected, isFalse);
    });

    test(
      'Verworfener Punkt in der Lücke: Lücke bleibt offen, keine Autopause',
      () {
        final r = Rig(autoPause: true)..s.start();
        r.move(20, 3);
        r.wait(40);
        r.s.addPosition(fix(60, r.north + 500)); // Sprung, wird verworfen
        expect(r.s.snapshot().positionLost, isTrue);
        expect(r.s.phase, RecordingPhase.running);
      },
    );

    test('Stillstand vor der Lücke wird nicht durch die Lücke ausgelöst', () {
      final r = Rig(autoPause: true)..s.start();
      r.move(20, 3);
      r.move(5, 0); // Kandidat läuft, 5 s von 10
      r.wait(30);
      r.s.addPosition(fix(r.clock.now().difference(t0).inSeconds, r.north));
      expect(r.s.phase, RecordingPhase.running);
    });
  });

  group('Runden (FR-0030)', () {
    test('Rundenzeit gesamt und in Bewegung, Index ab 1', () {
      final r = Rig()..s.start();
      r.move(30, 3);
      r.s.lap();
      r.move(20, 3);
      r.s.pause();
      r.wait(15);
      r.s.resume();
      r.move(5, 3);
      r.s.lap();
      final laps = r.s.snapshot().laps;
      expect(laps.map((l) => l.index), [1, 2]);
      expect(laps[0].lapTime, const Duration(seconds: 30));
      expect(laps[1].lapTime, const Duration(seconds: 40));
      expect(laps[1].movingTime, const Duration(seconds: 25));
      expect(laps[1].toStored().lapTime, const Duration(seconds: 40));
    });

    test('Runde bei manueller Pause wird abgelehnt (Entscheidung)', () {
      final r = Rig()..s.start();
      r.move(10, 3);
      r.s.pause();
      expect(r.s.lap(), CommandResult.rejected);
      expect(r.s.snapshot().laps, isEmpty);
    });

    test('Runde in der erkannten Pause ist erlaubt', () {
      final r = Rig(autoPause: true)..s.start();
      r.move(20, 3);
      r.move(20, 0);
      expect(r.s.phase, RecordingPhase.autoPaused);
      expect(r.s.lap(), CommandResult.ok);
    });
  });

  group('Rennen Stopp gegen Eingänge', () {
    test('Punkte und Puls nach dem Beenden werden verworfen', () {
      final r = Rig()..s.start();
      r.move(20, 3);
      r.s.addHeartRate(HeartRateReading('d', r.clock.now(), 140));
      r.s.finish();
      final before = r.s.snapshot();
      r.wait(1);
      final late = r.s.addPosition(fix(21, r.north + 3));
      final lateHr = r.s.addHeartRate(
        HeartRateReading('d', r.clock.now(), 150),
      );
      expect(late, Intake.ignoredFinished);
      expect(lateHr, Intake.ignoredFinished);
      final after = r.s.snapshot();
      expect(after.distanceMeters, before.distanceMeters);
      expect(after.totalTime, before.totalTime);
      expect(r.s.preprocessing()!.position.positions, hasLength(20));
    });

    test('Eingänge vor Start ignoriert, in der Pause nur gespeichert, nie verarbeitet', () {
      final r = Rig();
      expect(r.s.addPosition(fix(0, 0)), Intake.ignoredNotActive);
      r.s.start();
      r.move(5, 3);
      r.s.pause();
      r.wait(1);
      expect(r.s.addPosition(fix(10, 99)), Intake.recordedWhilePaused);
      r.s.resume();
      expect(r.s.preprocessing()!.position.positions, hasLength(5));
    });

    test('Nachgelieferter Altwert vor Start bzw. Fortsetzen ist veraltet', () {
      final r = Rig();
      r.wait(100);
      r.s.start();
      r.move(5, 3); // erster Punkt legt die Zeitbasis fest
      r.s.pause();
      r.wait(20);
      r.s.resume();
      expect(r.s.addPosition(fix(110, 0, ageMs: 21000)), Intake.ignoredStale);
      r.wait(1);
      expect(r.s.addPosition(fix(126, 0)), isNot(Intake.ignoredStale));
    });
  });

  test('PAR-008 live: Puls ohne Hautkontakt wird nicht übernommen', () {
    final r = Rig()..s.start();
    r.move(2, 3);
    r.s.addHeartRate(
      HeartRateReading('d', r.clock.now(), 140, contact: SensorContact.poor),
    );
    expect(r.s.snapshot().heartRateBpm, isNull);
    r.clock.advance(const Duration(seconds: 1));
    r.s.addHeartRate(
      HeartRateReading('d', r.clock.now(), 142, contact: SensorContact.good),
    );
    expect(r.s.snapshot().heartRateBpm, 142);
  });

  test('observe: Stand und Vorverarbeitung aus einem Aufbau (Soll 4)', () {
    final clock = _CountingClock(FakeClock(t0));
    final s = RecordingSession(clock: clock)..start();
    for (var i = 1; i <= 5; i++) {
      clock.inner.advance(const Duration(seconds: 1));
      s.addPosition(fix(i, i * 3.0));
    }
    clock.reads = 0;
    final o = s.observe();
    expect(clock.reads, 1, reason: 'ein Aufbau, eine Uhrablesung');
    expect(o.preprocessing, isNotNull);
    expect(o.snapshot.movingTime, o.preprocessing!.movement.movingTime);
    expect(o.snapshot.distanceMeters, o.preprocessing!.position.distanceMeters);
  });

  group('Zeitbasen: GPS-Zeit und Systemuhr (Review 1, Soll 1)', () {
    // Ein Lauf bei Uhrversatz: Punkte tragen die GPS-Zeit, die Uhr zeigt
    // GPS-Zeit + [offset]. Die Entscheidung über Lücke und Veraltung darf nicht
    // vom Versatz abhängen.
    for (final offset in [
      const Duration(seconds: 60),
      const Duration(seconds: -60),
    ]) {
      test('Uhrversatz $offset: Punkte werden angenommen, keine falsche Lücke, '
          'echte Lücke wird erkannt', () {
        final clock = FakeClock(t0.add(offset));
        final s = RecordingSession(clock: clock)..start();
        var accepted = 0;
        for (var i = 1; i <= 20; i++) {
          clock.advance(const Duration(seconds: 1));
          final r = s.addPosition(fix(i, i * 3.0));
          if (r == Intake.processed) accepted++;
          s.tick();
        }
        expect(accepted, 20);
        var snap = s.snapshot();
        expect(snap.positionLost, isFalse);
        expect(snap.gaps, isEmpty);
        expect(snap.distanceMeters, greaterThan(50));
        expect(s.preprocessing()!.pace.liveSpeed, closeTo(3, 0.1));

        for (var i = 0; i < 30; i++) {
          clock.advance(const Duration(seconds: 1));
          s.tick();
        }
        snap = s.snapshot();
        expect(snap.positionLost, isTrue);
        expect(snap.gaps.single.kind, RunGapKind.positionLoss);
        // Lücke in Uhrzeit: Beginn beim letzten Punkt (Empfang).
        expect(
          snap.gaps.single.start,
          t0.add(offset).add(const Duration(seconds: 20)),
        );
      });
    }

    test('Lücke beginnt mit dem Empfang des letzten Punkts, nicht mit seiner '
        'GPS-Zeit', () {
      final clock = FakeClock(t0);
      final s = RecordingSession(clock: clock)..start();
      for (var i = 1; i <= 5; i++) {
        clock.advance(const Duration(seconds: 1));
        s.addPosition(fix(i, i * 3.0));
      }
      // Letzter Punkt kommt 300 ms nach seiner (ausgerichteten) Zeit an.
      clock.advance(const Duration(milliseconds: 1300));
      s.addPosition(fix(6, 18));
      clock.advance(const Duration(seconds: 11));
      s.tick();
      expect(
        s.snapshot().gaps.single.start,
        t0.add(const Duration(milliseconds: 6300)),
      );
    });

    test('Die GPS-Uhrzeit des Punkts geht nicht ein: Zukunftszeit sperrt '
        'nichts', () {
      final r = Rig()..s.start();
      r.move(5, 3);
      r.wait(1);
      expect(r.s.addPosition(fix(6 + 3600, r.north + 3)), Intake.processed);
      r.north += 3;
      final before = r.s.snapshot().distanceMeters!;
      r.move(5, 3);
      expect(r.s.snapshot().distanceMeters!, greaterThan(before + 10));
      expect(r.s.preprocessing()!.position.positions.length, 11);
    });

    test('Punktzeit ist Empfang minus Alter; fehlt das Alter, der Empfang', () {
      final r = Rig()..s.start();
      r.wait(10);
      r.s.addPosition(fix(0, 0, ageMs: 400));
      expect(r.s.lastPointTime, t0.add(const Duration(milliseconds: 9600)));
      r.wait(1);
      r.s.addPosition(fix(0, 3));
      expect(r.s.lastPointTime, t0.add(const Duration(seconds: 11)));
      // Negatives Alter (Zeitgeber springt) zählt als 0: nie Zukunft.
      r.wait(1);
      r.s.addPosition(fix(0, 6, ageMs: -5000));
      expect(r.s.lastPointTime, t0.add(const Duration(seconds: 12)));
    });

    // Sondenfälle aus Review 2 (Blocker 1).
    test('P1: erster Punkt 60 s alt wird verworfen, Folgepunkte kommen an', () {
      final r = Rig()..s.start();
      r.wait(1);
      expect(r.s.addPosition(fix(0, 0, ageMs: 60000)), Intake.ignoredStale);
      r.move(20, 3);
      expect(r.s.snapshot().distanceMeters, greaterThan(40));
      expect(r.s.preprocessing()!.position.positions.length, 20);
    });

    test('P2: erster Punkt 7 s verspätet: Folgepunkte kommen an', () {
      final r = Rig()..s.start();
      r.wait(7);
      // Alter 7 s, aber nach dem Start gemessen: angenommen.
      expect(r.s.addPosition(fix(0, 0, ageMs: 6500)), Intake.processed);
      r.move(20, 3);
      expect(r.s.snapshot().distanceMeters, greaterThan(40));
      expect(r.s.preprocessing()!.position.positions.length, 21);
    });

    test('P3: Uhr springt 10 s zurück: Verlust höchstens die Sprungdauer', () {
      final r = Rig()..s.start();
      r.move(20, 3);
      final before = r.s.snapshot().distanceMeters!;
      r.clock.advance(const Duration(seconds: -10));
      var lost = 0;
      for (var i = 0; i < 30; i++) {
        r.clock.advance(const Duration(seconds: 1));
        r.north += 3;
        final res = r.s.addPosition(fix(0, r.north));
        if (res != Intake.processed) lost++;
      }
      expect(lost, 10); // genau die Sprungdauer, nicht mehr
      expect(r.s.snapshot().distanceMeters!, greaterThan(before + 30));
    });

    test('Zeitgleicher oder älterer Punkt als der letzte wird verworfen', () {
      final r = Rig()..s.start();
      r.move(3, 3);
      expect(r.s.addPosition(fix(0, 99)), Intake.ignoredStale);
      r.wait(1);
      expect(r.s.addPosition(fix(0, 99, ageMs: 5000)), Intake.ignoredStale);
      expect(r.s.preprocessing()!.position.positions.length, 3);
    });

    test('Rückspringende Uhr in der Pause: Punkt wird nicht gespeichert', () {
      final r = Rig()..s.start();
      r.move(3, 3);
      r.s.pause();
      r.wait(5);
      expect(r.s.addPosition(fix(0, 9)), Intake.recordedWhilePaused);
      r.clock.advance(const Duration(seconds: -3));
      expect(r.s.addPosition(fix(0, 9)), Intake.ignoredStale);
    });

    test('Pausenpunkt vor Pausenbeginn (Alter) ist veraltet', () {
      final r = Rig()..s.start();
      r.move(3, 3);
      r.wait(2);
      r.s.pause();
      expect(r.s.addPosition(fix(0, 9, ageMs: 1500)), Intake.ignoredStale);
    });
  });

  group('GPS-Lücke (FR-0194, PAR-004)', () {
    test(
      'Zeit und Puls laufen weiter, Lücke markiert, Strecke unverändert',
      () {
        final r = Rig()..s.start();
        r.move(20, 3);
        final dist = r.s.snapshot().distanceMeters!;
        for (var i = 0; i < 30; i++) {
          r.wait(1);
          r.s.addHeartRate(HeartRateReading('d', r.clock.now(), 140));
          r.s.tick();
        }
        var snap = r.s.snapshot();
        expect(snap.positionLost, isTrue);
        expect(snap.totalTime, const Duration(seconds: 50));
        expect(snap.movingTime, const Duration(seconds: 50));
        expect(snap.heartRateBpm, 140);
        expect(snap.distanceMeters, dist);
        final gap = snap.gaps.single;
        expect(gap.kind, RunGapKind.positionLoss);
        expect(gap.start, t0.add(const Duration(seconds: 20)));
        expect(gap.end, isNull);

        // Rückkehr: Lücke geschlossen, Strecke über die Lücke nicht geschätzt.
        r.north += 100;
        r.wait(1);
        r.s.addPosition(fix(51, r.north));
        snap = r.s.snapshot();
        expect(snap.positionLost, isFalse);
        expect(snap.gaps.single.end, t0.add(const Duration(seconds: 51)));
        expect(snap.distanceMeters, dist);
      },
    );

    test(
      'Lücke in Messzeit: Anfang und Ende sind die Zeiten der Randpunkte',
      () {
        final r = Rig()..s.start();
        r.move(10, 3);
        // Letzter Punkt vor der Lücke: Empfang bei 11 s, Alter 1 s -> Messzeit 10 s.
        r.wait(1);
        r.north += 3;
        r.s.addPosition(fix(11, r.north, ageMs: 1000));
        final before = r.s.lastPointTime!;
        expect(before, t0.add(const Duration(seconds: 10)));
        for (var i = 0; i < 30; i++) {
          r.wait(1);
          r.s.tick();
        }
        expect(r.s.snapshot().positionLost, isTrue);
        expect(r.s.snapshot().gaps.single.start, before);
        // Schließender Punkt: Empfang bei 42 s, Alter 2,5 s -> Messzeit 39,5 s.
        r.wait(1);
        r.north += 100;
        expect(
          r.s.addPosition(fix(42, r.north, ageMs: 2500)),
          Intake.processed,
        );
        final gap = r.s.snapshot().gaps.single;
        expect(gap.end, r.s.lastPointTime);
        expect(gap.end, t0.add(const Duration(milliseconds: 39500)));
        expect(gap.end!.isAfter(gap.start), isTrue);
        expect(r.s.snapshot().positionLost, isFalse);
      },
    );

    test('Exakt 10 s sind noch keine Lücke, darüber ja', () {
      final r = Rig()..s.start();
      r.move(5, 3);
      r.wait(10);
      r.s.tick();
      expect(r.s.snapshot().positionLost, isFalse);
      r.wait(1);
      r.s.tick();
      expect(r.s.snapshot().positionLost, isTrue);
    });

    test('Pausenzeit ist keine GPS-Lücke', () {
      final r = Rig()..s.start();
      r.move(5, 3);
      r.s.pause();
      r.wait(120);
      r.s.resume();
      r.s.tick();
      expect(r.s.snapshot().positionLost, isFalse);
      expect(
        r.s.snapshot().gaps.where((g) => g.kind == RunGapKind.positionLoss),
        isEmpty,
      );
    });

    test('Ohne Puls bleibt der Wert null, nie 0', () {
      final r = Rig()..s.start();
      r.move(5, 3);
      expect(r.s.snapshot().heartRateBpm, isNull);
      r.s.addHeartRate(HeartRateReading('d', r.clock.now(), 140));
      r.wait(30);
      expect(r.s.snapshot().heartRateBpm, isNull, reason: 'älter als 10 s');
    });
  });

  test('Höhe wird weitergereicht, fehlende Höhe nicht als 0', () {
    final r = Rig()..s.start();
    r.clock.advance(const Duration(seconds: 1));
    r.s.addPosition(fix(1, 0));
    expect(r.s.preprocessing()!.altitude.ascentMeters, isNull);
  });

  group('Neu ankern in der Sitzung (Nachbesserung E1)', () {
    void at(Rig r, int sec, num north, {double? alt}) {
      r.clock.advance(t0.add(Duration(seconds: sec)).difference(r.clock.now()));
      r.s.addPosition(fix(sec, north, alt: alt));
    }

    test('falscher Anker mit anderer Höhe: kein Anstieg daraus', () {
      final r = Rig()..s.start();
      at(r, 1, 500000, alt: 0); // falscher Anker, Höhe 0
      for (var i = 0; i < 4; i++) {
        at(r, 2 + i, 3.0 * i, alt: 495);
      }
      expect(r.s.preprocessing()!.altitude.ascentMeters, 0);
    });

    test('Neuberechnung aus Rohdaten = live, in jeder Reihenfolge', () {
      // (Sekunde, Nord, Höhe): falscher Anker, Re-Anker, danach Anstieg.
      final all = <(int, double, double)>[
        (1, 500000, 0),
        for (var i = 0; i < 4; i++) (2 + i, 3.0 * i, 495),
        for (var i = 0; i < 40; i++) (6 + i, 9 + 3.0 * i, 495 + 0.5 * (i + 1)),
      ];
      // Kurz (nur falscher Anker, Anstieg 0) und lang (danach echter Anstieg).
      for (final n in [5, all.length]) {
        final data = all.take(n).toList();
        final r = Rig()..s.start();
        for (final d in data) {
          at(r, d.$1, d.$2, alt: d.$3);
        }
        final live = r.s.preprocessing()!.altitude;
        expect(live.ascentMeters, n == 5 ? 0 : greaterThan(10));

        for (final altitudeFirst in [false, true]) {
          final pre = RunPreprocessor(start: t0);
          for (final d in data) {
            final f = fix(d.$1, d.$2, alt: d.$3);
            void pos() => pre.addPosition(
              RawPosition(
                time: f.time,
                source: 'gps',
                latitude: f.latitude,
                longitude: f.longitude,
                accuracyMeters: f.accuracyMeters,
              ),
            );
            void alt() => pre.addAltitude(
              RawAltitude(time: f.time, source: 'gps', meters: d.$3),
            );
            if (altitudeFirst) {
              alt();
              pos();
            } else {
              pos();
              alt();
            }
          }
          final re = pre.result(at: r.clock.now()).altitude;
          expect(
            re.ascentMeters,
            live.ascentMeters,
            reason: 'first=$altitudeFirst',
          );
          expect(re.acceptedValues.length, live.acceptedValues.length);
        }
      }
    });

    test('Höhe nach dem Re-Anker zählt wieder normal', () {
      final r = Rig()..s.start();
      at(r, 1, 500000, alt: 0);
      for (var i = 0; i < 4; i++) {
        at(r, 2 + i, 3.0 * i, alt: 495);
      }
      for (var i = 0; i < 40; i++) {
        at(r, 6 + i, 9 + 3.0 * i, alt: 495 + 0.5 * (i + 1));
      }
      expect(r.s.preprocessing()!.altitude.ascentMeters, greaterThan(10));
    });

    test('Re-Anker in einem offenen PAR-004-Verlust: genau eine Lücke', () {
      final r = Rig()..s.start();
      at(r, 1, 0);
      at(r, 12, 5000); // Verlust öffnet (11 s), hardJump
      at(r, 13, 5003);
      at(r, 14, 5006); // Re-Anker schließt den Verlust
      final snap = r.s.snapshot();
      final losses = snap.gaps.where((g) => g.kind == RunGapKind.positionLoss);
      expect(losses, hasLength(1));
      expect(losses.single.start, t0.add(const Duration(seconds: 1)));
      expect(losses.single.end, t0.add(const Duration(seconds: 14)));
      expect(snap.positionLost, isFalse);
    });
  });

  group('Genauigkeiten aus dem Standortpunkt (K12 Adapter-Teil)', () {
    test('Vertikalgenauigkeit erreicht die Höhenfilterung (PAR-013)', () {
      final r = Rig()..s.start();
      r.wait(1);
      r.s.addPosition(
        LocationSample(
          time: t0.add(const Duration(seconds: 1)),
          latitude: 10,
          longitude: 20,
          accuracyMeters: 5,
          altitudeMeters: 100,
          verticalAccuracyMeters: 50,
        ),
      );
      final alt = r.s.preprocessing()!.altitude;
      expect(alt.processed.single.state, MeasurementState.discarded);
      expect(alt.processed.single.reason, DiscardReason.verticalAccuracy);
    });

    test('Ohne Vertikalgenauigkeit wird die Höhe angenommen', () {
      final r = Rig()..s.start();
      r.wait(1);
      r.s.addPosition(fix(1, 0, alt: 100));
      expect(r.s.preprocessing()!.altitude.acceptedValues, hasLength(1));
    });
  });
}
