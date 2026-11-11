import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

/// 3 m/s nach Norden; die Uhr steht auf dem Messzeitpunkt.
LocationSample fix(num sec, num north) => LocationSample(
  time: t0.add(Duration(seconds: sec.round())),
  latitude: 10 + north / 111195,
  longitude: 20,
  accuracyMeters: 5,
);

class World {
  World._(this.session, this.clock);
  final StorageSession session;
  final FakeClock clock;

  static Future<World> open() async => World._(
    await FakeStorage().open(Uint8List(32)),
    FakeClock(t0, utcOffset: const Duration(hours: 2)),
  );

  RunRecorder recorder() => RunRecorder(
    clock: clock,
    runs: session.runs,
    rawData: session.rawData,
    markers: session.markers,
  );

  RunRecovery recovery() => RunRecovery(
    clock: clock,
    runs: session.runs,
    rawData: session.rawData,
    markers: session.markers,
  );

  /// Punkt zur Messzeit [sec] (Uhr dorthin gesetzt), Position [north] Meter.
  Intake feed(RunRecorder r, num sec, num north) {
    clock.set(t0.add(Duration(seconds: sec.round())));
    return r.addPosition(fix(sec, north));
  }

  /// Ein Lauf, der nach 30 s ohne Ende abbricht (kein finish, Prozess weg).
  Future<(int, double)> crashedRun({bool pausedAtEnd = false}) async {
    final r = recorder();
    await r.start();
    for (var s = 1; s <= 30; s++) {
      feed(r, s, 3.0 * s);
    }
    clock.set(t0.add(const Duration(seconds: 30)));
    if (pausedAtEnd) await r.pause();
    await r.flush();
    return (r.runId!, r.snapshot().distanceMeters!);
  }
}

/// Puls, Höhe und Schritte nach dem letzten GPS-Punkt (GPS weg, Sensoren
/// laufen weiter), dann Abbruch. Letzter Zeitpunkt: Sekunde 50.
Future<int> crashedWithSensorsAfterGps(World w) async {
  final r = w.recorder();
  await r.start();
  for (var s = 1; s <= 30; s++) {
    w.feed(r, s, 3.0 * s);
  }
  w.clock.set(t0.add(const Duration(seconds: 50)));
  r.addHeartRate(
    HeartRateReading('hr', t0.add(const Duration(seconds: 50)), 140),
  );
  await r.flush();
  return r.runId!;
}

