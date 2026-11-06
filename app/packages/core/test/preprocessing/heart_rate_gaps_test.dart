import 'package:core/core.dart';
import 'package:test/test.dart';

import 'hr_support.dart';
import 'support.dart';

void main() {
  group('PAR-010 Lücken ohne Interpolation (FR-0056)', () {
    test('Lücke senkt den Durchschnitt nicht, keine Null, keine Füllung', () {
      // 10 x 100, 30 s Pause im Signal, 10 x 120: Mittel genau 110.
      final r = runHr([...beat(0, 9, 100), ...beat(40, 49, 120)]);
      expect(r.averageBpm, 110);
      expect(r.maxBpm, 120);
      expect(r.acceptedValues, hasLength(20));
      expect(r.processed, hasLength(20));
      expect(r.acceptedValues.map((v) => v.bpm), isNot(contains(0)));
      expect(r.gaps, hasLength(1));
      expect(r.gaps.single.start, at(9));
      expect(r.gaps.single.end, at(40));
      expect(r.gaps.single.state, MeasurementState.unavailable);
    });

    test('ohne Werte sind Mittel, Maximum und Median null, nie 0', () {
      final r = runHr([hr(0, 20), hr(1, 100, contact: SensorContact.poor)]);
      expect(r.averageBpm, isNull);
      expect(r.maxBpm, isNull);
      expect(r.medianBpm, isNull);
      expect(r.acceptedValues, isEmpty);
    });

    test('Lücke erst über 10 s: genau 10 s wird überbrückt', () {
      expect(runHr([hr(0, 100), hr(10, 100)]).gaps, isEmpty);
      expect(runHr([hr(0, 100), hr(10.000001, 100)]).gaps, hasLength(1));
    });

    test('offene Lücke am Ende und vor dem ersten Wert', () {
      final r = runHr([hr(0, 100)], until: 11);
      expect(r.gaps.single.open, isTrue);
      expect(r.gaps.single.start, at(0));
      final first = runHr([hr(12, 100)], sectionStart: t0);
      expect(first.gaps.single.start, t0);
      expect(first.gaps.single.end, at(12));
    });

    test('Zuordnung über Zeitstempel: zu alter Wert ist nicht verfügbar', () {
      final proc = HeartRateProcessor(const PreprocessingParameters.v4());
      proc.add(hr(0, 100));
      expect(proc.heartRateAt(at(10)).state, MeasurementState.present);
      expect(proc.heartRateAt(at(10.5)).state, MeasurementState.unavailable);
    });

    test('Pausenzeit ist keine Lücke, Werte in der Pause zählen nicht', () {
      final proc = HeartRateProcessor(const PreprocessingParameters.v4());
      proc.add(hr(0, 100));
      proc.pause(at(5));
      expect(proc.add(hr(6, 100)).state, MeasurementState.unavailable);
      proc.resume(at(60));
      proc.add(hr(61, 100));
      expect(proc.result(at: at(62)).gaps, isEmpty);
    });
  });

  group('Vier Zustände (FR-0057) und Zeit', () {
    test('present, estimated, discarded, unavailable kommen an', () {
      final r = runHr([
        hr(0, 100),
        hr(1, 100, state: MeasurementState.estimated),
        hr(2, 250),
        hr(3, 100, state: MeasurementState.unavailable),
      ]);
      expect(r.processed.map((p) => p.state), [
        MeasurementState.present,
        MeasurementState.estimated,
        MeasurementState.discarded,
        MeasurementState.unavailable,
      ]);
      expect(r.acceptedValues, hasLength(2));
    });

    test('Zeit nicht größer als die letzte: verworfen, nonMonotonicTime', () {
      final r = runHr([hr(5, 100), hr(5, 100), hr(4, 100), hr(6, 100)]);
      expect(verdicts(r), [
        'present/null',
        'discarded/nonMonotonicTime',
        'discarded/nonMonotonicTime',
        'present/null',
      ]);
    });
  });

  group('Live = Gesamt je Präfix, Eingabe unverändert', () {
    List<RawHeartRate> mixed() => [
      ...beat(0, 20, 100),
      hr(21, 200),
      hr(22, 25),
      hr(23, 100, contact: SensorContact.poor),
      ...beat(24, 30, 105),
      hr(60, 110),
      hr(61, 110, state: MeasurementState.estimated),
    ];

    test('nach jedem Präfix gleicht result dem Neuaufbau', () {
      final values = mixed();
      final live = HeartRateProcessor(const PreprocessingParameters.v4());
      for (var i = 0; i < values.length; i++) {
        live.add(values[i]);
        final now = values[i].time;
        final whole = HeartRateProcessor(const PreprocessingParameters.v4());
        values.take(i + 1).forEach(whole.add);
        expect(
          hrFingerprint(live.result(at: now)),
          hrFingerprint(whole.result(at: now)),
          reason: 'Präfix $i',
        );
      }
    });

    test('Eingabeliste und Ergebnislisten bleiben unverändert', () {
      final values = mixed();
      final copy = [...values];
      final r = runHr(values);
      expect(values, orderedEquals(copy));
      expect(() => r.processed.add(r.processed.first), throwsUnsupportedError);
      expect(() => r.gaps.clear(), throwsUnsupportedError);
      expect(() => r.medianSeries.clear(), throwsUnsupportedError);
    });

    test('Ergebnis trägt Verfahren und Versionen', () {
      final r = runHr([hr(0, 100)]);
      expect(
        [r.method, r.methodVersion, r.parameterVersion],
        ['heart-rate-filter', 1, currentParameterVersion],
      );
    });
  });
}
