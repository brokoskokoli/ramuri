import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

LocationSample fix(
  num sec,
  num north, {
  double? speed,
  double? speedAcc,
  double? vAcc,
  double? alt,
  int? ageMs,
}) => LocationSample(
  time: t0.add(Duration(milliseconds: (sec * 1000).round())),
  latitude: 10 + north / 111195,
  longitude: 20,
  ageMs: ageMs,
  accuracyMeters: 5,
  altitudeMeters: alt,
  speedMetersPerSecond: speed,
  speedAccuracyMetersPerSecond: speedAcc,
  verticalAccuracyMeters: vAcc,
);

/// Speicher, dessen Schreibzugriffe protokolliert und angehalten werden können.
class Probe implements RawDataStore, RunStore {
  Probe(this.raw, this.runs);
  final RawDataStore raw;
  final RunStore runs;
  final log = <String>[];

  /// Solange gesetzt, wartet `append` darauf.
  Completer<void>? gate;
  StorageFailure? failNext;
  int appends = 0;
  int maxBatchRows = 0;

  @override
  Future<void> append(int runId, RawBatch batch) async {
    appends++;
    final rows =
        batch.positions.length +
        batch.altitudes.length +
        batch.heartRates.length;
    if (rows > maxBatchRows) maxBatchRows = rows;
    log.add('append:${batch.positions.length}');
    final g = gate;
    if (g != null) await g.future;
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw StorageException(f);
    }
    await raw.append(runId, batch);
    log.add('appended');
  }

  @override
  Future<StoredRawData> read(int runId) => raw.read(runId);

  @override
  Future<StoredRun> create({required DateTime startedAt}) {
    if (failNext == StorageFailure.failed && appends == -1) {
      throw const StorageException(StorageFailure.failed);
    }
    return runs.create(startedAt: startedAt);
  }

  @override
  Future<void> setState(int runId, RunState state, {DateTime? endedAt}) {
    log.add('state:${state.name}');
    return runs.setState(runId, state, endedAt: endedAt);
  }

  @override
  Future<StoredRun?> get(int runId) => runs.get(runId);
  @override
  Future<List<StoredRun>> list() => runs.list();
  @override
  Future<List<StoredRun>> unfinished() => runs.unfinished();
}

/// Lückenspeicher, dessen Öffnen bzw. Schließen auf Wunsch scheitert.
class FlakyMarkers implements RunMarkerStore {
  FlakyMarkers(this.inner);
  final RunMarkerStore inner;
  bool failOpens = false;
  bool failCloses = false;
  bool rejectOpens = false;
  int openCalls = 0;

  @override
  Future<int> openGap(int runId, RunGapKind kind, DateTime start) {
    openCalls++;
    if (rejectOpens) {
      throw const StorageException(StorageFailure.rejected);
    }
    if (failOpens) {
      throw const StorageException(StorageFailure.failed);
    }
    return inner.openGap(runId, kind, start);
  }

  @override
  Future<void> closeGap(int gapId, DateTime end) {
    if (failCloses) {
      throw const StorageException(StorageFailure.failed);
    }
    return inner.closeGap(gapId, end);
  }

  @override
  Future<void> addLap(int runId, StoredLap lap) => inner.addLap(runId, lap);
  @override
  Future<List<StoredLap>> laps(int runId) => inner.laps(runId);
  @override
  Future<List<StoredGap>> gaps(int runId) => inner.gaps(runId);
}

class Rig {
  Rig._(this.clock, this.session, this.probe, this.recorder);

  static Future<Rig> make({
    bool autoPause = false,
    int batchRows = rawBatchRows,
    bool flakyMarkers = false,
    Duration clockOffset = Duration.zero,
  }) async {
    final session = await FakeStorage().open(Uint8List(32));
    final flaky = flakyMarkers ? FlakyMarkers(session.markers) : null;
    final probe = Probe(session.rawData, session.runs);
    final clock = FakeClock(t0.add(clockOffset));
    final rec = RunRecorder(
      clock: clock,
      runs: probe,
      rawData: probe,
      markers: flaky ?? session.markers,
      session: RecordingSession(clock: clock, autoPause: autoPause),
      batchRows: batchRows,
    );
    return Rig._(clock, session, probe, rec).._flaky = flaky;
  }

