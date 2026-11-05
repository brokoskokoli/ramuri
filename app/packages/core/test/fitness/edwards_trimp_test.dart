import 'package:core/core.dart';
import 'package:test/test.dart';

const p = FitnessParameters.v3();
const trimp = EdwardsTrimp();
const sec = 1000000;

final t0 = DateTime.utc(2026, 1, 1, 10);
DateTime at(int s) => t0.add(Duration(seconds: s));
DateTime atMicros(int us) => t0.add(Duration(microseconds: us));
TimeSpan span(int a, int b) => TimeSpan(start: at(a), end: at(b));
RawHeartRate hr(int s, int bpm) =>
    RawHeartRate(time: at(s), source: 'x', bpm: bpm);
HeartRateGap gap(int a, int b) =>
    HeartRateGap(start: at(a), end: at(b), open: false);

FitnessResult<TrimpResult> run({
  HeartRateBasis basis = const HeartRateBasis(maxBpm: 200),
  required List<TimeSpan> moving,
  required List<RawHeartRate> hrs,
  List<HeartRateGap> gaps = const [],
  FitnessParameters params = p,
}) => trimp.compute(
  basis: basis,
  movingIntervals: moving,
  acceptedValues: hrs,
  gaps: gaps,
  p: params,
);

TrimpResult value(FitnessResult<TrimpResult> r) =>
    (r as FitnessAvailable<TrimpResult>).value;

UnavailableReason reason(FitnessResult<TrimpResult> r) =>
    (r as FitnessUnavailable<TrimpResult>).reason;

/// Eine Minute mit festem Puls; die Punkte sind dann das Gewicht.
FitnessResult<TrimpResult> minuteAt(int bpm, int max) => run(
  basis: HeartRateBasis(maxBpm: max),
  moving: [span(0, 60)],
  hrs: [hr(0, bpm)],
);

