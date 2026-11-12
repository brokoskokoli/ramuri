import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// WP25 C1: Auswertung eines Bandlaufs nach dem Ende (FR-0196, K57).
final _t0 = DateTime.utc(2030, 2, 25, 8);

BeltSetting _b(int sec, double v, [double? incline = 0]) => BeltSetting(
  offset: Duration(seconds: sec),
  speedMetersPerSecond: v,
  inclinePercent: incline,
);

/// Beendeter Bandlauf mit Puls [bpm] jede Sekunde und den Einstellungen.
Future<int> _seedBelt(
  RecalcWorld w,
  DateTime start, {
  required int seconds,
  required List<BeltSetting> belts,
  int bpm = 150,
  String source = 'strap',
  List<(int, int)> pauses = const [],
}) async {
  final run = await w.session.runs.create(
    startedAt: start,
    mode: RunMode.treadmill,
  );
  await w.session.rawData.append(
    run.id,
    RawBatch(
      heartRates: [
        for (var s = 0; s <= seconds; s++)
          RawHeartRate(
            time: start.add(Duration(seconds: s)),
            source: source,
            bpm: bpm,
            contact: SensorContact.good,
          ),
      ],
      beltSettings: belts,
    ),
  );
  for (final (a, b) in pauses) {
    final g = await w.session.markers.openGap(
      run.id,
      RunGapKind.manualPause,
      start.add(Duration(seconds: a)),
    );
    await w.session.markers.closeGap(g, start.add(Duration(seconds: b)));
  }
  final end = start.add(Duration(seconds: seconds));
  await w.session.runs.setState(run.id, RunState.finished, endedAt: end);
  w.clock.set(end.add(const Duration(minutes: 1)));
  return run.id;
}

