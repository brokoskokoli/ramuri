import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/support.dart';

const trimp = EdwardsTrimp();
const zones = ReserveZones(reserve: HeartRateReserve());
const p = FitnessParameters.v4();
const basis = HeartRateBasis(maxBpm: 200, restingBpm: 50);

/// 3 m/s Position im 1-Hz-Raster von 0 bis [until], Puls zu den Sekunden, für
/// die [bpmAt] einen Wert liefert. Optional eine manuelle Pause.
RunPreprocessing record({
  required int until,
  required int? Function(int s) bpmAt,
  (int, int)? pause,
  PreprocessingParameters params = const PreprocessingParameters.v4(),
}) {
  final r = RunPreprocessor(start: t0, parameters: params);
  for (var s = 0; s <= until; s++) {
    if (pause != null && s == pause.$1) r.pause(at(s));
    if (pause != null && s == pause.$2) r.resume(at(s));
    if (pause == null || s < pause.$1 || s > pause.$2) {
      r.addPosition(pos(s, 3.0 * s));
    }
    final bpm = bpmAt(s);
    if (bpm != null) {
      r.addHeartRate(RawHeartRate(time: at(s), source: 'x', bpm: bpm));
    }
  }
  return r.result(at: at(until));
}

FitnessResult<TrimpResult> load(RunPreprocessing x) => trimp.compute(
  basis: basis,
  heartRate: x.heartRate,
  movement: x.movement,
  p: p,
);

SectionQuality quality(RunPreprocessing x, int until) => SectionQuality.assess(
  from: at(0),
  to: at(until),
  heartRate: x.heartRate,
  position: x.position,
  settlingIntervals: const [],
  parameters: x.parameters,
);

TrimpResult value(FitnessResult<TrimpResult> r) =>
    (r as FitnessAvailable<TrimpResult>).value;

void main() {
  group('Muster: 3 Werte, dann 9 s nichts (Befund 1)', () {
    final x = record(until: 600, bpmAt: (s) => s % 12 < 3 ? 150 : null);

    test(
      'keine Einzellücke über PAR-010, SectionQuality misst 75 % fehlend',
      () {
        expect(x.heartRate.gaps, isEmpty);
        expect(quality(x, 600).missingHeartRateShare, closeTo(0.75, 0.01));
      },
    );

    test('TRIMP: unter 80 % Abdeckung, nicht bewertet', () {
      final r = load(x);
      expect(r, isA<FitnessUnavailable<TrimpResult>>());
      expect(
        (r as FitnessUnavailable<TrimpResult>).reason,
        UnavailableReason.insufficientCoverage,
      );
    });

    test('Reservezonen zählen nur den Takt je Wert', () {
      final r = zones.timeInZones(
        basis: basis,
        heartRate: x.heartRate,
        movement: x.movement,
        p: p,
      );
      final v = (r as FitnessAvailable<ReserveZoneTimes>).value;
      expect(v.coveredMicros / v.movingMicros, closeTo(0.25, 0.01));
    });
  });

  group('Abdeckung nahe 80 % im Durchstich (1-Hz-Puls mit Aussetzern)', () {
    // Einzelne fehlende Sekunden: jede kostet genau eine Sekunde Abdeckung.
    FitnessResult<TrimpResult> dropping(int count) {
      final drop = <int>{
        for (var s = 5; s <= 595; s += 5) s, // 119 Stück
        1,
        2,
      }.take(count).toSet();
      return load(
        record(until: 600, bpmAt: (s) => drop.contains(s) ? null : 150),
      );
    }

    test('119 Sekunden fehlen: unvollständig bewertet', () {
      final v = value(dropping(119));
      expect(v.incomplete, isTrue);
      expect(v.coveredMicros, v.movingMicros - 119 * 1000000);
    });
    test('120 Sekunden fehlen (genau 80 %): unvollständig bewertet', () {
      final v = value(dropping(120));
      expect(v.coverage, 0.8);
      expect(v.incomplete, isTrue);
    });
    test('121 Sekunden fehlen: nicht bewertet', () {
      final r = dropping(121);
      expect(r, isA<FitnessUnavailable<TrimpResult>>());
      expect(
        (r as FitnessUnavailable<TrimpResult>).reason,
        UnavailableReason.insufficientCoverage,
      );
    });
  });

  group('Takt und Laufanfang (Befund 8)', () {
    test('stabiler 5-s-Takt: vollständig', () {
      final x = record(until: 600, bpmAt: (s) => s % 5 == 0 ? 150 : null);
      final v = value(load(x));
      expect(v.incomplete, isFalse);
      expect(v.coveredMicros, v.movingMicros);
    });

    test('lückenloser Lauf mit Puls erst ab Sekunde 1: vollständig', () {
      final x = record(until: 600, bpmAt: (s) => s >= 1 ? 150 : null);
      final v = value(load(x));
      expect(v.incomplete, isFalse);
      expect(v.points, closeTo(600 * 3 / 60, 1e-9));
    });

    test('Puls erst ab Sekunde 3: Sekunden 0 bis 2 fehlen', () {
      final x = record(until: 600, bpmAt: (s) => s >= 3 ? 150 : null);
      final v = value(load(x));
      expect(v.incomplete, isTrue);
      expect(v.coveredMicros, v.movingMicros - 3 * 1000000);
    });

    test('kurze Pause: alter Puls gilt nicht weiter, neuer rückwirkend', () {
      // Manuelle Pause 300..305 (keine Lücke über 10 s), alter Puls 100,
      // neuer Puls 180 erst ab 306.
      final x = record(
        until: 600,
        pause: (300, 305),
        bpmAt: (s) => s < 300
            ? 100
            : s >= 306
            ? 180
            : null,
      );
      expect(x.heartRate.gaps, isEmpty);
      final v = value(load(x));
      expect(v.movingMicros, 595 * 1000000);
      expect(v.incomplete, isFalse);
      // 300 s mit Gewicht 1 (50 %), 295 s mit Gewicht 5 (90 %).
      expect(v.points, closeTo((300 * 1 + 295 * 5) / 60, 1e-9));
    });
  });

  group('Fremde Parameterversion (Befund 2)', () {
    const v4 = PreprocessingParameters(parameterVersion: 9);
    final x = record(until: 60, bpmAt: (s) => 150, params: v4);

    test('TRIMP und Zonen: Eingaben fremder Version gegen den aktuellen Satz -> Fehler', () {
      expect(x.heartRate.parameterVersion, 9);
      expect(x.movement.parameterVersion, 9);
      expect(() => load(x), throwsArgumentError);
      expect(
        () => zones.timeInZones(
          basis: basis,
          heartRate: x.heartRate,
          movement: x.movement,
          p: p,
        ),
        throwsArgumentError,
      );
    });

    test('mit passendem fremdem Parametersatz läuft es, Ergebnis nennt dessen Version', () {
      final p4 = FitnessParameters(parameterVersion: 9);
      final r = trimp.compute(
        basis: basis,
        heartRate: x.heartRate,
        movement: x.movement,
        p: p4,
      );
      expect(r.parameterVersion, 9);
    });
  });
}
