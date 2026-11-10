import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 11, 8).add(Duration(days: n));

TrainingGoal _goal({Set<int> days = const {2, 4, 6}, int capMin = 240}) =>
    TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime(2027, 6, 1),
      runDays: days,
      maxSessionSeconds: 7200,
      weeklyCapSeconds: capMin * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: true,
      canRun30: ContinuousRun30.yes,
    );

TrainingGoal _open(Set<int> days) => TrainingGoal(
  type: GoalType.open,
  runDays: days,
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.phase.name}|${u.weekIndex}|'
    '${u.minutes}|${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.runId}';

Future<List<PlanUnit>> _all(PlanRepository p) =>
    p.unitsBetween(_day(-400), _day(800));

class _Env {
  _Env(this.session)
    : plans = (session as PlanStorage).plans,
      goals = (session as GoalStorage).goals;
  final StorageSession session;
  final PlanRepository plans;
  final GoalStore goals;
  SettingsStore get settings => session.settings;

  static Future<_Env> open() async => _Env(
    await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
  );

  Future<PlanRecalculation> run(
    PlanTrigger t,
    int dayOffset, {
    PlanRepository? repo,
  }) => recalculatePlan(
    plans: repo ?? plans,
    settings: settings,
    trigger: t,
    today: _day(dayOffset),
    now: _now(dayOffset),
  );
}

class _FailingWrite implements PlanRepository {
  _FailingWrite(this._inner);
  final PlanRepository _inner;
  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft d) async =>
      throw const StorageException(StorageFailure.failed);
  @override
  Future<TrainingGoal?> currentGoal() => _inner.currentGoal();
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime a, DateTime b) =>
      _inner.unitsBetween(a, b);
  @override
  Future<PlanUnit?> unitOn(DateTime d) => _inner.unitOn(d);
  @override
  Future<List<PlanVersionRecord>> history() => _inner.history();
  @override
  Future<void> assignRun(int u, int? r) => _inner.assignRun(u, r);
  @override
  Future<void> confirmMove(int u, DateTime d, {required DateTime today}) =>
      _inner.confirmMove(u, d, today: today);
  @override
  Future<void> replaceUnit(int u, PlanUnit r, {required DateTime today}) =>
      _inner.replaceUnit(u, r, today: today);
  @override
  Future<void> setRestDay(
    PlanUnit r, {
    required DateTime today,
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) => _inner.setRestDay(
    r,
    today: today,
    expectedUnitId: expectedUnitId,
    moveUnitTo: moveUnitTo,
  );
  @override
  Future<void> clearRestDay(DateTime d, {required DateTime today}) =>
      _inner.clearRestDay(d, today: today);
}

/// Lehnt die ersten [rejections] Schreibversuche mit `rejected` ab und zählt
/// Lesen und Schreiben.
class _RejectingWrite implements PlanRepository {
  _RejectingWrite(this._inner, this.rejections, {this.failure});
  final PlanRepository _inner;
  final int rejections;
  final StorageFailure? failure;
  int writes = 0;
  int reads = 0;
  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft d) {
    writes++;
    if (writes <= rejections) {
      throw StorageException(failure ?? StorageFailure.rejected);
    }
    return _inner.writeVersion(d);
  }

  @override
  Future<TrainingGoal?> currentGoal() => _inner.currentGoal();
  @override
  Future<List<PlanUnit>> unitsBetween(DateTime a, DateTime b) {
    reads++;
    return _inner.unitsBetween(a, b);
  }

  @override
  Future<PlanUnit?> unitOn(DateTime d) => _inner.unitOn(d);
  @override
  Future<List<PlanVersionRecord>> history() => _inner.history();
  @override
  Future<void> assignRun(int u, int? r) => _inner.assignRun(u, r);
  @override
  Future<void> confirmMove(int u, DateTime d, {required DateTime today}) =>
      _inner.confirmMove(u, d, today: today);
  @override
  Future<void> replaceUnit(int u, PlanUnit r, {required DateTime today}) =>
      _inner.replaceUnit(u, r, today: today);
  @override
  Future<void> setRestDay(
    PlanUnit r, {
    required DateTime today,
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) => _inner.setRestDay(
    r,
    today: today,
    expectedUnitId: expectedUnitId,
    moveUnitTo: moveUnitTo,
  );
  @override
  Future<void> clearRestDay(DateTime d, {required DateTime today}) =>
      _inner.clearRestDay(d, today: today);
}

