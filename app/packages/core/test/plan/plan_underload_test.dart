import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Läufe; keine echten Messwerte.
final _t0 = DateTime.utc(2026, 11, 2, 7);

PlanUnderloadRun _run(
  int i, {
  PlanUnitKind kind = PlanUnitKind.easy,
  int? rpe = 3,
  double? hr = 12,
}) => PlanUnderloadRun(
  kind: kind,
  endedAt: _t0.add(Duration(days: i)),
  rpe: rpe,
  highHrMinutes: hr,
);

/// „hart nach Puls, leicht empfunden“
PlanUnderloadRun _hit(int i, {PlanUnitKind kind = PlanUnitKind.easy}) =>
    _run(i, kind: kind);

/// Zählt mit, passt aber nicht ins Muster (Puls niedrig).
PlanUnderloadRun _calm(int i) => _run(i, hr: 2);

final _m0 = DateTime.utc(2026, 11, 9); // Montag
DateTime _mon(int week) => _m0.add(Duration(days: 7 * week));

TrainingGoal _goal({int capMin = 600}) => TrainingGoal(
  type: GoalType.open,
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: false,
  canRun30: ContinuousRun30.yes,
);

PlanInputs _inputs(int start, {int offset = 0}) => PlanInputs(
  anchor: _m0,
  startWeeklyMinutes: start,
  today: _m0,
  weekCountOffset: offset,
);

PlanWeek _week(TrainingGoal g, PlanInputs i, int k) => planCourseSetup(
  g,
  i,
).course(today: _mon(k)).weeks.firstWhere((w) => w.start == _mon(k));