void main() {
  group('Letzter Zeitpunkt (Puls nach dem letzten GPS-Punkt)', () {
    test('Speichern: Endzeit ist der letzte Pulswert', () async {
      final w = await World.open();
      final id = await crashedWithSensorsAfterGps(w);
      final saved = await w.recovery().saveFinished(id);
      expect(saved!.endedAt, t0.add(const Duration(seconds: 50)));
    });

    test('Fortsetzen: Lücke beginnt am letzten Pulswert', () async {
      final w = await World.open();
      final id = await crashedWithSensorsAfterGps(w);
      w.clock.set(t0.add(const Duration(seconds: 300)));
      expect(await w.recorder().restore(id), CommandResult.ok);
      final g = (await w.session.markers.gaps(id))
          .singleWhere((g) => g.kind == RunGapKind.interruption);
      expect(g.start, t0.add(const Duration(seconds: 50)));
    });
  });

  group('Runden über die Wiederaufnahme', () {
    test('Index zählt weiter, Rundenzeit ab der letzten Marke, Bewegungszeit '
        'ohne Ausfall', () async {
      final w = await World.open();
      final r1 = w.recorder();
      await r1.start();
      for (var s = 1; s <= 30; s++) {
        w.feed(r1, s, 3.0 * s);
        if (s == 20) await r1.lap();
      }
      await r1.flush();
      final id = r1.runId!;
      // 10 Minuten Ausfall.
      w.clock.set(t0.add(const Duration(seconds: 630)));
      final r2 = w.recorder();
      await r2.restore(id);
      expect(r2.snapshot().laps.map((l) => l.index), [1]);
      for (var s = 631; s <= 640; s++) {
        w.feed(r2, s, 3000 + 3.0 * (s - 631));
      }
      await r2.lap();
      final laps = r2.snapshot().laps;
      expect(laps.map((l) => l.index), [1, 2]);
      expect(laps[1].lapTime, const Duration(seconds: 620));
      // Bewegt: Sekunden 20 bis 30 und 631 bis 640, nicht die 600 s Ausfall.
      expect(laps[1].movingTime, lessThan(const Duration(seconds: 30)));
      expect(laps[1].movingTime, greaterThan(const Duration(seconds: 10)));
      final stored = await w.session.markers.laps(id);
      expect(stored.map((l) => l.index), [1, 2]);
    });
  });

  group('Doppelstart', () {
    test('zwei gleichzeitige restore: einer ok, eine Lücke', () async {
      final w = await World.open();
      final (id, _) = await w.crashedRun();
      w.clock.set(t0.add(const Duration(seconds: 630)));
      final r = w.recorder();
      final both = await Future.wait([r.restore(id), r.restore(id)]);
      expect(both, unorderedEquals([CommandResult.ok, CommandResult.rejected]));
      final gaps = await w.session.markers.gaps(id);
      expect(gaps.where((g) => g.kind == RunGapKind.interruption).length, 1);
    });
  });

  group('Erkennung', () {
    test(
      'ohne unfertigen Lauf kein Angebot, auch nicht nach normalem Ende',
      () async {
        final w = await World.open();
        expect(await w.recovery().pending(serviceRunning: false), isNull);
        final r = w.recorder();
        await r.start();
        w.feed(r, 1, 3);
        await r.finish();
        expect(await w.recovery().pending(serviceRunning: false), isNull);
      },
    );

    test('unfertiger Lauf ohne Dienst wird angeboten, auch pausiert', () async {
      final w = await World.open();
      final (id, _) = await w.crashedRun(pausedAtEnd: true);
      expect((await w.session.runs.get(id))!.state, RunState.paused);
      final p = await w.recovery().pending(serviceRunning: false);
      expect(p?.id, id);
    });

    test('mit laufendem Dienst kein Angebot', () async {
      final w = await World.open();
      await w.crashedRun();
      expect(await w.recovery().pending(serviceRunning: true), isNull);
    });

    test('keine Frist: Uhr 400 Tage später bietet weiter an', () async {
      final w = await World.open();
      final (id, _) = await w.crashedRun();
      w.clock.advance(const Duration(days: 400));
      expect((await w.recovery().pending(serviceRunning: false))?.id, id);
    });
  });

  group('Als beendet speichern', () {
    test('Endzeit ist der letzte Zeitpunkt, Versatz gesetzt, Lücken zu, '
        'danach kein Angebot mehr', () async {
      final w = await World.open();
      final (id, _) = await w.crashedRun(pausedAtEnd: true);
      w.clock.advance(const Duration(days: 400));
      final saved = await w.recovery().saveFinished(id);
      expect(saved!.state, RunState.finished);
      expect(saved.endedAt, t0.add(const Duration(seconds: 30)));
      expect(saved.endedUtcOffset, const Duration(hours: 2));
      final gaps = await w.session.markers.gaps(id);
      expect(gaps, isNotEmpty);
      expect(gaps.every((g) => g.end != null), isTrue);
      expect(await w.recovery().pending(serviceRunning: false), isNull);
      expect(await w.recovery().saveFinished(id), isNull);
    });
  });

  group('Fortsetzen', () {
    test('derselbe Lauf, Lücke interruption, Strecke ohne die Lücke, '
        'Ausfallzeit nur in der Gesamtzeit', () async {
      final w = await World.open();
      final (id, d1) = await w.crashedRun();
      // 10 Minuten Ausfall, danach 3 km weiter weg (Ortssprung).
      w.clock.set(t0.add(const Duration(seconds: 630)));
      final r = w.recorder();
      expect(await r.restore(id), CommandResult.ok);
      expect(r.runId, id);
      expect(r.phase, RecordingPhase.running);
      for (var s = 631; s <= 640; s++) {
        w.feed(r, s, 3000 + 3.0 * (s - 631));
      }
      final snap = r.snapshot();
      // Nur die 9 Schritte nach der Wiederaufnahme kommen dazu (27 m).
      expect(snap.distanceMeters! - d1, closeTo(27, 3));
      expect(snap.totalTime, const Duration(seconds: 640));
      expect(snap.movingTime! < const Duration(seconds: 60), isTrue);
      final gaps = await w.session.markers.gaps(id);
      final g = gaps.singleWhere((g) => g.kind == RunGapKind.interruption);
      expect(g.start, t0.add(const Duration(seconds: 30)));
      expect(g.end, t0.add(const Duration(seconds: 630)));
      expect((await w.session.runs.get(id))!.state, RunState.active);
      // Kein zweiter Lauf, kein Angebot-Rest nach dem normalen Ende.
      await r.finish();
      expect((await w.session.runs.list()).length, 1);
      expect(await w.recovery().pending(serviceRunning: false), isNull);
    });

    test('zweiter Abbruch und erneutes Fortsetzen rechnet dasselbe', () async {
      final w = await World.open();
      final (id, d1) = await w.crashedRun();
      w.clock.set(t0.add(const Duration(seconds: 630)));
      final r2 = w.recorder();
      await r2.restore(id);
      for (var s = 631; s <= 640; s++) {
        w.feed(r2, s, 3000 + 3.0 * (s - 631));
      }
      await r2.flush();
      final d2 = r2.snapshot().distanceMeters!;
      w.clock.set(t0.add(const Duration(seconds: 1240)));
      final r3 = w.recorder();
      await r3.restore(id);
      final s3 = r3.snapshot();
      expect(s3.distanceMeters, closeTo(d2, 0.001));
      expect(d2 - d1, closeTo(27, 3));
      final gaps = await w.session.markers.gaps(id);
      expect(gaps.where((g) => g.kind == RunGapKind.interruption).length, 2);
      expect(gaps.every((g) => g.end != null), isTrue);
      expect(s3.totalTime, const Duration(seconds: 1240));
    });

    test('pausierter Lauf: Pause geschlossen, Lauf wieder aktiv', () async {
      final w = await World.open();
      final (id, _) = await w.crashedRun(pausedAtEnd: true);
      w.clock.set(t0.add(const Duration(seconds: 100)));
      final r = w.recorder();
      expect(await r.restore(id), CommandResult.ok);
      expect((await w.session.runs.get(id))!.state, RunState.active);
      final gaps = await w.session.markers.gaps(id);
      expect(gaps.every((g) => g.end != null), isTrue);
      expect(
        gaps.firstWhere((g) => g.kind == RunGapKind.manualPause).end,
        t0.add(const Duration(seconds: 30)),
      );
    });

    test('beendeter oder unbekannter Lauf wird nicht fortgesetzt', () async {
      final w = await World.open();
      final r = w.recorder();
      await r.start();
      await r.finish();
      expect(await w.recorder().restore(r.runId!), CommandResult.rejected);
      expect(await w.recorder().restore(999), CommandResult.rejected);
    });

    test(
      'Uhr zurück: Lücke leer, nie negativ, alte Punkte verworfen',
      () async {
        final w = await World.open();
        final (id, d1) = await w.crashedRun();
        w.clock.set(t0.subtract(const Duration(days: 1)));
        final r = w.recorder();
        expect(await r.restore(id), CommandResult.ok);
        final g = (await w.session.markers.gaps(id))
            .singleWhere((g) => g.kind == RunGapKind.interruption);
        expect(g.start, t0.add(const Duration(seconds: 30)));
        expect(g.end, g.start);
        // Punkt mit der zurückgesprungenen Uhr zählt nicht.
        w.clock.set(t0.subtract(const Duration(days: 1)));
        expect(r.addPosition(fix(0, 5000)), Intake.ignoredStale);
        expect(r.snapshot().distanceMeters, closeTo(d1, 0.001));
        // Sobald die Uhr den letzten Zeitpunkt überschreitet, geht es weiter.
        expect(w.feed(r, 31, 93), Intake.processed);
        expect(r.snapshot().distanceMeters!, greaterThanOrEqualTo(d1));
        expect(r.snapshot().totalTime! >= Duration.zero, isTrue);
      },
    );
  });

  group('RR-Pakete beim Wiederanlauf (FR-0213)', () {
    test('nach Absturz fehlt höchstens der ungeflushte Puffer', () async {
      final w = await World.open();
      // Grosser Stapel: Zeilen bleiben bis zum flush() im Puffer.
      final r = RunRecorder(
        clock: w.clock,
        runs: w.session.runs,
        rawData: w.session.rawData,
        markers: w.session.markers,
        batchRows: 1000,
      );
      await r.start();
      for (var s = 1; s <= 5; s++) {
        w.feed(r, s, 3.0 * s);
      }
      r.addHeartRate(
        HeartRateReading('hr', w.clock.now(), 140, rrIntervals: const [800]),
      );
      await r.flush(); // geflusht
      w.clock.set(t0.add(const Duration(seconds: 7)));
      r.addHeartRate(
        HeartRateReading('hr', w.clock.now(), 141, rrIntervals: const [790]),
      ); // nur im Puffer, Prozess stirbt
      final id = r.runId!;

      final raw = await w.session.rawData.read(id);
      expect(raw.rrPackets.map((p) => p.value.intervals), [
        [800],
      ]);
      expect(raw.heartRates, hasLength(1), reason: 'wie beim Puls');

      final saved = await w.recovery().saveFinished(id);
      expect(saved, isNotNull);
      expect(
        (await w.session.rawData.read(id)).rrPackets.map((p) => p.value.source),
        ['hr'],
        reason: 'gespeicherter Lauf behält das geflushte Paket',
      );
    });
  });
}
