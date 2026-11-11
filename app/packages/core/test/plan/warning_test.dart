import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 11, 8).add(Duration(days: n));

TrainingGoal _goal({int capMin = 240}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|'
    '${u.minutes}|${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Env {
  _Env(this.session)
    : plans = (session as PlanStorage).plans,
      goals = (session as GoalStorage).goals,
      warning = (session as WarningStorage).warning {
    service = WarningService(
      plans: plans,
      settings: session.settings,
      warning: warning,
    );
  }
  final StorageSession session;
  final PlanRepository plans;
  final GoalStore goals;
  final WarningStore warning;
  late final WarningService service;

  static Future<_Env> open() async => _Env(
    await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
  );

  Future<List<PlanUnit>> all() => plans.unitsBetween(_day(-400), _day(800));

  Future<List<String>> sigs() async => [for (final u in await all()) _sig(u)];

  Future<PlanRecalculation> recalc(PlanTrigger t, int n) => recalculatePlan(
    plans: plans,
    settings: session.settings,
    trigger: t,
    today: _day(n),
    now: _now(n),
    warning: warning,
  );

  /// Plan mit Festlegungen: tempo statt locker (fixed=kind), hart -> locker
  /// (easyForHard), ein Ruhetag des Nutzers (fixed=day).
  static Future<_Env> withFixed() async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.recalc(PlanTrigger.create, 0);
    final goal = (await e.plans.currentGoal())!;
    var inputs = (await e.plans.history()).last.inputs;
    var units = await e.all();
    Future<void> replace(PlanUnit u, PlanUnitKind k) async {
      final c = checkPlanReplace(
        units: units,
        unit: u,
        kind: k,
        goal: goal,
        inputs: inputs,
        today: _day(0),
      );
      expect(c.blocked, isNull);
      await e.plans.replaceUnit(u.id!, c.unit!, today: _day(0));
      units = await e.all();
    }

    await replace(
      units.firstWhere(
        (u) => u.kind == PlanUnitKind.easy && u.day.isAfter(_day(14)),
      ),
      PlanUnitKind.tempo,
    );
    await replace(
      units.firstWhere((u) => u.isHard && u.day.isAfter(_day(30))),
      PlanUnitKind.easy,
    );
    final restOn = units.firstWhere((u) => u.day.isAfter(_day(45)));
    await e.plans.setRestDay(
      planRestDayUnit(
        day: restOn.day,
        goal: goal,
        inputs: inputs,
        today: _day(0),
      ),
      today: _day(0),
      expectedUnitId: restOn.id,
    );
    inputs = (await e.plans.history()).last.inputs;
    return e;
  }
}

Future<PlanUnit> _single(_Env e, bool Function(PlanUnit) f) async =>
    (await e.all()).firstWhere(f);

