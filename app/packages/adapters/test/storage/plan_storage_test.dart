import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:adapters/src/storage/plan_access.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final DateTime _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));

TrainingGoal _goal({Set<int> days = const {2, 4, 6}}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
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

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/test.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<EncryptedStorageSession> open() async =>
      await EncryptedStorage(path).open(testKey()) as EncryptedStorageSession;

  Future<List<PlanUnit>> all(PlanRepository p) =>
      p.unitsBetween(_day(-400), _day(800));

  Future<void> exec(
    AppDatabase db,
    String sql, [
    List<Object?> args = const [],
  ]) => db.customStatement(sql, args);

  test('Geh-Lauf-Woche: Sekunden und Arten der Abschnitte bleiben '
      'verlustfrei (Rundreise)', () async {
    final s = await open();
    addTearDown(s.close);
    await s.goals.save(_goal());
    final week = planWalkRunWeek(
      week: PlanWeek(
        index: 0,
        start: _day(-2),
        minutes: null,
        phase: PlanPhase.entry,
        kind: WeekKind.walkRun,
      ),
      runDays: const {1, 3, 5},
      position: const WalkRunPosition(1),
    );
    String segs(PlanUnit u) => [
      for (final x in u.segments)
        '${x.kind.name}:${x.minutes}:${x.seconds}:${x.durationSeconds}',
    ].join(',');
    expect(
      week.units.any((u) => u.segments.any((x) => x.seconds != null)),
      isTrue,
      reason: 'die Woche enthält Sekunden-Abschnitte',
    );
    await s.plans.writeVersion(
      PlanVersionDraft(
        createdAt: _d0,
        validFrom: _day(-2),
        trigger: PlanTrigger.create,
        reason: 'start',
        version: const PlanVersion(),
        inputs: PlanInputs(
          anchor: _day(-2),
          startWeeklyMinutes: 90,
          today: _d0,
        ),
        summary: const {},
        units: week.units,
      ),
    );
    final got = await all(s.plans);
    expect(got.map((u) => u.kind), everyElement(PlanUnitKind.walkRun));
    expect(got.map(segs), week.units.map(segs));
    expect(
      got.expand((u) => u.segments).map((x) => x.kind),
      containsAll([PlanSegmentKind.run, PlanSegmentKind.walk]),
    );
  });

  group('recalculatePlan gegen die Datenbank', () {
    test('Fehler mitten im Schreiben: Fassung und Einheiten zurückgerollt, '
        'alter Plan und Prüftag unverändert', () async {
      final s = await open();
      addTearDown(s.close);
      await s.goals.save(_goal());
      final settings = s.settings;
      await recalculatePlan(
        plans: s.plans,
        settings: settings,
        trigger: PlanTrigger.create,
        today: _day(0),
        now: _d0,
      );
      final before = (await all(s.plans)).map(_sig).toList();
      final versions = (await s.plans.history()).length;
      expect(before.length, greaterThan(4));

      await s.goals.save(_goal(days: {1, 3, 5, 7}));
      final failing = DriftPlanRepository(
        s.database,
        beforeUnitInsert: (i) async {
          if (i == 3) throw StateError('Abbruch mitten im Schreiben');
        },
      );
      await expectLater(
        recalculatePlan(
          plans: failing,
          settings: settings,
          trigger: PlanTrigger.goalChange,
          today: _day(7),
          now: _day(7),
        ),
        throwsA(isA<StorageException>()),
      );
      expect((await all(s.plans)).map(_sig), before);
      expect((await s.plans.history()).length, versions);
      expect(await settings.get(planLastCheckDayKey), '2026-11-11');

      // Ohne Abbruch geht dieselbe Neuberechnung durch.
      final ok = await recalculatePlan(
        plans: s.plans,
        settings: settings,
        trigger: PlanTrigger.goalChange,
        today: _day(7),
        now: _day(7),
      );
      expect(ok.wasWritten, isTrue);
      expect((await s.plans.history()).length, versions + 1);
    });

    test('Wiederholung mit den gespeicherten Eingaben ergibt dieselben '
        'künftigen Einheiten', () async {
      final s = await open();
      addTearDown(s.close);
      await s.goals.save(_goal());
      await recalculatePlan(
        plans: s.plans,
        settings: s.settings,
        trigger: PlanTrigger.create,
        today: _day(0),
        now: _d0,
      );
      await s.goals.save(_goal(days: {1, 3, 5, 7}));
      await recalculatePlan(
        plans: s.plans,
        settings: s.settings,
        trigger: PlanTrigger.goalChange,
        today: _day(7),
        now: _day(7),
      );
      final rec = (await s.plans.history()).last;
      final goal = (await s.plans.currentGoal())!;
      final units = await all(s.plans);
      final frozen = [
        for (final u in units)
          if (u.day.isBefore(rec.validFrom) || u.runId != null) u,
      ];
      final future = [
        for (final u in units)
          if (!u.day.isBefore(rec.validFrom) && u.runId == null) u,
      ];
      expect(future, isNotEmpty);
      final again = generatePlan(goal, rec.inputs, frozen, rec.validFrom);
      expect(again.units.map(_sig), future.map(_sig));
    });

    test('Nach Neuöffnen: gleiche Einheiten, keine neue Fassung', () async {
      var s = await open();
      await s.goals.save(_goal());
      await recalculatePlan(
        plans: s.plans,
        settings: s.settings,
        trigger: PlanTrigger.create,
        today: _day(0),
        now: _d0,
      );
      final before = (await all(s.plans)).map(_sig).toList();
      await s.close();
      s = await open();
      addTearDown(s.close);
      final r = await recalculatePlan(
        plans: s.plans,
        settings: s.settings,
        trigger: PlanTrigger.weekly,
        today: _day(0),
        now: _d0,
      );
      expect(r.wasWritten, isFalse);
      expect((await all(s.plans)).map(_sig), before);
    });
  });

  group('CHECK-Bedingungen von plans und plan_units', () {
    late EncryptedStorageSession s;
    late AppDatabase db;
    setUp(() async {
      s = await open();
      db = s.database;
      await s.goals.save(_goal());
      await exec(
        db,
        "INSERT INTO runs (id, state, started_at_us) VALUES (1, 'active', 1)",
      );
    });
    tearDown(() => s.close());

    String plan(String col, String v) {
      final cols = {
        'goal_id': '1',
        'created_at_us': '1',
        'valid_from': "'2030-01-01'",
        'trigger': "'weekly'",
        'reason': "'r'",
        'method': "'m'",
        'method_version': '1',
        'parameter_version': '1',
        'inputs': "'{}'",
        'summary': "'{}'",
      }..[col] = v;
      return 'INSERT INTO plans (${cols.keys.map((k) => '"$k"').join(', ')}) '
          'VALUES (${cols.values.join(', ')})';
    }

    String unit(String col, String v) {
      final cols = {
        'plan_id': '1',
        'day': "'2030-01-01'",
        'week': '0',
        'phase': "'build'",
        'kind': "'easy'",
        'minutes': '30',
        'structure': "'[]'",
        'pinned': '0',
      }..[col] = v;
      return 'INSERT INTO plan_units (${cols.keys.join(', ')}) '
          'VALUES (${cols.values.join(', ')})';
    }

    test('plans: gültige Zeile geht, jede Verletzung wird abgelehnt', () async {
      await exec(db, plan('reason', "'r'"));
      for (final t in [
        'create',
        'goalChange',
        'weekly',
        'feedback',
        'run',
        'pause',
        'manual',
        'ruleVersion',
      ]) {
        await exec(db, plan('trigger', "'$t'"));
      }
      for (final bad in <(String, String)>[
        ('goal_id', '2'),
        ('valid_from', "'1.1.2030'"),
        ('valid_from', "'2030-02-30'"),
        ('trigger', "'other'"),
        ('reason', "''"),
        ('method', "''"),
        ('method_version', '0'),
        ('parameter_version', '0'),
        ('inputs', "'{'"),
        ('summary', "'nope'"),
      ]) {
        await expectLater(
          exec(db, plan(bad.$1, bad.$2)),
          throwsA(anything),
          reason: '$bad',
        );
      }
    });

    test(
      'plan_units: gültige Zeilen gehen, jede Verletzung wird abgelehnt',
      () async {
        await exec(db, plan('reason', "'r'"));
        await exec(db, unit('minutes', '0'));
        await exec(db, unit('run_id', '1'));
        await exec(db, unit('pinned', '1'));
        for (final k in [
          'easy',
          'long',
          'intervals',
          'tempo',
          'progressive',
          'walkRun',
          'rest',
        ]) {
          await exec(db, unit('kind', "'$k'"));
        }
        for (final bad in <(String, String)>[
          ('plan_id', '9'),
          ('day', "'2030-13-01'"),
          ('day', "'1.1.2030'"),
          ('week', '-1'),
          ('phase', "'peak'"),
          ('kind', "'sprint'"),
          ('minutes', '-1'),
          ('structure', "'['"),
          ('run_id', '9'),
          ('pinned', '2'),
        ]) {
          await expectLater(
            exec(db, unit(bad.$1, bad.$2)),
            throwsA(anything),
            reason: '$bad',
          );
        }
      },
    );
  });
}
