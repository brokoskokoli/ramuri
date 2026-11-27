import 'package:core/core.dart';
import 'package:test/test.dart';

import 'workflow_env.dart';

/// Neustart zur Pause (PAR-202) und neuer Einstieg nach langer Pause
/// (PAR-181) als Ablauf in `core` ([PlanPauseWorkflow]). Synthetische Daten:
/// Ziel und Läufe sind ausgedacht.

/// Ortszeit [hour]:[minute] am Kalendertag [day].
DateTime _at(DateTime day, [int hour = 0, int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// Legt einen beendeten Lauf an, der [ago] Tage vor heute um 9 Uhr endet.
Future<int> _finishedRun(StorageSession s, int ago) async {
  final start = workflowDay(-ago).add(const Duration(hours: 8));
  final r = await s.runs.create(startedAt: start);
  await s.runs.setState(
    r.id,
    RunState.finished,
    endedAt: start.add(const Duration(hours: 1)),
    endedUtcOffset: Duration.zero,
  );
  return r.id;
}

HintService _hints(WorkflowEnv e) =>
    HintService(session: e.session, clock: e.clock);

/// Nachfrage nach PAR-200 fällig, wie die Plan-Seite sie zeigt.
Future<bool> _feedbackDue(WorkflowEnv e) async => e.service.feedbackDue(
  await e.plans.history(),
  await e.warning.read(),
  planDay(calendarDay(e.clock.now())),
);

/// Ziel mit Plan, 80 Tage vor heute angelegt.
Future<WorkflowEnv> _planned({DateTime? target}) async {
  final e = await WorkflowEnv.open();
  e.clock.set(_at(workflowDay(-80), 12));
  await e.service.saveGoal(workflowGoal(target: target));
  e.clock.set(workflowNow);
  return e;
}

void main() {
  group('Öffnen: Pausenregel vor Wochenprüfung', () {
    Future<WorkflowEnv> prepared(int pauseDays, {bool recorded = true}) async {
      final e = await _planned();
      await _finishedRun(e.session, pauseDays);
      // Basiswoche vor der Pause (volle Kalenderwoche, 2 Läufe zu 60 min).
      await _finishedRun(e.session, pauseDays + 7);
      await _finishedRun(e.session, pauseDays + 8);
      if (recorded) {
        await LoadSettings.saveAllRecorded(
          e.session.settings,
          true,
          at: workflowNow,
        );
      }
      // Wochenprüfung fällig (frühere Kalenderwoche), diese Woche ohne Läufe.
      await e.session.settings.set(
        planLastCheckDayKey,
        '2026-11-02',
        at: workflowNow,
      );
      return e;
    }

    test(
      'Pause 10 Tage: genau eine Fassung (pause), 80 % der Basiswoche, '
      'keine harte Einheit; die Wochenprüfung schreibt keine zweite',
      () async {
        final e = await prepared(10);
        final before = (await e.plans.history()).length;
        final q = await _hints(e).pauseRestartDue();
        expect(q, isNotNull);
        expect(q!.baseWeekMinutes, greaterThan(0));
        await e.openPlan();
        final h = await e.plans.history();
        expect(h.length, before + 1);
        expect(h.last.trigger, PlanTrigger.pause);
        expect(h.last.inputs.noHardUntil, isNotNull);
        expect(
          h.last.inputs.startWeeklyMinutes,
          (q.baseWeekMinutes * 0.8).round(),
        );
        expect(h.last.inputs.anchor, DateTime.utc(2026, 11, 9));
        // Zweites Öffnen: weiterhin nichts Neues.
        await e.openPlan();
        expect((await e.plans.history()).length, before + 1);
      },
    );

    test('offene Pausenfrage: Öffnen rechnet keine Wochenprüfung; nach „Ja“ '
        'gilt die Pausenregel, danach nichts Neues', () async {
      final e = await prepared(10, recorded: false);
      final before = (await e.plans.history()).length;
      final q = await _hints(e).pauseQuestion();
      expect(q, isNotNull);
      await e.openPlan();
      expect((await e.plans.history()).length, before);
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await e.service.answerPause(true);
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.pause);
      expect(
        h.last.inputs.startWeeklyMinutes,
        (q!.baseWeekMinutes * 0.8).round(),
      );
      expect(h.last.inputs.noHardUntil, isNotNull);
      await e.openPlan();
      expect((await e.plans.history()).length, before + 1);
    });

    test('offene Pausenfrage: keine Nachfrage (PAR-200), nach der Antwort '
        'wieder fällig', () async {
      final e = await prepared(10, recorded: false);
      // Die Anlage liegt 80 Tage zurück: die Nachfrage wäre fällig.
      await e.openPlan();
      expect(await _feedbackDue(e), isFalse);
      await e.service.answerPause(true);
      await e.openPlan();
      expect(await _feedbackDue(e), isTrue);
    });

    test('Rückmeldung am Mittwoch, Pausenfrage am Donnerstag: Neustart mit '
        'Anker dieser Montag (PAR-202)', () async {
      final e = await prepared(6, recorded: false);
      await e.openPlan();
      expect(await _hints(e).pauseQuestion(), isNull);
      expect(await _feedbackDue(e), isTrue);
      await e.service.answerFeedback(PlanFeedback.tooEasy);
      final fb = (await e.plans.history()).last;
      expect(fb.trigger, PlanTrigger.feedback);
      expect(fb.inputs.anchor.isAfter(DateTime.utc(2026, 11, 9)), isTrue);
      // Einen Tag später steht die Pause (7 Tage) fest und die Frage ist offen.
      e.clock.set(workflowNow.add(const Duration(days: 1)));
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await e.service.answerPause(true);
      final h = (await e.plans.history()).last;
      expect(h.trigger, PlanTrigger.pause);
      expect(h.inputs.anchor, DateTime.utc(2026, 11, 9));
      expect(h.inputs.noHardUntil, isNotNull);
    });

    test('„zu leicht“, dann Pause ab pauseMinDays: die Pause startet höchstens '
        'mit der Woche, die vor der Rückmeldung galt', () async {
      final e = await prepared(6, recorded: false);
      await e.openPlan();
      expect(await _feedbackDue(e), isTrue);
      await e.service.answerFeedback(PlanFeedback.tooEasy);
      final history = await e.plans.history();
      final monday = DateTime.utc(2026, 11, 9);
      int weekMinutes(PlanInputs i) {
        // Wie die Pausenregel: ein späterer Anker gilt ab diesem Montag.
        final from = i.anchor.isAfter(monday) ? i.copyWith(anchor: monday) : i;
        final s = planCourseSetup(workflowGoal(), from);
        return s
            .course(today: monday)
            .weeks
            .firstWhere((w) => w.start == monday)
            .minutes!;
      }

      // Einen Tag später steht die Pause fest.
      e.clock.set(workflowNow.add(const Duration(days: 1)));
      await e.service.answerPause(true);
      final h = (await e.plans.history()).last;
      expect(h.trigger, PlanTrigger.pause);
      final shown = weekMinutes(history[history.length - 2].inputs);
      final raised = weekMinutes(history.last.inputs);
      // Die Rückmeldung hat die Woche angehoben, sonst prüft der Test nichts.
      expect(raised, greaterThan(shown));
      expect(h.inputs.startWeeklyMinutes, lessThanOrEqualTo(shown));
    });

    test('Rückmeldung wird bei offener Pausenfrage nicht angenommen (Karte '
        'über Mitternacht offen)', () async {
      final e = await prepared(6, recorded: false);
      await e.openPlan();
      final before = (await e.plans.history()).length;
      e.clock.set(workflowNow.add(const Duration(days: 1)));
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await expectLater(
        e.service.answerFeedback(PlanFeedback.tooEasy),
        throwsA(
          isA<StorageException>().having(
            (x) => x.failure,
            'failure',
            StorageFailure.rejected,
          ),
        ),
      );
      expect((await e.plans.history()).length, before);
    });

    test('Ziel speichern am Prüftag bei offener Pausenfrage, dann „Ja“ -> '
        'Fassung pause, 80 % der Basiswoche, noHardUntil', () async {
      final e = await prepared(10, recorded: false);
      final q = await _hints(e).pauseQuestion();
      expect(q, isNotNull);
      await e.service.saveGoal(workflowGoal(target: DateTime.utc(2027, 5, 1)));
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await e.service.answerPause(true);
      final last = (await e.plans.history()).last;
      expect(last.trigger, PlanTrigger.pause);
      expect(
        last.inputs.startWeeklyMinutes,
        (q!.baseWeekMinutes * 0.8).round(),
      );
      expect(last.inputs.noHardUntil, isNotNull);
    });

    test('Ziel speichern bei offener Pausenfrage, dann „Nein“ -> '
        'Wochenprüfung greift beim nächsten Öffnen', () async {
      final e = await prepared(10, recorded: false);
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await e.service.saveGoal(workflowGoal(target: DateTime.utc(2027, 5, 1)));
      expect(await _hints(e).pauseQuestion(), isNotNull);
      final before = (await e.plans.history()).length;
      await e.service.answerPause(false);
      await e.openPlan();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('offene Pausenfrage, Antwort „Nein“: die nächste Wochenprüfung läuft '
        'normal', () async {
      final e = await prepared(10, recorded: false);
      final before = (await e.plans.history()).length;
      await e.openPlan();
      expect((await e.plans.history()).length, before);
      await e.service.answerPause(false);
      await e.openPlan();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('ohne Pause greift die Wochenprüfung wie bisher', () async {
      final e = await prepared(2);
      final before = (await e.plans.history()).length;
      await e.openPlan();
      final h = await e.plans.history();
      expect(h.length, before + 1);
      expect(h.last.trigger, PlanTrigger.weekly);
    });

    test('einmal je Pause: nach dem Neustart (Zusage), einer Rückmeldung und '
        'dem Widerruf der Zusage schreibt „Ja“ auf die Pausenfrage keine '
        'zweite Fassung', () async {
      final e = await prepared(10);
      await e.openPlan();
      expect((await e.plans.history()).last.trigger, PlanTrigger.pause);
      final mark = PauseRestartMark.parse(
        await e.session.settings.get(planPauseRestartKey),
      );
      expect(mark?.restarted, isTrue);
      // Die Rückmeldung legt den Anker in eine spätere Woche; ein zweiter
      // Neustart fände damit wieder eine anpassbare Woche (PAR-202).
      await e.service.answerFeedback(PlanFeedback.tooEasy);
      final h = await e.plans.history();
      expect(h.last.trigger, PlanTrigger.feedback);
      expect(h.last.inputs.anchor.isAfter(DateTime.utc(2026, 11, 9)), isTrue);
      // Ohne Zusage stellt die App die Pausenfrage für dieselbe Pause; der
      // Merker gilt weiter (einmal je Pause).
      await LoadSettings.saveAllRecorded(
        e.session.settings,
        false,
        at: workflowNow,
      );
      expect(await _hints(e).pauseQuestion(), isNotNull);
      await e.service.answerPause(true);
      expect((await e.plans.history()).length, h.length);
      await e.openPlan();
      expect((await e.plans.history()).length, h.length);
      expect(
        PauseRestartMark.parse(
          await e.session.settings.get(planPauseRestartKey),
        )?.restarted,
        isTrue,
      );
    });

    group('Grenze pauseNewStartDays (PAR-202, PAR-181)', () {
      Future<(WorkflowEnv, PauseQuestion, PauseRestartMark?)> restarted(
        int Function(PlanParameters p) days,
      ) async {
        const p = PlanParameters();
        final e = await prepared(days(p));
        expect(e.service.parameters.pauseNewStartDays, p.pauseNewStartDays);
        final q = await _hints(e).pauseRestartDue();
        expect(q, isNotNull);
        // Die Tageszählung nach Ortstag liegt genau auf dem gewollten Tag.
        expect(q!.daysSinceTraining, days(p));
        await e.openPlan();
        final mark = PauseRestartMark.parse(
          await e.session.settings.get(planPauseRestartKey),
        );
        return (e, q, mark);
      }

      test(
        'ein Tag vor der Grenze: Neustart ohne vorläufige Vorgabe',
        () async {
          final (e, q, mark) = await restarted((p) => p.pauseNewStartDays - 1);
          final h = await e.plans.history();
          expect(h.last.trigger, PlanTrigger.pause);
          expect(mark?.restarted, isTrue);
          expect(mark?.provisional, isFalse);
          expect(mark?.day, warningDay(q.lastTrainingDay));
          expect(await e.service.newStartPossible(), isFalse);
        },
      );

      test(
        'am Grenztag: vorläufige Vorgabe (Stufe 2), Merker provisional',
        () async {
          final (e, q, mark) = await restarted((p) => p.pauseNewStartDays);
          final p = e.service.parameters;
          final h = await e.plans.history();
          expect(h.last.trigger, PlanTrigger.pause);
          expect(mark?.restarted, isTrue);
          expect(mark?.provisional, isTrue);
          expect(mark?.day, warningDay(q.lastTrainingDay));
          // Stufe 2 (2 bis unter 8 Wochen): Anteil der Basiswoche, keine harte
          // Einheit in den nächsten Wochen.
          expect(
            h.last.inputs.startWeeklyMinutes,
            (q.baseWeekMinutes * p.pauseLongShare).round(),
          );
          expect(h.last.inputs.noHardUntil, isNotNull);
          expect(h.last.inputs.anchor, DateTime.utc(2026, 11, 9));
          expect(
            h.last.inputs.noHardUntil!.difference(h.last.inputs.anchor).inDays,
            7 * p.pauseLongNoHardWeeks - 1,
          );
        },
      );

      test('nach der vorläufigen Vorgabe schreibt der gewählte Einstieg trotz '
          'Merker genau eine weitere Fassung, danach keine mehr', () async {
        final (e, _, mark) = await restarted((p) => p.pauseNewStartDays);
        expect(mark?.provisional, isTrue);
        final before = (await e.plans.history()).length;
        await e.service.restartAfterLongPause(
          workflowGoal(target: DateTime.utc(2027, 6, 1)),
        );
        final h = await e.plans.history();
        expect(h.length, before + 1);
        expect(h.last.trigger, PlanTrigger.goalChange);
        final chosen = PauseRestartMark.parse(
          await e.session.settings.get(planPauseRestartKey),
        );
        expect(chosen?.provisional, isFalse);
        // Ein zweiter gewählter Einstieg steht nicht mehr an.
        await expectLater(
          e.service.restartAfterLongPause(
            workflowGoal(target: DateTime.utc(2027, 6, 1)),
          ),
          throwsA(isA<StorageException>()),
        );
        await e.openPlan();
        expect((await e.plans.history()).length, before + 1);
      });
    });

    test(
      'ohne offene Pausenfrage: Antwort abgelehnt, nichts geändert',
      () async {
        final e = await prepared(2, recorded: false);
        final before = (await e.plans.history()).length;
        await expectLater(
          e.service.answerPause(true),
          throwsA(isA<StorageException>()),
        );
        expect((await e.plans.history()).length, before);
        expect(await e.session.settings.get(planPauseRestartKey), isNull);
      },
    );
  });

  group('Neuer Einstieg: Neustart möglich', () {
    Future<bool> possible(DateTime target) async {
      final e = await _planned(target: target);
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(
        e.session.settings,
        true,
        at: workflowNow,
      );
      return e.service.newStartPossible();
    }

    test(
      'ja bei langer Pause und weitem Termin, nein kurz vor dem Termin',
      () async {
        expect(await possible(DateTime.utc(2027, 6, 1)), isTrue);
        expect(await possible(DateTime.utc(2026, 11, 14)), isFalse);
      },
    );

    test('nein ohne anstehenden Einstieg (keine lange Pause)', () async {
      final e = await _planned();
      await _finishedRun(e.session, 20);
      await LoadSettings.saveAllRecorded(
        e.session.settings,
        true,
        at: workflowNow,
      );
      expect(await e.service.newStartPossible(), isFalse);
    });

    test('Einschätzung des neuen Einstiegs rechnet mit dem neuen Stand, auch '
        'nach der vorläufigen Vorgabe', () async {
      final e = await _planned();
      await _finishedRun(e.session, 70);
      await LoadSettings.saveAllRecorded(
        e.session.settings,
        true,
        at: workflowNow,
      );
      // Die wöchentliche Prüfung gilt als erledigt (sonst käme ihre Fassung
      // mit dem Anker dieser Woche zuerst und der Neustart entfiele).
      await e.session.settings.set(
        planLastCheckDayKey,
        '2026-11-11',
        at: workflowNow,
      );
      await e.openPlan();
      final h = await e.plans.history();
      expect(h.map((r) => r.trigger), contains(PlanTrigger.pause));
      // Der Merker hält die vorläufige Vorgabe fest.
      final mark = PauseRestartMark.parse(
        await e.session.settings.get(planPauseRestartKey),
      );
      expect(mark?.provisional, isTrue);
      expect(mark?.restarted, isTrue);
      // Neuer Stand: nicht 30 min am Stück -> Geh-Lauf-Abfolge im Neustart.
      final draft = TrainingGoal(
        type: GoalType.distance,
        distance: GoalDistance.tenKilometers,
        targetDate: DateTime.utc(2027, 6, 1),
        runDays: const {2, 4, 6},
        maxSessionSeconds: 7200,
        weeklyCapSeconds: 240 * 60.0,
        createdAt: DateTime.utc(2026, 11, 1),
        hardSessionEnabled: true,
        canRun30: ContinuousRun30.no,
      );
      final check = await e.service.checkGoal(draft, newStart: true);
      expect(check.walkRun, isTrue);
      // Gewählter Einstieg: Ziel gespeichert, Fassung `goalChange`, Merker
      // nicht mehr vorläufig.
      await e.service.restartAfterLongPause(draft);
      expect((await e.goals.goal())!.canRun30, ContinuousRun30.no);
      expect((await e.plans.history()).last.trigger, PlanTrigger.goalChange);
      final chosen = PauseRestartMark.parse(
        await e.session.settings.get(planPauseRestartKey),
      );
      expect(chosen?.provisional, isFalse);
    });

    test('ohne anstehenden Einstieg: gewählter Einstieg abgelehnt, Ziel '
        'unverändert', () async {
      final e = await _planned();
      await _finishedRun(e.session, 20);
      final goal = await e.goals.goal();
      await expectLater(
        e.service.restartAfterLongPause(
          workflowGoal(target: DateTime.utc(2027, 5, 1)),
        ),
        throwsA(
          isA<StorageException>().having(
            (x) => x.failure,
            'failure',
            StorageFailure.rejected,
          ),
        ),
      );
      expect((await e.goals.goal())!.targetDate, goal!.targetDate);
    });
  });

  test('Lauf über Mitternacht am Starttag beendet die lange Pause', () async {
    // Lange Pause (PAR-181) mit anstehendem neuem Einstieg.
    final e = await _planned();
    await _finishedRun(e.session, 70);
    await LoadSettings.saveAllRecorded(
      e.session.settings,
      true,
      at: workflowNow,
    );
    expect(await e.service.newStartPossible(), isTrue);
    // Ein Lauf, der heute nach Ortszeit des Laufs (UTC+14) um 22:00 beginnt
    // und nach Mitternacht endet, zählt am Starttag (PAR-237): Die Pause
    // endet heute, ein Neustart steht nicht mehr an.
    final start = workflowToday.add(const Duration(hours: 8));
    final r = await e.session.runs.create(startedAt: start);
    await e.session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: start.add(const Duration(hours: 3)),
      endedUtcOffset: const Duration(hours: 14),
    );
    expect(await e.service.newStartPossible(), isFalse);
  });
}