  final FakeClock clock;
  final StorageSession session;
  final Probe probe;
  final RunRecorder recorder;
  FlakyMarkers? _flaky;
  double north = 0;

  Future<void> move(int seconds, double speed) async {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      north += speed;
      recorder.addPosition(fix(clock.now().difference(t0).inSeconds, north));
    }
    await recorder.flush();
  }

  int get id => recorder.runId!;
  Future<StoredRawData> raw() => session.rawData.read(id);
  Future<List<StoredGap>> gaps() => session.markers.gaps(id);
}

void main() {
  group('Freier Lauf ohne Plan und Sensor (FR-0025, FR-0035, CON-0004)', () {
    test(
      'Start, Punkte, Runde, Ende: vollständig und lesbar (FR-0028)',
      () async {
        final r = await Rig.make();
        expect(await r.recorder.start(), CommandResult.ok);
        final run = await r.session.runs.get(r.id);
        expect(run!.state, RunState.active);
        expect(run.startedAt, t0);

        await r.move(5, 3);
        expect(await r.recorder.lap(), CommandResult.ok);
        await r.move(5, 3);
        expect(await r.recorder.finish(), CommandResult.ok);

        final done = (await r.session.runs.get(r.id))!;
        expect(done.state, RunState.finished);
        expect(done.endedAt, t0.add(const Duration(seconds: 10)));
        expect((await r.session.runs.list()).map((x) => x.id), [r.id]);
        expect(await r.session.runs.unfinished(), isEmpty);
        expect((await r.raw()).positions, hasLength(10));
        final laps = await r.session.markers.laps(r.id);
        expect(laps.single.index, 1);
        expect(laps.single.lapTime, const Duration(seconds: 5));
        expect((await r.raw()).heartRates, isEmpty);
      },
    );

    test('Rohwerte tragen Zeit, Quelle und Zustand', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(1, 3);
      final p = (await r.raw()).positions.single.value;
      expect(p.time, t0.add(const Duration(seconds: 1)));
      expect(p.source, 'gps');
      expect(p.state, MeasurementState.present);
    });
  });

  group('K12: Tempo, Genauigkeiten, fehlend bleibt fehlend', () {
    test('Werte landen je Punkt im Speicher', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(
        fix(1, 3, speed: 2.5, speedAcc: 0.4, vAcc: 3.5, alt: 40),
      );
      await r.recorder.flush();
      final d = await r.raw();
      final p = d.positions.single.value;
      expect(p.speedMetersPerSecond, 2.5);
      expect(p.speedAccuracyMetersPerSecond, 0.4);
      expect(p.verticalAccuracyMeters, 3.5);
      expect(d.altitudes.single.value.meters, 40);
      expect(d.altitudes.single.value.verticalAccuracyMeters, 3.5);
    });

    test('Fehlende Werte bleiben null, ein echtes 0 bleibt 0', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(1, 3));
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(2, 3, speed: 0, speedAcc: 0, vAcc: 0));
      await r.recorder.flush();
      final p = (await r.raw()).positions.map((x) => x.value).toList();
      expect(p[0].speedMetersPerSecond, isNull);
      expect(p[0].speedAccuracyMetersPerSecond, isNull);
      expect(p[0].verticalAccuracyMeters, isNull);
      expect(p[1].speedMetersPerSecond, 0);
      expect(p[1].speedAccuracyMetersPerSecond, 0);
      expect(p[1].verticalAccuracyMeters, 0);
    });

    test(
      'Nicht endliche Werte werden null, der Stapel scheitert nicht',
      () async {
        final r = await Rig.make();
        await r.recorder.start();
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(
          fix(1, 3, speed: double.nan, speedAcc: double.infinity),
        );
        await r.recorder.flush();
        expect(r.recorder.lastWriteFailure, isNull);
        final p = (await r.raw()).positions.single.value;
        expect(p.speedMetersPerSecond, isNull);
        expect(p.speedAccuracyMetersPerSecond, isNull);
      },
    );
  });

  group('GPS-Verlust (FR-0194, PAR-004)', () {
    test('Zeit und Puls laufen weiter, Lücke markiert, Strecke nicht '
        'geschätzt', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(5, 3); // letzter Punkt bei 5 s, 15 m
      final before = r.recorder.snapshot().distanceMeters!;

      // 20 s ohne Punkt; Puls kommt weiter.
      for (var i = 0; i < 20; i++) {
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addHeartRate(
          HeartRateReading('strap', r.clock.now(), 140 + i),
        );
        r.recorder.tick();
      }
      final during = r.recorder.snapshot();
      expect(during.positionLost, isTrue);
      expect(during.totalTime, const Duration(seconds: 25));
      expect(during.distanceMeters, before, reason: 'keine Schätzung');
      expect(during.heartRateBpm, 159);

      // Rückkehr 100 m weiter (4,8 m/s, plausibel): die Lücke wird nicht überbrückt.
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(26, 115));
      await r.recorder.flush();
      final after = r.recorder.snapshot();
      expect(after.positionLost, isFalse);
      expect(
        after.distanceMeters!,
        before,
        reason: 'Strecke über die Lücke wird nicht interpoliert',
      );

      final gaps = await r.gaps();
      final loss = gaps.where((g) => g.kind == RunGapKind.positionLoss).single;
      expect(loss.start, t0.add(const Duration(seconds: 5)));
      expect(loss.end, t0.add(const Duration(seconds: 26)));

      final raw = await r.raw();
      expect(raw.heartRates, hasLength(20), reason: 'Puls in der Lücke');
      expect(
        raw.positions.where((p) {
          final s = p.value.time.difference(t0).inSeconds;
          return s > 5 && s < 26;
        }),
        isEmpty,
        reason: 'keine erfundenen Punkte in der Lücke',
      );
    });

    test('Neu ankern: falscher erster Punkt, Lücke gespeichert, Strecke ohne '
        'Versatz', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(1, 500000)); // falscher Standardpunkt
      for (var i = 0; i < 3; i++) {
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(fix(2 + i, 3.0 * i));
      }
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(5, 9));
      await r.recorder.flush();
      final snap = r.recorder.snapshot();
      expect(snap.positionLost, isFalse);
      expect(snap.distanceMeters!, closeTo(3, 1e-3));
      final loss = (await r.gaps()).single;
      expect(loss.kind, RunGapKind.positionLoss);
      expect(loss.start, t0.add(const Duration(seconds: 1)));
      expect(loss.end, t0.add(const Duration(seconds: 4)));
    });

    test(
      'Scheitert das Öffnen der Lückenmarke, wird sie nachgeholt (Soll 2)',
      () async {
        final r = await Rig.make(flakyMarkers: true);
        r._flaky!.failOpens = true;
        await r.recorder.start();
        await r.move(5, 3);
        r.clock.advance(const Duration(seconds: 20));
        r.recorder.tick(); // Lücke beginnt, Speichern scheitert
        await r.recorder.flush().catchError((Object _) {});
        expect(r.recorder.lastWriteFailure, StorageFailure.failed);
        expect(await r.gaps(), isEmpty);
        r._flaky!.failOpens = false; // Speicher wieder da

        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(fix(26, 100));
        await r.recorder.flush();
        final loss = (await r.gaps()).single;
        expect(loss.kind, RunGapKind.positionLoss);
        expect(loss.start, t0.add(const Duration(seconds: 5)));
        expect(loss.end, t0.add(const Duration(seconds: 26)));
      },
    );

    test('Abgelehntes Öffnen der Lückenmarke wird beim Schließen nicht erneut '
        'versucht (Soll 4)', () async {
      final r = await Rig.make(flakyMarkers: true);
      r._flaky!.rejectOpens = true;
      await r.recorder.start();
      await r.move(5, 3);
      r.clock.advance(const Duration(seconds: 20));
      r.recorder.tick();
      await r.recorder.flush().catchError((Object _) {});
      expect(r._flaky!.openCalls, 1);
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(26, 100)); // schließt die Lücke
      await r.recorder.flush().catchError((Object _) {});
      expect(r._flaky!.openCalls, 1);
    });

    test(
      'Scheitert das Schließen der Lückenmarke, wird es nachgeholt',
      () async {
        final r = await Rig.make(flakyMarkers: true);
        r._flaky!.failCloses = true;
        await r.recorder.start();
        await r.move(5, 3);
        r.clock.advance(const Duration(seconds: 20));
        r.recorder.tick();
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(fix(26, 100));
        await r.recorder.flush().catchError((Object _) {});
        expect((await r.gaps()).single.end, isNull);
        r._flaky!.failCloses = false;
        await r.recorder.finish();
        expect(
          (await r.gaps()).single.end,
          t0.add(const Duration(seconds: 26)),
        );
      },
    );

    test(
      'Lückenmarke wird schon durch tick() gespeichert, ohne Anzeige',
      () async {
        final r = await Rig.make();
        await r.recorder.start();
        await r.move(5, 3);
        r.clock.advance(const Duration(seconds: 11));
        r.recorder.tick(); // kein snapshot(), kein Punkt
        await r.recorder.flush();
        final g = (await r.gaps()).single;
        expect(g.kind, RunGapKind.positionLoss);
        expect(g.start, t0.add(const Duration(seconds: 5)));
      },
    );

    test('Lücke ohne Rückkehr wird beim Ende geschlossen', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(3, 3);
      r.clock.advance(const Duration(seconds: 30));
      await r.recorder.finish();
      final g = (await r.gaps()).single;
      expect(g.kind, RunGapKind.positionLoss);
      expect(g.end, t0.add(const Duration(seconds: 33)));
    });
  });

  group('Pause', () {
    test('manuelle Pause: Zustand und Lücke', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(3, 3);
      await r.recorder.pause();
      expect((await r.session.runs.get(r.id))!.state, RunState.paused);
      r.clock.advance(const Duration(seconds: 10));
      await r.recorder.resume();
      expect((await r.session.runs.get(r.id))!.state, RunState.active);
      final g = (await r.gaps()).single;
      expect(g.kind, RunGapKind.manualPause);
      expect(g.start, t0.add(const Duration(seconds: 3)));
      expect(g.end, t0.add(const Duration(seconds: 13)));
      expect((await r.raw()).positions, hasLength(3));
    });

    test('Pausenpunkte werden gespeichert (Nachbesserung 2), liegen in der '
        'Pausenlücke und zählen nicht zu Strecke, Zeit, Runden', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(3, 3);
      final before = r.recorder.snapshot();
      await r.recorder.pause();
      for (var i = 4; i <= 8; i++) {
        r.clock.advance(const Duration(seconds: 1));
        expect(
          r.recorder.addPosition(fix(i, 9.0 + (i - 3) * 50)),
          Intake.recordedWhilePaused,
        );
      }
      await r.recorder.flush();
      final after = r.recorder.snapshot();
      expect(after.distanceMeters, before.distanceMeters);
      expect(after.movingTime, before.movingTime);
      expect(r.recorder.preprocessing()!.position.positions, hasLength(3));
      await r.recorder.resume();
      await r.recorder.finish();
      final raw = (await r.raw()).positions;
      expect(raw, hasLength(8));
      final gap = (await r.gaps()).single;
      expect(gap.kind, RunGapKind.manualPause);
      final inPause = raw
          .map((p) => p.value.time)
          .where((t) => t.isAfter(gap.start) && !t.isAfter(gap.end!));
      expect(inPause, hasLength(5));
      expect(raw.every((p) => p.value.state == MeasurementState.present), true);
    });

    test(
      'Pausenpunkt vor Pausenbeginn (Altwert) wird nicht gespeichert',
      () async {
        final r = await Rig.make();
        await r.recorder.start();
        await r.move(3, 3);
        r.clock.advance(const Duration(seconds: 2));
        await r.recorder.pause();
        expect(
          r.recorder.addPosition(fix(4, 12, ageMs: 3000)),
          Intake.ignoredStale,
        );
        await r.recorder.flush();
        expect((await r.raw()).positions, hasLength(3));
      },
    );

    for (final offset in [
      const Duration(seconds: 60),
      const Duration(seconds: -60),
    ]) {
      test('Uhrversatz $offset: Rohzeiten in Uhrbasis, innerhalb des Laufs und '
          'passend zu Lücken', () async {
        final r = await Rig.make(clockOffset: offset);
        // Punkte tragen GPS-Zeit t0 + sec, die Uhr geht um [offset] anders.
        var sec = 0;
        double north = 0;
        void gps(int n) {
          for (var k = 0; k < n; k++) {
            r.clock.advance(const Duration(seconds: 1));
            sec++;
            north += 3;
            r.recorder.addPosition(fix(sec, north));
          }
        }

        await r.recorder.start();
        gps(5);
        await r.recorder.pause();
        gps(1); // Pausenpunkt
        r.clock.advance(const Duration(seconds: 2));
        sec += 2; // GPS-Zeit geht mit der Uhr
        await r.recorder.resume();
        gps(3);
        await r.recorder.finish();
        final run = (await r.session.runs.get(r.id))!;
        final raw = (await r.raw()).positions.map((p) => p.value.time).toList();
        expect(raw, hasLength(9));
        for (final t in raw) {
          expect(t.isBefore(run.startedAt), isFalse, reason: '$t');
          expect(t.isAfter(run.endedAt!), isFalse, reason: '$t');
        }
        final gap = (await r.gaps()).single;
        expect(gap.start, run.startedAt.add(const Duration(seconds: 5)));
        // Der Pausenpunkt liegt in der Pausenlücke.
        final paused = raw.where(
          (t) => t.isAfter(gap.start) && !t.isAfter(gap.end!),
        );
        expect(paused, hasLength(1));
        expect(raw.first, run.startedAt.add(const Duration(seconds: 1)));
      });
    }

    test('Ende aus der Pause schließt die Pausenlücke', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(2, 3);
      await r.recorder.pause();
      r.clock.advance(const Duration(seconds: 7));
      await r.recorder.finish();
      final g = (await r.gaps()).single;
      expect(g.end, t0.add(const Duration(seconds: 9)));
      expect((await r.session.runs.get(r.id))!.state, RunState.finished);
    });

    test('erkannte Pause (Autopause): Punkte werden weiter gespeichert, '
        'Lauf bleibt aktiv, keine Lücke', () async {
      final r = await Rig.make(autoPause: true);
      await r.recorder.start();
      await r.move(10, 3);
      await r.move(20, 0); // Stand
      expect(r.recorder.phase, RecordingPhase.autoPaused);
      expect((await r.raw()).positions, hasLength(30));
      expect((await r.session.runs.get(r.id))!.state, RunState.active);
      expect(await r.gaps(), isEmpty);
    });

    test('ungültige Befehle schreiben nichts', () async {
      final r = await Rig.make();
      expect(await r.recorder.pause(), CommandResult.rejected);
      expect(await r.recorder.finish(), CommandResult.rejected);
      expect(r.recorder.runId, isNull);
      await r.recorder.start();
      expect(await r.recorder.start(), CommandResult.rejected);
      expect(await r.recorder.resume(), CommandResult.rejected);
      await r.recorder.finish();
      expect(await r.recorder.finish(), CommandResult.rejected);
      expect(await r.session.runs.list(), hasLength(1));
    });
  });

  group('Rennen und Serialisierung', () {
    test('Ende während laufendem Schreiben: Punkte danach verworfen, Zustand '
        'erst nach dem Stapel', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.probe.gate = Completer<void>();
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(1, 3)); // Schreiben hängt
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(2, 6)); // wartet im Puffer
      final done = r.recorder.finish();
      r.clock.advance(const Duration(seconds: 1));
      expect(r.recorder.addPosition(fix(3, 9)), Intake.ignoredFinished);
      expect(
        r.recorder.addHeartRate(HeartRateReading('s', r.clock.now(), 100)),
        Intake.ignoredFinished,
      );
      r.probe.gate!.complete();
      await done;
      await r.recorder.flush();

      expect((await r.raw()).positions, hasLength(2));
      expect((await r.raw()).heartRates, isEmpty);
      expect(
        r.probe.log.lastIndexOf('appended'),
        lessThan(r.probe.log.indexOf('state:finished')),
      );
      expect((await r.session.runs.get(r.id))!.state, RunState.finished);
    });

    test(
      'Pause und Fortsetzen während des Schreibens: Reihenfolge bleibt',
      () async {
        final r = await Rig.make();
        await r.recorder.start();
        r.probe.gate = Completer<void>();
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(fix(1, 3));
        final p = r.recorder.pause();
        r.clock.advance(const Duration(seconds: 1));
        final q = r.recorder.resume();
        r.probe.gate!.complete();
        await p;
        await q;
        await r.recorder.flush();
        expect(r.probe.log.where((e) => e.startsWith('state:')).toList(), [
          'state:paused',
          'state:active',
        ]);
        expect(
          r.probe.log.indexOf('appended'),
          lessThan(r.probe.log.indexOf('state:paused')),
        );
        expect((await r.session.runs.get(r.id))!.state, RunState.active);
        final g = (await r.gaps()).single;
        expect(g.end, isNotNull);
      },
    );

    test('Teilstapel (Größe 5): Ende, Pause und Runde schreiben den Rest '
        'vor dem Zustandswechsel', () async {
      final r = await Rig.make(batchRows: 5);
      await r.recorder.start();
      for (var i = 1; i <= 3; i++) {
        r.clock.advance(const Duration(seconds: 1));
        r.recorder.addPosition(fix(i, i * 3));
      }
      expect(r.probe.appends, 0, reason: 'unter der Größe wird gewartet');
      await r.recorder.pause();
      expect((await r.raw()).positions, hasLength(3));
      await r.recorder.resume();
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(4, 12));
      await r.recorder.lap();
      expect((await r.raw()).positions, hasLength(4));
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(5, 15));
      await r.recorder.finish();
      expect((await r.raw()).positions, hasLength(5));
      expect(
        r.probe.log.lastIndexOf('appended'),
        lessThan(r.probe.log.indexOf('state:finished')),
      );
      expect(r.probe.maxBatchRows, lessThanOrEqualTo(5));
    });

    test('Stapelgröße ist die Konstante', () async {
      final r = await Rig.make();
      await r.recorder.start();
      await r.move(7, 3);
      expect(rawBatchRows, 1);
      expect(r.probe.maxBatchRows, lessThanOrEqualTo(rawBatchRows));
      expect(r.probe.appends, 7);
    });
  });

  group('Speicherfehler', () {
    test('failed: Fehler gemeldet, Stapel geht nicht verloren', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.probe.failNext = StorageFailure.failed;
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(1, 3));
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(2, 6));
      await r.recorder.flush();
      expect(r.recorder.lastWriteFailure, StorageFailure.failed);
      expect((await r.raw()).positions.map((p) => p.value.time), [
        t0.add(const Duration(seconds: 1)),
        t0.add(const Duration(seconds: 2)),
      ]);
    });

    test('rejected: Stapel wird verworfen, nicht endlos wiederholt', () async {
      final r = await Rig.make();
      await r.recorder.start();
      r.probe.failNext = StorageFailure.rejected;
      r.clock.advance(const Duration(seconds: 1));
      r.recorder.addPosition(fix(1, 3));
      await r.recorder.flush().catchError((Object _) {});
      await r.recorder.flush();
      expect(r.recorder.lastWriteFailure, StorageFailure.rejected);
      expect(r.probe.appends, 1);
    });

    test(
      'Anlegen scheitert: Sitzung bleibt ungestartet, neuer Versuch geht',
      () async {
        final r = await Rig.make();
        r.probe.failNext = StorageFailure.failed;
        r.probe.appends = -1;
        await expectLater(r.recorder.start(), throwsA(isA<StorageException>()));
        expect(r.recorder.phase, RecordingPhase.idle);
        r.probe.appends = 0;
        expect(await r.recorder.start(), CommandResult.ok);
      },
    );
  });
}
