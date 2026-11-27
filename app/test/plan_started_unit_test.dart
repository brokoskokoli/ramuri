import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_started_unit.dart';

import 'helpers/local_clock.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
const _day = '2026-11-11';

/// Speicher mit Ziel (Mo, Mi, Fr) und erster Fassung; heute ist eine Einheit.
Future<(StorageSession, FakeClock, int)> _withPlan() async {
  final clock = LocalFakeClock(_now);
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

  test('gemerkte Einheit durch eine Neuberechnung ersetzt: die offene '
      'Einheit desselben Tags trägt den Lauf', () async {
    final (s, clock, unitId) = await _withPlan();
    final store = PlanStartedUnitStore(session: s, clock: clock);
    // Kennung einer Einheit, die es nach der Neuberechnung nicht mehr gibt.
    await store.remember(unitId + 1000, _day);
    final run = await _finishedRun(s, _now.add(const Duration(minutes: 1)));

    expect(await store.settle(serialize: _serial), PlanActionResult.done);
    expect((await (s as PlanStorage).plans.unitOn(_today))!.runId, run);
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
      expect(
        await c.assignRun(unitId, a, expectedRunId: null),
        PlanActionResult.done,
      );
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

  group('assignRunToUnit erwartet den Stand der Ansicht (offen)', () {
    test('ein anderer Schreiber ordnet der offen gesehenen Einheit Lauf A '
        'zu: Lauf B wird abgelehnt, A bleibt, keine neue Fassung', () async {
      final (s, clock, unitId) = await _withPlan();
      final plans = (s as PlanStorage).plans;
      final a = await _finishedRun(s, _now.add(const Duration(minutes: 1)));
      final b = await _finishedRun(s, _now.add(const Duration(hours: 1)));
      // Die Ansicht sieht die Einheit offen.
      expect(await openPlanUnitOn(s, _day), isNotNull);
      // Danach ordnet ein anderer Schreiber ihr A zu.
      expect(
        await plans.assignRun(unitId, a, expectedRunId: null),
        PlanAssignResult.assigned,
      );
      final versions = (await plans.history()).length;

      expect(
        await assignRunToUnit(
          session: s,
          clock: clock,
          unitId: unitId,
          day: _day,
          runId: b,
        ),
        PlanActionResult.rejected,
      );
      expect((await plans.unitOn(_today))!.runId, a);
      expect(await plans.history(), hasLength(versions));
    });

    test('Einheit offen: Lauf B wird zugeordnet, genau eine neue Fassung '
        '(Auslöser run)', () async {
      final (s, clock, _) = await _withPlan();
      final plans = (s as PlanStorage).plans;
      // Eine Fassung nur mit der Einheit von heute: Die Neuberechnung nach
      // der Zuordnung ergänzt die übrigen und schreibt so eine neue Fassung.
      final last = (await plans.history()).last;
      final today = (await plans.unitOn(_today))!;
      await plans.writeVersion(
        PlanVersionDraft(
          createdAt: _now.toUtc(),
          validFrom: _today,
          trigger: last.trigger,
          reason: 'test',
          version: last.version,
          inputs: last.inputs,
          summary: last.summary,
          units: [
            PlanUnit(
              day: today.day,
              kind: today.kind,
              phase: today.phase,
              weekIndex: today.weekIndex,
              minutes: today.minutes,
              segments: today.segments,
            ),
          ],
          readState: planUnitsFingerprint(
            await plans.unitsBetween(DateTime.utc(2000), planFarFuture),
          ),
        ),
      );
      final unitId = (await plans.unitOn(_today))!.id!;
      final b = await _finishedRun(s, _now.add(const Duration(minutes: 1)));
      final before = await plans.history();

      expect(
        await assignRunToUnit(
          session: s,
          clock: clock,
          unitId: unitId,
          day: _day,
          runId: b,
        ),
        PlanActionResult.done,
      );
      expect((await plans.unitOn(_today))!.runId, b);
      final after = await plans.history();
      expect(after, hasLength(before.length + 1));
      expect(after.last.trigger, PlanTrigger.run);
    });
  });
}
