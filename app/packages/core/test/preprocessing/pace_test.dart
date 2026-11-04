import 'package:core/core.dart';
import 'package:test/test.dart';

import 'motion_support.dart';
import 'support.dart';

void main() {
  const params = PreprocessingParameters.v2();

  group('Tempo und Pace (FR-0050, OQ-0037)', () {
    test('4 m/s sind 250 s/km', () {
      expect(speedMetersPerSecond(4, 1), 4);
      expect(paceSecondsPerKm(4), 250);
    });

    test('kein Wert bei Δt <= 0, keine Division durch 0', () {
      expect(speedMetersPerSecond(10, 0), isNull);
      expect(speedMetersPerSecond(10, -1), isNull);
      expect(speedMetersPerSecond(0, 0), isNull);
      expect(paceSecondsPerKm(0), isNull);
      expect(paceSecondsPerKm(-1), isNull);
      expect(paceSecondsPerKm(null), isNull);
    });

    test('Stillstand ergibt PaceStandstill, kein Wert PaceNoData', () {
      expect(paceDisplay(0, params), isA<PaceStandstill>());
      expect(paceDisplay(0.499, params), isA<PaceStandstill>());
      expect(paceDisplay(null, params), isA<PaceNoData>());
      final v = paceDisplay(0.501, params) as PaceValue;
      expect(v.secondsPerKm, closeTo(1000 / 0.501, 1e-9));
    });

    test('stehende Punkte liefern PaceStandstill (live)', () {
      final r = feed(track([(10, 0)]));
      expect(r.result(at: at(10)).pace.livePace, isA<PaceStandstill>());
    });
  });

  group('Live-Fenster (FR-0051, PAR-005)', () {
    PaceResult live(List<RawPosition> pts, num sec) =>
        feed(pts).result(at: at(sec)).pace;

    test('konstant 4 m/s ergeben 250 s/km', () {
      final r = live(track([(30, 4)]), 30);
      expect((r.livePace as PaceValue).secondsPerKm, closeTo(250, 1e-3));
    });

    test('4,9 s Daten liefern keinen Wert', () {
      final r = live(track([(4.9, 4)], dt: 2.45), 4.9);
      expect(r.liveCountedTime, const Duration(milliseconds: 4900));
      expect(r.livePace, isA<PaceNoData>());
      expect(r.liveSpeed, isNull);
    });

    test('genau 5 s liefern einen Wert', () {
      final r = live(track([(5, 4)], dt: 2.5), 5);
      expect(r.liveCountedTime, const Duration(seconds: 5));
      expect((r.livePace as PaceValue).secondsPerKm, closeTo(250, 1e-3));
    });

    test('das Fenster folgt: Punkt fällt nach 20 s heraus', () {
      final pts = track([(1, 10), (40, 4)]);
      // Fenster [0, 20] enthält das 10-m/s-Segment: (10 + 19 * 4) / 20.
      expect(live(pts, 20).liveSpeed, closeTo(4.3, 1e-6));
      // Fenster [1, 21]: der Punkt bei 0 s ist heraus.
      expect(live(pts, 21).liveSpeed, closeTo(4, 1e-6));
    });

    test('ein Ausreißer der Einzelgeschwindigkeit springt nicht durch', () {
      // Ein Segment mit 12 m/s statt 4 m/s (acc 10, damit kein Sprungfilter).
      final pts = track([(10, 4), (1, 12), (9, 4)], acc: 10);
      final r = live(pts, 20);
      expect(r.liveSpeed, closeTo((19 * 4 + 12) / 20, 1e-6)); // 4,4
      expect(r.liveSpeed, lessThan(6));
    });

    test('Lücke im Fenster: Lückenzeit und -strecke bleiben heraus', () {
      final pts = [
        ...track([(25, 4)]), // bis 25 s, 100 m
        // 11 s Lücke (> PAR-004), 80 m (7,3 m/s) werden nicht gezählt.
        ...track([(24, 4)], from: 36, north: 180),
      ];
      final r = live(pts, 40);
      // Fenster [20, 40]: 5 s vor und 4 s nach der Lücke, je 4 m/s.
      expect(r.liveCountedTime, const Duration(seconds: 9));
      expect(r.liveSpeed, closeTo(4, 1e-6));
    });

    test('Stillstand im Fenster ergibt PaceStandstill', () {
      final pts = track([(10, 4), (20, 0)]);
      expect(live(pts, 30).livePace, isA<PaceStandstill>());
    });
  });

  group('30-s-Median (PAR-006)', () {
    // Segmentenden 1..16 s mit 2 m/s, 17..31 s mit 6 m/s.
    final pts = track([(16, 2), (15, 6)]);

    test('Fenstergrenze: Wert bei at-30 s zählt, danach nicht mehr', () {
      final r = feed(pts);
      final a = r.result(at: at(31)).pace; // Enden 1..31: 16 x 2, 15 x 6
      expect(a.medianSpeed, closeTo(2, 1e-6));
      final b = r.result(at: at(31.5)).pace; // Enden 2..31: 15 x 2, 15 x 6
      expect(b.medianSpeed, closeTo(4, 1e-6));
    });

    test('Reihe: ein Median je akzeptiertem Segment, nachlaufend', () {
      final s = feed(pts).result(at: at(31)).pace.medianSeries;
      expect(s.length, 31);
      expect(s.first.time, at(1));
      expect(s.first.metersPerSecond, closeTo(2, 1e-6));
      expect(s.last.time, at(31));
      expect(s.last.metersPerSecond, closeTo(2, 1e-6));
      expect(() => s.add(s.first), throwsUnsupportedError);
    });

    test('Median ist unempfindlich gegen einen Ausreißer', () {
      final p = track([(10, 4), (1, 12), (10, 4)], acc: 10);
      final r = feed(p).result(at: at(21)).pace;
      expect(r.medianSpeed, closeTo(4, 1e-6));
    });
  });
}