void main() {
  group('rejected beim Schreiben (T1)', () {
    test(
      'einmal rejected: genau einmal neu lesen, rechnen, schreiben',
      () async {
        final e = await _Env.open();
        await e.goals.save(_goal(), today: _goal().createdAt);
        final repo = _RejectingWrite(e.plans, 1);
        final r = await e.run(PlanTrigger.create, 0, repo: repo);
        expect(r.wasWritten, isTrue);
        expect(repo.writes, 2);
        expect(repo.reads, 2);
        expect((await e.plans.history()).length, 1);
      },
    );

    test('zweites rejected wird gemeldet, kein dritter Versuch', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      final repo = _RejectingWrite(e.plans, 5);
      await expectLater(
        e.run(PlanTrigger.create, 0, repo: repo),
        throwsA(
          isA<StorageException>().having(
            (x) => x.failure,
            'failure',
            StorageFailure.rejected,
          ),
        ),
      );
      expect(repo.writes, 2);
      expect(await e.plans.history(), isEmpty);
    });

    test('anderer Fehler wird nicht wiederholt', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      final repo = _RejectingWrite(e.plans, 5, failure: StorageFailure.failed);
      await expectLater(
        e.run(PlanTrigger.create, 0, repo: repo),
        throwsA(isA<StorageException>()),
      );
      expect(repo.writes, 1);
    });
  });

  test('ohne Ziel: nichts gerechnet, nichts geschrieben', () async {
    final e = await _Env.open();
    final r = await e.run(PlanTrigger.weekly, 0);
    expect(r.hasGoal, isFalse);
    expect(r.wasWritten, isFalse);
    expect(await e.plans.history(), isEmpty);
    expect(await e.settings.get(planLastCheckDayKey), isNull);
  });

  test('erste Fassung: Einheiten wie generatePlan, Eingaben und Version '
      'gespeichert, Prüftag gesetzt', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    final r = await e.run(PlanTrigger.create, 0);
    expect(r.wasWritten, isTrue);
    final goal = (await e.plans.currentGoal())!;
    final direct = generatePlan(
      goal,
      PlanInputs.forNewGoal(goal, _day(0)),
      const [],
      _day(0),
    );
    final stored = await _all(e.plans);
    expect(stored.map(_sig), direct.units.map(_sig));
    expect(stored, isNotEmpty);
    final h = (await e.plans.history()).single;
    expect(h.trigger, PlanTrigger.create);
    expect(h.reason, 'create');
    expect(h.version, const PlanVersion());
    expect(h.validFrom, _day(0));
    expect(h.inputs.toJson(), PlanInputs.forNewGoal(goal, _day(0)).toJson());
    expect(h.summary['changedUnitCount'], stored.length);
    expect(stored.every((u) => u.method == planMethod), isTrue);
    expect(await e.settings.get(planLastCheckDayKey), '2026-11-11');
  });

  test('gleiche Einheiten: keine neue Fassung, nur der Prüftag wandert '
      '(auch am Folgetag, wenn die Vergangenheit einfriert)', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.run(PlanTrigger.create, 0);
    final before = (await _all(e.plans)).map(_sig).toList();
    for (final offset in [0, 1, 2, 5]) {
      final r = await e.run(PlanTrigger.weekly, offset);
      expect(r.hasGoal, isTrue);
      expect(r.wasWritten, isFalse, reason: 'Tag +$offset');
      expect(
        await e.settings.get(planLastCheckDayKey),
        _day(offset).toIso8601String().substring(0, 10),
      );
    }
    expect((await e.plans.history()).length, 1);
    expect((await _all(e.plans)).map(_sig), before);
  });

  test('Zieländerung: neue Fassung, Vergangenheit und Lauf-Einheiten bleiben, '
      'offene Zukunft ersetzt', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.run(PlanTrigger.create, 0);
    final run = (await e.session.runs.create(startedAt: _now(0))).id;
    final first = await _all(e.plans);
    // Heute ist Tag +7; eine künftige Einheit trägt einen Lauf.
    final withRun = first.firstWhere((u) => u.day.isAfter(_day(8)));
    await e.plans.assignRun(withRun.id!, run);
    final frozenBefore = [
      for (final u in await _all(e.plans))
        if (u.day.isBefore(_day(7)) || u.runId != null) _sig(u),
    ];
    expect(frozenBefore, isNotEmpty);

    await e.goals.save(
      _goal(days: {1, 3, 5, 7}),
      today: _goal(days: {1, 3, 5, 7}).createdAt,
    );
    final r = await e.run(PlanTrigger.goalChange, 7);
    expect(r.wasWritten, isTrue);
    final after = await _all(e.plans);
    final frozenAfter = [
      for (final u in after)
        if (u.day.isBefore(_day(7)) || u.runId != null) _sig(u),
    ];
    expect(frozenAfter, frozenBefore);
    expect(after.where((u) => u.day.isBefore(_day(7))).length, greaterThan(0));
    // Offene Zukunft: nur noch neue Lauftage (Mo, Mi, Fr, So) oder die Lauf-Einheit.
    for (final u in after.where(
      (u) => !u.day.isBefore(_day(7)) && u.runId == null,
    )) {
      expect({1, 3, 5, 7}, contains(u.day.weekday), reason: '${u.day}');
    }
    expect((await e.plans.history()).length, 2);
    expect((await e.plans.history()).last.trigger, PlanTrigger.goalChange);
  });

  test('pinned: der bestätigte Termin bleibt bei der Neuberechnung', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.run(PlanTrigger.create, 0);
    final units = await _all(e.plans);
    // Nächste Woche: erste Einheit auf einen freien Tag legen.
    final moving = units.firstWhere((u) => u.day.isAfter(_day(8)));
    var target = moving.day.add(const Duration(days: 1));
    while (units.any((u) => u.day == target) ||
        units.any(
          (u) =>
              u.id != moving.id &&
              (u.day.difference(target).inDays).abs() < 2 &&
              u.isIntensive &&
              moving.isIntensive,
        )) {
      target = target.add(const Duration(days: 1));
    }
    await e.plans.confirmMove(moving.id!, target, today: _day(0));
    await e.goals.save(_goal(capMin: 200), today: _goal(capMin: 200).createdAt);
    final r = await e.run(PlanTrigger.manual, 0);
    final pinned = (await _all(e.plans)).where((u) => u.pinned).toList();
    expect(pinned, hasLength(1), reason: '${r.generated?.pinnedConflicts}');
    expect(pinned.single.day, target);
  });

  test('Wiederholung mit den gespeicherten Eingaben ergibt dieselben '
      'künftigen Einheiten (Determinismus über den Speicher)', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.run(PlanTrigger.create, 0);
    await e.goals.save(
      _goal(days: {1, 3, 5, 7}),
      today: _goal(days: {1, 3, 5, 7}).createdAt,
    );
    await e.run(PlanTrigger.goalChange, 7);
    final rec = (await e.plans.history()).last;
    final goal = (await e.plans.currentGoal())!;
    final all = await _all(e.plans);
    final frozen = [
      for (final u in all)
        if (u.day.isBefore(rec.validFrom) || u.runId != null) u,
    ];
    final again = generatePlan(goal, rec.inputs, frozen, rec.validFrom);
    final future = [
      for (final u in all)
        if (!u.day.isBefore(rec.validFrom) && u.runId == null) u,
    ];
    expect(future, isNotEmpty);
    expect(again.units.map(_sig), future.map(_sig));
  });

  test('Abbruch beim Schreiben: alter Plan und Prüftag bleiben', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    await e.run(PlanTrigger.create, 0);
    final before = (await _all(e.plans)).map(_sig).toList();
    await e.goals.save(
      _goal(days: {1, 3, 5, 7}),
      today: _goal(days: {1, 3, 5, 7}).createdAt,
    );
    await expectLater(
      e.run(PlanTrigger.goalChange, 7, repo: _FailingWrite(e.plans)),
      throwsA(isA<StorageException>()),
    );
    expect((await _all(e.plans)).map(_sig), before);
    expect((await e.plans.history()).length, 1);
    expect(await e.settings.get(planLastCheckDayKey), '2026-11-11');
  });

  group('Einfrieren und Inhaltsänderungen (Nachbesserung NB1)', () {
    test(
      'Einheit mit Lauf bleibt eingefroren, am Tag entsteht keine zweite',
      () async {
        final e = await _Env.open();
        await e.goals.save(_goal(), today: _goal().createdAt);
        await e.run(PlanTrigger.create, 0);
        final target = (await _all(e.plans))
            .firstWhere((u) => u.day.difference(_day(0)).inDays >= 70);
        final run = (await e.session.runs.create(startedAt: _now(0))).id;
        await e.plans.assignRun(target.id!, run);
        // Niedrigere Wochengrenze: alle künftigen Einheiten ändern ihre Dauer.
        await e.goals.save(
          _goal(capMin: 100),
          today: _goal(capMin: 100).createdAt,
        );
        final r = await e.run(PlanTrigger.goalChange, 1);
        expect(r.wasWritten, isTrue);
        expect(
          r.generated!.units.any((u) => u.day == target.day),
          isFalse,
          reason: 'nicht neu erzeugt',
        );
        final onDay = (await _all(e.plans)).where((u) => u.day == target.day);
        expect(onDay.length, 1);
        expect(onDay.single.id, target.id);
        expect(onDay.single.runId, run);
        expect(onDay.single.minutes, target.minutes);
      },
    );

    test('automatisch: bei mehr Lauftagen bleiben nur die alten Tage im '
        'alten Zeitraum', () async {
      final e = await _Env.open();
      await e.goals.save(_open({2, 4, 6}), today: _open({2, 4, 6}).createdAt);
      await e.run(PlanTrigger.create, 0);
      await e.goals.save(
        _open({1, 2, 3, 4, 5, 6}),
        today: _open({1, 2, 3, 4, 5, 6}).createdAt,
      );
      final r = await e.run(PlanTrigger.weekly, 7);
      final horizonEnd = DateTime.utc(
        2026,
        11,
        9,
      ).add(const Duration(days: 182));
      final inside = r.generated!.units.where(
        (u) => u.day.isBefore(horizonEnd),
      );
      expect(inside, isNotEmpty);
      expect(
        inside.every((u) => const {2, 4, 6}.contains(u.day.weekday)),
        isTrue,
      );
      final stored = (await _all(e.plans))
          .where((u) => !u.day.isBefore(_day(7)) && u.day.isBefore(horizonEnd));
      expect(
        stored.every((u) => const {2, 4, 6}.contains(u.day.weekday)),
        isTrue,
      );
    });

    test('reine Intensitätsänderung schreibt eine neue Fassung', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await e.run(PlanTrigger.create, 0);
      final before = await e.plans.history();
      final base = before.last.inputs;
      final r = await recalculatePlan(
        plans: e.plans,
        settings: e.settings,
        trigger: PlanTrigger.run,
        today: _day(7),
        now: _now(7),
        inputs: base.copyWith(
          today: _day(7),
          intensity: IntensityInputs(
            referenceSeconds: 3000,
            referenceMeters: 10000,
            referenceDate: _day(-10),
          ),
        ),
      );
      expect(r.wasWritten, isTrue);
      expect((await e.plans.history()).length, before.length + 1);
      final changed = r.summary!.changedUnits;
      expect(changed, isNotEmpty);
      expect(
        changed.every(
          (c) =>
              c.oldUnit!.kind == c.newUnit!.kind &&
              c.oldUnit!.minutes == c.newUnit!.minutes,
        ),
        isTrue,
        reason: 'nur die Intensität unterscheidet sich',
      );
    });
  });

  group('automatische Auslöser halten den Zeitplan (ADR-0010 Punkt 8)', () {
    // Offenes Ziel: 26 Wochen ab Montag 9.11.; nach 70 Tagen kommen Wochen
    // am Ende dazu. Zwischen den Läufen ändern sich die Lauftage.
    final horizonEnd = DateTime.utc(2026, 11, 9).add(const Duration(days: 182));

    Future<_Env> setup(PlanTrigger second) async {
      final e = await _Env.open();
      await e.goals.save(_open({2, 4, 6}), today: _open({2, 4, 6}).createdAt);
      await e.run(PlanTrigger.create, 0);
      await e.goals.save(_open({1, 3, 5}), today: _open({1, 3, 5}).createdAt);
      await e.run(second, 70);
      return e;
    }

    for (final t in [
      PlanTrigger.weekly,
      PlanTrigger.feedback,
      PlanTrigger.run,
      PlanTrigger.pause,
      PlanTrigger.ruleVersion,
    ]) {
      test('${t.name}: Tage und Zahl der Läufe im alten Zeitraum bleiben, '
          'neue Wochen am Ende kommen dazu', () async {
        final e = await setup(t);
        final units = (await _all(e.plans))
            .where((u) => !u.day.isBefore(_day(70)))
            .toList();
        final inside = units.where((u) => u.day.isBefore(horizonEnd)).toList();
        final beyond = units.where((u) => !u.day.isBefore(horizonEnd)).toList();
        expect(
          inside.every((u) => const {2, 4, 6}.contains(u.day.weekday)),
          isTrue,
        );
        expect(beyond, isNotEmpty);
        expect(
          beyond.every((u) => const {1, 3, 5}.contains(u.day.weekday)),
          isTrue,
        );
        // Zahl der Läufe je volle Woche im alten Zeitraum: 3.
        final perWeek = <DateTime, int>{};
        for (final u in inside.where((u) => !u.day.isBefore(_day(75)))) {
          final m = u.day.subtract(Duration(days: u.day.weekday - 1));
          perWeek[m] = (perWeek[m] ?? 0) + 1;
        }
        expect(perWeek.values.toSet(), {3});
        expect(units.any((u) => u.pinned), isFalse);
      });
    }

    for (final t in [PlanTrigger.goalChange, PlanTrigger.manual]) {
      test('${t.name}: darf Tage ändern', () async {
        final e = await setup(t);
        final units = (await _all(e.plans))
            .where((u) => !u.day.isBefore(_day(70)))
            .toList();
        expect(
          units.every((u) => const {1, 3, 5}.contains(u.day.weekday)),
          isTrue,
        );
      });
    }

    test('echte Termine (pinned) bleiben pinned, andere nicht', () async {
      final e = await _Env.open();
      await e.goals.save(_open({2, 4, 6}), today: _open({2, 4, 6}).createdAt);
      await e.run(PlanTrigger.create, 0);
      final units = await _all(e.plans);
      final moving = units.firstWhere((u) => u.day.isAfter(_day(8)));
      var target = moving.day.add(const Duration(days: 1));
      while (units.any((u) => u.day == target)) {
        target = target.add(const Duration(days: 1));
      }
      await e.plans.confirmMove(moving.id!, target, today: _day(0));
      await e.run(PlanTrigger.weekly, 1);
      final after = await _all(e.plans);
      expect(after.where((u) => u.pinned).map((u) => u.day), [target]);
    });
  });

  group(
    'Ersetzen und Ruhetag bleiben über Neuberechnungen (WP22, Schema 8)',
    () {
      DateTime monday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

      /// Ersetzt eine lockere Einheit ab Tag +14 durch tempo und legt eine
      /// Woche später einen Ruhetag auf den Tag einer Einheit (sie entfällt).
      Future<(_Env, DateTime, DateTime)> setup() async {
        final e = await _Env.open();
        await e.goals.save(_goal(), today: _goal().createdAt);
        await e.run(PlanTrigger.create, 0);
        final units = await _all(e.plans);
        final easy = units.firstWhere(
          (u) => u.kind == PlanUnitKind.easy && u.day.isAfter(_day(14)),
        );
        final check = checkPlanReplace(
          units: units,
          unit: easy,
          kind: PlanUnitKind.tempo,
          goal: (await e.plans.currentGoal())!,
          inputs: (await e.plans.history()).last.inputs,
          today: _day(0),
        );
        expect(check.blocked, isNull);
        await e.plans.replaceUnit(easy.id!, check.unit!, today: _day(0));
        final restOn = units.firstWhere(
          (u) => u.day.isAfter(easy.day.add(const Duration(days: 7))),
        );
        await e.plans.setRestDay(
          planRestDayUnit(
            day: restOn.day,
            goal: (await e.plans.currentGoal())!,
            inputs: (await e.plans.history()).last.inputs,
            today: _day(0),
          ),
          today: _day(0),
          expectedUnitId: restOn.id,
        );
        return (e, easy.day, restOn.day);
      }

      /// Harte Einheiten (Tag|Art) ab [from] außerhalb der Wochen von [skip].
      Future<List<String>> hard(
        _Env e,
        DateTime from,
        Set<DateTime> skip,
      ) async => [
        for (final u in await _all(e.plans))
          if (u.isHard &&
              !u.day.isBefore(from) &&
              !skip.contains(monday(u.day)))
            '${u.day.toIso8601String()}|${u.kind.name}',
      ];

      test('über manual, goalChange und weekly: Art bleibt (Dauer neu '
          'gerechnet), Ruhetag bleibt ohne Lauf, die übrigen harten Formen '
          'rotieren wie ohne Ersetzen (PAR-198)', () async {
        final (e, replaced, rest) = await setup();
        final ref = await _Env.open();
        await ref.goals.save(_goal(), today: _goal().createdAt);
        await ref.run(PlanTrigger.create, 0);
        final skip = {monday(replaced), monday(rest)};

        var offset = 0;
        for (final (t, goal) in [
          (PlanTrigger.manual, _goal(capMin: 200)),
          (PlanTrigger.goalChange, _goal(capMin: 260)),
          (PlanTrigger.weekly, null),
          (PlanTrigger.manual, null),
        ]) {
          offset += 1;
          for (final x in [e, ref]) {
            if (goal != null) await x.goals.save(goal, today: goal.createdAt);
            await x.run(t, offset);
          }
          final units = await _all(e.plans);
          final r = units.where((u) => u.day == replaced).single;
          expect(r.kind, PlanUnitKind.tempo, reason: t.name);
          expect(r.fixed, PlanUnitFixed.kind, reason: t.name);
          expect(r.pinned, isTrue, reason: t.name);
          expect(
            r.segments.fold<int>(0, (a, s) => a + s.minutes),
            r.minutes,
            reason: 'Dauer und Abschnitte neu gerechnet (${t.name})',
          );
          final onRest = units.where((u) => u.day == rest).toList();
          expect(onRest, hasLength(1), reason: t.name);
          expect(onRest.single.isRestDay, isTrue, reason: t.name);
          expect(onRest.single.fixed, PlanUnitFixed.day, reason: t.name);
          final h = await hard(e, _day(offset), skip);
          expect(h, await hard(ref, _day(offset), skip), reason: t.name);
          expect(
            {for (final x in h) x.split('|')[1]}.length,
            greaterThan(1),
            reason: 'Rotation läuft weiter (${t.name})',
          );
        }
      });
    },
  );

  test('previewPlan: gleiche Hinweise und Einheiten wie die Rechnung, '
      'ohne zu schreiben (WP22)', () async {
    final e = await _Env.open();
    await e.goals.save(_goal(), today: _goal().createdAt);
    final r = await e.run(PlanTrigger.create, 0);
    final last = (await e.plans.history()).last;
    final before = await _all(e.plans);
    final p = previewPlan(
      goal: _goal(),
      inputs: last.inputs.copyWith(today: _day(0)),
      units: before,
      today: _day(0),
    );
    expect(p.units.map(_sig), r.generated!.units.map(_sig));
    expect(p.hardFit, r.generated!.hardFit);
    expect(p.hardOmissions.keys, r.generated!.hardOmissions.keys);
    expect((await _all(e.plans)).map(_sig), before.map(_sig));
    expect(await e.plans.history(), hasLength(1));
  });

  test('Stand aus Läufen ersetzt „30 min: nein“ des Ziels auch in der '
      'Neuberechnung: harte Einheiten möglich (PAR-192, PAR-198)', () async {
    final e = await _Env.open();
    final goal = TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime(2027, 6, 1),
      runDays: const {2, 4, 6},
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: true,
      canRun30: ContinuousRun30.no,
    );
    await e.goals.save(goal, today: goal.createdAt);
    String text(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    // 12 Läufe zu 50 min in den letzten 6 Wochen (2 je Woche).
    final runs = [
      for (var i = 0; i < 12; i++)
        RunFigures(
          runId: i + 1,
          endedAt: _day(-1 - 3 * i).add(const Duration(hours: 8)),
          day: text(_day(-1 - 3 * i)),
          distanceMeters: 8000,
          movingTime: const Duration(minutes: 50),
          totalTime: const Duration(minutes: 50),
        ),
    ];
    final built = buildPlanInputs(goal: goal, today: _day(0), runs: runs);
    expect(built.inputs.walkRunStart, isNull);
    expect(built.inputs.startWeeklyMinutes, greaterThanOrEqualTo(100));

    final created = await recalculatePlan(
      plans: e.plans,
      settings: e.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: _now(0),
      inputs: built.inputs,
    );
    expect(created.generated!.units.where((u) => u.isHard), isNotEmpty);
    expect(
      created.generated!.hardOmissions.values,
      isNot(contains(HardOmission.notContinuous30)),
    );

    // Die wöchentliche Prüfung rechnet mit gespeichertem Ziel und den
    // gespeicherten Eingaben ebenso (ADR-0010 Punkt 6).
    final weekly = await e.run(PlanTrigger.weekly, 7);
    expect(weekly.generated!.units.where((u) => u.isHard), isNotEmpty);
    expect(
      weekly.generated!.hardOmissions.values,
      isNot(contains(HardOmission.notContinuous30)),
    );
    expect(
      planAllowsFiveKilometerTest(
        goal: goal,
        inputs: (await e.plans.history()).last.inputs,
        today: _day(7),
      ),
      isTrue,
    );
  });

  test('automatische Rechnung: ersetzte Art in einer Geh-Lauf-Woche gilt '
      'nicht mehr als vom Nutzer festgelegt (Festlegung WP22)', () async {
    final e = await _Env.open();
    final goal = TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime(2027, 6, 1),
      runDays: const {2, 4, 6},
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: true,
      canRun30: ContinuousRun30.no,
    );
    await e.goals.save(goal, today: goal.createdAt);
    await e.run(PlanTrigger.create, 0);
    final v = (await e.plans.history()).last;
    final units = await _all(e.plans);
    final walk = units.firstWhere(
      (u) => u.kind == PlanUnitKind.walkRun && u.day.isAfter(_day(8)),
    );
    // Gespeichert: an dem Tag ein Tempolauf, den der Nutzer festgelegt hat.
    await e.plans.writeVersion(
      PlanVersionDraft(
        createdAt: _now(0),
        validFrom: _day(0),
        trigger: PlanTrigger.manual,
        reason: 'test',
        version: v.version,
        inputs: v.inputs,
        summary: const {},
        units: [
          for (final u in units)
            u.id == walk.id
                ? PlanUnit(
                    day: u.day,
                    kind: PlanUnitKind.tempo,
                    phase: u.phase,
                    weekIndex: u.weekIndex,
                    minutes: u.minutes,
                    segments: u.segments,
                    pinned: true,
                    fixed: PlanUnitFixed.kind,
                  )
                : u,
        ],
        readState: planUnitsFingerprint(units),
      ),
    );
    final r = await e.run(PlanTrigger.weekly, 1);
    expect(r.wasWritten, isTrue);
    final after = (await e.plans.unitOn(walk.day))!;
    expect(after.kind, PlanUnitKind.walkRun);
    expect(after.pinned, isTrue);
    expect(after.fixed, PlanUnitFixed.none);
    expect(
      r.generated!.pinnedConflicts.map((c) => '${c.kind.name}@${c.day}'),
      contains('walkRunFirst@${walk.day}'),
    );
  });

  group('Hinweise an der Fassung (summary, WP22)', () {
    test('die geschriebene Fassung trägt die Hinweise ihrer Rechnung, auch '
        'nach einer automatischen Neuberechnung', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      for (final (t, day) in [
        (PlanTrigger.create, 0),
        (PlanTrigger.weekly, 7),
      ]) {
        // Kleinerer Regler: die automatische Rechnung ändert Inhalte.
        if (day > 0) await e.goals.save(_goal(capMin: 100), today: _day(day));
        final r = await e.run(t, day);
        expect(r.wasWritten, isTrue);
        final v = (await e.plans.history()).last;
        expect(v.summary[planHintsKey], planHintsToJson(r.generated!));
        final units = await e.plans.unitsBetween(
          v.inputs.anchor,
          planFarFuture,
        );
        final read = planHintsFromSummary(
          v.summary,
          version: v.version,
          units: units,
          today: _day(day),
        )!;
        expect(planHintsToJson(read), planHintsToJson(r.generated!));
        expect(read.units.map(_sig), r.generated!.units.map(_sig));
      }
    });

    test('entfallener Tag, der jetzt ein Ruhetag des Nutzers ist, zählt '
        'nicht als entfallen (Befund E2b 1)', () {
      PlanUnit rest(DateTime d, {bool pinned = true}) => PlanUnit(
        day: d,
        kind: PlanUnitKind.rest,
        phase: PlanPhase.entry,
        weekIndex: 4,
        minutes: 0,
        segments: const [],
        pinned: pinned,
        fixed: pinned ? PlanUnitFixed.day : PlanUnitFixed.none,
      );
      final g = GeneratedPlan(
        version: PlanVersion.current,
        weeks: const [],
        units: const [],
        frozenUnits: const [],
        unplacedByWeek: const {},
        hardOmissions: const {},
        pinnedConflicts: const [],
        walkRunNoWeekFits: false,
        droppedDaysByWeek: {
          4: [DateTime.utc(2026, 12, 9), DateTime.utc(2026, 12, 11)],
          5: [DateTime.utc(2026, 12, 16)],
        },
        hardFit: HardFitStatus.notApplicable,
      );
      GeneratedPlan read(List<PlanUnit> units) => planHintsFromSummary(
        {planHintsKey: planHintsToJson(g)},
        version: PlanVersion.current,
        units: units,
        today: _day(0),
      )!;
      // Ruhetag des Nutzers am 11.12. und 16.12.: nur der 9.12. bleibt, die
      // Woche 5 fällt ganz weg.
      expect(
        read([
          rest(DateTime.utc(2026, 12, 11)),
          rest(DateTime.utc(2026, 12, 16)),
        ]).droppedDaysByWeek,
        {
          4: [DateTime.utc(2026, 12, 9)],
        },
      );
      // Eine erzeugte (nicht festgelegte) Ruhe-Einheit ändert nichts.
      expect(
        read([rest(DateTime.utc(2026, 12, 11), pinned: false)])
            .droppedDaysByWeek,
        g.droppedDaysByWeek,
      );
    });

    test('Rundweg aller Felder; fehlende oder fremde Hinweise: null', () {
      final g = GeneratedPlan(
        version: PlanVersion.current,
        weeks: [
          PlanWeek(
            index: 2,
            start: DateTime.utc(2026, 11, 23),
            minutes: null,
            phase: PlanPhase.entry,
            kind: WeekKind.values.last,
          ),
        ],
        units: const [],
        frozenUnits: const [],
        unplacedByWeek: const {2: 7},
        hardOmissions: const {3: HardOmission.notContinuous30},
        droppedDaysByWeek: {
          4: [DateTime.utc(2026, 12, 9)],
        },
        pinnedConflicts: [
          PinnedConflict(
            kind: PinnedConflictKind.spacing,
            day: DateTime.utc(2026, 12, 1),
            otherDay: DateTime.utc(2026, 12, 2),
          ),
          PinnedConflict(
            kind: PinnedConflictKind.noMatchingUnit,
            day: DateTime.utc(2026, 12, 3),
          ),
        ],
        walkRunStaysAtWeek: 5,
        walkRunNoWeekFits: true,
        hardFit: HardFitStatus.partialAtPeak,
      );
      final json = planHintsToJson(g);
      final read = planHintsFromSummary(
        {planHintsKey: jsonDecode(jsonEncode(json))},
        version: PlanVersion.current,
        units: const [],
        today: _day(0),
      )!;
      expect(planHintsToJson(read), json);
      // Wochen vor der Woche von heute fallen weg (wie generatePlan).
      final later = planHintsFromSummary(
        {planHintsKey: json},
        version: PlanVersion.current,
        units: const [],
        today: DateTime.utc(2026, 11, 30),
      )!;
      expect(later.weeks, isEmpty);
      // Konflikte von Terminen vor heute fallen weg.
      final dec2 = planHintsFromSummary(
        {planHintsKey: json},
        version: PlanVersion.current,
        units: const [],
        today: DateTime.utc(2026, 12, 2),
      )!;
      expect(dec2.pinnedConflicts.map((c) => c.day), [
        DateTime.utc(2026, 12, 3),
      ]);
      expect(
        planHintsFromSummary(
          const {},
          version: PlanVersion.current,
          units: const [],
          today: _day(0),
        ),
        isNull,
      );
      expect(
        planHintsFromSummary(
          {
            planHintsKey: {...json, 'hardFit': 'unbekannt'},
          },
          version: PlanVersion.current,
          units: const [],
          today: _day(0),
        ),
        isNull,
      );
    });
  });

  group('Ziel-Fingerabdruck an der Fassung (WP22 NB2)', () {
    TrainingGoal g({
      GoalType type = GoalType.time,
      double? target = 3000,
      DateTime? date,
      Set<int> days = const {2, 4, 6},
      double maxS = 7200,
      double cap = 14400,
      double? stand,
      ContinuousRun30 c30 = ContinuousRun30.yes,
      bool hard = true,
      DateTime? created,
    }) => TrainingGoal(
      type: type,
      distance: GoalDistance.tenKilometers,
      targetSeconds: type == GoalType.time ? target : null,
      targetDate: date ?? DateTime.utc(2027, 6, 1),
      runDays: days,
      maxSessionSeconds: maxS,
      weeklyCapSeconds: cap,
      createdAt: created ?? DateTime.utc(2026, 11, 1),
      hardSessionEnabled: hard,
      currentWeeklySeconds: stand,
      canRun30: c30,
    );

    test('jedes planrelevante Feld ändert ihn, createdAt nicht; ohne oder '
        'mit fremder Version: keine Änderung angenommen', () {
      final base = {planGoalFingerprintKey: planGoalFingerprint(g())};
      expect(planGoalChangedSince(base, g()), isFalse);
      expect(
        planGoalChangedSince(base, g(created: DateTime.utc(2026, 11, 5))),
        isFalse,
      );
      final changed = {
        'Art': g(type: GoalType.distance),
        'Zielzeit': g(target: 2900),
        'Zieldatum': g(date: DateTime.utc(2027, 5, 1)),
        'Lauftage': g(days: const {1, 3, 5}),
        'max. Zeit je Einheit': g(maxS: 3600),
        'Regler': g(cap: 12000),
        'Stand Wochenzeit': g(stand: 5400),
        'Stand 30 min': g(c30: ContinuousRun30.no),
        'harte Einheit': g(hard: false),
      };
      for (final e in changed.entries) {
        expect(planGoalChangedSince(base, e.value), isTrue, reason: e.key);
      }
      // Lauftage in anderer Reihenfolge: gleich.
      expect(planGoalFingerprint(g(days: {6, 2, 4})), planGoalFingerprint(g()));
      expect(planGoalChangedSince(const {}, g(hard: false)), isFalse);
      expect(
        planGoalChangedSince({
          planGoalFingerprintKey: planGoalFingerprint(g())
              .replaceFirst('"v":1', '"v":99'),
        }, g(hard: false)),
        isFalse,
      );
      expect(
        planGoalChangedSince({planGoalFingerprintKey: 'kaputt'}, g()),
        isFalse,
      );
    });

    test('die Fassung trägt den Fingerabdruck; geändertes Ziel bei gleichen '
        'Einheiten schreibt trotzdem, gleiches Ziel nicht', () async {
      final e = await _Env.open();
      await e.goals.save(_goal(), today: _goal().createdAt);
      await e.run(PlanTrigger.create, 0);
      var h = await e.plans.history();
      expect(
        h.single.summary[planGoalFingerprintKey],
        planGoalFingerprint((await e.goals.goal())!),
      );
      // Gleiches Ziel, gleiche Einheiten: keine Fassung.
      expect((await e.run(PlanTrigger.manual, 0)).wasWritten, isFalse);
      // Stand geändert: wirkt nur beim Anlegen, die Einheiten bleiben gleich.
      final stand = TrainingGoal(
        type: GoalType.distance,
        distance: GoalDistance.tenKilometers,
        targetDate: DateTime(2027, 6, 1),
        runDays: const {2, 4, 6},
        maxSessionSeconds: 7200,
        weeklyCapSeconds: 240 * 60.0,
        createdAt: DateTime.utc(2026, 11, 1),
        hardSessionEnabled: true,
        currentWeeklySeconds: 5400,
        canRun30: ContinuousRun30.yes,
      );
      await e.goals.save(stand, today: _day(0));
      expect(planGoalChangedSince(h.single.summary, stand), isTrue);
      final r = await e.run(PlanTrigger.goalChange, 0);
      expect(r.summary!.isEmpty, isTrue);
      expect(r.wasWritten, isTrue);
      h = await e.plans.history();
      expect(h, hasLength(2));
      expect(planGoalChangedSince(h.last.summary, stand), isFalse);
      expect((await e.run(PlanTrigger.weekly, 0)).wasWritten, isFalse);
    });
  });
}
