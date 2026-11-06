import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/motion_support.dart' show track;
import '../preprocessing/support.dart' show t0, at;
import 'support.dart';

double? pace(List<MotionSegment> s) => bestPace(s).secondsPerKm;

/// Referenz: Zeit als Funktion der Strecke fein abgetastet, kleinste Zeit für
/// 1000 m über alle Anfänge. Unabhängig von der Kandidatenwahl des Produkts.
double? oracle(List<MotionSegment> segments, double window) {
  // Ketten wie im Produkt: zusammenhängende Segmente.
  final chains = <List<MotionSegment>>[];
  for (final s in segments) {
    if (s.isGap) {
      chains.add([]);
      continue;
    }
    if (chains.isEmpty ||
        chains.last.isEmpty ||
        chains.last.last.end != s.start) {
      chains.add([]);
    }
    chains.last.add(s);
  }
  double? best;
  for (final c in chains.where((c) => c.isNotEmpty)) {
    final total = c.fold<double>(0, (a, s) => a + s.meters);
    if (total < window) continue;
    // Zeit bei Strecke x: frühester (lo) und spätester (hi) Zeitpunkt.
    double timeAt(double x, {required bool latest}) {
      var d = 0.0;
      var t = 0.0;
      for (final s in c) {
        final sec = s.seconds;
        final end = d + s.meters;
        if (latest ? x < end : x <= end) {
          if (s.meters == 0) return latest ? t + sec : t;
          return t + (x - d) / s.meters * sec;
        }
        d = end;
        t += sec;
      }
      return t;
    }

    const step = 0.05;
    for (var x = 0.0; x + window <= total + 1e-9; x += step) {
      final w =
          timeAt(min(x + window, total), latest: false) -
          timeAt(x, latest: true);
      if (best == null || w < best) best = w;
    }
  }
  return best;
}

