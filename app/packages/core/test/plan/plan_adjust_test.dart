import 'dart:math';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _m0 = DateTime.utc(2026, 11, 9); // Montag
DateTime _mon(int week) => _m0.add(Duration(days: 7 * week));

TrainingGoal _goal({
  int capMin = 240,
  Set<int> days = const {2, 4, 6},
  ContinuousRun30 canRun30 = ContinuousRun30.yes,
}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 8, 1),
  runDays: days,
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: canRun30,
);

PlanInputs _inputs(TrainingGoal g) => PlanInputs.forNewGoal(g, _m0);

PlanWeek _week(TrainingGoal g, PlanInputs i, int k) => planCourseSetup(
  g,
  i,
).course(today: _mon(k)).weeks.firstWhere((w) => w.start == _mon(k));

int _minutes(TrainingGoal g, PlanInputs i, int k) => _week(g, i, k).minutes!;

void main() {
  group('PAR-200 Nachfrage', () {
    test('Fälligkeit: 14 Tage ab Anlage bzw. letzter Antwort', () {
      final created = DateTime.utc(2026, 11, 1);
      expect(
        planFeedbackDue(created: created, today: DateTime.utc(2026, 11, 14)),
        isFalse,
      );
      expect(
        planFeedbackDue(created: created, today: DateTime.utc(2026, 11, 15)),
        isTrue,
      );
      final answer = DateTime.utc(2026, 11, 20);
      expect(
        planFeedbackDue(
          created: created,
          lastAnswer: answer,
          today: DateTime.utc(2026, 12, 3),
        ),
        isFalse,
      );
      expect(
        planFeedbackDue(
          created: created,
          lastAnswer: answer,
          today: DateTime.utc(2026, 12, 4),
        ),
        isTrue,
      );
    });

    test('zu leicht: ab der nächsten Woche +10 %, danach wieder PAR-193', () {
      final g = _goal();
      final i = _inputs(g);
      final base = _week(g, i, 1).baseMinutes!;
      final r = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.tooEasy,
        today: DateTime.utc(2026, 11, 11),
      );
      final n = r.inputs!;
      expect(n.anchor, _mon(1));
      expect(n.startWeeklyMinutes, (base * 1.1).round());
      expect(r.raiseGoalSignal, isFalse);
      // Die Woche davor ändert sich nicht, danach steigt es um PAR-193 (7 %).
      expect(_minutes(g, n, 1), (base * 1.1).round());
      final w2 = _week(g, n, 2).baseMinutes!;
      expect(w2, greaterThan(n.startWeeklyMinutes));
      expect(w2, lessThanOrEqualTo(n.startWeeklyMinutes * 1.10 + 1));
    });

    test('zu leicht: höchstens bis zum Regler; am Regler nur das Signal', () {
      final g = _goal(capMin: 100);
      final i = _inputs(g).copyWith(startWeeklyMinutes: 95);
      final r = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.tooEasy,
        today: DateTime.utc(2026, 11, 9),
      );
      expect(r.inputs!.startWeeklyMinutes, lessThanOrEqualTo(100));
      expect(_minutes(g, r.inputs!, 1), lessThanOrEqualTo(100));
      final atCap = _inputs(g).copyWith(startWeeklyMinutes: 100);
      final s = applyPlanFeedback(
        goal: g,
        inputs: atCap,
        answer: PlanFeedback.tooEasy,
        today: DateTime.utc(2026, 11, 9),
      );
      expect(s.raiseGoalSignal, isTrue);
      expect(s.inputs, isNull);
    });

    test('zu schwer −10 %, passt ändert nichts', () {
      final g = _goal();
      final i = _inputs(g);
      final base = _week(g, i, 1).baseMinutes!;
      final r = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.tooHard,
        today: DateTime.utc(2026, 11, 9),
      );
      expect(r.inputs!.startWeeklyMinutes, (base * 0.9).round());
      final f = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.fits,
        today: DateTime.utc(2026, 11, 9),
      );
      expect(f.inputs, isNull);
      expect(f.raiseGoalSignal, isFalse);
    });

    test('die Zählung der leichteren Woche (PAR-194) läuft weiter', () {
      final g = _goal();
      final i = _inputs(g);
      // Referenz: leichtere Wochen im alten Plan.
      final ref = [
        for (var k = 0; k < 12; k++)
          if (_week(g, i, k).kind == WeekKind.lighter) k,
      ];
      expect(ref, isNotEmpty);
      // Antwort in Woche 1 (neuer Anker Woche 2).
      final n = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.tooHard,
        today: _mon(1),
      ).inputs!;
      expect(n.anchor, _mon(2));
      final after = [
        for (var k = 2; k < 12; k++)
          if (_week(g, n, k).kind == WeekKind.lighter) k,
      ];
      expect(after, ref.where((k) => k >= 2).toList());
    });

    test('Geh-Lauf-Abfolge: keine Änderung', () {
      final g = _goal(canRun30: ContinuousRun30.no);
      final i = _inputs(g);
      expect(i.walkRunStart, isNotNull);
      final r = applyPlanFeedback(
        goal: g,
        inputs: i,
        answer: PlanFeedback.tooEasy,
        today: DateTime.utc(2026, 11, 9),
      );
      expect(r.inputs, isNull);
    });

    test('Rundweg: neue Felder in toJson/fromJson, inputsVersion bleibt 1', () {
      final g = _goal();
      final n = applyPlanFeedback(
        goal: g,
        inputs: _inputs(g),
        answer: PlanFeedback.tooHard,
        today: _mon(1),
      ).inputs!.copyWith(noHardUntil: _mon(2));
      final j = n.toJson();
      expect(j['inputsVersion'], 1);
      expect(PlanInputs.fromJson(j).toJson(), j);
      expect(PlanInputs.fromJson(j).noHardUntil, _mon(2));
      expect(PlanInputs.fromJson(j).weekCountOffset, n.weekCountOffset);
    });
  });

  group('PAR-201 von selbst nur nach unten', () {
    final g = _goal();
    final i = _inputs(g);
    // Woche 0 abgeschlossen, heute Montag Woche 1.
    WeekAdjustment? eval(
      double done, {
      List<int?> rpe = const [],
      bool tired = false,
      PlanInputs? inputs,
    }) => evaluateWeekAdjustment(
      goal: g,
      inputs: inputs ?? i,
      today: _mon(1),
      doneMinutes: done,
      recentEasyRpe: rpe,
      fatigueReported: tired,
    );
    final planned = _minutes(g, i, 0);
    final nextMin = _minutes(g, i, 1);

    test('unter der Hälfte: Woche wiederholen (gleiche Wochenzeit)', () {
      final a = eval(planned * 0.49)!;
      expect(a.reasons, {WeekAdjustmentReason.repeatWeek});
      expect(_minutes(g, a.inputs, 1), planned);
      expect(a.inputs.anchor, _mon(1));
      expect(a.inputs.achievedShare, closeTo(0.49, 0.01));
      expect(a.inputs.lastWeekMinutes, planned);
    });

    test('Grenze genau 50 %: keine Wiederholung, aber keine Steigerung', () {
      final a = eval(planned * 0.5)!;
      expect(a.reasons, {WeekAdjustmentReason.noIncrease});
      expect(_minutes(g, a.inputs, 1), _week(g, i, 0).baseMinutes);
      expect(_minutes(g, a.inputs, 1), lessThan(nextMin));
    });

    test('Grenze genau 80 %: nichts', () {
      expect(eval(planned * 0.8), isNull);
      expect(eval(planned * 0.79), isNotNull);
    });

    test('Zusatzläufe erhöhen nichts: Anteil höchstens 1', () {
      expect(eval(planned * 3), isNull);
    });

    test('Ermüdung: 2 der letzten 3 mit RPE >= 6: −10 % und keine harte '
        'Einheit; 1 von 3 nicht; gemeldete Ermüdung zählt', () {
      final a = eval(planned.toDouble(), rpe: [3, 6, 7])!;
      expect(a.reasons, {WeekAdjustmentReason.fatigue});
      expect(_minutes(g, a.inputs, 1), (nextMin * 0.9).round());
      expect(a.inputs.noHardUntil, _mon(1).add(const Duration(days: 6)));
      expect(eval(planned.toDouble(), rpe: [3, 6, 5]), isNull);
      expect(eval(planned.toDouble(), rpe: [9, 9, 2, 3, 4]), isNull);
      expect(eval(planned.toDouble(), tired: true), isNotNull);
    });

    test('keine harte Einheit in der Woche nach Ermüdung', () {
      final rich = i.copyWith(startWeeklyMinutes: 150);
      final a = eval(
        _minutes(g, rich, 0).toDouble(),
        rpe: [7, 7, 7],
        inputs: rich,
      )!;
      // Plan ab Woche 1: genügend Wochen mit harter Einheit im Referenzplan.
      var hardRef = 0, hardNew = 0;
      for (final week in [1, 2, 3, 4, 5]) {
        final ref = generatePlan(g, rich, const [], _mon(1));
        final adj = generatePlan(g, a.inputs, const [], _mon(1));
        bool inWeek(PlanUnit u) =>
            !u.day.isBefore(_mon(week)) &&
            u.day.isBefore(_mon(week + 1)) &&
            u.isHard;
        hardRef += ref.units.where(inWeek).length;
        hardNew += adj.units.where(inWeek).length;
        if (week == 1) {
          expect(adj.units.where(inWeek), isEmpty);
        }
      }
      expect(hardRef, greaterThan(0));
      expect(hardNew, greaterThan(0), reason: 'danach wieder wie geplant');
    });

    test('schon bewertete Woche und Geh-Lauf-Abfolge: null', () {
      final a = eval(0)!;
      // Zweite Auswertung mit den neuen Eingaben: Woche 0 liegt vor dem Anker.
      expect(eval(0, inputs: a.inputs), isNull);
      final w = _goal(canRun30: ContinuousRun30.no);
      expect(
        evaluateWeekAdjustment(
          goal: w,
          inputs: _inputs(w),
          today: _mon(1),
          doneMinutes: 0,
        ),
        isNull,
      );
    });

    test('Ausgefallenes wird nicht nachgeholt: Woche 1 ohne Lauf ändert nur '
        'die nächste Woche', () {
      final a = eval(0)!;
      expect(_minutes(g, a.inputs, 0 + 1), planned);
      expect(a.inputs.anchor, _mon(1));
    });
  });

  group('PAR-202 Pause', () {
    final g = _goal();
    final i = _inputs(g).copyWith(startWeeklyMinutes: 150);
    final today = DateTime.utc(2026, 12, 7); // Montag
    PauseRestart run(int gapDays, {double ran = 100, PlanInputs? inputs}) =>
        planPauseRestart(
          goal: g,
          inputs: inputs ?? i,
          today: today,
          lastTrainingDay: today.subtract(Duration(days: gapDays)),
          ranWeekMinutes: ran,
        );

    test('Grenzen 6/7/13/14/55/56 Tage', () {
      expect(run(6).kind, PauseRestartKind.none);
      expect(run(7).kind, PauseRestartKind.short);
      expect(run(13).kind, PauseRestartKind.short);
      expect(run(14).kind, PauseRestartKind.long);
      expect(run(55).kind, PauseRestartKind.long);
      expect(run(56).kind, PauseRestartKind.newStart);
    });

    test('80 % bzw. 50 % der gelaufenen Woche, keine harte Einheit '
        '1 bzw. 2 Wochen', () {
      final s = run(10).inputs!;
      expect(s.startWeeklyMinutes, 80);
      expect(s.anchor, today);
      expect(s.noHardUntil, today.add(const Duration(days: 6)));
      final l = run(30).inputs!;
      expect(l.startWeeklyMinutes, 50);
      expect(l.noHardUntil, today.add(const Duration(days: 13)));
    });

    test('Basis ist die gelaufene Woche, nicht die geplante; nie über dem '
        'bisherigen Plan und dem Regler', () {
      expect(run(10, ran: 40).inputs!.startWeeklyMinutes, 32);
      expect(
        run(10, ran: 5000).inputs!.startWeeklyMinutes,
        lessThanOrEqualTo(240),
      );
      final weeks = planCourseSetup(g, i).course(today: today).weeks;
      expect(
        run(10, ran: 5000).inputs!.startWeeklyMinutes,
        lessThanOrEqualTo(weeks.first.minutes!),
      );
      expect(run(10, ran: 0).inputs!.startWeeklyMinutes, 1);
    });

    test(
      'ab 8 Wochen: neuer Start nach PAR-192 mit Tempo der alten Eingaben',
      () {
        final old = i.copyWith(easyPaceSecondsPerKm: 400);
        final n = run(60, inputs: old).inputs!;
        expect(n.anchor, today);
        expect(n.easyPaceSecondsPerKm, 400);
        expect(n.startWeeklyMinutes, 90);
      },
    );

    test('gilt der Neustart schon in dieser Woche, nichts mehr', () {
      final s = run(10).inputs!;
      expect(run(10, inputs: s).kind, PauseRestartKind.none);
    });

    test('Geh-Lauf-Abfolge: nichts', () {
      final w = _goal(canRun30: ContinuousRun30.no);
      expect(
        planPauseRestart(
          goal: w,
          inputs: _inputs(w),
          today: today,
          lastTrainingDay: today.subtract(const Duration(days: 10)),
          ranWeekMinutes: 100,
        ).kind,
        PauseRestartKind.none,
      );
    });
  });

  group('PAR-140 Wiederholen in der Geh-Lauf-Phase', () {
    WalkRunOutcome d(int? rpe) => WalkRunOutcome(done: true, rpe: rpe);
    const miss = WalkRunOutcome(done: false);
    WalkRunRepeatSuggestion? s(
      List<WalkRunOutcome> o, {
      int week = 1,
      bool over = true,
    }) => suggestWalkRunRepeat(programWeek: week, outcomes: o, weekOver: over);

    test('weniger als 2 von 3 absolviert: Woche wiederholen', () {
      expect(
        s([d(3), miss, miss]),
        const WalkRunRepeatSuggestion(
          WalkRunRepeatScope.week,
          WalkRunPosition(1),
        ),
      );
      expect(s([d(3), d(3), miss]), isNull);
      expect(s([]), isNotNull);
    });

    test('mindestens 2 mit RPE >= 6: wiederholen; RPE 5 nicht', () {
      expect(s([d(6), d(7), d(2)]), isNotNull);
      expect(s([d(5), d(5), d(9)]), isNull);
      expect(s([d(6), d(5), d(5)]), isNull);
    });

    test('Woche läuft noch: kein Vorschlag (außer Woche 5, Lauf 3)', () {
      expect(s([d(7), d(7)], over: false), isNull);
    });

    test('vor Woche 5, Lauf 3: Lauf 2 mit RPE >= 6 wiederholen', () {
      expect(
        s([d(3), d(6)], week: 4, over: false),
        const WalkRunRepeatSuggestion(
          WalkRunRepeatScope.session,
          WalkRunPosition(4, 1),
        ),
      );
      expect(s([d(3), d(5)], week: 4, over: false), isNull);
      expect(s([d(3), d(6)], week: 3, over: false), isNull);
      // Lauf 3 schon absolviert: zu spät.
      expect(s([d(3), d(6), d(2)], week: 4, over: false), isNull);
    });

    test('in der Geh-Lauf-Phase gilt nicht PAR-201', () {
      final g = _goal(canRun30: ContinuousRun30.no);
      expect(
        evaluateWeekAdjustment(
          goal: g,
          inputs: _inputs(g),
          today: _mon(1),
          doneMinutes: 0,
          fatigueReported: true,
        ),
        isNull,
      );
    });

    test('Anwenden: neue Stelle mit neuem Anker, Länge der Abfolge neu', () {
      final g = _goal(canRun30: ContinuousRun30.no);
      final i = _inputs(g);
      final n = applyWalkRunRepeat(
        i,
        const WalkRunRepeatSuggestion(
          WalkRunRepeatScope.week,
          WalkRunPosition(2),
        ),
        from: DateTime.utc(2026, 11, 18),
      );
      expect(n.anchor, _mon(1));
      expect(n.walkRunStart, const WalkRunPosition(2));
      final plan = generatePlan(g, n, const [], _mon(1));
      expect(
        plan.units.firstWhere((u) => u.kind == PlanUnitKind.walkRun).day,
        isNot(isNull),
      );
    });
  });

  group('refreshMeasuredInputs', () {
    test('übernimmt gültigen Beleg, verwirft ungültigen; Zählung und '
        '„keine harte Einheit“ bleiben', () {
      final g = _goal();
      final stored = _inputs(g).copyWith(
        lastWeekMinutes: 90,
        achievedShare: 0.4,
        weekCountOffset: 2,
        noHardUntil: _mon(2),
      );
      final measured = _inputs(g).copyWith(today: _mon(3));
      final r = refreshMeasuredInputs(stored, measured);
      expect(r.achievedShare, 0.4);
      expect(r.lastWeekMinutes, 90);
      expect(r.weekCountOffset, 2);
      expect(r.noHardUntil, _mon(2));
      expect(r.today, _mon(3));
      // Ungültig: PlanInputs lässt den Anteil > 1 nicht zu; Minuten ohne
      // Anteil sind ein halber Beleg und entfallen.
      final half = PlanInputs(
        anchor: _m0,
        startWeeklyMinutes: 90,
        today: _m0,
        lastWeekMinutes: 90,
      );
      final h = refreshMeasuredInputs(half, measured);
      expect(h.lastWeekMinutes, isNull);
      expect(h.achievedShare, isNull);
    });
  });

  group('Eigenschaft und Simulation über mehrere Wochen', () {
    int weekSum(List<PlanUnit> u, int k) => u
        .where((x) => !x.day.isBefore(_mon(k)) && x.day.isBefore(_mon(k + 1)))
        .fold(0, (a, x) => a + x.minutes);

    double rate(double m) => m < 120 ? 0.10 : (m < 240 ? 0.07 : 0.05);

    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('Seed $seed: Ausfälle, Pause, hohe RPE', () {
        final rnd = Random(seed);
        final g = _goal();
        var inputs = _inputs(g);
        final all = <PlanUnit>[]; // eingefrorener Verlauf
        final sums = <int>[];
        final pauseFrom = 7 + rnd.nextInt(3);
        final pauseLen = 1 + rnd.nextInt(4);
        DateTime? lastTrained;
        var ranWeek = 0.0;
        var restarts = 0, adjusts = 0;
        for (var k = 0; k < 22; k++) {
          // Wochenende der Vorwoche: bewerten.
          if (k > 0) {
            final prev = sums[k - 1];
            final paused =
                (k - 1) >= pauseFrom && (k - 1) < pauseFrom + pauseLen;
            final frac = paused
                ? 0.0
                : (rnd.nextDouble() < 0.3
                      ? const [0.0, 0.3, 0.6]
                      : const [0.9, 1.0, 1.4])[rnd.nextInt(3)];
            final done = prev * frac;
            if (done > 0) {
              lastTrained = _mon(k).subtract(const Duration(days: 2));
              ranWeek = done;
            }
            // Pause nur mit einem früheren erfassten Training (der Aufrufer
            // fragt sonst nicht).
            final pause = lastTrained == null
                ? const PauseRestart(PauseRestartKind.none)
                : planPauseRestart(
                    goal: g,
                    inputs: inputs,
                    today: _mon(k),
                    lastTrainingDay: lastTrained,
                    ranWeekMinutes: ranWeek,
                  );
            if (pause.inputs != null &&
                pause.kind != PauseRestartKind.newStart) {
              inputs = pause.inputs!;
              restarts++;
            } else {
              final rpe = [for (var j = 0; j < 3; j++) rnd.nextInt(10) + 1];
              final a = evaluateWeekAdjustment(
                goal: g,
                inputs: inputs,
                today: _mon(k),
                doneMinutes: done,
                plannedMinutes: prev,
                recentEasyRpe: rpe,
              );
              if (a != null) {
                inputs = a.inputs;
                adjusts++;
              }
            }
          }
          final frozen = [...all];
          final plan = generatePlan(g, inputs, frozen, _mon(k));
          // Absolvierte (eingefrorene) Einheiten bleiben unverändert.
          for (final f in frozen) {
            expect(
              plan.allUnits.where((u) => u.day == f.day).single.minutes,
              f.minutes,
            );
          }
          all.addAll(plan.units.where((u) => u.day.isBefore(_mon(k + 1))));
          sums.add(weekSum(all, k));
        }
        for (var k = 1; k < sums.length; k++) {
          final prevMax = max(sums[k - 1], k > 1 ? sums[k - 2] : 0);
          // Nie stärker als PAR-193 (Wochenzeit, Rundung der Einheiten) und
          // nie über dem Regler.
          final limit = prevMax * (1 + rate(prevMax.toDouble())) + 4;
          if (sums[k] > limit) {
            fail(
              'Woche $k: ${sums[k]} > $limit (Vorwochen ${sums[k - 1]}, '
              '${k > 1 ? sums[k - 2] : '-'}); Summen $sums',
            );
          }
          expect(sums[k], lessThanOrEqualTo(240 + 4), reason: 'Regler');
        }
        expect(restarts + adjusts, greaterThan(0), reason: 'Seed ohne Wirkung');
        expect(
          sums.where((m) => m < 10).length,
          lessThan(sums.length ~/ 2),
          reason: 'Plan darf nicht auf nichts zusammenfallen: $sums',
        );
      });
    }

    test('alles geschafft, Zusatzläufe, niedrige RPE: nichts ändert sich '
        'von selbst, der Plan ist der Referenzplan', () {
      final g = _goal();
      final i = _inputs(g);
      final ref = generatePlan(g, i, const [], _mon(0));
      var inputs = i;
      for (var k = 1; k < 20; k++) {
        final planned = _minutes(g, i, k - 1);
        final a = evaluateWeekAdjustment(
          goal: g,
          inputs: inputs,
          today: _mon(k),
          doneMinutes: planned * (k.isEven ? 1.0 : 1.6),
          recentEasyRpe: const [3, 5, 4],
        );
        expect(a, isNull, reason: 'Woche $k');
      }
      expect(inputs.toJson(), i.toJson());
      expect(ref.units, isNotEmpty);
    });
  });
}
