import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'app_harness.dart';

// Karte der Unterforderung auf „Heute“ (PAR-236): „HFmax prüfen“ öffnet das
// Profil mit dem Feld HFmax im Fokus, „Ja, steigern“ rechnet über den
// Neuberechnungsdienst neu. Synthetische Daten: Ziel und Plan sind
// ausgedacht.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

final _now = DateTime.utc(2026, 11, 11, 12);
final _created = DateTime.utc(2026, 11, 2, 12);

TrainingGoal _goal() => TrainingGoal(
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

Finder _key(String k) => find.byKey(Key(k));

/// Einrichtung erledigt, Plan bei „adaptiv“, Wochenprüfung erledigt,
/// gespeicherte Stufe [stage] der Unterforderung.
Future<StorageSession> _preopen(Device d, String stage) async {
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
  d.clock.set(_now);
  await s.settings.set(planLastCheckDayKey, '2026-11-11', at: _now);
  await SettingsPlanAdaptationStore(s.settings)
      .set(PlanAdaptationMode.adaptive, at: _now);
  await s.settings.set(planUnderloadStageKey, stage, at: _now);
  await s.settings.set(planUnderloadSinceKey, _now.toIso8601String(), at: _now);
  return s;
}

Future<void> _tap(WidgetTester tester, String k) async {
  await tester.ensureVisible(_key(k));
  await tester.tap(_key(k));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Hinweis: „HFmax prüfen“ beantwortet ihn und öffnet das Profil '
      'mit dem Feld HFmax im Fokus', (tester) async {
    final d = Device();
    final s = await _preopen(d, 'hint');
    await d.start(tester, const Locale('de'));
    expect(_key('plan_underload_hint'), findsOneWidget);
    await _tap(tester, 'plan_underload_check');
    expect(await s.settings.get(planUnderloadStageKey), 'hintDone');
    final field = find.descendant(
      of: _key('profile_max'),
      matching: find.byType(EditableText),
    );
    expect(field, findsOneWidget);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
  });

  testWidgets('Frage: „Ja, steigern“ → neue Fassung mit Grund underload', (
    tester,
  ) async {
    final d = Device();
    final s = await _preopen(d, 'question');
    final plans = (s as PlanStorage).plans;
    final before = (await plans.history()).length;
    await d.start(tester, const Locale('de'));
    expect(_key('plan_underload_question'), findsOneWidget);
    await _tap(tester, 'plan_underload_yes');
    expect(_key('plan_underload_card'), findsNothing);
    expect(await s.settings.get(planUnderloadStageKey), 'accepted');
    final history = await plans.history();
    expect(history, hasLength(before + 1));
    expect(history.last.reason, planReasonUnderload);
  });

  testWidgets('„Ja, steigern“ wartet auf eine laufende Berechnung', (
    tester,
  ) async {
    final d = Device();
    final s = await _preopen(d, 'question');
    final plans = (s as PlanStorage).plans;
    final before = (await plans.history()).length;
    await d.start(tester, const Locale('de'));
    final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
    final gate = Completer<void>();
    unawaited(home.recalculation.exclusive(() => gate.future));
    await tester.ensureVisible(_key('plan_underload_yes'));
    await tester.tap(_key('plan_underload_yes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await plans.history(), hasLength(before));
    expect(await s.settings.get(planUnderloadStageKey), 'question');
    gate.complete();
    await tester.pumpAndSettle();
    expect(await plans.history(), hasLength(before + 1));
    expect(await s.settings.get(planUnderloadStageKey), 'accepted');
  });

  testWidgets('Frage: „Nein“ → keine neue Fassung', (tester) async {
    final d = Device();
    final s = await _preopen(d, 'question');
    final plans = (s as PlanStorage).plans;
    final before = (await plans.history()).length;
    await d.start(tester, const Locale('de'));
    await _tap(tester, 'plan_underload_no');
    expect(_key('plan_underload_card'), findsNothing);
    expect(await s.settings.get(planUnderloadStageKey), 'declined');
    expect(await plans.history(), hasLength(before));
  });
}
