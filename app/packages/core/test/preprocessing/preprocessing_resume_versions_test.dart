import 'package:core/core.dart';
import 'package:test/test.dart';

import 'hr_support.dart';
import 'motion_support.dart';
import 'support.dart';

void main() {
  group('Befund 9: Lookup behält den Zustand', () {
    test('überbrückte Position und geschätzter Puls sind estimated', () {
      final pos3 = processor()
        ..add(pos(0, 0))
        ..add(pos(1, 5, acc: 90))
        ..add(pos(2, 6));
      expect(pos3.positionAt(at(2)).state, MeasurementState.estimated);
      expect(pos3.positionAt(at(0)).state, MeasurementState.present);
      final h = HeartRateProcessor(const PreprocessingParameters.v4())
        ..add(hr(0, 100))
        ..add(hr(1, 101, state: MeasurementState.estimated));
      expect(h.heartRateAt(at(1)).state, MeasurementState.estimated);
      expect(h.heartRateAt(at(0)).state, MeasurementState.present);
    });
  });

  group('Befund 10: resume ohne Pause', () {
    test('Fortsetzen ohne Pause ändert nichts (Segment, Lücke ab Start)', () {
      final r = RunPreprocessor(start: t0);
      for (final x in track([(10, 3)])) {
        r.addPosition(x);
      }
      r.resume(at(10));
      for (final x in track([(10, 3)], from: 10, north: 30, first: false)) {
        r.addPosition(x);
      }
      // 20 Segmente; ein Reset hätte das Segment 10 -> 11 verschluckt.
      expect(r.result(at: at(20)).pace.medianSeries, hasLength(20));
      // Erster Punkt erst bei 30 s: Lücke ab Start t0, auch nach resume(25).
      final g = RunPreprocessor(start: t0)..resume(at(25));
      g.addPosition(pos(30, 0));
      expect(g.result(at: at(30)).position.gaps.single.start, t0);
    });

    test('doppeltes Fortsetzen verschluckt kein Segment', () {
      final r = RunPreprocessor(start: t0);
      r.pause(at(0));
      r.resume(at(1));
      for (final x in track([(5, 3)], from: 1)) {
        r.addPosition(x);
      }
      r.resume(at(4));
      for (final x in track([(5, 3)], from: 6, north: 15, first: false)) {
        r.addPosition(x);
      }
      expect(r.result(at: at(11)).pace.medianSeries, hasLength(10));
    });
  });

  group('Befund 10: Prozessoren allein', () {
    test('resume ohne Pause lässt die Lücke ab Start stehen', () {
      final p = processor(const PreprocessingParameters.v4(), t0)
        ..resume(at(25))
        ..add(pos(30, 0));
      expect(p.result(at: at(30)).gaps.single.start, t0);
      final h = HeartRateProcessor(
        const PreprocessingParameters.v4(),
        sectionStart: t0,
      )..resume(at(25));
      h.add(hr(30, 100));
      expect(h.result(at: at(30)).gaps.single.start, t0);
    });
  });

  group('Befund 11: Aussetzer des Sensors überbrückt', () {
    test('unavailable im Lauf: Folgepunkt estimated, Strecke überbrückt', () {
      final p = processor()
        ..add(pos(0, 0))
        ..add(pos(1, 3))
        ..add(pos(2, 6, state: MeasurementState.unavailable));
      final r = p.add(pos(3, 9));
      expect(r.state, MeasurementState.estimated);
      expect(r.countedDistanceMeters, closeTo(6, 0.01));
      expect(p.result(at: at(3)).bridgedDistanceMeters, closeTo(6, 0.01));
    });

    test('in der Pause zählt unavailable nicht als überbrückt', () {
      final p = processor()
        ..add(pos(0, 0))
        ..pause(at(1))
        ..add(pos(2, 6, state: MeasurementState.unavailable))
        ..resume(at(3));
      expect(p.add(pos(4, 12)).state, MeasurementState.present);
      expect(p.add(pos(5, 15)).state, MeasurementState.present);
    });
  });

  test('Befund 12: Bewegungszeit nie größer als die Gesamtzeit', () {
    final r = feed(track([(600, 3), (12, 0)]));
    for (final s in [0, 1, 300, 609, 610, 611, 612]) {
      final m = r.result(at: at(s)).movement;
      expect(m.movingTime <= m.totalTime, isTrue, reason: 'at $s');
    }
    // Pause bei 610: geschlossenes Intervall [0,610], Abfrage bei 300.
    final m = r.result(at: at(300)).movement;
    expect(m.totalTime, const Duration(seconds: 300));
    expect(m.movingTime, const Duration(seconds: 300));
    expect(m.movingIntervals.single.end, at(300));
  });

  test('Befund 12: Abfrage vor einem späteren geschlossenen Intervall', () {
    // Stand 100..112 (Pause bei 110), Wiederbeginn 115, Stand 212..222
    // (Pause bei 222): Intervalle [0,110], [115,222]. Abfrage bei 50.
    final r = feed(track([(100, 3), (12, 0), (100, 3), (12, 0), (100, 3)]))
        .result(at: at(50))
        .movement;
    expect(r.movingIntervals, hasLength(1));
    expect(r.movingTime, const Duration(seconds: 50));
  });

  group('Befund 13/14: Versionen, öffentlicher Konstruktor', () {
    const v4 = PreprocessingParameters(
      parameterVersion: 9,
      hardJumpMaxSpeed: 99,
    );

    test('abweichender Parametersatz trägt seine Version', () {
      final r = RunPreprocessor(start: t0, parameters: v4)
        ..addPosition(pos(0, 0));
      final res = r.result(at: at(1));
      expect(res.parameterVersion, 9);
      expect(res.position.parameterVersion, 9);
      expect(res.settling.parameterVersion, 9);
      expect(
        const PreprocessingParameters.v4().parameterVersion,
        currentParameterVersion,
      );
    });

    SectionQuality q(
      HeartRateResult h,
      PositionResult p,
      PreprocessingParameters pp,
    ) => SectionQuality.assess(
      from: at(0),
      to: at(10),
      heartRate: h,
      position: p,
      settlingIntervals: const [],
      parameters: pp,
    );

    test('assess übernimmt die Version, wirft bei Abweichung', () {
      final h4 = runHr(beat(0, 10, 100), p: v4);
      final p4 = run([pos(0, 0)], p: v4);
      expect(q(h4, p4, v4).parameterVersion, 9);
      final p3 = run([pos(0, 0)]);
      expect(() => q(h4, p3, v4), throwsArgumentError);
      expect(
        () => q(h4, p4, const PreprocessingParameters.v4()),
        throwsArgumentError,
      );
    });

    test('Bewertung lässt sich aus Werten wieder aufbauen', () {
      final a = q(
        runHr(beat(0, 10, 100)),
        run([pos(0, 0)]),
        const PreprocessingParameters.v4(),
      );
      final b = SectionQuality(
        parameterVersion: a.parameterVersion,
        from: a.from,
        to: a.to,
        heartRateCounts: a.heartRateCounts,
        positionCounts: a.positionCounts,
        missingHeartRateShare: a.missingHeartRateShare,
        longestHeartRateGap: a.longestHeartRateGap,
        meetsHeartRateGapRule: a.meetsHeartRateGapRule,
        settlingOverlap: a.settlingOverlap,
        settlingShare: a.settlingShare,
        gpsGaps: a.gpsGaps,
      );
      expect(b.heartRateCounts, a.heartRateCounts);
      expect(
        () => b.heartRateCounts[MeasurementState.present] = 0,
        throwsUnsupportedError,
      );
    });
  });

  test('Befund 15: ohne akzeptierten Punkt ist die Strecke null', () {
    expect(run([], until: 0).distanceMeters, isNull);
    expect(run([pos(0, 0, acc: 90)], until: 0).distanceMeters, isNull);
    expect(run([pos(0, 0)], until: 0).distanceMeters, 0);
  });

  group('PAR-010 Takt ohne nichtmonotone Werte (Runde 1b D2)', () {
    test('verworfene Zeit-Rückläufer senken den Takt nicht', () {
      // 10-s-Sensor 0..100, nach 50 kommen 41..49 (nichtmonoton).
      final values = [
        for (var s = 0; s <= 50; s += 10) hr(s, 100),
        for (var s = 41; s <= 49; s++) hr(s, 100),
        for (var s = 60; s <= 100; s += 10) hr(s, 100),
      ];
      final qual = SectionQuality.assess(
        from: at(0),
        to: at(100),
        heartRate: runHr(values),
        position: run([pos(0, 0)]),
        settlingIntervals: const [],
        parameters: const PreprocessingParameters.v4(),
      );
      expect(qual.missingHeartRateShare, 0);
      expect(qual.meetsHeartRateGapRule, isTrue);
    });
  });

  group('PAR-009 Fenster [t-30 s, t] (Runde 1b D1)', () {
    test('verworfener Wert aus der Zukunft stützt den Median nicht', () {
      // 35 bei 0, dann 240 bei 10 (Rate 20,5 > 5, Median 137,5: Ausreißer).
      // 150 bei 1: Fenster [-29, 1] = {35, 150}, Median 92,5, Abweichung
      // 57,5 > 25, Rate 115 > 5: Ausreißer. Mit dem 240er im Fenster wäre
      // der Median 150 und 150 bliebe.
      final r = runHr([hr(0, 35), hr(10, 240), hr(1, 150)]);
      expect(verdicts(r), [
        'present/null',
        'discarded/heartRateOutlier',
        'discarded/heartRateOutlier',
      ]);
    });

    test('Sprung um 90 bpm: erst der Median gibt das Plateau frei', () {
      // 100 bis 29, danach 190. Bei k s nach 30 hat das Fenster 30-k mal 100
      // und k+1 mal 190: Median 190 ab k = 15. Die Rate 90/s gegen 29 s wäre erst
      // nach 18 s (bei 47) nicht mehr über 5. Erster akzeptierter Wert: Index 45.
      final v = verdicts(runHr([...beat(0, 29, 100), ...beat(30, 80, 190)]));
      expect(v.sublist(30, 45), everyElement('discarded/heartRateOutlier'));
      expect(v.sublist(45), everyElement('present/null'));
    });
  });
}
