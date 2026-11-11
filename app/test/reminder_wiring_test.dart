// WP22 Teil F, Nachbesserung (Review F, Befund 2): Verdrahtung der Erinnerungen (FR-0174) über die App-Wurzel mit
// FakeReminderScheduler. Stornieren bei „Alles löschen“, Neuplanen nach einer Änderung auf der Plan-Seite, nach einer
// DataChanges-Meldung und nach der Rückkehr in die App.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/app_shell.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/reminders/reminder_controller.dart';

import 'app_harness.dart';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2026, 10, 4),
  runDays: const {1, 3, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 6, 1),
  canRun30: ContinuousRun30.yes,
  hardSessionEnabled: false,
);

/// App mit Erinnerungen (erlaubt), Ziel samt Plan und eingeschalteten
/// Erinnerungen. Eingeschaltet wird im Speicher; die Rückkehr in die App liest
/// das neu und plant (Lifecycle `resumed`).
Future<(Device, FakeReminderScheduler)> _started(WidgetTester tester) async {
  final reminders = FakeReminderScheduler(granted: true);
  final d = Device()..reminders = reminders;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  final c = PlanController(
    session: d.session,
    clock: d.clock,
    reader: PlanDataReader(
      session: d.session,
      clock: d.clock,
      loadRuns: () async => const [],
    ),
  );
  expect(
    await tester.runAsync(() => c.saveGoal(_goal())),
    PlanActionResult.done,
  );
  c.dispose();
  await tester.runAsync(
    () =>
        const ReminderSettings(enabled: true)
            .save(d.session.settings, at: d.clock.now()),
  );
  await _returnToApp(tester);
  return (d, reminders);
}

Future<void> _returnToApp(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Rückkehr in die App plant aus dem gespeicherten Plan', (
    tester,
  ) async {
    final (_, reminders) = await _started(tester);
    expect(reminders.scheduled, isNotEmpty);
    expect(reminders.labels?.title, 'Geplantes Training');
    final before = reminders.replaceCount;
    await _returnToApp(tester);
    expect(reminders.replaceCount, before + 1);
  });

  testWidgets('„Alles löschen“ storniert alle Erinnerungen', (tester) async {
    final (_, reminders) = await _started(tester);
    expect(reminders.scheduled, isNotEmpty);
    final cancels = reminders.cancelCount;
    final replaces = reminders.replaceCount;

    await openOverview(tester);
    await tester.tap(key('overview_data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alles löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Alles löschen'));
    await tester.pumpAndSettle();

    expect(reminders.cancelCount, greaterThan(cancels));
    expect(reminders.scheduled, isEmpty);
    expect(reminders.replaceCount, replaces, reason: 'nichts neu geplant');
    // Der Schalter steht sofort auf aus (Stand des ersten Starts), nicht erst
    // nach dem nächsten Neuladen.
    final controller = ReminderScope.read(
      tester.element(find.byType(Scaffold).first),
    )!;
    expect(controller.settings.enabled, isFalse);
    expect(controller.active, isFalse);
  });

  testWidgets('Änderung auf der Plan-Seite (Ruhetag festlegen) plant neu', (
    tester,
  ) async {
    final (d, reminders) = await _started(tester);
    final plans = (d.session as PlanStorage).plans;
    // Ein freier künftiger Tag dieser Woche (Mo 1.6.2026 ist heute).
    DateTime? free;
    for (var i = 1; i <= 6 && free == null; i++) {
      final day = DateTime.utc(2026, 6, 1 + i);
      final unit = await tester.runAsync(() => plans.unitOn(day));
      if (unit == null) free = day;
    }
    expect(free, isNotNull);
    final before = reminders.replaceCount;

    await tester.tap(key('home_plan'));
    await tester.pumpAndSettle();
    await tester.tap(key('plan_open_calendar'));
    await tester.pumpAndSettle();
    await tester.tap(key('calendar_day_${_iso(free!)}'));
    await tester.pumpAndSettle();
    await tester.tap(key('calendar_rest_set'));
    await tester.pumpAndSettle();
    await tester.tap(key('calendar_rest_confirm'));
    await tester.pumpAndSettle();

    final rest = await tester.runAsync(() => plans.unitOn(free!));
    expect(rest?.isRestDay, isTrue, reason: 'Ruhetag gespeichert');
    expect(reminders.replaceCount, greaterThan(before));
    expect(reminders.scheduled, isNotEmpty);
  });

  testWidgets('DataChanges-Meldung (Lauf, Neuberechnung) plant neu', (
    tester,
  ) async {
    final (_, reminders) = await _started(tester);
    final before = reminders.replaceCount;
    tester.widget<AppShell>(find.byType(AppShell)).changes.changed();
    await tester.pumpAndSettle();
    expect(reminders.replaceCount, before + 1);
    expect(reminders.scheduled, isNotEmpty);
  });
}
