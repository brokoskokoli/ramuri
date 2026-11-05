import 'package:core/core.dart';
import 'package:test/test.dart';

import 'hr_support.dart';
import 'support.dart';

final PositionResult noPosition = run([pos(0, 0)]);

SectionQuality assess(
  List<RawHeartRate> values,
  num from,
  num to, {
  List<TimeSpan> settling = const [],
  PositionResult? position,
}) => SectionQuality.assess(
  from: at(from),
  to: at(to),
  heartRate: runHr(values, until: to),
  position: position ?? noPosition,
  settlingIntervals: settling,
  parameters: const PreprocessingParameters.v3(),
);

/// 0..[to] im Sekundentakt ohne die Sekunden in [skip].
List<RawHeartRate> without(int to, Iterable<int> skip) => [
  for (var s = 0; s <= to; s++)
    if (!skip.contains(s)) hr(s, 100),
];

void main() {
  group('PAR-010 Anteil fehlender Zeit (höchstens 5 %)', () {
    test('genau 5 % zählt', () {
      final q = assess(without(100, [40, 41, 42, 43, 44]), 0, 100);
      expect(q.missingHeartRateShare, 0.05);
      expect(q.longestHeartRateGap, const Duration(seconds: 6));
      expect(q.meetsHeartRateGapRule, isTrue);
    });

    test('knapp darüber fällt (Einzellücken klein)', () {
      final q = assess(without(100, [40, 41, 42, 43, 44]), 0, 99.99);
      expect(q.missingHeartRateShare, greaterThan(0.05));
      expect(q.longestHeartRateGap, lessThan(const Duration(seconds: 10)));
      expect(q.meetsHeartRateGapRule, isFalse);
    });

    test('viele kurze Lücken summieren sich', () {
      final q = assess(without(100, [10, 20, 30, 40, 50, 60]), 0, 100);
      expect(q.missingHeartRateShare, 0.06);
      expect(q.longestHeartRateGap, const Duration(seconds: 2));
      expect(q.meetsHeartRateGapRule, isFalse);
    });

    test('Anfang und Ende des Abschnitts zählen mit', () {
      final q = assess([for (var s = 20; s <= 80; s++) hr(s, 100)], 0, 100);
      expect(q.missingHeartRateShare, closeTo(0.38, 1e-12));
      expect(q.longestHeartRateGap, const Duration(seconds: 20));
    });

    test('Werte außerhalb des Abschnitts zählen nicht', () {
      final q = assess(beat(0, 200, 100), 50, 100);
      expect(q.missingHeartRateShare, 0);
      expect(q.heartRateCounts[MeasurementState.present], 51);
    });
  });

  group('PAR-010 Einzellücke (höchstens 10 s)', () {
    test('genau 10 s zählt', () {
      final q = assess(
        without(200, [for (var s = 91; s < 100; s++) s]),
        0,
        200,
      );
      expect(q.longestHeartRateGap, const Duration(seconds: 10));
      expect(q.missingHeartRateShare, closeTo(9 / 200, 1e-12));
      expect(q.meetsHeartRateGapRule, isTrue);
    });

    test('knapp darüber fällt, obwohl der Anteil klein bleibt', () {
      final values = [
        ...beat(0, 90, 100),
        for (var s = 100; s <= 200; s++) hr(s + 0.001, 100),
      ];
      final q = assess(values, 0, 201);
      expect(
        q.longestHeartRateGap,
        const Duration(seconds: 10, milliseconds: 1),
      );
      expect(q.missingHeartRateShare, lessThan(0.05));
      expect(q.meetsHeartRateGapRule, isFalse);
    });

    test('ohne Pulsdaten: Anteil 1,0, Lücke über den ganzen Abschnitt', () {
      final q = assess([], 0, 60);
      expect(q.missingHeartRateShare, 1.0);
      expect(q.longestHeartRateGap, const Duration(seconds: 60));
      expect(q.meetsHeartRateGapRule, isFalse);
      expect(q.heartRateCounts.values, everyElement(0));
    });

    test('nur verworfene Werte gelten als ohne Pulsdaten', () {
      final q = assess(
        [hr(1, 250), hr(2, 100, contact: SensorContact.poor)],
        0,
        60,
      );
      expect(q.missingHeartRateShare, 1.0);
      expect(q.heartRateCounts[MeasurementState.discarded], 2);
    });

    test('ein einzelner Wert reicht nicht: kein Takt, alles fehlt', () {
      final q = assess([hr(50, 100)], 0, 100);
      expect(q.missingHeartRateShare, 1.0);
    });
  });

  group('PAR-011 Einschwingzeit im Abschnitt', () {
    final settling = [TimeSpan(start: t0, end: at(180))];

    test('Abschnitt außerhalb: keine Überlappung', () {
      final q = assess(beat(200, 300, 100), 200, 300, settling: settling);
      expect(q.overlapsSettling, isFalse);
      expect(q.settlingOverlap, Duration.zero);
      expect(q.settlingShare, 0);
    });

    test('Abschnitt teils darin: Dauer und Anteil', () {
      final q = assess(beat(100, 200, 100), 100, 200, settling: settling);
      expect(q.overlapsSettling, isTrue);
      expect(q.settlingOverlap, const Duration(seconds: 80));
      expect(q.settlingShare, 0.8);
    });

    test('Berührung an der Grenze ist keine Überlappung', () {
      final q = assess(beat(180, 240, 100), 180, 240, settling: settling);
      expect(q.overlapsSettling, isFalse);
    });

    test('mehrere Zeiträume addieren sich', () {
      final q = assess(
        beat(0, 400, 100),
        0,
        400,
        settling: [
          TimeSpan(start: at(0), end: at(100)),
          TimeSpan(start: at(300), end: at(350)),
        ],
      );
      expect(q.settlingOverlap, const Duration(seconds: 150));
    });
  });

  group('GPS-Lücken und Zustände im Abschnitt', () {
    final gappy = run([
      for (var s = 0; s <= 10; s++) pos(s, s * 3),
      for (var s = 40; s <= 50; s++) pos(s, s * 3),
    ]);

    test('Lücke im Abschnitt wird gemeldet, außerhalb nicht', () {
      expect(
        assess(beat(5, 20, 100), 5, 20, position: gappy).gpsGaps,
        hasLength(1),
      );
      expect(assess(beat(0, 8, 100), 0, 8, position: gappy).gpsGaps, isEmpty);
      expect(
        assess(beat(45, 50, 100), 45, 50, position: gappy).gpsGaps,
        isEmpty,
      );
    });

    test('alle vier Zustände kommen an, getrennt für Puls und Position', () {
      final position = run([
        pos(0, 0),
        pos(1, 3, state: MeasurementState.estimated),
        pos(2, 6, acc: 100),
        pos(3, 9, state: MeasurementState.unavailable),
      ]);
      final values = [
        hr(0, 100),
        hr(1, 100, state: MeasurementState.estimated),
        hr(2, 250),
        hr(3, 100, state: MeasurementState.unavailable),
      ];
      final q = assess(values, 0, 3, position: position);
      const each = {
        MeasurementState.present: 1,
        MeasurementState.estimated: 1,
        MeasurementState.discarded: 1,
        MeasurementState.unavailable: 1,
      };
      expect(q.heartRateCounts, each);
      expect(q.positionCounts, each);
      expect(
        () => q.heartRateCounts[MeasurementState.present] = 0,
        throwsUnsupportedError,
      );
    });

    test('Abschnitt ohne Dauer ist ein Fehler', () {
      expect(() => assess([], 5, 5), throwsArgumentError);
    });

    test('Verfahren und Versionen', () {
      final q = assess(beat(0, 10, 100), 0, 10);
      expect(
        [q.method, q.methodVersion, q.parameterVersion],
        ['section-quality', 1, 3],
      );
    });
  });

  test('über RunPreprocessor: Ergebnis kommt mit allen Teilen an', () {
    final run = RunPreprocessor(start: t0);
    for (var s = 0; s <= 300; s++) {
      run.addPosition(pos(s, s * 3.0));
      run.addHeartRate(hr(s, 120));
    }
    final r = run.result(at: at(300));
    final q = r.assessSection(at(200), at(300));
    expect(q.meetsHeartRateGapRule, isTrue);
    expect(q.overlapsSettling, isFalse);
    expect(q.positionCounts[MeasurementState.present], 101);
    expect(r.assessSection(at(100), at(300)).overlapsSettling, isTrue);
    expect(r.heartRate.averageBpm, 120);
  });
}
