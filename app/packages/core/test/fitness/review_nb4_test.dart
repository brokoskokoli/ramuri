import 'package:core/core.dart';
import 'package:core/src/preprocessing/heart_rate_beat.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const p = FitnessParameters.v4();
const zones = ReserveZones(reserve: HeartRateReserve());
const trimp = EdwardsTrimp();
const basis = HeartRateBasis(maxBpm: 200, restingBpm: 50);

class _UnavailableReserve extends HeartRateReserveModel {
  const _UnavailableReserve();
  @override
  String get method => 'unavailable-reserve';
  @override
  int get methodVersion => 2;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
  @override
  UnavailableReason? check(HeartRateBasis basis, FitnessParameters p) => null;
  @override
  FitnessResult<double> relativeLoad(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  ) => FitnessUnavailable(
    reason: UnavailableReason.missingRestingHeartRate,
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
}

class _Fixed extends HeartRateReserveModel {
  const _Fixed();
  @override
  String get method => 'fixed-reserve';
  @override
  int get methodVersion => 9;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
  @override
  UnavailableReason? check(HeartRateBasis basis, FitnessParameters p) => null;
  @override
  FitnessResult<double> relativeLoad(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  ) => FitnessAvailable(
    value: 0.7,
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
}

MovementResult moving(int a, int b) => fitMovement([fitSpan(a, b)]);

void main() {
  group('Befund 2 (Review 2): überlebende Mutanten', () {
    test('M1: nicht monotone Werte senken den Takt nicht', () {
      final hr = HeartRateResult(
        parameterVersion: currentParameterVersion,
        processed: [
          for (var s = 0; s <= 100; s += 5)
            ProcessedHeartRate(
              input: fitHr(s, 150),
              state: MeasurementState.present,
            ),
          // Zeitstempel mitten im 5-s-Raster, verworfen als nicht monoton.
          for (var s = 2; s <= 100; s += 5)
            ProcessedHeartRate(
              input: fitHr(s, 150),
              state: MeasurementState.discarded,
              reason: DiscardReason.nonMonotonicTime,
            ),
        ],
        acceptedValues: [for (var s = 0; s <= 100; s += 5) fitHr(s, 150)],
        gaps: const [],
        averageBpm: null,
        maxBpm: null,
        medianBpm: null,
        medianSeries: const [],
      );
      expect(
        medianBeatMicros(receivedHeartRateTimes(hr)),
        const Duration(seconds: 5).inMicroseconds,
      );
    });

    test('M3: gerade Anzahl Abstände nimmt den unteren Median', () {
      final times = [
        for (final s in [0, 1, 3, 6, 10]) fitAt(s),
      ];
      // Abstände 1, 2, 3, 4 s: unterer Median 2 s (ein vorkommender Abstand).
      expect(medianBeatMicros(times), 2000000);
    });

    test('M4: Rückgriff endet am Spannenende, nicht am nächsten Wert', () {
      // Bewegung 10 bis 11 s, Werte ab 11,4 s (Takt 1 s): Rückgriff höchstens
      // bis zum Spannenende, Abdeckung <= Spanne.
      final x = fitHeartRate([
        for (var s = 0; s <= 9; s++)
          RawHeartRate(
            time: fitT0.add(Duration(milliseconds: 11400 + s * 1000)),
            source: 'x',
            bpm: 150,
          ),
      ]);
      final t = heartRateTimeByBpm(
        heartRate: x,
        movement: moving(10, 11),
        p: p,
      );
      expect(t.movingMicros, 1000000);
      expect(t.coveredMicros, lessThanOrEqualTo(t.movingMicros));
      expect(t.coveredMicros, 1000000);
    });
  });

  group('Befund 2 (Review 3): Takt ist ein vorkommender Abstand', () {
    // Jeder 3. Wert fehlt im 1-Hz-Raster: Abstände 1 s und 2 s im Wechsel.
    HeartRateResult gapped(int lastSecond) => fitHeartRate([
      for (var s = 0; s <= lastSecond; s++)
        if (s % 3 != 2) fitHr(s, 150),
    ]);

    double coverage(int lastSecond) {
      final t = heartRateTimeByBpm(
        heartRate: gapped(lastSecond),
        movement: moving(0, lastSecond),
        p: p,
      );
      return t.coveredMicros / t.movingMicros;
    }

    FitnessResult<TrimpResult> load(int lastSecond) => trimp.compute(
      basis: basis,
      heartRate: gapped(lastSecond),
      movement: moving(0, lastSecond),
      p: p,
    );

    test(
      'je 3. Wert fehlt, 30 s (gerade Abstandszahl): Takt 1 s, 2/3 Abdeckung, '
      'TRIMP nicht bewertet',
      () {
        expect(
          medianBeatMicros(receivedHeartRateTimes(gapped(30))),
          const Duration(seconds: 1).inMicroseconds,
        );
        // Je 3 s fehlt 1 s (Lücke 2 s minus Takt 1 s): 20 von 30 s.
        expect(coverage(30), closeTo(20 / 30, 1e-9));
        // 2/3 liegt unter der Mindestabdeckung von 80 Prozent.
        final r = load(30);
        expect(r, isA<FitnessUnavailable<TrimpResult>>());
        expect(
          (r as FitnessUnavailable).reason,
          UnavailableReason.insufficientCoverage,
        );
      },
    );

    test('je 3. Wert fehlt, 31 s (ungerade Abstandszahl): gleiche Wertung, '
        '21/31 Abdeckung, TRIMP nicht bewertet', () {
      // 10 Lücken zu je 1 s fehlend in 31 s.
      expect(coverage(31), closeTo(21 / 31, 1e-9));
      final r = load(31);
      expect(r, isA<FitnessUnavailable<TrimpResult>>());
      expect(
        (r as FitnessUnavailable).reason,
        UnavailableReason.insufficientCoverage,
      );
    });
  });

  group('Befund 1: gemeinsame Regel round(Δt / Takt) <= 1', () {
    test('beatCoversGap: 1,49 Takte gelten, 1,5 nicht', () {
      expect(beatCoversGap(1490000, 1000000), isTrue);
      expect(beatCoversGap(1500000, 1000000), isFalse);
      expect(beatCoversGap(1000000, 1000000), isTrue);
      expect(beatCoversGap(100, 0), isFalse);
      expect(missingMicrosInGap(1490000, 1000000), 0);
      expect(missingMicrosInGap(2000000, 1000000), 1000000);
    });

    test('Wert hält bis zum nächsten bei 1,4 Takten', () {
      // Takt 1 s (Median), ein Abstand 1,4 s, Bewegung 0 bis 30 s.
      final times = [
        for (var s = 0; s <= 10; s++) s * 1000,
        11400,
        for (var s = 12; s <= 30; s++) s * 1000 + 400,
      ];
      final hr = fitHeartRate([
        for (final ms in times)
          RawHeartRate(
            time: fitT0.add(Duration(milliseconds: ms)),
            source: 'x',
            bpm: 150,
          ),
      ]);
      final t = heartRateTimeByBpm(
        heartRate: hr,
        movement: moving(0, 30),
        p: p,
      );
      expect(t.coveredMicros, t.movingMicros);
    });

    test('letzter Wert hält bis zum Spannenende bei 1,4 Takten', () {
      final hr = fitHeartRate(fitDense(0, 28, 150));
      final t = heartRateTimeByBpm(
        heartRate: hr,
        movement: moving(0, 29),
        p: p,
      );
      expect(t.coveredMicros, t.movingMicros);
      // Spanne 29,4 s: letzter Wert bei 28 s, 1,4 Takte bis zum Ende.
      final t2 = heartRateTimeByBpm(
        heartRate: hr,
        movement: fitMovement([
          TimeSpan(
            start: fitAt(0),
            end: fitT0.add(const Duration(milliseconds: 29400)),
          ),
        ]),
        p: p,
      );
      expect(t2.movingMicros, 29400000);
      expect(t2.coveredMicros, 29400000);
    });

    test('Spannenende 2 Takte hinter dem letzten Wert: ein Takt fehlt', () {
      final hr = fitHeartRate(fitDense(0, 28, 150));
      final t = heartRateTimeByBpm(
        heartRate: hr,
        movement: moving(0, 30),
        p: p,
      );
      expect(t.movingMicros - t.coveredMicros, 1000000);
    });

    test('Spannenanfang: erster Wert nach 1,4 Takten zählt rückwirkend', () {
      final hr = fitHeartRate([
        for (var s = 0; s <= 29; s++)
          RawHeartRate(
            time: fitT0.add(Duration(milliseconds: s * 1000 + 1400)),
            source: 'x',
            bpm: 150,
          ),
      ]);
      final t = heartRateTimeByBpm(
        heartRate: hr,
        movement: moving(0, 30),
        p: p,
      );
      expect(t.coveredMicros, t.movingMicros);
    });
  });

  group('Befund 3: Grund bei langsamem Takt', () {
    test('stabiler 15-s-Takt, alles Lücken: insufficientCoverage', () {
      // Stabiler Takt ohne Lücken wäre abgedeckt; bei 15 s Takt meldet der
      // Prozessor jeden Abstand als Lücke (> PAR-010), nichts ist abgedeckt.
      final hr = fitHeartRate(
        fitDense(0, 300, 150, step: 15),
        gaps: [for (var s = 0; s < 300; s += 15) fitGap(s, s + 15)],
      );
      final m = moving(0, 300);
      final r = trimp.compute(basis: basis, heartRate: hr, movement: m, p: p);
      expect(
        (r as FitnessUnavailable).reason,
        UnavailableReason.insufficientCoverage,
      );
      final z = zones.timeInZones(
        basis: basis,
        heartRate: hr,
        movement: m,
        p: p,
      );
      expect(
        (z as FitnessUnavailable).reason,
        UnavailableReason.insufficientCoverage,
      );
    });

    test('ohne akzeptierte Werte bleibt es noHeartRate', () {
      final hr = fitHeartRate(const []);
      final r = trimp.compute(
        basis: basis,
        heartRate: hr,
        movement: moving(0, 200),
        p: p,
      );
      expect((r as FitnessUnavailable).reason, UnavailableReason.noHeartRate);
    });
  });

  group('Befund 4: Puls <= 0', () {
    for (final bpm in [0, -5]) {
      test('bpm $bpm: nicht verfügbar statt Wert', () {
        final z = zones.zoneFor(basis, bpm, p);
        expect((z as FitnessUnavailable).reason, UnavailableReason.noHeartRate);
        final r = const HeartRateReserve().relativeLoad(basis, bpm, p);
        expect((r as FitnessUnavailable).reason, UnavailableReason.noHeartRate);
      });
    }
  });

  test('Befund 4: zoneFor prüft den Puls selbst, auch bei fremder Reserve', () {
    const z = ReserveZones(reserve: _Fixed());
    for (final bpm in [0, -1]) {
      expect(
        (z.zoneFor(basis, bpm, p) as FitnessUnavailable).reason,
        UnavailableReason.noHeartRate,
      );
    }
    expect(z.zoneFor(basis, 1, p), isA<FitnessAvailable>());
  });

  group('Befund 5: Reserve im Ergebnis', () {
    test('Zonenzeit und Platzierung nennen die Reserve', () {
      const z = ReserveZones(reserve: _Fixed());
      final placed = (z.zoneFor(
        basis,
        150,
        p,
      ) as FitnessAvailable<ReserveZonePlacement>).value;
      expect(
        [placed.reserveMethod, placed.reserveMethodVersion],
        ['fixed-reserve', 9],
      );
      final times = (z.timeInZones(
        basis: basis,
        heartRate: fitHeartRate(fitDense(0, 60, 150)),
        movement: moving(0, 60),
        p: p,
      ) as FitnessAvailable<ReserveZoneTimes>).value;
      expect(
        [times.reserveMethod, times.reserveMethodVersion],
        ['fixed-reserve', 9],
      );
    });

    test('Reserve ohne Wert bei check == null: nicht verfügbar, kein Wurf', () {
      const z = ReserveZones(reserve: _UnavailableReserve());
      final r = z.timeInZones(
        basis: basis,
        heartRate: fitHeartRate(fitDense(0, 60, 150)),
        movement: moving(0, 60),
        p: p,
      );
      expect(
        (r as FitnessUnavailable).reason,
        UnavailableReason.missingRestingHeartRate,
      );
    });
  });

  group('Median-Takt', () {
    test('bekannte Grenze: überwiegen Abstände von zwei Takten, gilt der '
        'längere Abstand als Takt, der Ausfall bleibt unerkannt', () {
      // Vier Abstände zu 2 s, einer zu 1 s: Takt 2 s, obwohl das Gerät
      // eigentlich jede Sekunde sendet und jeder zweite Wert fehlt.
      final times = [
        for (final s in [0, 2, 4, 6, 8, 9]) fitAt(s),
      ];
      expect(medianBeatMicros(times), 2000000);
      expect(beatCoversGap(2000000, 2000000), isTrue);
      expect(missingMicrosInGap(2000000, 2000000), 0);
    });
  });
}
