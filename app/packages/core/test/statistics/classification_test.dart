import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Lauf mit Durchschnittspace [pace] s/km (1 km Strecke).
RunFigures withPace(int id, String day, double pace, {int hour = 12}) =>
    figures(id, day, km: 1, paceSec: pace.round(), hour: hour);

void main() {
  group('Einordnung gegenüber vorherigen Läufen (OQ-0037)', () {
    final prev = [
      for (var i = 0; i < 7; i++)
        withPace(
          i + 1,
          '2030-01-${(i + 1).toString().padLeft(2, '0')}',
          300.0 + i * 10,
        ),
    ];
    final run = withPace(20, '2030-01-20', 290);

    test('Schnitt der letzten 5 Läufe, nicht aller', () {
      final c = classifyRun(run, prev);
      // Letzte 5: Läufe 3..7 = 320..360 -> Mittel 340.
      expect(c.comparedRuns, 5);
      expect(c.referenceSecondsPerKm, 340);
      expect(c.deltaSecondsPerKm, -50);
      expect(c.relation, PaceRelation.faster);
    });

    test('Referenz ist Σ Strecke / Σ Zeit, nicht das Mittel der Paces', () {
      // 1 km in 300 s (300 s/km) und 9 km in 3600 s (400 s/km):
      // gewichtet 3900 s / 10 km = 390, ungewichtet 350.
      final others = [
        figures(1, '2030-01-01', km: 1, paceSec: 300),
        figures(2, '2030-01-02', km: 9, paceSec: 3600),
      ];
      final c = classifyRun(run, others);
      expect(c.referenceSecondsPerKm, closeTo(390, 1e-9));
      expect(c.deltaSecondsPerKm, closeTo(-100, 1e-9));
    });

    test('gleich nur bei |Δ| unter 1 s/km, sonst nur der Unterschied', () {
      PaceRelation? rel(double pace) => classifyRun(
        RunFigures(
          runId: 20,
          endedAt: run.endedAt,
          day: run.day,
          distanceMeters: 1000,
          paceTime: Duration(milliseconds: (pace * 1000).round()),
        ),
        prev,
      ).relation;
      expect(rel(340.9), PaceRelation.same);
      expect(rel(339.1), PaceRelation.same);
      expect(rel(341), PaceRelation.slower);
      expect(rel(339), PaceRelation.faster);
    });

    test('Lauf mit gleichem Laufende zählt nicht als Vorlauf', () {
      final same = withPace(30, '2030-01-20', 100); // Tag/Stunde wie der Lauf
      final c = classifyRun(run, [same, ...prev]);
      expect(c.referenceSecondsPerKm, 340);
      expect(c.comparedRuns, 5);
    });

    test('langsamer und genau gleich', () {
      expect(
        classifyRun(withPace(20, '2030-01-20', 400), prev).relation,
        PaceRelation.slower,
      );
      expect(
        classifyRun(withPace(20, '2030-01-20', 340), prev).relation,
        PaceRelation.same,
      );
    });

    test(
      'weniger als 5 Vorläufe: Vergleich mit den vorhandenen, Anzahl dabei',
      () {
        final c = classifyRun(run, prev.take(2));
        expect(c.isAvailable, isTrue);
        expect(c.comparedRuns, 2);
        expect(c.referenceSecondsPerKm, 305);
      },
    );

    test('ohne Vorläufe: nicht verfügbar, nicht 0', () {
      final c = classifyRun(run, const []);
      expect(c.isAvailable, isFalse);
      expect(c.unavailable, ClassificationUnavailable.tooFewPreviousRuns);
      expect(c.referenceSecondsPerKm, isNull);
      expect(c.deltaSecondsPerKm, isNull);
      expect(c.relation, isNull);
      expect(c.comparedRuns, 0);
    });

    test('Toleranz für "gleich" kommt aus den Parametern', () {
      PaceRelation? rel(double pace, StatisticsParameters p) => classifyRun(
        RunFigures(
          runId: 20,
          endedAt: run.endedAt,
          day: run.day,
          distanceMeters: 1000,
          paceTime: Duration(milliseconds: (pace * 1000).round()),
        ),
        prev,
        parameters: p,
      ).relation;
      const wide = StatisticsParameters(sameToleranceSecondsPerKm: 5);
      const none = StatisticsParameters(sameToleranceSecondsPerKm: 0);
      expect(rel(344, wide), PaceRelation.same);
      expect(rel(344, const StatisticsParameters()), PaceRelation.slower);
      expect(rel(340.5, none), PaceRelation.slower);
    });

    test('Mindestzahl ist an einer Stelle austauschbar', () {
      const strict = StatisticsParameters(minimumComparisonRuns: 5);
      final c = classifyRun(run, prev.take(4), parameters: strict);
      expect(c.isAvailable, isFalse);
      expect(c.comparedRuns, 4);
      expect(classifyRun(run, prev, parameters: strict).isAvailable, isTrue);
    });

    test('spätere Läufe, der Lauf selbst und Läufe ohne Pace zählen nicht', () {
      final others = [
        withPace(20, '2030-01-20', 100), // der Lauf selbst
        withPace(21, '2030-01-21', 100), // später
        figures(22, '2030-01-10', km: 1), // ohne Zeit: keine Pace
        withPace(3, '2030-01-03', 330),
      ];
      final c = classifyRun(run, others);
      expect(c.comparedRuns, 1);
      expect(c.referenceSecondsPerKm, 330);
    });

    test('Lauf ohne Pace: nicht verfügbar', () {
      final c = classifyRun(figures(20, '2030-01-20'), prev);
      expect(c.unavailable, ClassificationUnavailable.noPaceForRun);
    });

    test('Reihenfolge der Eingabe ist egal', () {
      expect(
        classifyRun(run, prev.reversed).referenceSecondsPerKm,
        classifyRun(run, prev).referenceSecondsPerKm,
      );
    });
  });
}
