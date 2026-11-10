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
}

void main() {
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
    await e.goals.save(_goal());
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
    await e.goals.save(_goal());
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
    await e.goals.save(_goal());
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

    await e.goals.save(_goal(days: {1, 3, 5, 7}));
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
    await e.goals.save(_goal());
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
    await e.goals.save(_goal(capMin: 200));
    final r = await e.run(PlanTrigger.manual, 0);
    final pinned = (await _all(e.plans)).where((u) => u.pinned).toList();
    expect(pinned, hasLength(1), reason: '${r.generated?.pinnedConflicts}');
    expect(pinned.single.day, target);
  });

  test('Wiederholung mit den gespeicherten Eingaben ergibt dieselben '
      'künftigen Einheiten (Determinismus über den Speicher)', () async {
    final e = await _Env.open();
    await e.goals.save(_goal());
    await e.run(PlanTrigger.create, 0);
    await e.goals.save(_goal(days: {1, 3, 5, 7}));
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
    await e.goals.save(_goal());
    await e.run(PlanTrigger.create, 0);
    final before = (await _all(e.plans)).map(_sig).toList();
    await e.goals.save(_goal(days: {1, 3, 5, 7}));
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
        await e.goals.save(_goal());
        await e.run(PlanTrigger.create, 0);
        final target = (await _all(e.plans))
            .firstWhere((u) => u.day.difference(_day(0)).inDays >= 70);
        final run = (await e.session.runs.create(startedAt: _now(0))).id;
        await e.plans.assignRun(target.id!, run);
        // Niedrigere Wochengrenze: alle künftigen Einheiten ändern ihre Dauer.
        await e.goals.save(_goal(capMin: 100));
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
      await e.goals.save(_open({2, 4, 6}));
      await e.run(PlanTrigger.create, 0);
      await e.goals.save(_open({1, 2, 3, 4, 5, 6}));
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
      await e.goals.save(_goal());
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
      await e.goals.save(_open({2, 4, 6}));
      await e.run(PlanTrigger.create, 0);
      await e.goals.save(_open({1, 3, 5}));
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
      await e.goals.save(_open({2, 4, 6}));
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
}
