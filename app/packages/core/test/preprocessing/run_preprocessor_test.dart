import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Ereignis eines Laufs: Punkt, Pause oder Fortsetzen.
typedef Step = ({RawPosition? point, DateTime? pause, DateTime? resume});

Step p(RawPosition x) => (point: x, pause: null, resume: null);
Step pa(num s) => (point: null, pause: at(s), resume: null);
Step re(num s) => (point: null, pause: null, resume: at(s));

RunPreprocessor apply(List<Step> steps) {
  final r = RunPreprocessor(start: t0);
  for (final s in steps) {
    if (s.point != null) r.addPosition(s.point!);
    if (s.pause != null) r.pause(s.pause!);
    if (s.resume != null) r.resume(s.resume!);
  }
  return r;
}

void main() {
  test('Parametersatz v3 trägt alle Startwerte PAR-001..015', () {
    const v = PreprocessingParameters.v3();
    expect(v.parameterVersion, 3);
    expect(v.positionMaxAccuracyMeters, 25);
    expect(v.hardJumpMaxSpeed, 12.5);
    expect(v.softJumpSpeed, 8);
    expect(v.gapMaxDuration, const Duration(seconds: 10));
    expect(v.liveSmoothingWindow, const Duration(seconds: 20));
    expect(v.liveMinData, const Duration(seconds: 5));
    expect(v.selectionMedianWindow, const Duration(seconds: 30));
    expect([v.heartRateMin, v.heartRateMax], [30, 240]);
    expect(v.heartRateDiscardPoorContact, isTrue);
    expect(v.heartRateOutlierDeviation, 25);
    expect(v.heartRateOutlierRate, 5);
    expect(v.heartRateOutlierWindow, const Duration(seconds: 30));
    expect(v.heartRateMaxMissingShare, 0.05);
    expect(v.heartRateMaxSingleGap, const Duration(seconds: 10));
    expect(v.settlingDuration, const Duration(minutes: 3));
    expect(v.settlingPaceWindow, const Duration(minutes: 2));
    expect(v.settlingPaceChange, 0.25);
    expect(v.ascentThresholdMeters, 3);
    expect(v.altitudeMedianWindow, const Duration(seconds: 30));
    expect(v.altitudeMaxVerticalAccuracyMeters, 15);
    expect([v.standstillBelow, v.movementFrom], [0.5, 0.8]);
    expect(v.standstillMinDuration, const Duration(seconds: 10));
    expect(v.resumeMinDuration, const Duration(seconds: 3));
  });

  test('alle vier Zustände sind unterscheidbar', () {
    final r = apply([
      p(pos(0, 0)),
      p(pos(1, 2)), // vorhanden
      p(pos(2, 4, acc: 90)), // verworfen
      p(pos(3, 6)), // geschätzt (überbrückt)
      pa(4),
      p(pos(5, 8)), // nicht verfügbar (Pause)
    ]);
    final states = r.result(at: at(5)).position.positions.map((e) => e.state);
    expect(states, [
      MeasurementState.present,
      MeasurementState.present,
      MeasurementState.discarded,
      MeasurementState.estimated,
      MeasurementState.unavailable,
    ]);
    expect(states.toSet(), hasLength(4));
  });

  test('RunPreprocessor meldet Versionen und ordnet über Zeitstempel zu', () {
    final r = apply([p(pos(0, 0)), p(pos(1, 1))]);
    final res = r.result(at: at(1));
    expect(res.parameterVersion, 3);
    expect(res.position.parameterVersion, 3);
    expect(r.positionAt(at(3)).age, const Duration(seconds: 2));
  });

  test('Live == Gesamt je Präfix (Punkte, Sprünge, Lücke, Pause)', () {
    final steps = <Step>[
      p(pos(0, 0)),
      p(pos(1, 3)),
      p(pos(2, 600)), // Sprung
      p(pos(2, 5, acc: null)), // Zeit rückwärts/gleich und ohne Genauigkeit
      p(pos(3, 6)),
      p(pos(4, 8, acc: 90)),
      p(pos(5, 10)), // überbrückt
      p(pos(20, 40)), // Lücke
      pa(21),
      p(pos(22, 41)), // Pause
      re(30),
      p(pos(31, 900)),
      p(pos(32, 903)),
      p(pos(50, 910)), // Lücke
    ];
    final live = RunPreprocessor(start: t0);
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      if (s.point != null) live.addPosition(s.point!);
      if (s.pause != null) live.pause(s.pause!);
      if (s.resume != null) live.resume(s.resume!);
      for (final q in [0, 5, 100]) {
        final when = at(
          (s.point?.time ?? s.pause ?? s.resume!).difference(t0).inSeconds + q,
        );
        final whole = apply(steps.sublist(0, i + 1)).result(at: when);
        expect(
          fingerprint(live.result(at: when).position),
          fingerprint(whole.position),
          reason: 'Präfix $i, +$q s',
        );
      }
    }
  });

  test('Abfrage mitten im Lauf verändert spätere Ergebnisse nicht', () {
    final a = apply([p(pos(0, 0)), p(pos(1, 3)), p(pos(2, 5))]);
    final b = RunPreprocessor(start: t0);
    for (final x in [pos(0, 0), pos(1, 3), pos(2, 5)]) {
      b.addPosition(x);
      b.result(at: at(500));
    }
    expect(
      fingerprint(b.result(at: at(2)).position),
      fingerprint(a.result(at: at(2)).position),
    );
  });
}