void main() {
  group('Warnsignal: Vorrang und Wiederherstellung (FR-0203, K58)', () {
    test('Ruhetage ab heute auch bei fixed=kind/easyForHard; nach dem '
        'Aufheben gleicher Plan wie vorher', () async {
      final e = await _Env.withFixed();
      final before = await e.sigs();
      final fixedKinds = {
        for (final u in await e.all())
          if (u.fixed != PlanUnitFixed.none) u.fixed,
      };
      expect(
        fixedKinds,
        containsAll({
          PlanUnitFixed.kind,
          PlanUnitFixed.easyForHard,
          PlanUnitFixed.day,
        }),
      );
      final base = (await e.plans.history()).length;

      final r = await e.service.report(
        source: WarningSource.manual,
        today: _day(3),
        now: _now(3),
      );
      expect(r.version!.trigger, PlanTrigger.feedback);
      expect(r.version!.reason, 'warning');
      final during = await e.all();
      for (final u in during.where((u) => !u.day.isBefore(_day(3)))) {
        expect(u.kind, PlanUnitKind.rest, reason: '${u.day}');
      }
      // Festlegung bleibt (fixed, pinned), nur die Art ruht.
      final byDay = {for (final u in during) u.day: u};
      for (final u in await _beforeUnits(before)) {
        if (!u.day.isBefore(_day(3)) && u.fixed != PlanUnitFixed.none) {
          expect(byDay[u.day]!.fixed, u.fixed);
          expect(byDay[u.day]!.pinned, u.pinned);
        }
      }

      // Doppelt melden: idempotent, keine zweite Fassung.
      final again = await e.service.report(
        source: WarningSource.runFeedback,
        today: _day(3),
        now: _now(3),
        runId: 5,
      );
      expect(again.wasWritten, isFalse);
      expect((await e.plans.history()).length, base + 1);
      expect((await e.warning.read())!.source, WarningSource.manual);

      final lifted = await e.service.lift(today: _day(3), now: _now(3));
      expect(lifted.version!.reason, 'warningLifted');
      expect(lifted.version!.trigger, PlanTrigger.feedback);
      expect(await e.warning.read(), isNull);
      expect(await e.sigs(), before);
      // Aufheben ohne Warnsignal: nichts Neues.
      final n = (await e.plans.history()).length;
      expect(
        (await e.service.lift(today: _day(3), now: _now(3))).wasWritten,
        isFalse,
      );
      expect((await e.plans.history()).length, n);
    });

    test('Ruhetag, den der Nutzer unter Warnsignal festlegt, übersteht das '
        'Aufheben (ADR-0010)', () async {
      final e = await _Env.withFixed();
      final before = await e.all();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(3),
        now: _now(3),
      );
      final goal = (await e.plans.currentGoal())!;
      final inputs = (await e.plans.history()).last.inputs;
      final target = (await e.all()).firstWhere(
        (u) =>
            u.day.isAfter(_day(10)) &&
            u.kind == PlanUnitKind.rest &&
            !u.pinned &&
            before.any(
              (b) =>
                  b.day == u.day && b.kind != PlanUnitKind.rest && !b.pinned,
            ),
      );
      await e.plans.setRestDay(
        planRestDayUnit(
          day: target.day,
          goal: goal,
          inputs: inputs,
          today: _day(3),
        ),
        today: _day(3),
        expectedUnitId: target.id,
      );
      await e.service.lift(today: _day(3), now: _now(3));
      final after = {for (final u in await e.all()) u.day: u};
      final kept = after[target.day]!;
      expect(kept.kind, PlanUnitKind.rest);
      expect(kept.pinned, isTrue);
      expect(kept.fixed, PlanUnitFixed.day);
      // Die übrigen gehaltenen Tage kehren zurück.
      final other = before.firstWhere(
        (b) =>
            b.day.isAfter(_day(3)) &&
            b.day != target.day &&
            b.kind != PlanUnitKind.rest,
      );
      expect(after[other.day]!.kind, other.kind);
    });

    test('Neuberechnung unter Warnsignal (manual, weekly, run, '
        'goalChange): bleibt Ruhe, nach Aufheben wie ohne Warnsignal', () async {
      final e = await _Env.withFixed();
      final ref = await _Env.withFixed();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(1),
        now: _now(1),
      );
      var k = 1;
      for (final (t, cap) in [
        (PlanTrigger.manual, 200),
        (PlanTrigger.weekly, 200),
        (PlanTrigger.run, 200),
        (PlanTrigger.goalChange, 260),
      ]) {
        k += 1;
        final g = _goal(capMin: cap);
        await e.goals.save(g, today: g.createdAt);
        await ref.goals.save(g, today: g.createdAt);
        await e.recalc(t, k);
        await ref.warning.lift();
        await ref.recalc(t, k);
        for (final u in (await e.all()).where(
          (u) => !u.day.isBefore(_day(k)),
        )) {
          expect(u.kind, PlanUnitKind.rest, reason: '${t.name} ${u.day}');
        }
      }
      await e.service.lift(today: _day(k), now: _now(k));
      // Tage, die unter dem Warnsignal vergingen, waren Ruhetage (eingefroren).
      List<String> from(List<PlanUnit> us) => [
        for (final u in us)
          if (!u.day.isBefore(_day(k))) _sig(u),
      ];
      expect(from(await e.all()), from(await ref.all()));
    });

    test('absolvierte und zugeordnete Einheiten bleiben unverändert', () async {
      final e = await _Env.withFixed();
      final first = await _single(e, (u) => !u.day.isBefore(_day(0)));
      final run = await e.session.runs.create(startedAt: _now(0));
      await e.plans.assignRun(first.id!, run.id);
      final past = await _single(e, (u) => u.runId == run.id);
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      final after = await e.all();
      expect(_sig(after.firstWhere((u) => u.runId == run.id)), _sig(past));
      expect(
        after
            .where((u) => u.runId == null && !u.day.isBefore(_day(0)))
            .every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
    });

    test('Warnsignal übersteht das Löschen des Laufs (deleteRun)', () async {
      final e = await _Env.withFixed();
      final run = await e.session.runs.create(startedAt: _now(0));
      await e.service.report(
        source: WarningSource.runFeedback,
        today: _day(0),
        now: _now(0),
        runId: run.id,
      );
      await e.session.deleteRun(run.id);
      final w = await e.warning.read();
      expect(w!.source, WarningSource.runFeedback);
      expect(w.runId, run.id);
      expect(
        (await e.all())
            .where((u) => !u.day.isBefore(_day(0)))
            .every((u) => u.kind == PlanUnitKind.rest),
        isTrue,
      );
    });

    test('Scheitert das Schreiben beim Aufheben, stellt die nächste '
        'Neuberechnung die Festlegungen her', () async {
      final e = await _Env.withFixed();
      final before = await e.sigs();
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      await e.warning.lift(); // Dienst nach dem Aufheben abgebrochen
      await e.recalc(PlanTrigger.weekly, 0);
      expect(await e.sigs(), before);
    });
  });

  test('applyWarningRest: Einheit mit Lauf und vergangene bleiben', () {
    PlanUnit u(int n, {int? runId}) => PlanUnit(
      day: _day(n),
      kind: PlanUnitKind.easy,
      phase: PlanPhase.entry,
      weekIndex: 0,
      minutes: 30,
      segments: const [],
      runId: runId,
      fixed: PlanUnitFixed.kind,
      pinned: true,
    );
    final out = applyWarningRest([u(0), u(1, runId: 3), u(2)], _day(1));
    expect(out.map((x) => x.kind), [
      PlanUnitKind.easy,
      PlanUnitKind.easy,
      PlanUnitKind.rest,
    ]);
    expect(out[2].fixed, PlanUnitFixed.kind);
    expect(out[2].pinned, isTrue);
  });

  group('Erinnerung (reine Funktion)', () {
    test('fällig nach 7 Tagen', () {
      final on = DateTime.utc(2026, 11, 1);
      expect(
        warningReminderDue(reportedOn: on, today: DateTime.utc(2026, 11, 7)),
        isFalse,
      );
      expect(
        warningReminderDue(reportedOn: on, today: DateTime.utc(2026, 11, 8)),
        isTrue,
      );
    });

    test('Dienst: fällig nur mit Warnsignal', () async {
      final e = await _Env.open();
      expect(await e.service.reminderDue(_day(30)), isFalse);
      await e.service.report(
        source: WarningSource.manual,
        today: _day(0),
        now: _now(0),
      );
      expect(await e.service.reminderDue(_day(6)), isFalse);
      expect(await e.service.reminderDue(_day(7)), isTrue);
    });
  });
}

Future<List<PlanUnit>> _beforeUnits(List<String> sigs) async => [
  // Nur für den Vergleich der Festlegungen: aus den Signaturen gelesen.
  for (final s in sigs)
    () {
      final p = s.split('|');
      return PlanUnit(
        day: DateTime.parse(p[0]),
        kind: PlanUnitKind.values.byName(p[1]),
        phase: PlanPhase.values.byName(p[2]),
        weekIndex: int.parse(p[3]),
        minutes: int.parse(p[4]),
        segments: const [],
        pinned: p[6] == 'true',
        fixed: PlanUnitFixed.values.byName(p[7]),
      );
    }(),
];