void main() {
  group('Muster (PAR-236)', () {
    test('1 von 3 → nein', () {
      expect(planUnderloadPattern([_calm(0), _hit(1), _calm(2)]), isFalse);
    });

    test('2 von 3 → ja', () {
      expect(planUnderloadPattern([_hit(0), _calm(1), _hit(2)]), isTrue);
    });

    test('nur die letzten 3 zählenden Läufe', () {
      // Zwei frühe Treffer, dann drei ruhige: nein.
      expect(
        planUnderloadPattern([_hit(0), _hit(1), _calm(2), _calm(3), _calm(4)]),
        isFalse,
      );
      // Reihenfolge nach Ende, nicht nach Liste.
      expect(planUnderloadPattern([_hit(4), _calm(0), _hit(3)]), isTrue);
    });

    test('Lauf ohne Puls oder ohne RPE zählt nicht mit', () {
      // Ohne Puls: fällt aus dem Fenster, die zwei Treffer bleiben drin.
      expect(
        planUnderloadPattern([_hit(0), _calm(1), _run(2, hr: null), _hit(3)]),
        isTrue,
      );
      expect(
        planUnderloadPattern([_hit(0), _calm(1), _run(2, rpe: null), _hit(3)]),
        isTrue,
      );
      // Zählten sie mit, wären es 1 von 3.
      expect(
        planUnderloadPattern([_hit(0), _calm(1), _run(2, rpe: 6), _hit(3)]),
        isFalse,
      );
      // Ohne Puls ist es auch kein Treffer.
      expect(
        planUnderloadPattern([_run(0, hr: null), _run(1, rpe: null), _hit(2)]),
        isFalse,
      );
      expect(planUnderloadCounts(_run(0, hr: null)), isFalse);
      expect(planUnderloadCounts(_run(0, rpe: null)), isFalse);
    });

    test('RPE 5 bei locker → nicht „leicht empfunden“, RPE 4 → leicht', () {
      expect(planUnderloadRunMatches(_run(0, rpe: 5)), isFalse);
      expect(planUnderloadRunMatches(_run(0, rpe: 4)), isTrue);
      expect(planUnderloadPattern([_run(0, rpe: 5), _run(1, rpe: 5)]), isFalse);
    });

    test('9 / 10 min über 80 % HFmax → nein / ja (PAR-058)', () {
      expect(planUnderloadRunMatches(_run(0, hr: 9)), isFalse);
      expect(planUnderloadRunMatches(_run(0, hr: 9.99)), isFalse);
      expect(planUnderloadRunMatches(_run(0, hr: 10)), isTrue);
      expect(planUnderloadPattern([_run(0, hr: 9), _run(1, hr: 9)]), isFalse);
      expect(planUnderloadPattern([_run(0, hr: 10), _run(1, hr: 10)]), isTrue);
    });

    test('locker geplant: locker, lang, Geh-Lauf; harte Einheit nicht', () {
      expect(planUnderloadRunMatches(_hit(0, kind: PlanUnitKind.long)), isTrue);
      expect(
        planUnderloadRunMatches(_hit(0, kind: PlanUnitKind.walkRun)),
        isTrue,
      );
      expect(planUnderloadCounts(_hit(0, kind: PlanUnitKind.tempo)), isFalse);
      expect(
        planUnderloadPattern([
          _hit(0, kind: PlanUnitKind.intervals),
          _hit(1, kind: PlanUnitKind.tempo),
        ]),
        isFalse,
      );
    });
  });

  group('Ablauf (PAR-236)', () {
    final now = DateTime.utc(2026, 11, 20, 9);
    PlanUnderloadState? step(
      PlanUnderloadState s, {
      bool pattern = true,
      bool blocked = false,
      bool canRaise = true,
    }) => planUnderloadAdvance(
      state: s,
      pattern: pattern,
      blocked: blocked,
      canRaise: canRaise,
      now: now,
    );

    test('erstes Muster → Hinweis, erneutes Muster → Frage', () {
      const none = PlanUnderloadState();
      expect(step(none, pattern: false), isNull);
      final hint = step(none)!;
      expect(hint.stage, PlanUnderloadStage.hint);
      expect(hint.prompt, PlanUnderloadPrompt.hint);
      expect(hint.since, now);
      final done = PlanUnderloadState(
        stage: PlanUnderloadStage.hintDone,
        since: hint.since,
      );
      expect(done.prompt, isNull);
      expect(step(done, pattern: false), isNull);
      final q = step(done)!;
      expect(q.stage, PlanUnderloadStage.question);
      expect(q.prompt, PlanUnderloadPrompt.question);
      // Offene Frage bleibt.
      expect(step(q), isNull);
    });

    test('Nein bzw. Ja: Frage erst nach neuem Muster', () {
      for (final s in [
        PlanUnderloadStage.declined,
        PlanUnderloadStage.accepted,
      ]) {
        final st = PlanUnderloadState(stage: s, since: now);
        expect(st.prompt, isNull);
        expect(step(st, pattern: false), isNull);
        expect(step(st)!.stage, PlanUnderloadStage.question);
      }
    });

    test('gesperrt (fix, Warnsignal, Korrektur, Readiness) → nichts', () {
      expect(step(const PlanUnderloadState(), blocked: true), isNull);
      expect(
        step(
          const PlanUnderloadState(stage: PlanUnderloadStage.hintDone),
          blocked: true,
        ),
        isNull,
      );
    });

    test('ohne mögliche Steigerung keine Frage', () {
      expect(
        step(
          const PlanUnderloadState(stage: PlanUnderloadStage.hintDone),
          canRaise: false,
        ),
        isNull,
      );
    });

    test('Zählung ab der späteren Zeit: Stufe oder Änderung der HFmax', () {
      final a = DateTime.utc(2026, 11, 10);
      final b = DateTime.utc(2026, 11, 12);
      expect(planUnderloadCountFrom(const PlanUnderloadState(), null), isNull);
      expect(planUnderloadCountFrom(const PlanUnderloadState(), b), b);
      expect(planUnderloadCountFrom(PlanUnderloadState(since: a), null), a);
      expect(planUnderloadCountFrom(PlanUnderloadState(since: a), b), b);
      expect(planUnderloadCountFrom(PlanUnderloadState(since: b), a), b);
    });

    test('Zählung: späteste Zeit aus Stufe, gespeicherter Änderung und '
        'Jahresbeginn der genäherten HFmax', () {
      final since = DateTime.utc(2026, 11, 20);
      final year = DateTime.utc(2027);
      final saved = DateTime.utc(2027, 1, 5);
      // Gespeicherter Zeitpunkt nach dem Jahresbeginn hat Vorrang.
      expect(
        planUnderloadCountFrom(
          PlanUnderloadState(since: since),
          saved,
          estimatedChangedAt: year,
        ),
        saved,
      );
      // Jahresbeginn nach Stufe und gespeichertem Zeitpunkt hat Vorrang.
      expect(
        planUnderloadCountFrom(
          PlanUnderloadState(since: since),
          DateTime.utc(2026, 11, 1),
          estimatedChangedAt: year,
        ),
        year,
      );
      expect(
        planUnderloadCountFrom(
          const PlanUnderloadState(),
          null,
          estimatedChangedAt: year,
        ),
        year,
      );
      // Stufe nach dem Jahresbeginn hat Vorrang.
      final later = DateTime.utc(2027, 1, 9);
      expect(
        planUnderloadCountFrom(
          PlanUnderloadState(since: later),
          saved,
          estimatedChangedAt: year,
        ),
        later,
      );
    });

    group('Jahreswechsel der genäherten HFmax (FR-0004, PAR-236)', () {
      final now = DateTime(2027, 1, 2, 9);
      test('Näherung ändert sich → 1. Januar 00:00 des aktuellen Jahres', () {
        // 1987: 2026 Alter 39 → 181, 2027 Alter 40 → 180 (208 − 0,7 · Alter).
        expect(approximateMaxHeartRate(39), 181);
        expect(approximateMaxHeartRate(40), 180);
        final t = estimatedMaxHeartRateChangedAt(
          const ProfileRecord(birthYear: 1987),
          now: now,
        );
        expect(t, DateTime(2027).toUtc());
        expect(t!.isUtc, isTrue);
        expect(t.toLocal(), DateTime(2027));
        expect(
          estimatedMaxHeartRateChangedAt(
            const ProfileRecord(birthYear: 1987),
            now: DateTime.utc(2027, 12, 31, 23),
          ),
          DateTime.utc(2027),
        );
      });

      test('gerundeter Wert in beiden Jahren gleich → null', () {
        // 1992: 2026 Alter 34 → 184,2 → 184, 2027 Alter 35 → 183,5 → 184.
        expect(approximateMaxHeartRate(34), 184);
        expect(approximateMaxHeartRate(35), 184);
        expect(
          estimatedMaxHeartRateChangedAt(
            const ProfileRecord(birthYear: 1992),
            now: now,
          ),
          isNull,
        );
      });

      test('eingetragene HFmax → null; kein Geburtsjahr → null', () {
        expect(
          estimatedMaxHeartRateChangedAt(
            const ProfileRecord(birthYear: 1987, maxHeartRateBpm: 190),
            now: now,
          ),
          isNull,
        );
        expect(
          estimatedMaxHeartRateChangedAt(const ProfileRecord(), now: now),
          isNull,
        );
        expect(
          estimatedMaxHeartRateChangedAt(
            const ProfileRecord(restingHeartRateBpm: 55),
            now: now,
          ),
          isNull,
        );
      });
    });

    test('Zustand aus den Einstellungen und zurück', () {
      final s = PlanUnderloadState(
        stage: PlanUnderloadStage.question,
        since: now,
      );
      final back = PlanUnderloadState.parse(s.stageText, s.sinceText);
      expect(back.stage, s.stage);
      expect(back.since, now);
      expect(
        PlanUnderloadState.parse('kaputt', 'x').stage,
        PlanUnderloadStage.none,
      );
      expect(PlanUnderloadState.parse(null, 'x').since, isNull);
    });
  });

  group('Steigerung nach Ja (PAR-236, PAR-193)', () {
    test('nächste Woche zwei Schritte über der Vorwoche', () {
      final g = _goal();
      final i = _inputs(90);
      // Woche 1 nach PAR-193: 90 → 99; mit Ja zwei Schritte: 90 · 1,1 · 1,1.
      expect(_week(g, i, 1).minutes, 99);
      final n = applyPlanUnderloadRaise(
        goal: g,
        inputs: i,
        today: DateTime.utc(2026, 11, 11),
      )!;
      expect(n.anchor, _mon(1));
      expect(n.startWeeklyMinutes, (90 * 1.1 * 1.1).round());
      expect(_week(g, n, 1).minutes, 109);
      // Danach wieder ein Schritt je Woche.
      expect(_week(g, n, 2).minutes, (109 * 1.1).round());
    });

    test('Rate nach der Höhe der Woche (ab 2 h +7 %)', () {
      final g = _goal();
      final i = _inputs(150);
      final base = _week(g, i, 1).baseMinutes!;
      final n = applyPlanUnderloadRaise(
        goal: g,
        inputs: i,
        today: DateTime.utc(2026, 11, 9),
      )!;
      expect(n.startWeeklyMinutes, (base * 1.07).round());
    });

    test('nie über dem Regler (PAR-196); am Regler keine Steigerung', () {
      final g = _goal(capMin: 100);
      final n = applyPlanUnderloadRaise(
        goal: g,
        inputs: _inputs(90),
        today: _m0,
      )!;
      expect(n.startWeeklyMinutes, 100);
      expect(_week(g, n, 1).minutes, 100);
      expect(
        applyPlanUnderloadRaise(goal: g, inputs: _inputs(100), today: _m0),
        isNull,
      );
    });

    test('Entlastungswoche → Wirkung eine Woche später (PAR-194)', () {
      final g = _goal();
      // Offset 2: Woche 1 ab Anker ist die 4. Woche, also leichter.
      final i = _inputs(90, offset: 2);
      expect(_week(g, i, 1).kind, WeekKind.lighter);
      final lighter = _week(g, i, 1).minutes;
      final after = _week(g, i, 2).baseMinutes!;
      final n = applyPlanUnderloadRaise(goal: g, inputs: i, today: _m0)!;
      expect(n.anchor, _mon(2));
      expect(n.startWeeklyMinutes, (after * 1.1).round());
      // Die leichtere Woche selbst bleibt.
      expect(_week(g, i, 1).minutes, lighter);
    });

    test('Geh-Lauf-Abfolge: keine Steigerung', () {
      final g = _goal();
      final i = PlanInputs(
        anchor: _m0,
        startWeeklyMinutes: 90,
        today: _m0,
        walkRunWeeks: 9,
      );
      expect(applyPlanUnderloadRaise(goal: g, inputs: i, today: _m0), isNull);
    });
  });

  group('Korrektur nach unten (PAR-201)', () {
    PlanVersionRecord v(String reason, DateTime anchor) => PlanVersionRecord(
      id: 1,
      goalId: 1,
      createdAt: anchor,
      validFrom: anchor,
      trigger: PlanTrigger.weekly,
      reason: reason,
      version: PlanVersion.current,
      inputsJson: jsonEncode(_inputs(90).copyWith(anchor: anchor).toJson()),
      summaryJson: '{}',
    );
    final today = DateTime.utc(2026, 11, 11);

    test('Grund der Wochenprüfung mit Anker dieser Woche → ja', () {
      for (final r in [
        'fatigue',
        'repeatWeek',
        'noIncrease',
        'goalChange,fatigue',
        'ruleVersion,noIncrease',
      ]) {
        expect(
          planCorrectedDownThisWeek([v(r, _m0)], today),
          isTrue,
          reason: r,
        );
      }
    });

    test('andere Gründe oder eine frühere Woche → nein', () {
      expect(planCorrectedDownThisWeek([v('weekly', _m0)], today), isFalse);
      expect(planCorrectedDownThisWeek([v('feedback', _m0)], today), isFalse);
      expect(
        planCorrectedDownThisWeek([v('fatigue', _mon(-1))], today),
        isFalse,
      );
    });
  });
}