void main() {
  test('FR-0092: 10 min Z1, 30 min Z2, 10 min Z4 ergibt 110 (von Hand)', () {
    // HFmax 200: Z1 = 50..60 % (110 bpm), Z2 = 60..70 % (130), Z4 = 80..90 %
    // (170). 10*1 + 30*2 + 10*4 = 10 + 60 + 40 = 110.
    final r = run(
      moving: [span(0, 3000)],
      hrs: [hr(0, 110), hr(600, 130), hr(2400, 170)],
    );
    final v = value(r);
    expect(v.points, 110);
    expect(v.incomplete, isFalse);
    expect(v.coverage, 1);
    expect(v.aboveHint, isFalse);
  });

  test('Ergebnis nennt Methode, Version, Kategorie, Parameterversion', () {
    final r = run(moving: [span(0, 60)], hrs: [hr(0, 150)]);
    expect(r.method, 'edwards-trimp');
    expect(r.methodVersion, 1);
    expect(r.parameterVersion, 3);
    expect(trimp.category, AlgorithmCategory.established);
  });

  group('Gewichtsgrenzen (OQ-0014), HFmax 1000', () {
    const lower = {500: 1, 600: 2, 700: 3, 800: 4, 900: 5};
    for (final e in lower.entries) {
      test('${e.key ~/ 10} %: knapp unter, genau, knapp über', () {
        expect(value(minuteAt(e.key - 1, 1000)).points, e.value - 1);
        expect(value(minuteAt(e.key, 1000)).points, e.value);
        expect(value(minuteAt(e.key + 1, 1000)).points, e.value);
      });
    }
    test('unter 50 % Gewicht 0, nicht 1 und nicht nicht-verfügbar', () {
      final r = minuteAt(499, 1000);
      expect(r, isA<FitnessAvailable<TrimpResult>>());
      expect(value(r).points, 0);
      expect(value(minuteAt(1, 1000)).points, 0);
    });
    test(
      '100 %: Gewicht 5 ohne Hinweis; knapp darüber Gewicht 5 mit Hinweis',
      () {
        final at100 = value(minuteAt(1000, 1000));
        expect(at100.points, 5);
        expect(at100.aboveHint, isFalse);
        final above = value(minuteAt(1001, 1000));
        expect(above.points, 5);
        expect(above.aboveHint, isTrue);
        expect(value(minuteAt(1500, 1000)).points, 5);
      },
    );
  });

  test('Raster: jeder exakt treffbare Grenzwert, HFmax 100..230', () {
    var checked = 0;
    for (var max = 100; max <= 230; max++) {
      for (var k = 5; k <= 10; k++) {
        if (max * k % 10 != 0) continue;
        final hf = max * k ~/ 10;
        final w = k == 10 ? 5 : k - 4;
        expect(value(minuteAt(hf, max)).points, w, reason: '$max/$hf');
        // Unter 100 % bleibt es Gewicht 5, es ist keine Grenze.
        if (k < 10) {
          expect(
            value(minuteAt(hf - 1, max)).points,
            w - 1,
            reason: '$max/$hf',
          );
        }
        expect(value(minuteAt(hf, max)).aboveHint, isFalse, reason: '$max');
        if (k == 10) {
          expect(value(minuteAt(hf + 1, max)).aboveHint, isTrue);
        }
        checked++;
      }
    }
    expect(checked, greaterThan(250));
  });

  test('OQ-0015: Bewegungszeit zählt, nicht die Gesamtzeit', () {
    // 0..60 und 120..180 in Bewegung, dazwischen 60 s Pause. 150/200 = 75 %
    // ist Gewicht 3: 2 min * 3 = 6 (Gesamtzeit gäbe 9).
    final r = run(moving: [span(0, 60), span(120, 180)], hrs: [hr(0, 150)]);
    expect(value(r).points, 6);
    expect(value(r).movingMicros, 120 * sec);
    expect(value(r).incomplete, isFalse);
  });

  group('Abdeckung (OQ-0051), Bewegungszeit 100 s, Lücke am Anfang', () {
    // Lücke [0, g]: abgedeckt ist 100 s minus g, Puls 150 (Gewicht 3).
    FitnessResult<TrimpResult> withCovered(int coveredMicros) => run(
      moving: [span(0, 100)],
      hrs: [hr(0, 150)],
      gaps: [
        HeartRateGap(
          start: at(0),
          end: atMicros(100 * sec - coveredMicros),
          open: false,
        ),
      ],
    );

    test('knapp unter 80 %: nicht bewertet', () {
      final r = withCovered(80 * sec - 1);
      expect(reason(r), UnavailableReason.insufficientCoverage);
    });
    test('genau 80 %: unvollständig bewertet, zählt die vorhandene Zeit', () {
      final v = value(withCovered(80 * sec));
      expect(v.incomplete, isTrue);
      expect(v.coverage, 0.8);
      expect(v.points, closeTo(80 * 3 / 60, 1e-12));
    });
    test('knapp über 80 %: unvollständig', () {
      expect(value(withCovered(80 * sec + 1)).incomplete, isTrue);
    });
    test('knapp unter 100 %: unvollständig', () {
      expect(value(withCovered(100 * sec - 1)).incomplete, isTrue);
    });
    test('genau 100 %: vollständig', () {
      final v = value(withCovered(100 * sec));
      expect(v.incomplete, isFalse);
      expect(v.coverage, 1);
    });
  });

  test('ohne Puls: nicht bewertet, kein Wert 0', () {
    final r = run(moving: [span(0, 60)], hrs: []);
    expect(r, isA<FitnessUnavailable<TrimpResult>>());
    expect(reason(r), UnavailableReason.noHeartRate);
    expect(r.method, 'edwards-trimp');
  });

  test('Puls nur in Lücken: ohne Puls, nicht 0', () {
    final r = run(moving: [span(0, 60)], hrs: [hr(0, 150)], gaps: [gap(0, 60)]);
    expect(reason(r), UnavailableReason.noHeartRate);
  });

  test('ohne Bewegungszeit: noMovingTime, keine Division durch 0', () {
    expect(
      reason(run(moving: [], hrs: [hr(0, 150)])),
      UnavailableReason.noMovingTime,
    );
    expect(
      reason(run(moving: [span(5, 5)], hrs: [hr(0, 150)])),
      UnavailableReason.noMovingTime,
    );
    expect(reason(run(moving: [], hrs: [])), UnavailableReason.noMovingTime);
  });

  group('FR-0093: nur HFmax zählt', () {
    double points(HeartRateBasis b, [FitnessParameters params = p]) => value(
      run(
        basis: b,
        moving: [span(0, 600)],
        hrs: [hr(0, 130), hr(300, 170)],
        params: params,
      ),
    ).points;

    test('Ruhepuls ändert den TRIMP nicht, auch nicht sein Fehlen', () {
      final base = points(const HeartRateBasis(maxBpm: 200));
      expect(base, 5 * 2 + 5 * 4);
      for (final rest in [30, 45, 60, 100, 150]) {
        expect(points(HeartRateBasis(maxBpm: 200, restingBpm: rest)), base);
      }
    });

    test('andere Reservezonen ändern den TRIMP nicht', () {
      final other = FitnessParameters(
        parameterVersion: 3,
        reserveZoneBounds: const [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
        minHeartRateReserveBpm: 80,
      );
      final b = const HeartRateBasis(maxBpm: 200, restingBpm: 60);
      expect(points(b, other), points(b));
    });

    test(
      'Herzfrequenzreserve unter 50 bpm (PAR-019) berührt den TRIMP nicht',
      () {
        const small = HeartRateBasis(maxBpm: 200, restingBpm: 160);
        expect(points(small), points(const HeartRateBasis(maxBpm: 200)));
      },
    );

    test('HFmax <= HFRuhe (PAR-018): nicht verfügbar mit Grund', () {
      for (final rest in [200, 201, 250]) {
        final r = run(
          basis: HeartRateBasis(maxBpm: 200, restingBpm: rest),
          moving: [span(0, 600)],
          hrs: [hr(0, 150)],
        );
        expect(reason(r), UnavailableReason.maxNotAboveResting);
      }
      // HFmax = HFRuhe + 1 bleibt verfügbar.
      expect(
        run(
          basis: const HeartRateBasis(maxBpm: 200, restingBpm: 199),
          moving: [span(0, 600)],
          hrs: [hr(0, 150)],
        ),
        isA<FitnessAvailable<TrimpResult>>(),
      );
    });
  });

  test('fehlende HFmax: nicht verfügbar, auch mit Ruhepuls', () {
    for (final b in const [HeartRateBasis(), HeartRateBasis(restingBpm: 50)]) {
      final r = run(basis: b, moving: [span(0, 60)], hrs: [hr(0, 150)]);
      expect(reason(r), UnavailableReason.missingMaxHeartRate);
    }
  });

  test('geschätzte HFmax wird weitergegeben, auch bei nicht verfügbar', () {
    const b = HeartRateBasis(maxBpm: 200, maxIsEstimated: true);
    expect(
      run(basis: b, moving: [span(0, 60)], hrs: [hr(0, 150)]).maxIsEstimated,
      isTrue,
    );
    expect(run(basis: b, moving: [], hrs: []).maxIsEstimated, isTrue);
  });
}
