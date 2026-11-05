import 'package:core/core.dart';
import 'package:test/test.dart';

import 'hr_support.dart';

void main() {
  group('PAR-007 absolute Plausibilität', () {
    // Je Wert eigener Lauf, damit PAR-009 (Sprung) nicht mitspielt.
    String one(int bpm, [PreprocessingParameters? p]) => verdicts(
      runHr([hr(0, bpm)], p: p ?? const PreprocessingParameters.v3()),
    ).single;

    test('30 und 240 gelten, 29 und 241 nicht', () {
      expect(one(29), 'discarded/implausibleHeartRate');
      expect(one(30), 'present/null');
      expect(one(240), 'present/null');
      expect(one(241), 'discarded/implausibleHeartRate');
    });

    test('abweichende Grenzen im Parametersatz wirken', () {
      const p = PreprocessingParameters(
        parameterVersion: 3,
        heartRateMin: 50,
        heartRateMax: 200,
      );
      expect(one(49, p), 'discarded/implausibleHeartRate');
      expect(one(50, p), 'present/null');
      expect(one(200, p), 'present/null');
      expect(one(201, p), 'discarded/implausibleHeartRate');
    });
  });

  group('PAR-008 Hautkontakt', () {
    test('poor verworfen, good und unsupported gelten', () {
      final r = runHr([
        hr(0, 100, contact: SensorContact.poor),
        hr(1, 100, contact: SensorContact.good),
        hr(2, 100, contact: SensorContact.unsupported),
      ]);
      expect(verdicts(r), [
        'discarded/noContact',
        'present/null',
        'present/null',
      ]);
    });

    test('Reihenfolge: unplausibel vor Kontakt', () {
      final r = runHr([hr(0, 20, contact: SensorContact.poor)]);
      expect(verdicts(r), ['discarded/implausibleHeartRate']);
    });
  });

  group('PAR-009 Ausreißer', () {
    // 100 bpm im Sekundentakt, danach ein Kandidat.
    List<RawHeartRate> base() => beat(0, 4, 100);

    test('Abweichung genau 25 bleibt, über 25 fällt (Rate 25 bpm/s)', () {
      expect(verdicts(runHr([...base(), hr(5, 125)])).last, 'present/null');
      expect(
        verdicts(runHr([...base(), hr(5, 126)])).last,
        'discarded/heartRateOutlier',
      );
    });

    test('Rate genau 5 bleibt, über 5 fällt (Abweichung über 25)', () {
      // Letzter akzeptierter Wert bei 4 s; 6 s später 130 bzw. 131.
      expect(verdicts(runHr([...base(), hr(10, 130)])).last, 'present/null');
      expect(
        verdicts(runHr([...base(), hr(10, 131)])).last,
        'discarded/heartRateOutlier',
      );
    });

    test('Nach unten gilt dasselbe (Betrag)', () {
      expect(
        verdicts(runHr([...beat(0, 4, 150), hr(5, 124)])).last,
        'discarded/heartRateOutlier',
      );
      expect(
        verdicts(runHr([...beat(0, 4, 150), hr(5, 125)])).last,
        'present/null',
      );
    });

    test('Erster Wert wird akzeptiert', () {
      expect(verdicts(runHr([hr(0, 200)])), ['present/null']);
    });

    test('Einzel-Ausreißer wird verworfen, danach geht es normal weiter', () {
      final r = runHr([...base(), hr(5, 190), hr(6, 100), hr(7, 100)]);
      expect(verdicts(r).skip(5), [
        'discarded/heartRateOutlier',
        'present/null',
        'present/null',
      ]);
    });

    test('Kurzes Plateau wird verworfen', () {
      final r = runHr([...beat(0, 29, 100), ...beat(30, 36, 170)]);
      expect(verdicts(r).skip(30), everyElement('discarded/heartRateOutlier'));
    });

    test('Dauerhafter Wechsel sperrt nicht für immer', () {
      final r = runHr([...beat(0, 29, 100), ...beat(30, 80, 170)]);
      final v = verdicts(r);
      expect(v[30], 'discarded/heartRateOutlier');
      expect(v.last, 'present/null');
      // 100 -> 170: Die Rate 70/s gegen den letzten akzeptierten Wert (bei
      // 29 s) fällt 14 s später, bei 43 s, auf 5 bpm/s (nicht darüber) und
      // gibt frei; der Median kippt erst bei 45 s.
      final firstOk = v.indexOf('present/null', 30);
      expect(firstOk, 43);
      expect(v.skip(firstOk), everyElement('present/null'));
    });

    test('Echter Anstieg über Zeit bleibt', () {
      // 100 -> 160 in 60 s (1 bpm/s).
      final r = runHr([for (var s = 0; s <= 60; s++) hr(s, 100 + s)]);
      expect(verdicts(r), everyElement('present/null'));
    });

    test('Fenster 30 s ist inklusive; ältere Werte zählen nicht', () {
      // Rate-Grenze 0 isoliert die Fensterfrage: 130 bei 30 s gegen {100, 160,
      // 160, 130} (Median 145, Abweichung 15) bleibt; eine Mikrosekunde später
      // fällt der 100er heraus (Median 160, Abweichung 30) und 130 fällt.
      const p = PreprocessingParameters(
        parameterVersion: 3,
        heartRateOutlierRate: 0,
      );
      final head = [hr(0, 100), hr(1, 160), hr(2, 160)];
      expect(
        verdicts(runHr([...head, hr(30, 130)], p: p)).last,
        'present/null',
      );
      expect(
        verdicts(runHr([...head, hr(30.000001, 130)], p: p)).last,
        'discarded/heartRateOutlier',
      );
    });

    test('verworfene Werte aus PAR-007/008 gehen nicht in den Median ein', () {
      // Wären die zwei Nullen (unplausibel) im Fenster, läge der Median bei
      // 50 und 100 wäre Ausreißer.
      final r = runHr([
        hr(0, 100),
        hr(1, 0),
        hr(2, 0),
        hr(3, 5, contact: SensorContact.poor),
        hr(4, 100),
      ]);
      expect(verdicts(r).last, 'present/null');
    });
  });

  group('PAR-006 Median-Puls', () {
    test('Fenstergrenze 30 s ist inklusive', () {
      final r = runHr([hr(0, 100), hr(10, 110), hr(30, 120)]);
      // [0, 30] enthält alle drei: Median 110.
      expect(r.medianBpm, 110);
      // Eine Mikrosekunde später fällt der erste heraus: Mittel von 110/120.
      final later = runHr([
        hr(0, 100),
        hr(10, 110),
        hr(30, 120),
      ], until: 30.000001);
      expect(later.medianBpm, 115);
    });

    test('Reihe je akzeptiertem Wert, nachlaufend; ohne Werte null', () {
      final r = runHr([hr(0, 100), hr(1, 102), hr(2, 104)]);
      expect(r.medianSeries.map((s) => s.bpm), [100, 101, 102]);
      expect(runHr([]).medianBpm, isNull);
    });
  });
}
