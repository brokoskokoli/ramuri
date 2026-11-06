import 'package:core/core.dart';
import 'package:test/test.dart';

import '../preprocessing/support.dart';

const trimp = EdwardsTrimp();
const p = FitnessParameters.v4();
const basis = HeartRateBasis(maxBpm: 200);

/// Lauf mit 3 m/s Position im 1-Hz-Raster, manueller Pause 300..330 s und
/// Puls (150 bpm) in den Sekunden [hrFrom, hrTo]; Auswertung bei 600 s. Der
/// Puls läuft auch durch die Pause (dort ist er „nicht verfügbar“).
RunPreprocessing record(int hrFrom, int hrTo) {
  final r = RunPreprocessor(start: t0);
  for (var s = 0; s <= 600; s++) {
    if (s == 300) r.pause(at(300));
    if (s == 330) r.resume(at(330));
    if (s < 300 || s > 330) r.addPosition(pos(s, 3.0 * s));
    if (s >= hrFrom && s <= hrTo) {
      r.addHeartRate(RawHeartRate(time: at(s), source: 'x', bpm: 150));
    }
  }
  return r.result(at: at(600));
}

FitnessResult<TrimpResult> compute(RunPreprocessing x) => trimp.compute(
  basis: basis,
  heartRate: x.heartRate,
  movement: x.movement,
  p: p,
);

void main() {
  test('Vorverarbeitung liefert Bewegungszeit 0..300 und 330..600', () {
    final x = record(0, 600);
    expect(x.movement.movingTime, const Duration(seconds: 570));
  });

  test('Puls startet spät und fällt am Ende aus: unvollständig', () {
    // Puls 40..559. Lücken aus der Vorverarbeitung: 0..40 und 559..600.
    // Abgedeckt: 40..300 (260 s) + 330..559 (229 s) = 489 s von 570 s.
    final x = record(40, 559);
    expect(x.heartRate.gaps.map((g) => g.start), [at(0), at(559)]);
    final v = (compute(x) as FitnessAvailable<TrimpResult>).value;
    expect(v.movingMicros, 570 * 1000000);
    expect(v.coveredMicros, 489 * 1000000);
    expect(v.incomplete, isTrue);
    expect(v.coverage, closeTo(489 / 570, 1e-12));
    // 150 bpm = 75 % von 200: Gewicht 3. 489 s * 3 / 60 s = 24,45.
    expect(v.points, closeTo(24.45, 1e-9));
  });

  test('Puls zu spät und zu früh weg: unter 80 %, nicht bewertet', () {
    // Abgedeckt: 60..300 + 330..539 = 449 s von 570 s = 78,8 %.
    final r = compute(record(60, 539));
    expect(
      (r as FitnessUnavailable<TrimpResult>).reason,
      UnavailableReason.insufficientCoverage,
    );
  });

  test('lückenloser 1-Hz-Puls: nicht unvollständig', () {
    final x = record(0, 600);
    expect(x.heartRate.gaps, isEmpty);
    final v = (compute(x) as FitnessAvailable<TrimpResult>).value;
    expect(v.incomplete, isFalse);
    expect(v.coveredMicros, v.movingMicros);
    expect(v.points, closeTo(570 * 3 / 60, 1e-9));
  });

  test('Lauf ohne Puls: nicht bewertet', () {
    final r = compute(record(1, 0));
    expect(
      (r as FitnessUnavailable<TrimpResult>).reason,
      UnavailableReason.noHeartRate,
    );
  });
}
