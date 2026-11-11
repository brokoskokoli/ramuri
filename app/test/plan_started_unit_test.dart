import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_started_unit.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags (UTC).
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
const _day = '2026-11-11';

/// Speicher mit Ziel (Mo, Mi, Fr) und erster Fassung; heute ist eine Einheit.
Future<(StorageSession, FakeClock, int)> _withPlan() async {
  final clock = FakeClock(_now);
  final s = await FakeStorage().open(_key);
  final c = PlanController(
    session: s,
    clock: clock,
    reader: PlanDataReader(
      session: s,
      clock: clock,
      loadRuns: () async => const [],
    ),
  );
  final goal = TrainingGoal(
    type: GoalType.distance,
    distance: GoalDistance.tenKilometers,
    targetDate: DateTime.utc(2027, 3, 14),
    runDays: const {1, 3, 5},
    maxSessionSeconds: 7200,
    weeklyCapSeconds: 240 * 60.0,
    createdAt: DateTime.utc(2026, 11, 1),
    hardSessionEnabled: false,
    canRun30: ContinuousRun30.yes,
  );
  expect(await c.saveGoal(goal), PlanActionResult.done);
  c.dispose();
  final unit = (await (s as PlanStorage).plans.unitOn(_today))!;
  return (s, clock, unit.id!);
}

Future<void> _serial(Future<void> Function() action) => action();

Future<int> _finishedRun(StorageSession s, DateTime start) async {
  final run = await s.runs.create(startedAt: start);
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(const Duration(minutes: 30)),
  );
  return run.id;
}

void main() {
  test('Aufnahmedienst läuft noch (Neustart, Lauf aktiv): keine Zuordnung, '
      'Merker bleibt', () async {
    final (s, clock, unitId) = await _withPlan();
    final store = PlanStartedUnitStore(session: s, clock: clock);
    await store.remember(unitId, _day);
    final run = await s.runs.create(
      startedAt: _now.add(const Duration(minutes: 1)),
    );
    expect((await s.runs.get(run.id))!.state, isNot(RunState.finished));

    expect(await store.settle(serialize: _serial), isNull);
    expect((await store.read())?.unitId, unitId);
    expect((await (s as PlanStorage).plans.unitOn(_today))!.runId, isNull);
  });

  test('Ohne bekannte Kennung: der erste Lauf seit dem Start zählt', () async {
    final (s, clock, unitId) = await _withPlan();
    final store = PlanStartedUnitStore(session: s, clock: clock);
    await store.remember(unitId, _day);
    // Ein Lauf vor dem Start zählt nicht.
    await _finishedRun(s, _now.subtract(const Duration(hours: 2)));
    final first = await _finishedRun(s, _now.add(const Duration(minutes: 1)));
    await _finishedRun(s, _now.add(const Duration(hours: 1)));

    expect(await store.settle(serialize: _serial), PlanActionResult.done);
    expect((await (s as PlanStorage).plans.unitOn(_today))!.runId, first);
    expect(await store.read(), isNull);
  });

  test(
    'planRunAssignedOn: nur der zugeordnete Lauf (runId), null = irgendeiner, '
    'anderer Tag nein',
    () async {
      final (s, clock, unitId) = await _withPlan();
      final a = await _finishedRun(s, _now.add(const Duration(minutes: 1)));
      final b = await _finishedRun(s, _now.add(const Duration(hours: 1)));
      expect(await planRunAssignedOn(s, _day, a), isFalse);
      expect(await planRunAssignedOn(s, _day, null), isFalse);

      final c = PlanController(session: s, clock: clock);
      expect(await c.assignRun(unitId, a), PlanActionResult.done);
      c.dispose();

      expect(await planRunAssignedOn(s, _day, a), isTrue);
      expect(await planRunAssignedOn(s, _day, null), isTrue);
      // Ein anderer Lauf ist dieser Einheit nicht zugeordnet.
      expect(await planRunAssignedOn(s, _day, b), isFalse);
      // Am Freitag ist nichts zugeordnet.
      expect(await planRunAssignedOn(s, '2026-11-13', a), isFalse);
    },
  );

  test('zweiter Start: der Merker wird ersetzt, zugeordnet wird zur neuen '
      'Einheit', () async {
    final (s, clock, unitId) = await _withPlan();
    final store = PlanStartedUnitStore(session: s, clock: clock);
    final friday = (await (s as PlanStorage).plans.unitOn(
      DateTime.utc(2026, 11, 13),
    ))!.id!;
    expect(friday, isNot(unitId));
    await store.remember(unitId, _day);
    clock.advance(const Duration(minutes: 5));
    await store.remember(friday, '2026-11-13');

    final marker = (await store.read())!;
    expect(marker.unitId, friday);
    expect(marker.day, '2026-11-13');
    // Ein Lauf zwischen beiden Starts gehört nicht mehr zum Merker.
    await _finishedRun(s, _now.add(const Duration(minutes: 1)));
    final later = await _finishedRun(s, _now.add(const Duration(minutes: 10)));

    expect(await store.settle(serialize: _serial), PlanActionResult.done);
    final plans = (s as PlanStorage).plans;
    expect((await plans.unitOn(DateTime.utc(2026, 11, 13)))!.runId, later);
    expect((await plans.unitOn(_today))!.runId, isNull);
    expect(await store.read(), isNull);
  });
}