void main() {
  group('computeBeltTrack', () {
    test('Strecke, Bewegungszeit und Pace; Pause und 0 m/s zählen nicht', () {
      final track = computeBeltTrack(
        start: _t0,
        to: _t0.add(const Duration(minutes: 40)),
        settings: [
          _b(0, 2.5),
          _b(600, 2.5), // Lebenszeichen: unveränderte Wiederholung
          _b(900, 0), // Stillstand 5 min
          _b(1200, 3.0),
        ],
        // Pause 1500..1800 s im Abschnitt mit 3 m/s
        pauses: [
          (
            _t0.add(const Duration(minutes: 25)),
            _t0.add(const Duration(minutes: 30)),
          ),
        ],
      );
      // 900 s * 2.5 + 0 + (1200..1500 und 1800..2400 = 900 s) * 3.0
      expect(track.meters, closeTo(2250 + 2700, 1e-6));
      expect(track.moving, const Duration(seconds: 1800));
      // Lebenszeichen sind mit dem Vorgänger zusammengefasst.
      expect(track.pieces.length, 4);
      expect(track.averagePaceSecondsPerKm, closeTo(1800 / 4.95, 1e-6));
    });

    test('offene Pause endet am Laufende; Pause vor der Einstellung', () {
      final track = computeBeltTrack(
        start: _t0,
        to: _t0.add(const Duration(seconds: 600)),
        settings: [_b(0, 3.0)],
        pauses: [
          (
            _t0.add(const Duration(seconds: 300)),
            _t0.add(const Duration(seconds: 600)),
          ),
        ],
      );
      expect(track.meters, closeTo(900, 1e-6));
      expect(track.moving, const Duration(seconds: 300));
    });
  });

  group('Auswertung nach dem Ende', () {
    test(
      'Strecke, Zeit und VO2max aus den Einstellungen, höchstens vorläufig',
      () async {
        final w = await RecalcWorld.create();
        // 30 min mit 3 m/s, Steigung 0, Lebenszeichen alle 30 s.
        final id = await _seedBelt(
          w,
          _t0,
          seconds: 1800,
          belts: [for (var s = 0; s < 1800; s += 30) _b(s, 3.0)],
        );
        await w.calc().calculateAfterRun(id);

        final pair = await runVo2(w.session, id);
        // ACSM wie beim GPS-Lauf gleicher Werte: 55,5 ml/kg/min.
        expect(pair.original.value, closeTo(55.5, 0.1));
        expect(pair.original.quality, ValueQuality.provisional);
        expect(pair.original.sections, isNotEmpty);
        expect(
          pair.original.sections.map((s) => s.reasons).expand((r) => r),
          isNot(contains(SectionRule.gpsMedianAccuracy)),
        );
        final o = (await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load()).single;
        expect(o.distanceMeters, closeTo(5400, 1e-6));
        expect(o.movingTime, const Duration(minutes: 30));
        expect(o.averagePaceSecondsPerKm, closeTo(1800 / 5.4, 1e-6));
        expect(o.bestPaceSecondsPerKm, isNull);
      },
    );

    test(
      'Geschwindigkeitswechsel trennt Abschnitte, Einschwingzeit danach',
      () async {
        final w = await RecalcWorld.create();
        final id = await _seedBelt(
          w,
          _t0,
          seconds: 1800,
          belts: [_b(0, 2.5), _b(900, 3.5)],
        );
        final a =
            await RunAnalyzer(
              fitness: const FitnessParameters.v4(),
              preprocessing: const PreprocessingParameters.v4(),
              basis: const HeartRateBasis(maxBpm: 190, restingBpm: 60),
            ).analyze(
              w.session,
              (await w.session.runs.get(id))!,
              calculatedAt: w.clock.now(),
            );
        expect(a.belt, isNotNull);
        final s = a.selection.sections;
        // Je Phase 12 min nach 3 min Einschwingzeit: zwei Teile (PAR-021).
        expect(s.map((e) => e.speedMetersPerMinute), [150, 150, 210, 210]);
        expect(s[0].from, _t0.add(const Duration(minutes: 3)));
        expect(s[1].to, _t0.add(const Duration(minutes: 15)));
        expect(s[2].from, _t0.add(const Duration(minutes: 18)));
        expect(s[3].to, _t0.add(const Duration(minutes: 30)));
      },
    );

    test('manuelle Pause: nicht in Strecke und Bewegungszeit', () async {
      final w = await RecalcWorld.create();
      final id = await _seedBelt(
        w,
        _t0,
        seconds: 1800,
        belts: [_b(0, 3.0)],
        pauses: [(600, 900)],
      );
      await w.calc().calculateAfterRun(id);
      final o = (await RunOverviewService(
        session: w.session,
        clock: w.clock,
      ).load()).single;
      expect(o.distanceMeters, closeTo(4500, 1e-6));
      expect(o.movingTime, const Duration(minutes: 25));
    });

    test(
      'Belastung zählt normal: TRIMP und Zonenzeiten aus der Bandzeit',
      () async {
        final w = await RecalcWorld.create();
        final id = await _seedBelt(w, _t0, seconds: 1800, belts: [_b(0, 3.0)]);
        await w.calc().calculateAfterRun(id);
        final byKey = {
          for (final p in await w.session.values.read(ValueOwner.run(id)))
            p.original.key: p.original,
        };
        final trimp = byKey[trimpRunValueKey]!;
        expect(trimp.value, isNotNull);
        expect(trimp.value!, greaterThan(0));
        final zoneSeconds = [
          for (final p in byKey.values)
            if (p.key != vo2maxRunValueKey && p.key != trimpRunValueKey)
              p.value,
        ].whereType<num>().fold<num>(0, (a, b) => a + b);
        expect(zoneSeconds, greaterThan(0));
      },
    );

    test(
      'GPS-Lauf unverändert: kein Bandergebnis, Strecke und Bestpace aus GPS',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 25, 8));
        final a =
            await RunAnalyzer(
              fitness: const FitnessParameters.v4(),
              preprocessing: const PreprocessingParameters.v4(),
              basis: const HeartRateBasis(maxBpm: 190, restingBpm: 60),
            ).analyze(
              w.session,
              (await w.session.runs.get(id))!,
              calculatedAt: w.clock.now(),
            );
        expect(a.belt, isNull);
        await w.calc().calculateAfterRun(id);
        final o = (await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load()).single;
        expect(o.distanceMeters, greaterThan(5000));
        expect(o.bestPaceSecondsPerKm, isNotNull);
      },
    );
  });

  group('Ausschlüsse', () {
    test(
      'Referenzvorschläge, Riegel und Plan: Bandlauf fehlt im Leser',
      () async {
        final w = await RecalcWorld.create();
        final band = await _seedBelt(
          w,
          _t0,
          seconds: 1800,
          belts: [_b(0, 3.0)],
        );
        final gps = await w.seedRun(DateTime.utc(2030, 2, 26, 8));
        await w.calc().calculateAfterRun(band);
        await w.calc().calculateAfterRun(gps);
        final runs = await PredictionRunReader(
          session: w.session,
          clock: w.clock,
        ).load();
        expect([for (final r in runs) r.id], ['$gps']);
      },
    );

    test(
      'aerobe Effizienz: Bandlauf zählt nicht (Quelle fehlt im Wert)',
      () async {
        final w = await RecalcWorld.create();
        final ids = <int>[];
        for (final (d, v, src) in [
          (DateTime.utc(2030, 1, 20, 8), 3.0, 'strap'),
          (DateTime.utc(2030, 2, 20, 8), 3.0, 'bandstrap'),
        ]) {
          ids.add(
            src == 'strap'
                ? await w.seedRun(d, speed: v)
                : await _seedBelt(
                    w,
                    d,
                    seconds: 1800,
                    belts: [_b(0, v)],
                    source: src,
                  ),
          );
        }
        for (final id in ids) {
          await w.calc().calculateAfterRun(id);
        }
        final eff = [
          for (final p in await w.allPairs())
            if (p.original.key == aerobicEfficiencyValueKey) p.current,
        ];
        expect(eff, isNotEmpty);
        for (final e in eff) {
          expect(e.sources, isNot(contains('bandstrap')));
        }
        // Gegenprobe: Belastung zählt normal (TRIMP vorhanden).
        expect(
          (await w.session.values.read(ValueOwner.run(ids.last)))
              .map((p) => p.original.key),
          contains(vo2maxRunValueKey),
        );
      },
    );
  });
}
