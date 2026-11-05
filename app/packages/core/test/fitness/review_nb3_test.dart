import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const p = FitnessParameters.v3();
const zones = ReserveZones(reserve: HeartRateReserve());
const trimp = EdwardsTrimp();

/// Reserve-Fake: liefert für jeden Puls festes `r`.
class _FakeReserve extends HeartRateReserveModel {
  const _FakeReserve(this.r);
  final double r;
  @override
  String get method => 'fake-reserve';
  @override
  int get methodVersion => 7;
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
    value: r,
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
}

class _FakeZones extends ReserveZoneModel {
  const _FakeZones();
  @override
  String get method => 'fake-zones';
  @override
  int get methodVersion => 2;
  @override
  AlgorithmCategory get category => AlgorithmCategory.calibrated;
  @override
  FitnessResult<ReserveZonePlacement> zoneFor(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  ) => FitnessAvailable(
    value: const BelowReserveZone1(
      aboveHint: false,
      reserveMethod: 'fake-reserve',
      reserveMethodVersion: 7,
    ),
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
  @override
  FitnessResult<ReserveZoneTimes> timeInZones({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) => FitnessUnavailable(
    reason: UnavailableReason.insufficientData,
    method: method,
    methodVersion: methodVersion,
    parameterVersion: p.parameterVersion,
  );
}

HeartRateResult hr() => fitHeartRate(fitDense(0, 59, 150));
MovementResult mv() => fitMovement([fitSpan(0, 60)]);

UnavailableReason? reasonOf(FitnessResult<Object?> r) =>
    r is FitnessUnavailable ? r.reason : null;

void main() {
  test('Befund 3: v3() nimmt currentParameterVersion, kein Literal', () {
    final src = File('lib/src/preprocessing/preprocessing_parameters.dart')
        .readAsStringSync();
    final lines = src.split('\n');
    final at = lines.indexWhere((l) => l.contains('.v3()'));
    final line = '${lines[at]} ${lines[at + 1]}';
    expect(line, contains('currentParameterVersion'));
    expect(line, isNot(matches(RegExp(r'parameterVersion:\s*\d'))));
    expect(
      const PreprocessingParameters.v3().parameterVersion,
      currentParameterVersion,
    );
  });

  group('Befund 4: zoneFor', () {
    const basis = HeartRateBasis(
      maxBpm: 190,
      restingBpm: 60,
      maxIsEstimated: true,
    );

    test('nennt Variante und Parameterversion, Zone und Hinweis', () {
      final res = zones.zoneFor(basis, 151, p);
      expect(res.method, 'reserve-zones');
      expect(res.methodVersion, 1);
      expect(res.parameterVersion, p.parameterVersion);
      expect(res.maxIsEstimated, isTrue);
      final v = (res as FitnessAvailable<ReserveZonePlacement>).value;
      expect((v as InReserveZone).zone, 3);
    });

    test('unter Zone 1 ist ein eigener Fall, kein null', () {
      final v = (zones.zoneFor(
        basis,
        100,
        p,
      ) as FitnessAvailable<ReserveZonePlacement>).value;
      expect(v, isA<BelowReserveZone1>());
    });

    test('fehlende Basis: nicht verfügbar mit Kennung', () {
      final res = zones.zoneFor(const HeartRateBasis(), 150, p);
      expect(reasonOf(res), UnavailableReason.missingMaxHeartRate);
      expect(res.method, 'reserve-zones');
      expect(res.maxIsEstimated, isFalse);
      final est = zones.zoneFor(
        const HeartRateBasis(maxBpm: 190, maxIsEstimated: true),
        150,
        p,
      );
      expect(reasonOf(est), UnavailableReason.missingRestingHeartRate);
      expect(est.maxIsEstimated, isTrue);
    });
  });

  group('Befund 5: Fake je Familie über die Registry', () {
    test('Reserve-Fake ersetzt die Reserve in den Zonen', () {
      final reg = AlgorithmRegistry.standard()
        ..register(heartRateReserveFamily, const _FakeReserve(0.75))
        ..setActive(heartRateReserveFamily, 'fake-reserve', 7);
      final active = reg.active(heartRateReserveFamily);
      expect(active.method, 'fake-reserve');
      final z = ReserveZones(reserve: active);
      // r = 0,75 -> Zone 3, egal welche Basis oder welcher Puls.
      final placed = (z.zoneFor(
        const HeartRateBasis(maxBpm: 190, restingBpm: 60),
        70,
        p,
      ) as FitnessAvailable<ReserveZonePlacement>).value;
      expect((placed as InReserveZone).zone, 3);
      final times = (z.timeInZones(
        basis: const HeartRateBasis(),
        heartRate: hr(),
        movement: mv(),
        p: p,
      ) as FitnessAvailable<ReserveZoneTimes>).value;
      expect(times.zoneMicros[2], times.coveredMicros);
    });

    test('Zonen-Fake wird über die Registry aktiv', () {
      final reg = AlgorithmRegistry.standard()
        ..register(reserveZonesFamily, const _FakeZones())
        ..setActive(reserveZonesFamily, 'fake-zones', 2);
      final z = reg.active(reserveZonesFamily);
      expect(z.method, 'fake-zones');
      expect(z.zoneFor(const HeartRateBasis(), 1, p).method, 'fake-zones');
      expect(
        reasonOf(
          z.timeInZones(
            basis: const HeartRateBasis(),
            heartRate: hr(),
            movement: mv(),
            p: p,
          ),
        ),
        UnavailableReason.insufficientData,
      );
      expect(reg.variants(reserveZonesFamily), hasLength(2));
    });
  });

  group('Befund 6: HFmax oder Ruhepuls <= 0 gilt als fehlend', () {
    for (final bad in [0, -1]) {
      test('Wert $bad', () {
        final badMax = HeartRateBasis(maxBpm: bad, restingBpm: 50);
        final badRest = HeartRateBasis(maxBpm: 190, restingBpm: bad);
        const reserve = HeartRateReserve();
        expect(
          reasonOf(reserve.relativeLoad(badMax, 150, p)),
          UnavailableReason.missingMaxHeartRate,
        );
        expect(
          reasonOf(reserve.relativeLoad(badRest, 150, p)),
          UnavailableReason.missingRestingHeartRate,
        );
        expect(
          reasonOf(zones.zoneFor(badMax, 150, p)),
          UnavailableReason.missingMaxHeartRate,
        );
        expect(
          reasonOf(zones.zoneFor(badRest, 150, p)),
          UnavailableReason.missingRestingHeartRate,
        );
        expect(
          reasonOf(
            zones.timeInZones(
              basis: badMax,
              heartRate: hr(),
              movement: mv(),
              p: p,
            ),
          ),
          UnavailableReason.missingMaxHeartRate,
        );
        expect(
          reasonOf(
            zones.timeInZones(
              basis: badRest,
              heartRate: hr(),
              movement: mv(),
              p: p,
            ),
          ),
          UnavailableReason.missingRestingHeartRate,
        );
        expect(
          reasonOf(
            trimp.compute(basis: badMax, heartRate: hr(), movement: mv(), p: p),
          ),
          UnavailableReason.missingMaxHeartRate,
        );
      });
    }

    test('TRIMP braucht den Ruhepuls nicht: 0 oder -1 stört nicht', () {
      for (final bad in [0, -1]) {
        final res = trimp.compute(
          basis: HeartRateBasis(maxBpm: 190, restingBpm: bad),
          heartRate: hr(),
          movement: mv(),
          p: p,
        );
        expect(res, isA<FitnessAvailable<TrimpResult>>());
      }
    });
  });

  group('Befund 7: maxIsEstimated überall', () {
    const est = HeartRateBasis(
      maxBpm: 190,
      restingBpm: 60,
      maxIsEstimated: true,
    );
    const exact = HeartRateBasis(maxBpm: 190, restingBpm: 60);

    test('Zonenzeiten verfügbar', () {
      for (final (b, want) in [(est, true), (exact, false)]) {
        final res = zones.timeInZones(
          basis: b,
          heartRate: hr(),
          movement: mv(),
          p: p,
        );
        expect(res, isA<FitnessAvailable<ReserveZoneTimes>>());
        expect(res.maxIsEstimated, want);
      }
    });

    test(
      'Zonenzeiten nicht verfügbar: keine Bewegungszeit, kein Puls, Basis',
      () {
        final noMoving = zones.timeInZones(
          basis: est,
          heartRate: hr(),
          movement: fitMovement([]),
          p: p,
        );
        expect(reasonOf(noMoving), UnavailableReason.noMovingTime);
        expect(noMoving.maxIsEstimated, isTrue);
        final noHr = zones.timeInZones(
          basis: est,
          heartRate: fitHeartRate([]),
          movement: mv(),
          p: p,
        );
        expect(reasonOf(noHr), UnavailableReason.noHeartRate);
        expect(noHr.maxIsEstimated, isTrue);
        const badEst = HeartRateBasis(
          maxBpm: 60,
          restingBpm: 60,
          maxIsEstimated: true,
        );
        final badBasis = zones.timeInZones(
          basis: badEst,
          heartRate: hr(),
          movement: mv(),
          p: p,
        );
        expect(reasonOf(badBasis), UnavailableReason.maxNotAboveResting);
        expect(badBasis.maxIsEstimated, isTrue);
      },
    );

    test('Reserve verfügbar und nicht verfügbar', () {
      const reserve = HeartRateReserve();
      expect(reserve.relativeLoad(est, 150, p).maxIsEstimated, isTrue);
      expect(reserve.relativeLoad(exact, 150, p).maxIsEstimated, isFalse);
      const missing = HeartRateBasis(maxBpm: 190, maxIsEstimated: true);
      final res = reserve.relativeLoad(missing, 150, p);
      expect(reasonOf(res), UnavailableReason.missingRestingHeartRate);
      expect(res.maxIsEstimated, isTrue);
    });

    test('zoneFor gibt die Schätzung weiter', () {
      expect(zones.zoneFor(est, 150, p).maxIsEstimated, isTrue);
      expect(zones.zoneFor(exact, 150, p).maxIsEstimated, isFalse);
    });
  });

  group('Befund 10: Kategorien-Tabelle gegen die Registry', () {
    final rows = <String, (int, String, String)>{};
    final doc = File('../../../docs/architecture/algorithm-categories.md')
        .readAsLinesSync();
    for (final l in doc) {
      final m = RegExp(
        r'^\| [^|]+ \| `([a-z0-9-]+)` v(\d+) \| ([ABC]) \|.*\| (WP\d+) \|$',
      ).firstMatch(l);
      if (m != null) rows[m[1]!] = (int.parse(m[2]!), m[3]!, m[4]!);
    }
    String letter(AlgorithmCategory c) => switch (c) {
      AlgorithmCategory.established => 'A',
      AlgorithmCategory.heuristic => 'B',
      AlgorithmCategory.calibrated => 'C',
    };

    test('Tabelle ist lesbar', () {
      expect(rows.length, greaterThanOrEqualTo(11));
    });

    test('jede registrierte Variante steht mit Version und Kategorie drin', () {
      final reg = AlgorithmRegistry.standard();
      expect(reg.allVariants, isNotEmpty);
      for (final v in reg.allVariants) {
        final row = rows[v.method];
        expect(row, isNotNull, reason: '${v.method} fehlt in der Tabelle');
        expect(row!.$1, v.methodVersion, reason: v.method);
        expect(row.$2, letter(v.category), reason: v.method);
      }
    });

    test('jede Zeile von WP04 ist registriert', () {
      final registered = {
        for (final v in AlgorithmRegistry.standard().allVariants) v.method,
      };
      for (final e in rows.entries.where((e) => e.value.$3 == 'WP04')) {
        expect(registered, contains(e.key));
      }
    });
  });

  group('Befund 11: TRIMP-Grenzen und Gewichte', () {
    FitnessParameters with_({List<double>? bounds, List<int>? weights}) =>
        FitnessParameters(
          parameterVersion: p.parameterVersion,
          trimpZoneLowerBounds: bounds ?? p.trimpZoneLowerBounds,
          trimpWeights: weights ?? p.trimpWeights,
        );

    test('ungültige Angaben werfen ArgumentError, kein RangeError', () {
      for (final bad in [
        with_(weights: [1, 2, 3, 4]), // zu kurz
        with_(weights: [1, 2, 3, 4, 5, 6]), // zu lang
        with_(bounds: [0.5, 0.7, 0.6, 0.8, 0.9]), // absteigend
        with_(bounds: [0.5, 0.6, 0.6, 0.8, 0.9]), // gleich
        with_(bounds: [-0.1, 0.6, 0.7, 0.8, 0.9]), // negativ
        with_(bounds: [0.5, 0.6, 0.7, 0.8, double.nan]),
        with_(bounds: [0.5, 0.6, 0.7, 0.8, double.infinity]),
        with_(bounds: [], weights: []),
      ]) {
        expect(
          () => trimp.compute(
            basis: const HeartRateBasis(maxBpm: 190),
            heartRate: hr(),
            movement: mv(),
            p: bad,
          ),
          throwsArgumentError,
        );
      }
    });

    test('eigene gültige Werte gelten', () {
      final ok = with_(bounds: [0.4, 0.8], weights: [1, 3]);
      expect(
        trimp.compute(
          basis: const HeartRateBasis(maxBpm: 190),
          heartRate: hr(),
          movement: mv(),
          p: ok,
        ),
        isA<FitnessAvailable<TrimpResult>>(),
      );
    });
  });
}
