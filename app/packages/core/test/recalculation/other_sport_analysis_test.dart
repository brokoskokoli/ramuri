import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recalc_support.dart';

/// Auswertung einer anderen Sportart nach dem Ende (FR-0221, PAR-232).
/// Synthetische Pulsreihen, keine echten Daten (SEC-0001 bis SEC-0010).
final _t0 = DateTime.utc(2030, 2, 25, 8);

/// Puls je Sekunde: Abschnitte (Dauer in s, bpm); `null` = kein Wert.
List<int?> _series(List<(int, int?)> parts) => [
  for (final (n, bpm) in parts) ...List.filled(n, bpm),
];

Future<void> _finish(
  RecalcWorld w,
  int id,
  DateTime start,
  List<int?> hr,
  String source,
  List<(int, int)> pauses, {
  List<BeltSetting> belts = const [],
  List<int> laps = const [],
  List<(int, int)> interruptions = const [],
}) async {
  await w.session.rawData.append(
    id,
    RawBatch(
      heartRates: [
        for (var s = 0; s < hr.length; s++)
          if (hr[s] != null)
            RawHeartRate(
              time: start.add(Duration(seconds: s)),
              source: source,
              bpm: hr[s]!,
              contact: SensorContact.good,
            ),
      ],
      beltSettings: belts,
    ),
  );
  for (final (a, b) in pauses) {
    final g = await w.session.markers.openGap(
      id,
      RunGapKind.manualPause,
      start.add(Duration(seconds: a)),
    );
    await w.session.markers.closeGap(g, start.add(Duration(seconds: b)));
  }
  for (final (a, b) in interruptions) {
    final g = await w.session.markers.openGap(
      id,
      RunGapKind.interruption,
      start.add(Duration(seconds: a)),
    );
    await w.session.markers.closeGap(g, start.add(Duration(seconds: b)));
  }
  for (var i = 0; i < laps.length; i++) {
    await w.session.markers.addLap(
      id,
      StoredLap(
        index: i + 1,
        markedAt: start.add(Duration(seconds: laps[i])),
        lapTime: Duration(seconds: laps[i] - (i == 0 ? 0 : laps[i - 1])),
      ),
    );
  }
  final end = start.add(Duration(seconds: hr.length));
  await w.session.runs.setState(id, RunState.finished, endedAt: end);
  w.clock.set(end.add(const Duration(minutes: 1)));
}

/// Beendete Sporteinheit mit dem Puls [hr] (je Sekunde ab [start]).
Future<int> seedSport(
  RecalcWorld w,
  DateTime start,
  List<int?> hr, {
  OtherSport sport = OtherSport.rope,
  String source = 'strap',
  List<(int, int)> pauses = const [],
  List<int> laps = const [],
  List<(int, int)> interruptions = const [],
}) async {
  final run = await w.session.runs.create(
    startedAt: start,
    mode: RunMode.sport,
    sport: sport,
  );
  await _finish(
    w,
    run.id,
    start,
    hr,
    source,
    pauses,
    laps: laps,
    interruptions: interruptions,
  );
  return run.id;
}

/// Bandlauf mit konstanter Geschwindigkeit (alles Bewegungszeit) und
/// demselben Puls: der Vergleichslauf „gleiche Bewegungszeit“.
Future<int> seedBelt(RecalcWorld w, DateTime start, List<int?> hr) async {
  final run = await w.session.runs.create(
    startedAt: start,
    mode: RunMode.treadmill,
  );
  await _finish(
    w,
    run.id,
    start,
    hr,
    'strap',
    const [],
    belts: const [BeltSetting(offset: Duration.zero, speedMetersPerSecond: 3)],
  );
  return run.id;
}

Future<Map<String, ComputedValue>> values(RecalcWorld w, int id) async => {
  for (final p in await w.session.values.read(ValueOwner.run(id)))
    p.original.key: p.original,
};

Future<RunOverview> overview(RecalcWorld w, int id) async =>
    (await RunOverviewService(
      session: w.session,
      clock: w.clock,
    ).load()).singleWhere((o) => o.run.id == id);

