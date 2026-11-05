import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const p = FitnessParameters.v3();
const zones = ReserveZones(reserve: HeartRateReserve());

/// Plausible Basis mit Spanne 10000, damit `r` in Schritten von 1e-4
/// einstellbar ist: `r = (bpm - 100) / 10000`.
const scaled = HeartRateBasis(maxBpm: 10100, restingBpm: 100);

ReserveZonePlacement placeR(double r, [FitnessParameters params = p]) {
  final res = zones.zoneFor(scaled, 100 + (r * 10000).round(), params);
  return (res as FitnessAvailable<ReserveZonePlacement>).value;
}

/// Zonennummer, `null` bei unter Zone 1.
int? zoneNo(ReserveZonePlacement x) => x is InReserveZone ? x.zone : null;

int? zoneOf(double r) => zoneNo(placeR(r));

void main() {
  test(
    'FR-0062: r 0,65 liegt in Zone 2, 0,60 in Zone 2 (Untergrenze inklusiv)',
    () {
      expect(zoneOf(0.65), 2);
      expect(zoneOf(0.6), 2);
      expect(zoneOf(0.5), 1);
      expect(zoneOf(0.7), 3);
      expect(zoneOf(0.8), 4);
      expect(zoneOf(0.9), 5);
    },
  );

  test('FR-0063: unter 50 % gesondert, nicht Zone 1', () {
    expect(placeR(0.4999), isA<BelowReserveZone1>());
    expect(placeR(0), isA<BelowReserveZone1>());
    expect(placeR(-0.3), isA<BelowReserveZone1>());
    expect(placeR(0.5), isA<InReserveZone>());
  });

  test(
    'genau 100 % liegt in Zone 5 ohne Hinweis, knapp darüber mit Hinweis',
    () {
      final at = placeR(1.0);
      expect(zoneNo(at), 5);
      expect(at.aboveHint, isFalse);
      final above = placeR(1.0001);
      expect(zoneNo(above), 5);
      expect(above.aboveHint, isTrue);
      expect(zoneNo(placeR(1.4)), 5);
      expect(placeR(0.99).aboveHint, isFalse);
    },
  );

  test('Grenzwert-Raster: jeder exakt treffbare Grenzwert, HFmax 100..230', () {
    var checked = 0;
    for (var max = 100; max <= 230; max++) {
      for (var rest = 30; rest <= max - 50; rest += 3) {
        final span = max - rest;
        for (var k = 5; k <= 10; k++) {
          if (span * k % 10 != 0) continue;
          final hf = rest + span * k ~/ 10;
          final basis = HeartRateBasis(maxBpm: max, restingBpm: rest);
          final at = (zones.zoneFor(
            basis,
            hf,
            p,
          ) as FitnessAvailable<ReserveZonePlacement>).value;
          final expectedZone = k >= 10 ? 5 : k - 4;
          expect(zoneNo(at), expectedZone, reason: '$max/$rest/$hf k=$k');
          expect(at.aboveHint, isFalse, reason: '$max/$rest/$hf');
          final below = (zones.zoneFor(
            basis,
            hf - 1,
            p,
          ) as FitnessAvailable<ReserveZonePlacement>).value;
          if (k < 10) expect(zoneNo(below), k == 5 ? isNull : k - 5);
          final over = (zones.zoneFor(
            basis,
            hf + 1,
            p,
          ) as FitnessAvailable<ReserveZonePlacement>).value;
          if (k == 10) expect(over.aboveHint, isTrue);
          checked++;
        }
      }
    }
    expect(checked, greaterThan(1000));
  });

  group('ungültige Grenzen', () {
    FitnessParameters withBounds(List<double> b) => FitnessParameters(
      parameterVersion: p.parameterVersion,
      reserveZoneBounds: b,
    );

    test('werfen ArgumentError', () {
      for (final b in [
        [0.5, 0.6, 0.7, 0.8, 0.9], // zu wenige
        [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1], // zu viele
        [0.5, 0.6, 0.6, 0.8, 0.9, 1.0], // gleiche Grenze
        [0.5, 0.7, 0.6, 0.8, 0.9, 1.0], // absteigend
        [-0.1, 0.6, 0.7, 0.8, 0.9, 1.0], // negativ
        [0.5, 0.6, 0.7, 0.8, 0.9, double.nan],
        [0.5, 0.6, 0.7, 0.8, 0.9, double.infinity],
      ]) {
        expect(
          () => zones.zoneFor(scaled, 7100, withBounds(b)),
          throwsArgumentError,
          reason: '$b',
        );
      }
    });

    test('eigene gültige Grenzen gelten', () {
      final custom = withBounds([0.4, 0.5, 0.6, 0.7, 0.8, 0.9]);
      expect(zoneNo(placeR(0.45, custom)), 1);
      expect(placeR(0.39, custom), isA<BelowReserveZone1>());
      // Hinweis hängt an 100 %, nicht an der obersten Grenze.
      final top = placeR(0.95, custom);
      expect(zoneNo(top), 5);
      expect(top.aboveHint, isFalse);
    });
  });

  group('Zeit je Zone', () {
    final t0 = DateTime.utc(2026, 1, 1, 10);
    DateTime at(int s) => t0.add(Duration(seconds: s));
    TimeSpan span(int a, int b) => TimeSpan(start: at(a), end: at(b));
    HeartRateGap gap(int a, int b) =>
        HeartRateGap(start: at(a), end: at(b), open: false);
    const basis = HeartRateBasis(maxBpm: 190, restingBpm: 60);
    // HFR 130: 125 bpm = 0,5; 138 = 0,6; 151 = 0,7; 190 = 1,0.
    ReserveZoneTimes run({
      required List<TimeSpan> moving,
      required List<RawHeartRate> hrs,
      List<HeartRateGap> gaps = const [],
    }) => (zones.timeInZones(
      basis: basis,
      heartRate: fitHeartRate(hrs, gaps: gaps),
      movement: fitMovement(moving),
      p: p,
    ) as FitnessAvailable<ReserveZoneTimes>).value;
    const sec = 1000000;

    test('Zeit unter Zone 1 getrennt, Zonen in Mikrosekunden', () {
      final v = run(
        moving: [span(0, 30)],
        hrs: [
          ...fitDense(0, 9, 100),
          ...fitDense(10, 19, 138),
          ...fitDense(20, 29, 190),
        ],
      );
      expect(v.belowZone1Micros, 10 * sec);
      expect(v.zoneMicros, [0, 10 * sec, 0, 0, 10 * sec]);
      expect(v.coveredMicros, 30 * sec);
      expect(v.movingMicros, 30 * sec);
      expect(v.aboveHint, isFalse);
    });

    test('Puls über 100 % löst den Hinweis aus, genau 100 % nicht', () {
      expect(
        run(moving: [span(0, 10)], hrs: fitDense(0, 9, 190)).aboveHint,
        isFalse,
      );
      final v = run(moving: [span(0, 10)], hrs: fitDense(0, 9, 191));
      expect(v.aboveHint, isTrue);
      expect(v.zoneMicros[4], 10 * sec);
    });

    test('Lücke wird nicht in eine Zone gezählt', () {
      final v = run(
        moving: [span(0, 100)],
        hrs: [...fitDense(0, 19, 138), ...fitDense(70, 99, 138)],
        gaps: [gap(20, 70)],
      );
      expect(v.zoneMicros[1], 50 * sec);
      expect(v.coveredMicros, 50 * sec);
      expect(v.movingMicros, 100 * sec);
    });

    test('Pause (kein Bewegungsintervall) zählt nicht', () {
      final v = run(
        moving: [span(0, 10), span(50, 60)],
        hrs: [...fitDense(0, 9, 138), ...fitDense(50, 59, 190)],
        gaps: [gap(10, 50)],
      );
      expect(v.zoneMicros[1], 10 * sec);
      expect(v.zoneMicros[4], 10 * sec);
      expect(v.movingMicros, 20 * sec);
    });

    void expectUnavailable(
      FitnessResult<ReserveZoneTimes> res,
      UnavailableReason reason,
    ) {
      expect(res, isA<FitnessUnavailable<ReserveZoneTimes>>());
      final u = res as FitnessUnavailable<ReserveZoneTimes>;
      expect(u.reason, reason);
      expect(u.method, 'reserve-zones');
      expect(u.methodVersion, zones.methodVersion);
      expect(u.parameterVersion, p.parameterVersion);
    }

    FitnessResult<ReserveZoneTimes> raw({
      required List<TimeSpan> moving,
      required List<RawHeartRate> hrs,
      List<HeartRateGap> gaps = const [],
    }) => zones.timeInZones(
      basis: basis,
      heartRate: fitHeartRate(hrs, gaps: gaps),
      movement: fitMovement(moving),
      p: p,
    );

    test('ohne Puls: nicht verfügbar (noHeartRate), nicht 0', () {
      expectUnavailable(
        raw(moving: [span(0, 10)], hrs: []),
        UnavailableReason.noHeartRate,
      );
    });

    test('Puls nur in Lücke: nicht verfügbar (noHeartRate)', () {
      expectUnavailable(
        raw(
          moving: [span(0, 10)],
          hrs: fitDense(0, 9, 138),
          gaps: [gap(0, 10)],
        ),
        UnavailableReason.noHeartRate,
      );
    });

    test('ohne Bewegungszeit: nicht verfügbar (noMovingTime)', () {
      expectUnavailable(
        raw(moving: [], hrs: fitDense(0, 9, 138)),
        UnavailableReason.noMovingTime,
      );
      expectUnavailable(
        raw(moving: [], hrs: []),
        UnavailableReason.noMovingTime,
      );
    });

    test('Teilabdeckung bleibt verfügbar', () {
      final v = run(
        moving: [span(0, 100)],
        hrs: fitDense(0, 9, 138),
        gaps: [gap(10, 100)],
      );
      expect(v.coveredMicros, 10 * sec);
      expect(v.movingMicros, 100 * sec);
    });

    test('Basis-Fehler liefern nicht verfügbar', () {
      for (final (b, reason) in [
        (
          const HeartRateBasis(restingBpm: 60),
          UnavailableReason.missingMaxHeartRate,
        ),
        (
          const HeartRateBasis(maxBpm: 190),
          UnavailableReason.missingRestingHeartRate,
        ),
        (
          const HeartRateBasis(maxBpm: 60, restingBpm: 60),
          UnavailableReason.maxNotAboveResting,
        ),
        (
          const HeartRateBasis(maxBpm: 109, restingBpm: 60),
          UnavailableReason.reserveTooSmall,
        ),
      ]) {
        final res = zones.timeInZones(
          basis: b,
          heartRate: fitHeartRate(fitDense(0, 9, 100)),
          movement: fitMovement([span(0, 10)]),
          p: p,
        );
        expect((res as FitnessUnavailable).reason, reason);
        expect(res.method, 'reserve-zones');
      }
    });
  });

  test('Standardbestückung enthält Reserve (A) und Reservezonen (B)', () {
    final reg = AlgorithmRegistry.standard();
    expect(
      reg.active(heartRateReserveFamily).category,
      AlgorithmCategory.established,
    );
    expect(
      reg.active(reserveZonesFamily).category,
      AlgorithmCategory.heuristic,
    );
  });
}
