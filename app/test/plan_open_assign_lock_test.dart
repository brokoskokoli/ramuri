import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';

import 'app_harness.dart';

// PAR-231: Die Zuordnung beim Öffnen von „Heute“ und der Plan-Seite läuft in
// der App hinter der Sperre der Wertberechnung. Solange eine Aktion die Sperre
// hält (etwa die Berechnung nach dem Lauf-Ende), ordnet keine der beiden Seiten
// zu; danach genau einmal. Ziel, Plan und Lauf sind ausgedacht.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));
final _created = DateTime.utc(2026, 11, 11, 8);

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

PlanRepository _plans(StorageSession s) => (s as PlanStorage).plans;

/// Speicher vor dem Start: Einrichtung erledigt, Ziel und Plan, die Uhr am
/// Mittag des ersten Tags mit Einheit (Prüfung der Woche erledigt). Liefert
/// diesen Tag.
Future<DateTime> _preopen(Device d) async {
  d.clock.set(_created);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  final c = PlanController(
    session: s,
    clock: d.clock,
    reader: PlanDataReader(
      session: s,
      clock: d.clock,
      loadRuns: () async => const [],
    ),
  );
  expect(await c.saveGoal(_goal()), PlanActionResult.done);
  c.dispose();
  final start = calendarDay(_created);
  for (var n = 1; n < 14; n++) {
    final day = start.add(Duration(days: n));
    if (await _plans(s).unitOn(day) == null) continue;
    d.clock.set(localAt(day, 12));
    await s.settings.set(planLastCheckDayKey, isoDay(day), at: d.clock.now());
    return day;
  }
  fail('keine Einheit');
}

/// Beendeter Lauf am Tag [day] um 8:00 Ortszeit, 40 Minuten.
Future<int> _finishedRun(StorageSession s, DateTime day) async {
  final start = localAt(day, 8);
  final end = start.add(const Duration(minutes: 40));
  final r = await s.runs.create(startedAt: start);
  await s.runs.setState(
    r.id,
    RunState.finished,
    endedAt: end,
    endedUtcOffset: end.timeZoneOffset,
  );
  return r.id;
}

/// Hält die Sperre der Wertberechnung der App, legt einen beendeten Lauf an
/// und lässt die gezeigte Seite neu öffnen ([reopen]). Solange die Sperre
/// gehalten wird, darf nichts zugeordnet sein; danach genau einmal.
Future<void> _expectAssignAfterLock(
  WidgetTester tester,
  Device d,
  DateTime day,
  Future<void> Function() reopen,
) async {
  final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
  final recalculation = home.recalculation;
  final s = d.session;
  final before = d.storage.data.planAssignWrites;
  final release = Completer<void>();
  final busy = recalculation.serialized(() => release.future);
  final run = await _finishedRun(s, day);
  await reopen();
  for (var i = 0; i < 50; i++) {
    await tester.pump();
  }
  expect(d.storage.data.planAssignWrites, before);
  expect((await _plans(s).unitOn(day))!.runId, isNull);
  release.complete();
  await busy;
  await tester.pumpAndSettle();
  expect(d.storage.data.planAssignWrites, before + 1);
  expect((await _plans(s).unitOn(day))!.runId, run);
}

void main() {
  testWidgets('„Heute“ ordnet beim Öffnen erst zu, wenn die Wertberechnung '
      'die Sperre freigibt (PAR-231)', (tester) async {
    final d = Device();
    final day = await _preopen(d);
    await d.start(tester, const Locale('de'));
    expect(find.byType(HomeScreen), findsOneWidget);
    final changes = tester.widget<HomeScreen>(find.byType(HomeScreen)).changes;
    // Die Datenmeldung baut „Heute“ neu auf, die Seite öffnet erneut.
    await _expectAssignAfterLock(tester, d, day, () async => changes.changed());
    await d.stop(tester);
  });

  testWidgets('Die Plan-Seite ordnet beim Öffnen erst zu, wenn die '
      'Wertberechnung die Sperre freigibt (PAR-231)', (tester) async {
    final d = Device();
    final day = await _preopen(d);
    await d.start(tester, const Locale('de'));
    await _expectAssignAfterLock(tester, d, day, () async {
      await tester.tap(find.byKey(const Key('home_plan')));
      await tester.pump();
      expect(find.byType(PlanScreen), findsOneWidget);
    });
    await d.stop(tester);
  });
}
