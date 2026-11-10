import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, seedRun, text;
import 'run_test.dart' show walk;

// Heute mit Plan (FR-0209, WP22 Teil D): Karte „Heute geplant“, Wochenziel
// als Zeit, Einstieg „Ziel anlegen“ ohne Plan und die Zuordnung eines
// beendeten Laufs zur gestarteten Einheit. Alle Werte sind erfunden.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags (UTC, Versatz 0).
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

TrainingGoal _goal(Set<int> days) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: days,
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: false,
  canRun30: ContinuousRun30.yes,
);

/// Speicher vor dem Start: Einrichtung erledigt, mit [days] ein Ziel samt
/// erster Fassung (über den echten Controller).
Future<StorageSession> _preopen(Device d, {Set<int>? days}) async {
  d.clock.set(_now);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  if (days != null) {
    final c = PlanController(
      session: s,
      clock: d.clock,
      reader: PlanDataReader(
        session: s,
        clock: d.clock,
        loadRuns: () async => const [],
      ),
    );
    expect(await c.saveGoal(_goal(days)), PlanActionResult.done);
    c.dispose();
  }
  return s;
}

Future<PlanUnit?> _unitToday(StorageSession s) =>
    (s as PlanStorage).plans.unitOn(_today);

/// Startet, läuft 30 s und beendet den Lauf über die Abschlussansicht.
Future<void> _runAndFinish(Device d, WidgetTester tester, String start) async {
  await tester.tap(key(start));
  await tester.pumpAndSettle();
  await tester.tap(key('run_start_ready'));
  await tester.pumpAndSettle();
  await walk(d, tester, 30);
  await tester.tap(key('run_pause'));
  await tester.pump();
  await tester.tap(key('run_finish'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_finish_confirm'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_done_close'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ohne Plan: bisheriger Zustand plus „Ziel anlegen“, das '
      'Formular öffnet sich', (tester) async {
    final d = Device();
    await _preopen(d);
    await d.start(tester, const Locale('de'));
    expect(key('home_start_run'), findsOneWidget);
    expect(key('home_empty'), findsOneWidget);
    expect(key('home_today_plan'), findsNothing);
    expect(key('home_start_unit'), findsNothing);
    expect(key('home_week_goal'), findsNothing);
    expect(find.textContaining('geplant'), findsNothing);
    await tester.tap(key('home_create_goal'));
    await tester.pumpAndSettle();
    expect(key('plan_form_title'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final locale in ['de', 'en']) {
      testWidgets('mit Plan, Einheit heute: Karte und Wochenziel '
          '($locale, ${dark ? 'dunkel' : 'hell'})', (tester) async {
        if (dark) {
          tester.platformDispatcher.platformBrightnessTestValue =
              Brightness.dark;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
        }
        final d = Device();
        final s = await _preopen(d, days: {1, 3, 5});
        final unit = (await _unitToday(s))!;
        expect(unit.kind, isNot(PlanUnitKind.rest));
        await d.start(tester, Locale(locale));
        final de = locale == 'de';
        expect(key('home_today_plan'), findsOneWidget);
        expect(
          find.text(de ? 'Heute geplant' : 'Planned for today'),
          findsOneWidget,
        );
        expect(key('home_today_unit'), findsOneWidget);
        expect(text('home_today_duration'), '${unit.minutes} min');
        expect(
          text('home_today_week'),
          startsWith(de ? 'Woche ${unit.weekIndex + 1}' : 'Week'),
        );
        expect(key('home_today_purpose'), findsOneWidget);
        expect(
          find.text(de ? 'Einheit starten' : 'Start session'),
          findsOneWidget,
        );
        expect(key('home_start_run'), findsOneWidget);
        expect(key('home_create_goal'), findsNothing);
        // Ohne Läufe: Hinweis und Wochenziel als Zeit, ohne Kilometer
        // (lockeres Tempo unbekannt).
        expect(key('home_empty'), findsOneWidget);
        expect(key('home_week_goal'), findsOneWidget);
        expect(
          text('home_week_goal_time'),
          startsWith(de ? '0 min von' : '0 min of'),
        );
        expect(key('home_week_goal_km'), findsNothing);
        expect(find.textContaining('Erholung'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Ruhetag: Satz statt Einheit, nur „Frei laufen“', (tester) async {
    final d = Device();
    final s = await _preopen(d, days: {1, 5});
    expect(await _unitToday(s), isNull);
    await d.start(tester, const Locale('de'));
    expect(key('home_today_plan'), findsOneWidget);
    expect(text('home_today_rest'), 'Heute ist Ruhetag.');
    expect(key('home_today_none'), findsNothing);
    expect(key('home_start_unit'), findsNothing);
    expect(key('home_start_run'), findsOneWidget);
  });

  testWidgets('nach dem Ende des Plans: keine Einheit geplant (en)', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    d.clock.set(DateTime.utc(2027, 5, 5, 12));
    await d.start(tester, const Locale('en'));
    expect(key('home_today_plan'), findsOneWidget);
    expect(text('home_today_none'), 'No session is planned for today.');
    expect(key('home_today_rest'), findsNothing);
    expect(key('home_start_unit'), findsNothing);
    expect(key('home_start_run'), findsOneWidget);
  });

  testWidgets('Einheit starten -> Lauf beendet: Lauf an der Einheit, '
      'Karte erledigt', (tester) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    await _runAndFinish(d, tester, 'home_start_unit');
    final run = (await d.session.runs.list()).single;
    expect(run.state, RunState.finished);
    expect((await _unitToday(d.session))!.runId, run.id);
    expect(key('home_today_done'), findsOneWidget);
    expect(key('home_start_unit'), findsNothing);
    // Wochenziel zählt die gelaufene Zeit.
    expect(text('home_week_goal_time'), startsWith('0 min von'));
  });

  testWidgets('Frei laufen: keine Zuordnung zur Einheit von heute', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    await _runAndFinish(d, tester, 'home_start_run');
    expect((await d.session.runs.list()).single.state, RunState.finished);
    expect((await _unitToday(d.session))!.runId, isNull);
    expect(key('home_start_unit'), findsOneWidget);
  });

  testWidgets('Einheit starten, dann abgebrochen: keine Zuordnung', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    await tester.tap(key('home_start_unit'));
    await tester.pumpAndSettle();
    expect(key('run_start_ready'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await d.session.runs.list(), isEmpty);
    expect((await _unitToday(d.session))!.runId, isNull);
    expect(key('home_start_unit'), findsOneWidget);
  });

  testWidgets('Wochenziel: gelaufene Zeit der Woche gegen die Planzeit', (
    tester,
  ) async {
    final d = Device();
    final s = await _preopen(d, days: {1, 3, 5});
    // Montag dieser Woche, 40 min, beendet.
    final id = await seedRun(s, DateTime.utc(2026, 11, 9, 7), minutes: 40);
    await s.runs.setState(
      id,
      RunState.finished,
      endedAt: DateTime.utc(2026, 11, 9, 7, 40),
      endedUtcOffset: Duration.zero,
    );
    await d.start(tester, const Locale('de'));
    expect(key('home_week'), findsOneWidget);
    expect(text('home_week_goal_time'), startsWith('40 min von '));
    final bar = tester.widget<LinearProgressIndicator>(
      key('home_week_goal_bar'),
    );
    expect(bar.value, greaterThan(0));
    expect(bar.value, lessThanOrEqualTo(1));
  });

  testWidgets('Einheit gestartet, Lauf noch nicht beendet: keine Zuordnung', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    await tester.tap(key('home_start_unit'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_start_ready'));
    await tester.pumpAndSettle();
    await walk(d, tester, 10);
    await tester.tap(key('run_pause'));
    await tester.pump();
    final run = (await d.session.runs.list()).single;
    expect(run.state, isNot(RunState.finished));
    expect((await _unitToday(d.session))!.runId, isNull);
  });
}