void main() {
  group('Bewegungszeit (PAR-232)', () {
    test(
      '30 min mit 5 min Pause-Taste und Puls auf der Stelle: 25 min',
      () async {
        final w = await RecalcWorld.create();
        final id = await seedSport(
          w,
          _t0,
          _series([(1800, 150)]),
          pauses: [(600, 900)],
        );
        await w.calc().calculateAfterRun(id);
        final o = await overview(w, id);
        expect(o.movingTime, const Duration(minutes: 25));
        expect(o.totalTime, const Duration(minutes: 30));
        final v = await values(w, id);
        // 150 bpm = 79 % von 190: Gewicht 3, 25 min.
        expect(v[trimpRunValueKey]!.value, closeTo(75, 0.1));
      },
    );

    test(
      'ohne Pause-Taste 30 min; Pausen zwischen Runden zählen mit',
      () async {
        final w = await RecalcWorld.create();
        // Runden mit Erholung (Puls 120) dazwischen, ohne Pause-Taste.
        final id = await seedSport(
          w,
          _t0,
          _series([(300, 160), (300, 120), (300, 160), (300, 120), (600, 160)]),
          laps: [300, 600, 900, 1200],
        );
        await w.calc().calculateAfterRun(id);
        final o = await overview(w, id);
        expect(o.movingTime, const Duration(minutes: 30));
        expect(o.load.trimpStored, isTrue);
      },
    );

    test(
      'Ausfall nach Prozessende (FR-0193) fehlt wie die Pause-Taste',
      () async {
        final w = await RecalcWorld.create();
        // 30 min: Pause-Taste 10.–15. min (Puls läuft weiter), Unterbrechung
        // nach einem Prozessende 20.–25. min (keine Daten).
        final id = await seedSport(
          w,
          _t0,
          _series([(1200, 150), (300, null), (300, 150)]),
          pauses: [(600, 900)],
          interruptions: [(1200, 1500)],
        );
        await w.calc().calculateAfterRun(id);
        final o = await overview(w, id);
        expect(o.movingTime, const Duration(minutes: 20));
        expect(o.totalTime, const Duration(minutes: 30));
        final t = (await values(w, id))[trimpRunValueKey]!;
        // 150 bpm = 79 % von 190: Gewicht 3, 20 min; volle Pulsabdeckung.
        expect(t.value, closeTo(60, 0.1));
        expect(t.quality, isNot(ValueQuality.provisional));
        // Neuberechnung aus den Rohdaten liefert dieselbe Zeit.
        final fresh = await RecalcWorld.create();
        final id2 = await seedSport(
          fresh,
          _t0,
          _series([(1200, 150), (300, null), (300, 150)]),
          pauses: [(600, 900)],
          interruptions: [(1200, 1500)],
        );
        expect(
          (await overview(fresh, id2)).movingTime,
          const Duration(minutes: 20),
        );
      },
    );

    test('Neuberechnung der Kurzfassung liefert dieselbe Zeit', () async {
      final w = await RecalcWorld.create();
      final id = await seedSport(
        w,
        _t0,
        _series([(1800, 150)]),
        pauses: [(600, 900)],
      );
      // Ohne Berechnung nach dem Ende: die Historie rechnet aus den Rohdaten.
      final o = await overview(w, id);
      expect(o.movingTime, const Duration(minutes: 25));
      expect(o.distanceMeters, isNull);
    });
  });

  group('TRIMP wie beim Lauf (FR-0092, FR-0197)', () {
    test('Edwards: Testfall 10/30/10 min ergibt 110 wie beim Lauf', () async {
      final w = await RecalcWorld.create();
      // HFmax 190: 105 bpm = 55 % (Zone 1), 124 = 65 % (Zone 2), 162 = 85 %.
      final hr = _series([(600, 105), (1800, 124), (600, 162)]);
      for (final sport in OtherSport.values) {
        final id = await seedSport(
          w,
          _t0.add(Duration(days: sport.index)),
          hr,
          sport: sport,
        );
        await w.calc().calculateAfterRun(id);
        final t = (await values(w, id))[trimpRunValueKey]!;
        // Übergänge zwischen den Zonen glättet die Pulsaufbereitung wie beim Lauf.
        expect(t.value, closeTo(110, 1), reason: sport.wire);
        expect(t.method, EdwardsTrimp.methodId);
      }
      final belt = await seedBelt(w, _t0.add(const Duration(days: 10)), hr);
      await w.calc().calculateAfterRun(belt);
      final sport = await seedSport(w, _t0.add(const Duration(days: 11)), hr);
      await w.calc().calculateAfterRun(sport);
      expect(
        (await values(w, sport))[trimpRunValueKey]!.value,
        (await values(w, belt))[trimpRunValueKey]!.value,
      );
      expect(
        (await values(w, sport))[zoneTimeValueKey(2)]!.value,
        (await values(w, belt))[zoneTimeValueKey(2)]!.value,
      );
    });

    test(
      'Banister: Testfall 30 min HF 130 ergibt rund 32 wie beim Lauf',
      () async {
        final w = await RecalcWorld.create(
          profile: const ProfileRecord(
            maxHeartRateBpm: 200,
            restingHeartRateBpm: 40,
          ),
        );
        await LoadSettings.writeCoefficients(
          w.session.settings,
          LoadCoefficients.male,
          at: w.clock.now(),
        );
        await LoadSettings.writeActiveProfile(
          w.session.settings,
          LoadProfile.banister,
          at: w.clock.now(),
        );
        final hr = _series([(1800, 130)]);
        final sport = await seedSport(w, _t0, hr, sport: OtherSport.cycling);
        await w.calc().calculateAfterRun(sport);
        final belt = await seedBelt(w, _t0.add(const Duration(days: 1)), hr);
        await w.calc().calculateAfterRun(belt);
        final ts = (await values(w, sport))[trimpRunValueKey]!;
        expect(ts.method, BanisterTrimp.methodIdMale);
        expect(ts.value, closeTo(32, 0.5));
        expect(ts.value, (await values(w, belt))[trimpRunValueKey]!.value);
      },
    );

    test(
      'Pulslücke (PAR-010) wie beim Lauf: gleicher Wert, vorläufig',
      () async {
        final w = await RecalcWorld.create();
        // 30 min, 4 min ohne Puls in der Mitte: 87 % Abdeckung.
        final hr = _series([(900, 150), (240, null), (660, 150)]);
        final sport = await seedSport(w, _t0, hr);
        await w.calc().calculateAfterRun(sport);
        final belt = await seedBelt(w, _t0.add(const Duration(days: 1)), hr);
        await w.calc().calculateAfterRun(belt);
        final ts = (await values(w, sport))[trimpRunValueKey]!;
        final tb = (await values(w, belt))[trimpRunValueKey]!;
        expect(ts.value, isNotNull);
        expect(ts.value, tb.value);
        expect(ts.quality, ValueQuality.provisional);
        expect(ts.quality, tb.quality);
      },
    );

    test('unter 80 % Pulsabdeckung: TRIMP nicht verfügbar mit Grund', () async {
      final w = await RecalcWorld.create();
      final id = await seedSport(w, _t0, _series([(1200, 150), (600, null)]));
      await w.calc().calculateAfterRun(id);
      final t = (await values(w, id))[trimpRunValueKey]!;
      expect(t.value, isNull);
      expect(t.unavailableReason, UnavailableReason.insufficientCoverage);
    });
  });

  group('keine Laufwerte (FR-0221, DEC-0056)', () {
    // Eine Sporteinheit hat nie Positionen aus der Aufzeichnung; ein Archiv
    // oder eine Fremdquelle könnte welche mitbringen. Auch dann gibt es keine
    // Strecke und keine Pace.
    Future<int> sportWithPositions(RecalcWorld w, {double speed = 3}) async {
      final id = await seedSport(w, _t0, _series([(1800, 150)]));
      await w.session.rawData.append(
        id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 1800; s += 5)
              RawPosition(
                time: _t0.add(Duration(seconds: s)),
                source: 'gps',
                latitude: 10 + s * speed / 111195,
                longitude: 20,
                accuracyMeters: 5,
              ),
          ],
        ),
      );
      return id;
    }

    test('mit Positionen: keine Strecke nach der Berechnung', () async {
      final w = await RecalcWorld.create();
      final id = await sportWithPositions(w);
      await w.calc().calculateAfterRun(id);
      final o = await overview(w, id);
      expect(o.distanceMeters, isNull);
      expect(o.averagePaceSecondsPerKm, isNull);
      expect(o.bestPaceSecondsPerKm, isNull);
      expect(o.movingTime, const Duration(minutes: 30));
    });

    test('Positionen auf der Stelle: keine Stillstandserkennung', () async {
      final w = await RecalcWorld.create();
      final id = await sportWithPositions(w, speed: 0);
      // Historie aus den Rohdaten und Berechnung nach dem Ende.
      expect((await overview(w, id)).movingTime, const Duration(minutes: 30));
      await w.calc().calculateAfterRun(id);
      expect((await overview(w, id)).movingTime, const Duration(minutes: 30));
      // 150 bpm = 79 % von 190: Gewicht 3, 30 min.
      expect((await values(w, id))[trimpRunValueKey]!.value, closeTo(90, 0.1));
    });

    test(
      'mit Positionen: keine Strecke in der Historie, keine Prognose',
      () async {
        final w = await RecalcWorld.create();
        final id = await sportWithPositions(w);
        final runs = await PredictionRunReader(
          session: w.session,
          clock: w.clock,
        ).load();
        expect(runs, isEmpty);
        final o = await overview(w, id);
        expect(o.distanceMeters, isNull);
        expect(o.averagePaceSecondsPerKm, isNull);
        expect(o.bestPaceSecondsPerKm, isNull);
        expect(o.movingTime, const Duration(minutes: 30));
      },
    );

    test(
      'keine Strecke, Pace, VO2max; nicht in Prognose und Effizienz',
      () async {
        final w = await RecalcWorld.create();
        final gps = await w.seedRun(DateTime.utc(2030, 2, 20, 8));
        await w.calc().calculateAfterRun(gps);
        final id = await seedSport(
          w,
          _t0,
          _series([(1800, 150)]),
          source: 'sportstrap',
        );
        await w.calc().calculateAfterRun(id);
        final o = await overview(w, id);
        expect(o.distanceMeters, isNull);
        expect(o.averagePaceSecondsPerKm, isNull);
        expect(o.bestPaceSecondsPerKm, isNull);
        final vo2 = await runVo2(w.session, id);
        expect(vo2.original.value, isNull);
        expect(vo2.original.sections, isEmpty);
        final runs = await PredictionRunReader(
          session: w.session,
          clock: w.clock,
        ).load();
        expect([for (final r in runs) r.id], ['$gps']);
        for (final p in await w.allPairs()) {
          if (p.original.key == aerobicEfficiencyValueKey) {
            expect(p.current.sources, isNot(contains('sportstrap')));
          }
        }
      },
    );
  });
}
