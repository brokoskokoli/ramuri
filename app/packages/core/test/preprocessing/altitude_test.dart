import 'package:core/core.dart';
import 'package:test/test.dart';

import 'altitude_support.dart';
import 'support.dart';

AltitudeResult runAlt(
  List<RawAltitude> v, {
  PreprocessingParameters p = const PreprocessingParameters.v2(),
  num? until,
}) {
  final proc = AltitudeProcessor(p);
  v.forEach(proc.add);
  return proc.result(at: at(until ?? v.last.time.difference(t0).inSeconds));
}

/// Werte im Abstand von 40 s: jedes Medianfenster (30 s) enthält nur den
/// aktuellen Wert, geglättet == roh.
double? ascentOf(List<double> meters) =>
    runAlt([for (var i = 0; i < meters.length; i++) alt(i * 40, meters[i])])
        .ascentMeters;

String altFingerprint(AltitudeResult r) => [
  r.method,
  r.methodVersion,
  r.parameterVersion,
  r.ascentMeters,
  r.withoutVerticalAccuracy,
  r.medianMeters,
  r.processed.map((p) => '${p.state.name}/${p.reason?.name}').join(','),
  r.smoothed.map((s) => '${s.time}/${s.meters}').join(','),
].join('|');

void main() {
  group('PAR-013 Vertikalgenauigkeit', () {
    test('15 zählt, knapp darüber verworfen, null bleibt und wird gezählt', () {
      final r = runAlt([
        alt(0, 100, va: 15),
        alt(1, 100, va: 15.01),
        alt(2, 100, va: null),
      ]);
      expect(
        [for (final p in r.processed) '${p.state.name}/${p.reason?.name}'],
        ['present/null', 'discarded/verticalAccuracy', 'present/null'],
      );
      expect(r.acceptedValues, hasLength(2));
      expect(r.withoutVerticalAccuracy, 1);
      expect(r.method, 'altitude-filter');
      expect(r.parameterVersion, 2);
    });

    test('abweichender Parameter wirkt', () {
      const p = PreprocessingParameters(
        parameterVersion: 2,
        altitudeMaxVerticalAccuracyMeters: 4,
      );
      final r = runAlt([alt(0, 100, va: 5)], p: p);
      expect(r.processed.single.reason, DiscardReason.verticalAccuracy);
      expect(r.ascentMeters, isNull);
    });

    test(
      'Median 30 s: Fenstergrenze inklusive, danach fällt der Wert raus',
      () {
        final r = runAlt([alt(0, 100), alt(30, 110), alt(30.001, 130)]);
        // t=30: {100,110} -> 105; t=30.001: 100 liegt außerhalb, {110,130} -> 120.
        expect([for (final s in r.smoothed) s.meters], [100, 105, 120]);
        expect(runAlt([alt(0, 100), alt(30, 110)]).medianMeters, 105);
        expect(
          runAlt([alt(0, 100), alt(30, 110)], until: 30.001).medianMeters,
          110,
        );
      },
    );

    test('Sensorzustand unavailable und rückwärtige Zeit', () {
      final r = runAlt([
        alt(1, 100),
        alt(1, 101),
        alt(2, 100, state: MeasurementState.unavailable),
        alt(3, 100, state: MeasurementState.estimated),
      ]);
      expect(
        [for (final p in r.processed) p.state.name],
        ['present', 'discarded', 'unavailable', 'estimated'],
      );
      expect(r.processed[1].reason, DiscardReason.nonMonotonicTime);
    });
  });

  group('PAR-012 Aufstieg', () {
    test('knapp unter 3 zählt nicht, genau 3 und darüber zählen', () {
      expect(ascentOf([100, 102.9]), 0);
      expect(ascentOf([100, 103]), 3);
      expect(ascentOf([100, 103.1]), closeTo(3.1, 1e-9));
    });

    test('Referenz springt nach jedem Zählen: zweimal 3 ergibt 6', () {
      expect(ascentOf([100, 103, 106]), 6);
      // Referenz bleibt bei 100 (2 < 3), erst 104 zählt, mit 4 m: nichts geht verloren.
      expect(ascentOf([100, 102, 104]), 4);
    });

    test('Abstieg setzt die Referenz', () {
      expect(ascentOf([100, 90, 93]), 3);
      expect(
        ascentOf([100, 98, 96, 94]),
        0,
      ); // Abstieg < 3 je Schritt, 94 = 100-6
    });

    test('Abstieg um genau 3 setzt die Referenz', () {
      // Referenz 97, dann 100 = genau +3: zählt. Ohne Referenzwechsel wäre es 0.
      expect(ascentOf([100, 97, 100]), 3);
    });

    test('resume ohne Pause verwirft Fenster und Referenz nicht', () {
      final proc = AltitudeProcessor(const PreprocessingParameters.v2())
        ..add(alt(0, 100))
        ..resume()
        ..add(alt(40, 200));
      expect(proc.result(at: at(40)).ascentMeters, 100);
    });

    test('Rauschen unter 3 m ergibt 0, nicht null', () {
      expect(ascentOf([100, 102, 99, 101.5, 98.5, 102]), 0);
    });

    test('keine Höhenwerte ergibt null, auch wenn alle verworfen sind', () {
      expect(
        AltitudeProcessor(const PreprocessingParameters.v2())
            .result(at: at(0))
            .ascentMeters,
        isNull,
      );
      expect(runAlt([alt(0, 100, va: 99)]).ascentMeters, isNull);
    });

    test('ein einzelner Wert ergibt 0', () {
      expect(ascentOf([100]), 0);
    });

    test('abweichende Schwelle wirkt', () {
      const p = PreprocessingParameters(
        parameterVersion: 2,
        ascentThresholdMeters: 1,
      );
      final r = runAlt([alt(0, 100), alt(40, 101)], p: p);
      expect(r.ascentMeters, 1);
    });
  });

  test('Live == Gesamt je Präfix; Eingabe und Ergebnislisten unverändert', () {
    final input = [
      alt(0, 100),
      alt(10, 101, va: null),
      alt(20, 120, va: 30), // verworfen
      alt(25, 104),
      alt(25, 105), // gleiche Zeit
      alt(60, 109),
      alt(100, 100),
      alt(140, 104),
    ];
    final copy = [...input];
    final live = AltitudeProcessor(const PreprocessingParameters.v2());
    for (var i = 0; i < input.length; i++) {
      live.add(input[i]);
      final when = input[i].time.difference(t0).inSeconds + 3;
      expect(
        altFingerprint(live.result(at: at(when))),
        altFingerprint(runAlt(input.sublist(0, i + 1), until: when)),
        reason: 'Präfix $i',
      );
    }
    expect(input, copy);
    final r = live.result(at: at(150));
    expect(() => r.smoothed.add(r.smoothed.first), throwsUnsupportedError);
    expect(() => r.processed.clear(), throwsUnsupportedError);
  });

  test('altitudeAt: letzter Wert <= t mit Alter, ohne Altersgrenze', () {
    final proc = AltitudeProcessor(const PreprocessingParameters.v2())
      ..add(alt(0, 100))
      ..add(alt(5, 101, va: 99));
    final l = proc.altitudeAt(at(1000));
    expect(l.state, MeasurementState.present);
    expect(l.value!.meters, 100);
    expect(l.age, const Duration(seconds: 1000));
    expect(proc.altitudeAt(at(-1)).state, MeasurementState.unavailable);
  });
}
