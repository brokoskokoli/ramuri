import 'package:core/core.dart';
import 'package:test/test.dart';

import 'workflow_env.dart';

/// Automatische Zuordnung als Ablauf in `core` ([PlanAssignWorkflow],
/// PAR-231): Fenster ab dem Sonntag der Vorwoche bzw. dem Starttag eines
/// Laufs, Merker „Einheit starten“, Verschieben, Idempotenz. Synthetische
/// Daten: Ziel und Läufe sind ausgedacht.

/// Ortszeit [hour]:[minute] am Kalendertag [day].
DateTime _at(DateTime day, [int hour = 0, int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

TrainingGoal _goal(Set<int> days) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: days,
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

/// Beendeter Lauf, der am Tag [d] um [h]:[m] Ortszeit beginnt und [minutes]
/// dauert (Versatz der Prozesszone).
Future<int> _runAt(
  StorageSession s,
  DateTime d,
  int h,
  int m, {
  int minutes = 40,
}) async {
  final start = _at(d, h, m);
  final end = start.add(Duration(minutes: minutes));
  final r = await s.runs.create(startedAt: start);
  await s.runs.setState(
    r.id,
    RunState.finished,
    endedAt: end,
    endedUtcOffset: end.timeZoneOffset,
  );
  return r.id;
}

Future<Map<int, int?>> _assigned(WorkflowEnv e) async => {
  for (final u in await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture))
    if (u.runId != null) u.id!: u.runId,
};

Future<PlanUnit?> _unitOn(WorkflowEnv e, DateTime day) => e.plans.unitOn(day);

/// Ein zweiter Dienst auf derselben Sitzung, wie nach einem Neustart der App.
PlanWorkflowService _again(WorkflowEnv e) => PlanWorkflowService(
  session: e.session,
  clock: e.clock,
  reader: e.reader,
  pauses: WorkflowPauses(e),
);

/// Öffnen über [service] (Neustart, Prüfung, Zuordnung) wie [WorkflowEnv.open].
Future<void> _openWith(PlanWorkflowService service) async {
  await service.restartIfDue();
  await service.runDue(await service.dueCheck());
  await service.autoAssignQuietly();
}

void main() {
  final today = workflowToday;
  DateTime day(int n) => workflowDay(n);

  group('PAR-231: Läufe zählen automatisch für die offene Einheit', () {
    test('Lauf um 17:30, Plan um 19:00 desselben Tags: die heutige Einheit '
        'ist erledigt (FR-0156)', () async {
      final e = await WorkflowEnv.open();
      final run = await _runAt(e.session, today, 17, 30);
      e.clock.set(_at(today, 19));
      await e.service.saveGoal(_goal({1, 3, 5}));
      final unit = await _unitOn(e, today);
      expect(unit, isNotNull);
      expect(unit!.runId, run);
    });

    test('Lauf gestern, Plan heute: keine Einheit gestern, nichts '
        'zugeordnet', () async {
      final e = await WorkflowEnv.open();
      await _runAt(e.session, day(-1), 17, 30);
      await e.service.saveGoal(_goal({2, 3, 5}));
      expect(await _unitOn(e, day(-1)), isNull);
      expect(await _assigned(e), isEmpty);
      expect((await e.plans.history()).map((v) => v.trigger), [
        PlanTrigger.create,
      ]);
    });

    test('Idempotenz: Plan und App erneut öffnen ändert nichts und rechnet '
        'nicht noch einmal', () async {
      final e = await WorkflowEnv.open();
      final run = await _runAt(e.session, today, 7, 0);
      await e.service.saveGoal(_goal({1, 3, 5}));
      final before = await _assigned(e);
      final versions = (await e.plans.history()).length;
      expect(before.values, [run]);
      await e.openPlan();
      await e.openPlan();
      await _openWith(_again(e));
      expect(await _assigned(e), before);
      expect((await e.plans.history()).length, versions);
    });

    test('Öffnen ordnet einen Lauf der Woche nachträglich zu', () async {
      final e = await WorkflowEnv.open();
      await e.service.saveGoal(_goal({1, 3, 5}));
      expect(await _assigned(e), isEmpty);
      final run = await _runAt(e.session, today, 7, 0);
      await e.openPlan();
      expect((await _unitOn(e, today))!.runId, run);
    });

    test('Verschobene Einheit: Lauf am neuen Tag zählt, die Einheit am '
        'alten Tag bleibt ohne Lauf', () async {
      final e = await WorkflowEnv.open();
      await e.service.saveGoal(_goal({2, 4, 6}));
      expect(await _unitOn(e, today), isNull);
      final run = await _runAt(e.session, today, 7, 0);
      await e.openPlan();
      expect(await _assigned(e), isEmpty);
      final tomorrow = (await _unitOn(e, day(1)))!;
      await e.service.confirmMove(tomorrow.id!, today);
      final moved = (await _unitOn(e, today))!;
      expect(moved.kind, tomorrow.kind);
      expect(moved.runId, run);
      expect((await _unitOn(e, day(1)))?.runId, isNull);
      expect((await _assigned(e)).values, [run]);
    });

    test('Bestehende Zuordnung bleibt, auch wenn später ein längerer Lauf '
        'folgt', () async {
      final e = await WorkflowEnv.open();
      await e.service.saveGoal(_goal({1, 3, 5}));
      final short = await _runAt(e.session, today, 6, 0, minutes: 20);
      final unit = (await _unitOn(e, today))!;
      await e.service.assignRun(unit.id!, short, expectedRunId: null);
      await _runAt(e.session, today, 10, 0, minutes: 90);
      await e.openPlan();
      expect((await _unitOn(e, today))!.runId, short);
      expect((await _assigned(e)).values, [short]);
    });

    test('Zwei Läufe am Tag der Einheit: der längere zählt', () async {
      final e = await WorkflowEnv.open();
      await _runAt(e.session, today, 6, 0, minutes: 20);
      final long = await _runAt(e.session, today, 9, 0, minutes: 50);
      await e.service.saveGoal(_goal({1, 3, 5}));
      expect((await _unitOn(e, today))!.runId, long);
    });

    test(
      'Ein Lauf seit „Einheit starten“ bleibt dem Merker überlassen',
      () async {
        final e = await WorkflowEnv.open();
        await e.service.saveGoal(_goal({1, 3, 5}));
        final unit = (await _unitOn(e, today))!;
        e.clock.set(_at(today, 13));
        await e.session.settings.set(
          SettingKeys.planStartedUnit,
          PlanStartedUnit(
            unitId: unit.id!,
            day: workflowDayText(today),
            since: _at(today, 13).toUtc(),
          ).encode(),
          at: e.clock.now(),
        );
        await _runAt(e.session, today, 13, 1);
        await e.openPlan();
        expect((await _unitOn(e, today))!.runId, isNull);
      },
    );

    test(
      'Lauf Sonntag 23:50 bis Montag 00:20: die Einheit vom Sonntag '
      'trägt den Lauf, auch wenn die Zuordnung erst am Montag läuft',
      () async {
        final e = await WorkflowEnv.open();
        final sunday = day(4);
        expect(sunday.weekday, DateTime.sunday);
        await e.service.saveGoal(_goal({3, 5, 7}));
        expect((await _unitOn(e, sunday))?.runId, isNull);
        final run = await _runAt(e.session, sunday, 23, 50, minutes: 30);
        // Uhr am Montag kurz nach Mitternacht: die Woche beginnt heute, der
        // Starttag des Laufs liegt davor.
        e.clock.set(_at(day(5), 0, 25));
        expect(await e.service.autoAssign(since: sunday), 1);
        expect((await _unitOn(e, sunday))!.runId, run);
        expect((await _unitOn(e, day(5)))?.runId, isNull);
      },
    );

    group('Öffnen holt ab dem Sonntag der Vorwoche nach (PAR-231)', () {
      final sunday = day(4);
      final monday = day(5);
      final saturday = day(3);

      /// Plan mit Einheiten am Mittwoch, Samstag und Sonntag; noch kein Lauf.
      Future<WorkflowEnv> planned() async {
        expect(sunday.weekday, DateTime.sunday);
        expect(saturday.weekday, DateTime.saturday);
        final e = await WorkflowEnv.open();
        await e.service.saveGoal(_goal({3, 6, 7}));
        expect((await _unitOn(e, sunday))?.runId, isNull);
        expect(await _assigned(e), isEmpty);
        return e;
      }

      test('Lauf Sonntag 23:50 bis Montag 00:20 ohne Zuordnung nach dem '
          'Lauf: Öffnen am Montag 00:25 ordnet ihn der Einheit vom Sonntag '
          'zu, nicht der vom Montag', () async {
        final e = await planned();
        final run = await _runAt(e.session, sunday, 23, 50, minutes: 30);
        e.clock.set(_at(monday, 0, 25));
        await e.openPlan();
        expect((await _unitOn(e, sunday))!.runId, run);
        expect((await _unitOn(e, monday))?.runId, isNull);
        expect((await _assigned(e)).values, [run]);
      });

      test('Lauf Sonntag 18:00 bis 18:40, Öffnen erst am Dienstag: '
          'zugeordnet', () async {
        final e = await planned();
        final run = await _runAt(e.session, sunday, 18, 0);
        e.clock.set(_at(day(6), 9));
        await e.openPlan();
        expect((await _unitOn(e, sunday))!.runId, run);
        expect((await _assigned(e)).values, [run]);
      });

      test('Lauf am Samstag der Vorwoche, Öffnen am Montag: außerhalb des '
          'Fensters, die Einheit bleibt offen', () async {
        final e = await planned();
        final unit = (await _unitOn(e, saturday))!;
        expect(unit.kind, isNot(PlanUnitKind.rest));
        await _runAt(e.session, saturday, 9, 0);
        e.clock.set(_at(monday, 9));
        await e.openPlan();
        final after = (await _unitOn(e, saturday))!;
        expect(after.kind, unit.kind);
        expect(after.runId, isNull);
        expect(await _assigned(e), isEmpty);
      });

      test('Lauf am Samstag der Vorwoche, Zuordnung am Montag mit dem '
          'Starttag des Laufs: die Einheit vom Samstag trägt den Lauf; ohne '
          'Starttag bleibt sie offen', () async {
        // Gegenprobe: ohne Starttag beginnt das Fenster am Sonntag.
        final plain = await planned();
        final unit = (await _unitOn(plain, saturday))!;
        expect(unit.kind, isNot(PlanUnitKind.rest));
        await _runAt(plain.session, saturday, 9, 0);
        plain.clock.set(_at(monday, 9));
        expect(await plain.service.autoAssign(), 0);
        expect((await _unitOn(plain, saturday))!.runId, isNull);
        expect(await _assigned(plain), isEmpty);

        // Mit dem Starttag des Laufs (Samstag) reicht das Fenster zurück.
        final e = await planned();
        final run = await _runAt(e.session, saturday, 9, 0);
        e.clock.set(_at(monday, 9));
        expect(await e.service.autoAssign(since: saturday), 1);
        final after = (await _unitOn(e, saturday))!;
        expect(after.kind, unit.kind);
        expect(after.runId, run);
        expect((await _assigned(e)).values, [run]);
      });

      test('Starttag nach dem Sonntag der Vorwoche (Montag): das Fenster '
          'beginnt weiter am Sonntag, der Lauf vom Sonntag wird '
          'zugeordnet', () async {
        final e = await planned();
        final run = await _runAt(e.session, sunday, 18, 0);
        e.clock.set(_at(monday, 9));
        expect(await e.service.autoAssign(since: monday), 1);
        expect((await _unitOn(e, sunday))!.runId, run);
        expect((await _assigned(e)).values, [run]);
      });

      test('Idempotenz: erneutes Öffnen ordnet nichts weiter zu und schreibt '
          'keine weitere Fassung', () async {
        final e = await planned();
        final run = await _runAt(e.session, sunday, 23, 50, minutes: 30);
        e.clock.set(_at(monday, 0, 25));
        await e.openPlan();
        final before = await _assigned(e);
        final versions = (await e.plans.history()).length;
        expect(before.values, [run]);
        expect((await e.plans.history()).last.trigger, PlanTrigger.run);
        await e.openPlan();
        await _openWith(_again(e));
        expect(await _assigned(e), before);
        expect((await e.plans.history()).length, versions);
      });

      test('Zuordnung über „Einheit starten“ am Sonntag bleibt, auch mit '
          'einem längeren freien Lauf am Sonntag', () async {
        final e = await planned();
        final unit = (await _unitOn(e, sunday))!;
        final short = await _runAt(e.session, sunday, 8, 1, minutes: 20);
        await e.service.assignStartedRun(
          unitId: unit.id!,
          day: workflowDayText(sunday),
          runId: short,
        );
        expect((await _unitOn(e, sunday))!.runId, short);
        final long = await _runAt(e.session, sunday, 18, 0, minutes: 90);
        e.clock.set(_at(monday, 9));
        await e.openPlan();
        expect((await _unitOn(e, sunday))!.runId, short);
        expect((await _assigned(e)).values, [short]);
        expect((await _assigned(e)).values, isNot(contains(long)));
      });
    });

    test('Zuordnung über „Einheit starten“: ersetzte Einheit (neue Kennung) '
        '→ die offene Einheit desselben Tags', () async {
      final e = await WorkflowEnv.open();
      await e.service.saveGoal(_goal({1, 3, 5}));
      final unit = (await _unitOn(e, today))!;
      final run = await _runAt(e.session, today, 7, 0);
      await e.service.assignStartedRun(
        unitId: unit.id! + 1000,
        day: workflowDayText(today),
        runId: run,
      );
      expect((await _unitOn(e, today))!.runId, run);
      // Ohne offene Einheit am Tag bleibt es bei `notFound`.
      await expectLater(
        e.service.assignStartedRun(
          unitId: unit.id! + 1000,
          day: workflowDayText(day(-1)),
          runId: run,
        ),
        throwsA(
          isA<StorageException>().having(
            (x) => x.failure,
            'failure',
            StorageFailure.notFound,
          ),
        ),
      );
    });

    test('Zuordnung über „Einheit starten“: ersetzte Einheit, die Einheit des '
        'Tags trägt schon einen Lauf → `notFound`, die bestehende Zuordnung '
        'bleibt (PAR-231)', () async {
      final e = await WorkflowEnv.open();
      await e.service.saveGoal(_goal({1, 3, 5}));
      final first = await _runAt(e.session, today, 7, 0);
      await e.service.assignRun(
        (await _unitOn(e, today))!.id!,
        first,
        expectedRunId: null,
      );
      // Die Zuordnung rechnet neu und kann Kennungen ersetzen: neu lesen.
      final unit = (await _unitOn(e, today))!;
      expect(unit.runId, first);
      final second = await _runAt(e.session, today, 12, 0);
      final versions = (await e.plans.history()).length;
      await expectLater(
        e.service.assignStartedRun(
          unitId: unit.id! + 1000,
          day: workflowDayText(today),
          runId: second,
        ),
        throwsA(
          isA<StorageException>().having(
            (x) => x.failure,
            'failure',
            StorageFailure.notFound,
          ),
        ),
      );
      expect((await _unitOn(e, today))!.runId, first);
      expect((await _assigned(e)).values, [first]);
      expect((await _assigned(e)).values, isNot(contains(second)));
      expect((await e.plans.history()).length, versions);
    });
  });

  group('Fenster der Zuordnung (PAR-231) an den Grenzen', () {
    test('Montag: Fenster ab dem Vortag (Sonntag)', () {
      expect(
        planAutoAssignFrom(DateTime.utc(2026, 11, 16)),
        DateTime.utc(2026, 11, 15),
      );
    });

    test('Sonntag: Fenster ab dem Sonntag der Vorwoche, nicht ab heute', () {
      expect(
        planAutoAssignFrom(DateTime.utc(2026, 11, 22)),
        DateTime.utc(2026, 11, 15),
      );
    });

    test('Starttag: früher erweitert, gleich oder später nicht', () {
      final monday = DateTime.utc(2026, 11, 16);
      final sunday = DateTime.utc(2026, 11, 15);
      final saturday = DateTime.utc(2026, 11, 14);
      expect(planAutoAssignFrom(monday, since: saturday), saturday);
      expect(planAutoAssignFrom(monday, since: sunday), sunday);
      expect(planAutoAssignFrom(monday, since: monday), sunday);
    });
  });
}
