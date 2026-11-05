import 'package:core/core.dart';
import 'package:test/test.dart';

import 'fitness_support.dart';

const sec = 1000000;
const p = FitnessParameters.v3();

HeartRateTime run(
  List<TimeSpan> m,
  List<RawHeartRate> h, [
  List<HeartRateGap> g = const [],
]) => heartRateTimeByBpm(
  heartRate: fitHeartRate(h, gaps: g),
  movement: fitMovement(m),
  p: p,
);

void main() {
  final span = fitSpan;
  final hr = fitHr;
  final at = fitAt;

  test('Halten: letzter Wert gilt bis zum nächsten', () {
    final v = run(
      [span(0, 30)],
      [...fitDense(0, 19, 100), ...fitDense(20, 29, 120)],
    );
    expect(v.microsByBpm, {100: 20 * sec, 120: 10 * sec});
    expect(v.coveredMicros, 30 * sec);
    expect(v.movingMicros, 30 * sec);
  });

  test('Summe je Puls ist die abgedeckte Zeit; Ausgabe aufsteigend', () {
    final v = run(
      [span(0, 7)],
      [...fitDense(0, 2, 150), ...fitDense(3, 6, 90)],
    );
    expect(v.microsByBpm.keys.toList(), [90, 150]);
    expect(v.microsByBpm.values.fold<int>(0, (a, b) => a + b), v.coveredMicros);
  });

  test('Lücke wird abgezogen, auch über Intervallgrenzen', () {
    final v = run(
      [span(0, 10), span(20, 40)],
      [...fitDense(0, 5, 100), ...fitDense(25, 39, 100)],
      [fitGap(5, 25)],
    );
    expect(v.movingMicros, 30 * sec);
    expect(v.coveredMicros, 5 * sec + 15 * sec);
    expect(v.microsByBpm, {100: 20 * sec});
  });

  test('Lücke deckt ein ganzes Intervall und ragt über den Rand', () {
    final v = run(
      [span(10, 20), span(30, 40)],
      fitDense(25, 34, 100),
      [fitGap(0, 25), fitGap(34, 100)],
    );
    // Bewegung 30..40 minus Lücke ab 34: 30..34, dazu der Halt bis 35 gilt
    // nur bis zur Lücke.
    expect(v.coveredMicros, 4 * sec);
    expect(v.microsByBpm, {100: 4 * sec});
  });

  test('Überschneidende Intervalle und Lücken zählen einmal', () {
    final v = run(
      [span(0, 20), span(10, 30)],
      [...fitDense(0, 4, 100), ...fitDense(15, 29, 100)],
      [fitGap(5, 15), fitGap(10, 12)],
    );
    expect(v.movingMicros, 30 * sec);
    expect(v.coveredMicros, 20 * sec);
  });

  test('Reihenfolge der Eingaben ist egal', () {
    final a = run(
      [span(30, 40), span(0, 10)],
      [...fitDense(30, 39, 120), ...fitDense(0, 9, 100)],
      [fitGap(10, 30)],
    );
    expect(a.microsByBpm, {100: 10 * sec, 120: 10 * sec});
  });

  test('gleiche Zeit: der spätere Eintrag gilt', () {
    final b = run(
      [span(0, 10)],
      [...fitDense(0, 4, 100), hr(5, 100), hr(5, 130), ...fitDense(6, 9, 130)],
    );
    expect(b.microsByBpm, {100: 5 * sec, 130: 5 * sec});
    final c = run(
      [span(0, 10)],
      [
        hr(0, 100),
        hr(1, 100),
        hr(2, 100),
        hr(2, 110),
        hr(2, 120),
        ...fitDense(3, 9, 120),
      ],
    );
    expect(c.microsByBpm, {100: 2 * sec, 120: 8 * sec});
  });

  group('Pause', () {
    test('alter Puls gilt nicht über die Pause, neuer Puls rückwirkend', () {
      // Bewegung 0..10 und 15..25; Pause 5 s (keine Lücke > 10 s). Der neue
      // Puls kommt erst bei 16, einen Takt nach dem Wiederbeginn.
      final v = run(
        [span(0, 10), span(15, 25)],
        [...fitDense(0, 9, 100), ...fitDense(16, 24, 140)],
      );
      expect(v.microsByBpm, {100: 10 * sec, 140: 10 * sec});
      expect(v.coveredMicros, v.movingMicros);
    });

    test('neuer Puls weiter als ein Takt entfernt: Rest fehlt', () {
      final v = run(
        [span(0, 10), span(15, 25)],
        [...fitDense(0, 9, 100), ...fitDense(18, 24, 140)],
      );
      expect(v.microsByBpm, {100: 10 * sec, 140: 7 * sec});
      expect(v.movingMicros, 20 * sec);
    });
  });

  group('Takt (PAR-010, wie SectionQuality)', () {
    test('Muster 3 Werte, dann 9 s nichts: nur ein Takt je Wert gilt', () {
      final h = [
        for (var k = 0; k < 8; k++) ...fitDense(12 * k, 12 * k + 2, 150),
      ];
      final v = run([span(0, 96)], h);
      // 8 x (Takt 1 s je Wert, 3 Werte) = 24 s von 96 s.
      expect(v.coveredMicros, 24 * sec);
      expect(v.movingMicros, 96 * sec);
    });

    test('stabiler 5-s-Takt ist vollständig abgedeckt', () {
      final v = run([span(0, 100)], fitDense(0, 95, 150, step: 5));
      expect(v.coveredMicros, 100 * sec);
    });

    test('eingegangene, verworfene Werte senken den Takt', () {
      // Akzeptiert alle 10 s, dazwischen je ein verworfener Wert: Takt 5 s.
      final accepted = fitDense(0, 40, 150, step: 10);
      final v = heartRateTimeByBpm(
        heartRate: fitHeartRate(
          accepted,
          discarded: [for (var s = 5; s < 40; s += 10) hr(s, 250)],
        ),
        movement: fitMovement([span(0, 50)]),
        p: p,
      );
      expect(v.coveredMicros, 25 * sec);
    });

    test('Takt unbekannt: weniger als zwei akzeptierte Werte, nichts', () {
      final v = run([span(0, 10)], [hr(0, 100)]);
      expect(v.coveredMicros, 0);
      expect(v.movingMicros, 10 * sec);
      final w = heartRateTimeByBpm(
        heartRate: fitHeartRate([hr(0, 100)], discarded: [hr(5, 250)]),
        movement: fitMovement([span(0, 10)]),
        p: p,
      );
      expect(w.coveredMicros, 0);
    });
  });

  test('ohne Puls nichts abgedeckt, Bewegungszeit bleibt', () {
    final v = run([span(0, 10)], []);
    expect(v.coveredMicros, 0);
    expect(v.movingMicros, 10 * sec);
    expect(v.microsByBpm, isEmpty);
  });

  test('keine Bewegungszeit, leere und negative Intervalle', () {
    final v = run([span(5, 5), span(9, 3)], fitDense(0, 9, 100));
    expect(v.movingMicros, 0);
    expect(v.coveredMicros, 0);
  });

  test('Mikrosekunden bleiben exakt (keine Rundung)', () {
    DateTime us(int n) => fitT0.add(Duration(microseconds: n));
    RawHeartRate v(int n, int bpm) =>
        RawHeartRate(time: us(n), source: 'x', bpm: bpm);
    final r = heartRateTimeByBpm(
      heartRate: fitHeartRate([v(0, 100), v(1, 110), v(2, 110)]),
      movement: fitMovement([TimeSpan(start: us(0), end: us(3))]),
      p: p,
    );
    expect(r.microsByBpm, {100: 1, 110: 2});
    expect(at(0), fitT0);
  });

  group('Parameterversion (NFR-0001)', () {
    final h = fitDense(0, 9, 100);
    final m = [span(0, 10)];
    test('Puls oder Bewegungszeit mit anderer Version: ArgumentError', () {
      expect(
        () => heartRateTimeByBpm(
          heartRate: fitHeartRate(h, version: 4),
          movement: fitMovement(m),
          p: p,
        ),
        throwsArgumentError,
      );
      expect(
        () => heartRateTimeByBpm(
          heartRate: fitHeartRate(h),
          movement: fitMovement(m, version: 4),
          p: p,
        ),
        throwsArgumentError,
      );
    });
    test('passende Version: kein Fehler', () {
      expect(run(m, h).coveredMicros, 10 * sec);
    });
  });
}
