import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('PAR-001 Genauigkeit', () {
    MeasurementState stateFor(double? acc) =>
        run([pos(0, 0, acc: acc)]).positions.single.state;

    test('knapp innerhalb (24,9) und genau 25 zählen', () {
      expect(stateFor(24.9), MeasurementState.present);
      expect(stateFor(25), MeasurementState.present);
    });
    test('knapp außerhalb (25,1) wird verworfen', () {
      final r = run([pos(0, 0, acc: 25.1)]);
      expect(r.positions.single.state, MeasurementState.discarded);
      expect(r.positions.single.reason, DiscardReason.accuracy);
      expect(r.acceptedPoints, isEmpty);
    });
    test('fehlende Genauigkeit (null) wird verworfen, nicht als 0 gelesen', () {
      final r = run([pos(0, 0, acc: null)]);
      expect(r.positions.single.reason, DiscardReason.accuracy);
    });
    test('abweichender Parameter wirkt (Schwelle 10)', () {
      const p = PreprocessingParameters(
        parameterVersion: currentParameterVersion,
        positionMaxAccuracyMeters: 10,
      );
      expect(run([pos(0, 0, acc: 10)], p: p).acceptedPoints, hasLength(1));
      expect(run([pos(0, 0, acc: 10.1)], p: p).acceptedPoints, isEmpty);
    });
  });

  group('PAR-002 harte Sprunggrenze (12,5 m/s)', () {
    test('12,4 m in 1 s innerhalb, 12,6 m außerhalb', () {
      // Genauigkeit 25: die weiche Grenze (Summe 50 m) greift nicht.
      expect(
        run([pos(0, 0, acc: 25), pos(1, 12.4, acc: 25)]).acceptedPoints,
        hasLength(2),
      );
      final r = run([pos(0, 0, acc: 25), pos(1, 12.6, acc: 25)]);
      expect(r.positions[1].reason, DiscardReason.hardJump);
    });
    test('genau die Grenze ist akzeptiert (Parameter = berechnete Geschwindigkeit)', () {
      final a = pos(0, 0, acc: 25), b = pos(1, 13, acc: 25);
      final v = dist(a, b) / 1;
      expect(
        run(
          [a, b],
          p: PreprocessingParameters(
            parameterVersion: currentParameterVersion,
            hardJumpMaxSpeed: v,
          ),
        ).acceptedPoints,
        hasLength(2),
      );
      expect(
        run(
          [a, b],
          p: PreprocessingParameters(
            parameterVersion: currentParameterVersion,
            hardJumpMaxSpeed: v - 1e-6,
          ),
        ).positions[1].reason,
        DiscardReason.hardJump,
      );
    });
    test('Sprung erhöht die Strecke nicht, danach geht es normal weiter', () {
      final r = run([pos(0, 0), pos(1, 5), pos(2, 500), pos(3, 10)]);
      expect(r.positions[2].reason, DiscardReason.hardJump);
      expect(r.distanceMeters, closeTo(10, 1e-6));
    });
    test(
      'Vergleich gegen den letzten akzeptierten Punkt, nicht den verworfenen',
      () {
        final r = run([pos(0, 0), pos(1, 500), pos(2, 8)]);
        expect(r.positions[2].state, MeasurementState.estimated);
        expect(r.acceptedPoints, hasLength(2));
      },
    );
  });

  group(
    'PAR-003 weiche Sprunggrenze (8 m/s und > Summe der Genauigkeiten)',
    () {
      test('9 m in 1 s bei je 5 m Genauigkeit (Summe 10): akzeptiert', () {
        expect(run([pos(0, 0), pos(1, 9)]).acceptedPoints, hasLength(2));
      });
      test('11 m in 1 s bei Summe 10: verworfen', () {
        final r = run([pos(0, 0), pos(1, 11)]);
        expect(r.positions[1].reason, DiscardReason.softJump);
      });
      test('genau die Summe der Genauigkeiten: akzeptiert (strikt >)', () {
        final a = pos(0, 0, acc: 5), b0 = pos(1, 10, acc: 5);
        final d = dist(a, b0);
        final b = pos(1, 10, acc: d / 2), a2 = pos(0, 0, acc: d / 2);
        expect(run([a2, b]).acceptedPoints, hasLength(2));
      });
      test(
        'Geschwindigkeit genau 8 m/s (Parameter) ist akzeptiert, darüber nicht',
        () {
          final a = pos(0, 0, acc: 1), b = pos(1, 9, acc: 1);
          final v = dist(a, b);
          expect(
            run(
              [a, b],
              p: PreprocessingParameters(
                parameterVersion: currentParameterVersion,
                softJumpSpeed: v,
              ),
            ).acceptedPoints,
            hasLength(2),
          );
          expect(
            run(
              [a, b],
              p: PreprocessingParameters(
                parameterVersion: currentParameterVersion,
                softJumpSpeed: v - 1e-6,
              ),
            ).positions[1].reason,
            DiscardReason.softJump,
          );
        },
      );
      test('schnell (9 m/s), aber unter der Genauigkeitssumme: akzeptiert', () {
        // 9 m/s > 8, aber Summe 40 m
        expect(
          run([pos(0, 0, acc: 20), pos(1, 9, acc: 20)]).acceptedPoints,
          hasLength(2),
        );
      });
      test('langsam (7 m/s), weit über der Summe: akzeptiert', () {
        expect(
          run([pos(0, 0, acc: 1), pos(1, 7, acc: 1)]).acceptedPoints,
          hasLength(2),
        );
      });
    },
  );

  group('Zeit und Eingabe', () {
    test('Zeit rückwärts oder gleich wird verworfen, ohne Sortierung', () {
      final r = run([pos(2, 0), pos(1, 5), pos(2, 6), pos(3, 3)]);
      expect(r.positions[1].reason, DiscardReason.nonMonotonicTime);
      expect(r.positions[2].reason, DiscardReason.nonMonotonicTime);
      expect(r.positions[3].state, MeasurementState.present);
      expect(r.distanceMeters, closeTo(3, 1e-6));
    });
    test(
      'Eingabeliste bleibt unverändert, Ergebnislisten sind unveränderlich',
      () {
        final input = [pos(0, 0), pos(1, 500), pos(2, 4)];
        final copy = [...input];
        final proc = processor();
        input.forEach(proc.add);
        final r = proc.result(at: at(2));
        expect(input, orderedEquals(copy));
        expect(
          () => r.positions.add(r.positions.first),
          throwsUnsupportedError,
        );
        expect(() => r.acceptedPoints.clear(), throwsUnsupportedError);
        expect(() => r.gaps.clear(), throwsUnsupportedError);
      },
    );
    test('Ergebnis trägt Verfahren, Version und Parameterversion', () {
      final r = run([pos(0, 0)]);
      expect(r.method, isNotEmpty);
      expect(r.methodVersion, 2);
      expect(r.parameterVersion, currentParameterVersion);
    });
  });
}