void main() {
  group('Bestpace: schnellster zusammenhängender Kilometer (OQ-0037)', () {
    test('gleichmäßiges Tempo: Pace des Tempos', () {
      // 1200 m in 400 s = 3 m/s -> 333,33 s/km.
      final s = chain([for (var i = 0; i < 40; i++) (10, 30)]);
      expect(pace(s), closeTo(1000 / 3, 1e-6));
    });

    test(
      'schneller Kilometer mitten im Lauf, nicht auf Grenzen ausgerichtet',
      () {
        // 450 m @2 m/s, 1000 m @4 m/s, 450 m @2 m/s: der Kilometer mit 4 m/s.
        final s = chain([(225, 450), (250, 1000), (225, 450)]);
        expect(pace(s), closeTo(250, 1e-6));
        final w = bestPace(s);
        expect(w.sectionStart, sBase.add(const Duration(seconds: 225)));
        expect(w.sectionEnd, sBase.add(const Duration(seconds: 475)));
      },
    );

    test('Fenster beginnt mitten in einem Segment', () {
      // 700 m @2 (350 s) | 1000 m @4 (250 s): schnellstes Fenster ganz im
      // zweiten Segment; ein Fenster 300 m @2 + 700 m @4 wäre 150+175=325 s.
      final s = chain([(350, 700), (250, 1000)]);
      expect(pace(s), closeTo(250, 1e-6));
    });

    test('Lauf kürzer als ein Kilometer: nicht verfügbar, nicht 0', () {
      final r = bestPace(chain([(100, 999)]));
      expect(r.secondsPerKm, isNull);
      expect(r.isAvailable, isFalse);
      expect(r.unavailable, BestPaceUnavailable.noQualifyingSection);
      expect(r.sectionStart, isNull);
    });

    test('genau ein Kilometer zählt', () {
      expect(pace(chain([(300, 1000)])), closeTo(300, 1e-9));
    });

    test('ohne Segmente: nicht verfügbar', () {
      expect(bestPace(const []).isAvailable, isFalse);
    });

    test('Lücke (PAR-004) trennt: 2 x 600 m ergeben keinen Kilometer', () {
      final s = [
        ...chain([(100, 600)]),
        seg(100, 130, 0, gap: true),
        ...chain([(100, 600)], from: 130),
      ];
      expect(pace(s), isNull);
    });

    test('manuelle Pause trennt: nicht anschließende Segmente', () {
      // Segmente ohne Lücken-Segment, aber mit Zeitsprung (Pause).
      final s = [
        ...chain([(100, 600)]),
        ...chain([(100, 600)], from: 400),
      ];
      expect(pace(s), isNull);
    });

    test('schneller Abschnitt über der Lücke zählt nicht', () {
      // Schnell (5 m/s) 700 m | Lücke | 700 m schnell -> zusammen 1400 m,
      // aber getrennt. Dahinter ein langsamer ganzer Kilometer (2 m/s).
      final s = [
        ...chain([(140, 700)]),
        seg(140, 170, 0, gap: true),
        ...chain([(140, 700), (500, 1000)], from: 170),
      ];
      // Ein Fenster über die Lücke wäre 300 m + 700 m schnell = 200 s.
      // Erlaubt ist nur der Kilometer im zweiten Abschnitt: 700 m @5 + 300 m
      // @2 = 140 + 150 s.
      expect(pace(s), closeTo(290, 1e-6));
    });

    test('Stillstand im Fenster zählt als Zeit', () {
      // 500 m in 100 s, 60 s Stillstand, 500 m in 100 s -> 260 s je km.
      final s = chain([(100, 500), (60, 0), (100, 500)]);
      expect(pace(s), closeTo(260, 1e-6));
    });

    test('Stillstand vor dem schnellen Stück verlängert das Fenster nicht', () {
      final s = chain([(100, 0), (250, 1000)]);
      expect(pace(s), closeTo(250, 1e-6));
    });

    test('mehrere Abschnitte: der schnellere gewinnt', () {
      final s = [
        ...chain([(400, 1000)]),
        seg(400, 420, 0, gap: true),
        ...chain([(300, 1000)], from: 420),
      ];
      expect(pace(s), closeTo(300, 1e-6));
    });

    test('abweichende Länge über Parameter (500 m)', () {
      final s = chain([(100, 500), (200, 500)]);
      final r = bestPace(
        s,
        parameters: const StatisticsParameters(bestPaceDistanceMeters: 500),
      );
      expect(r.secondsPerKm, closeTo(200, 1e-6));
    });

    test('Zufallsläufe stimmen mit der Abtast-Referenz überein', () {
      final rnd = Random(7);
      var available = 0;
      for (var run = 0; run < 25; run++) {
        final legs = <(num, num)>[
          for (var i = 0; i < 12 + rnd.nextInt(30); i++)
            (
              5 + rnd.nextInt(60),
              rnd.nextInt(5) == 0 ? 0 : 20 + rnd.nextInt(250),
            ),
        ];
        final s = chain(legs);
        final got = pace(s);
        final ref = oracle(s, 1000);
        if (ref == null) {
          expect(got, isNull, reason: 'Lauf $run');
        } else {
          expect(got, isNotNull, reason: 'Lauf $run');
          available++;
          // Referenz abgetastet: nie besser als exakt, höchstens Schrittweite.
          expect(got!, lessThanOrEqualTo(ref + 1e-6), reason: 'Lauf $run');
          expect(ref - got, lessThan(0.3), reason: 'Lauf $run');
        }
      }
      expect(available, greaterThan(10)); // die Prüfung ist nicht leer
    });
  });

  group('Bestpace aus der Vorverarbeitung (RunPreprocessor)', () {
    test('1200 m gleichmäßig: Bestpace ~ Tempo', () {
      final r = RunPreprocessor(start: t0);
      track([(400, 3.0)]).forEach(r.addPosition);
      final segs = r.result(at: at(400)).pace.segments;
      expect(segs, isNotEmpty);
      expect(pace(segs), closeTo(1000 / 3, 0.5));
    });

    test('Lauf unter einem Kilometer: nicht verfügbar', () {
      final r = RunPreprocessor(start: t0);
      track([(300, 3.0)]).forEach(r.addPosition); // 900 m
      expect(pace(r.result(at: at(300)).pace.segments), isNull);
    });

    test('manuelle Pause in der Mitte trennt, auch bei 1200 m insgesamt', () {
      final r = RunPreprocessor(start: t0);
      final pts = track([(400, 3.0)]);
      for (final p in pts) {
        final s = p.time.difference(t0).inSeconds;
        if (s == 200) r.pause(at(200));
        if (s == 230) r.resume(at(230));
        if (s <= 200 || s >= 230) r.addPosition(p);
      }
      expect(pace(r.result(at: at(400)).pace.segments), isNull);
    });

    test('GPS-Lücke über PAR-004 trennt', () {
      final r = RunPreprocessor(start: t0);
      for (final p in track([(400, 3.0)])) {
        final s = p.time.difference(t0).inSeconds;
        if (s > 200 && s < 230) continue; // 30 s ohne Punkte, > 10 s
        r.addPosition(p);
      }
      expect(pace(r.result(at: at(400)).pace.segments), isNull);
    });
  });
}
