import 'package:core/core.dart';
import 'package:test/test.dart';

import 'altitude_support.dart';
import 'hr_support.dart';
import 'motion_support.dart';
import 'support.dart';

RawSteps st(num sec, int count) =>
    RawSteps(time: at(sec), source: 'test', count: count);

RawPosition posAt(num sec, double lat, double lon, double? acc) => RawPosition(
  time: at(sec),
  source: 'test',
  latitude: lat,
  longitude: lon,
  accuracyMeters: acc,
);

void main() {
  group('Befund 1: Höhe und Schritte in der manuellen Pause', () {
    test(
      'Werte in der Pause sind unavailable, kein Aufstieg über die Pause',
      () {
        final r = RunPreprocessor(start: t0);
        r.addAltitude(alt(0, 100));
        r.pause(at(10));
        final a = r.addAltitude(alt(20, 300));
        final b = r.addAltitude(alt(30, 500));
        r.resume(at(40));
        r.addAltitude(alt(50, 500));
        expect(a!.state, MeasurementState.unavailable);
        expect(b!.state, MeasurementState.unavailable);
        expect(r.result(at: at(50)).altitude.ascentMeters, 0);
      },
    );

    test('Sprung über die Pause ohne Werte darin zählt nicht', () {
      final r = RunPreprocessor(start: t0);
      r.addAltitude(alt(0, 100));
      r.pause(at(10));
      r.resume(at(20));
      r.addAltitude(alt(50, 500));
      r.addAltitude(alt(90, 510));
      expect(r.result(at: at(90)).altitude.ascentMeters, 10);
    });

    test('bisheriger Aufstieg bleibt, Fenster neu', () {
      final r = RunPreprocessor(start: t0);
      r.addAltitude(alt(0, 100));
      r.addAltitude(alt(40, 110));
      r.pause(at(50));
      r.resume(at(60));
      // Fenster neu: Median nur aus dem neuen Wert.
      r.addAltitude(alt(65, 400));
      final res = r.result(at: at(65)).altitude;
      expect(res.ascentMeters, 10);
      expect(res.smoothed.last.meters, 400);
    });

    test('Schritte in der Pause sind unavailable', () {
      final r = RunPreprocessor(start: t0);
      r.addSteps(st(5, 10));
      r.pause(at(10));
      final s = r.addSteps(st(20, 50));
      r.resume(at(30));
      final t = r.addSteps(st(40, 80));
      expect(s.state, MeasurementState.unavailable);
      expect(t.state, MeasurementState.present);
      expect(r.stepsAt(at(25)).value!.count, 10);
    });
  });

  group('Befund 2: PAR-010 mit verworfenen Werten', () {
    SectionQuality q(List<RawHeartRate> v, num to) => SectionQuality.assess(
      from: at(0),
      to: at(to),
      heartRate: runHr(v, until: to),
      position: run([pos(0, 0)]),
      settlingIntervals: const [],
      parameters: const PreprocessingParameters.v4(),
    );

    test('jeder zweite Wert poor: Regel verletzt', () {
      final r = q([
        for (var s = 0; s <= 300; s++)
          hr(
            s,
            100,
            contact: s.isOdd ? SensorContact.poor : SensorContact.good,
          ),
      ], 300);
      expect(r.missingHeartRateShare, closeTo(0.5, 0.01));
      expect(r.meetsHeartRateGapRule, isFalse);
    });

    test('nur jeder zehnte Wert gültig: Regel verletzt', () {
      final r = q([
        for (var s = 0; s <= 300; s++)
          hr(
            s,
            100,
            contact: s % 10 == 0 ? SensorContact.good : SensorContact.poor,
          ),
      ], 300);
      expect(r.missingHeartRateShare, closeTo(0.9, 0.01));
      expect(r.meetsHeartRateGapRule, isFalse);
    });
  });

  group('Befund 3: nicht endliche Eingaben fail-closed', () {
    final nan = double.nan;
    final inf = double.infinity;

    test(
      'Position: Breite/Länge NaN/inf werden verworfen, Strecke bleibt endlich',
      () {
        final p = PositionProcessor(const PreprocessingParameters.v4());
        p.add(pos(0, 0));
        final a = p.add(posAt(1, nan, 20, 5));
        final b = p.add(posAt(2, 10, inf, 5));
        p.add(pos(3, 3));
        expect(a.state, MeasurementState.discarded);
        expect(b.state, MeasurementState.discarded);
        expect(p.result(at: at(3)).distanceMeters!.isFinite, isTrue);
        expect(p.result(at: at(3)).distanceMeters, closeTo(3, 0.01));
      },
    );

    test('Position: Genauigkeit NaN, negativ, inf wird verworfen', () {
      final p = PositionProcessor(const PreprocessingParameters.v4());
      final r = [
        for (final (i, acc) in [nan, -1.0, inf].indexed)
          p.add(pos(i, 0, acc: acc)),
      ];
      expect([
        for (final x in r) x.state,
      ], everyElement(MeasurementState.discarded));
    });

    test(
      'Höhe: NaN/inf verworfen, Vertikalgenauigkeit NaN/negativ verworfen',
      () {
        final p = AltitudeProcessor(const PreprocessingParameters.v4());
        final a = p.add(alt(0, nan));
        final b = p.add(alt(1, inf));
        final c = p.add(alt(2, 100, va: nan));
        final d = p.add(alt(3, 100, va: -1));
        p.add(alt(40, 100));
        p.add(alt(80, 110));
        expect(
          [a, b, c, d].map((x) => x.state),
          everyElement(MeasurementState.discarded),
        );
        expect(p.result(at: at(80)).ascentMeters, 10);
      },
    );
  });

  group('Befund 4: verworfener Wert sperrt den Kanal nicht', () {
    test('Position: Punkt +1 h mit Genauigkeit 99 m', () {
      final p = PositionProcessor(const PreprocessingParameters.v4());
      p.add(pos(0, 0));
      p.add(pos(3600, 0, acc: 99));
      for (var s = 1; s <= 5; s++) {
        p.add(pos(s, s * 3));
      }
      final res = p.result(at: at(5));
      expect(res.acceptedPoints, hasLength(6));
      expect(res.distanceMeters, closeTo(15, 0.01));
    });

    test('Puls: 250 bpm bei +1 h', () {
      final p = HeartRateProcessor(const PreprocessingParameters.v4());
      p.add(hr(0, 100));
      p.add(hr(3600, 250));
      for (var s = 1; s <= 5; s++) {
        p.add(hr(s, 100));
      }
      expect(p.result(at: at(5)).acceptedValues, hasLength(6));
    });

    test('Höhe: Wert +1 h mit Vertikalgenauigkeit 99 m', () {
      final p = AltitudeProcessor(const PreprocessingParameters.v4());
      p.add(alt(0, 100));
      p.add(alt(3600, 100, va: 99));
      final r = p.add(alt(40, 110));
      expect(r.accepted, isTrue);
    });

    test('Schritte: unavailable-Wert in der Zukunft sperrt nicht', () {
      final s = StepsSeries(parameterVersion: currentParameterVersion);
      s.add(st(0, 1));
      s.add(
        RawSteps(
          time: at(3600),
          source: 'test',
          count: 5,
          state: MeasurementState.unavailable,
        ),
      );
      expect(s.add(st(10, 2)).state, MeasurementState.present);
    });
  });

  group('Befund 5: genaue Schwellen PAR-014', () {
    MovementTimeProcessor mtp() =>
        MovementTimeProcessor(const PreprocessingParameters.v4(), start: t0);
    void feedSeg(MovementTimeProcessor m, int from, int to, double meters) {
      for (var s = from; s < to; s++) {
        m.add(
          MotionSegment(
            start: at(s),
            end: at(s + 1),
            meters: meters,
            isGap: false,
          ),
        );
      }
    }

    test('genau 0,5 m/s ist keine Pause', () {
      final m = mtp();
      feedSeg(m, 0, 30, 0.5);
      expect(m.result(at: at(30)).autoPauseState, AutoPauseState.moving);
    });

    test('genau 0,8 m/s setzt die Pause fort', () {
      final m = mtp();
      feedSeg(m, 0, 20, 0);
      expect(
        m.result(at: at(20)).autoPauseState,
        AutoPauseState.standstillPause,
      );
      feedSeg(m, 20, 23, 0.8);
      expect(m.result(at: at(23)).autoPauseState, AutoPauseState.moving);
    });

    test('paceDisplay(0.5) ergibt einen Wert', () {
      expect(
        paceDisplay(0.5, const PreprocessingParameters.v4()),
        isA<PaceValue>(),
      );
    });
  });

  group('Befund 6: Lücken im 2-min-Mittel (PAR-011)', () {
    test('Lücke im Fenster bei gleichem Tempo löst nicht aus', () {
      final p = SettlingProcessor(
        const PreprocessingParameters.v4(),
        start: t0,
      );
      for (var s = 1; s <= 800; s++) {
        final gap = s > 650 && s <= 700;
        p.add(
          MotionSegment(
            start: at(s - 1),
            end: at(s),
            meters: gap ? 0 : 3,
            isGap: gap,
          ),
        );
      }
      expect(
        [for (final i in p.result(restarts: []).intervals) (i.start, i.end)],
        [(t0, at(180))],
      );
    });
  });

  group('Befund 7: kein Segment über eine kurze Pause', () {
    test('5-s-Pause ergibt kein Segment über die Pause', () {
      final r = RunPreprocessor(start: t0);
      for (final x in track([(10, 3)])) {
        r.addPosition(x);
      }
      r.pause(at(10));
      r.resume(at(15));
      for (final x in track([(10, 3)], from: 15, north: 30, first: true)) {
        r.addPosition(x);
      }
      final res = r.result(at: at(25));
      // 10 Segmente vor, 10 nach der Pause, keines dazwischen.
      expect(res.pace.medianSeries, hasLength(20));
      // Fenster [5, 25]: 5 s vor der Pause, 10 s danach, nichts dazwischen.
      expect(res.pace.liveCountedTime, const Duration(seconds: 15));
    });
  });
}
