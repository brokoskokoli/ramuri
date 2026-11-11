import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

/// WP22-Befund „Neu berechnen macht die heutige offene Einheit zum
/// Ruhetag“ (WP23 C1): in der App-Schicht (PlanController, gemessene
/// Eingaben, lokales „heute“) nicht reproduzierbar; diese Prüfung hält fest,
/// dass die heutige offene Einheit nach [PlanController.recalculate] bleibt.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _t0 = DateTime.utc(2026, 11, 11);

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

void main() {
  test('Neu berechnen lässt die heutige offene Einheit stehen', () async {
    var checked = 0;
    final lost = <String>[];
    for (final days in [
      {2, 4, 6},
      {1, 3, 5},
      {2, 3, 4},
      {1, 2, 3, 4, 5, 6, 7},
    ]) {
      for (var d = 0; d < 21; d++) {
        final s = await FakeStorage().open(_k);
        final clock = FakeClock(_t0);
        PlanController make() => PlanController(
          session: s,
          clock: clock,
          reader: PlanDataReader(
            session: s,
            clock: clock,
            loadRuns: () async => const [],
          ),
        );
        await make().saveGoal(_goal(days));
        clock.set(_t0.add(Duration(days: d, hours: 12)));
        final c = make();
        await c.open();
        final plans = (s as PlanStorage).plans;
        final today = calendarDay(clock.now());
        final before = await plans.unitOn(today);
        if (before == null || before.kind == PlanUnitKind.rest) continue;
        checked++;
        expect(await c.recalculate(), PlanActionResult.done);
        final after = await plans.unitOn(today);
        if (after == null || after.kind == PlanUnitKind.rest) {
          lost.add('$days +$d');
        }
      }
    }
    expect(checked, greaterThan(30));
    expect(lost, isEmpty);
  });
}
