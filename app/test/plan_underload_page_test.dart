import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/offload_scope.dart';

import 'app_harness.dart';
import 'support/settle_storage.dart';

// Karte der Unterforderung auf der Plan-Seite (PAR-236): Hinweis „HFmax
// prüfen“ / „Passt so“ und Frage „Ja, steigern“ / „Nein“ sind an den
// Controller angeschlossen. Synthetische Daten: Ziel und Plan sind
// ausgedacht.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i + 9));
final _now = DateTime(2026, 11, 11, 12);

Finder key(String k) => find.byKey(Key(k));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: false,
  canRun30: ContinuousRun30.yes,
);

/// Plan bei „adaptiv“ mit gespeicherter Stufe [stage] der Unterforderung.
Future<StorageSession> _withStage(Clock clock, String stage) async {
  final session = await FakeStorage().open(_k);
  final c = PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => const [],
    ),
  );
  expect(await c.saveGoal(_goal()), PlanActionResult.done);
  c.dispose();
  await SettingsPlanAdaptationStore(session.settings)
      .set(PlanAdaptationMode.adaptive, at: clock.now());
  await session.settings.set(planUnderloadStageKey, stage, at: clock.now());
  await session.settings.set(
    planUnderloadSinceKey,
    clock.now().toUtc().toIso8601String(),
    at: clock.now(),
  );
  return session;
}

Future<void> _pump(
  WidgetTester tester,
  StorageSession session,
  Clock clock,
) async {
  tester.view.physicalSize = const Size(411, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = (await tester.runAsync(
    () => AppSettings.load(session.settings, clock),
  ))!;
  final holder = AppSettingsHolder()..attach(settings);
  await tester.pumpWidget(
    OffloadScope(
      offload: inlineOffload,
      child: AppSettingsScope(
        holder: holder,
        child: localizedApp(
          locale: const Locale('de'),
          home: PlanScreen(session: session, clock: clock),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await observeFrames(tester, 5, frame: Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.tap(key(k));
  await _settle(tester);
}

void main() {
  testWidgets('Hinweis: Text und Knöpfe; „Passt so“ beantwortet ihn', (
    tester,
  ) async {
    final clock = LocalFakeClock(_now);
    final session = (await tester.runAsync(() => _withStage(clock, 'hint')))!;
    await _pump(tester, session, clock);
    expect(
      find.text(
        'Dein Puls lag bei den letzten lockeren Läufen oft hoch, obwohl sie '
        'sich leicht anfühlten. Stimmt deine HFmax im Profil?',
      ),
      findsOneWidget,
    );
    expect(find.text('HFmax prüfen'), findsOneWidget);
    expect(find.text('Passt so'), findsOneWidget);
    await _tap(tester, 'plan_underload_fine');
    expect(key('plan_underload_card'), findsNothing);
    expect(
      await tester.runAsync(() => session.settings.get(planUnderloadStageKey)),
      'hintDone',
    );
  });

  testWidgets('„HFmax prüfen“ ohne Neuberechnungsdienst schließt den Hinweis', (
    tester,
  ) async {
    final clock = LocalFakeClock(_now);
    final session = (await tester.runAsync(() => _withStage(clock, 'hint')))!;
    await _pump(tester, session, clock);
    await _tap(tester, 'plan_underload_check');
    expect(key('plan_underload_card'), findsNothing);
    expect(
      await tester.runAsync(() => session.settings.get(planUnderloadStageKey)),
      'hintDone',
    );
  });

  testWidgets('Frage: „Ja, steigern“ → neue Fassung mit Grund underload', (
    tester,
  ) async {
    final clock = LocalFakeClock(_now);
    final session = (await tester.runAsync(
      () => _withStage(clock, 'question'),
    ))!;
    final plans = (session as PlanStorage).plans;
    await _pump(tester, session, clock);
    expect(
      find.text(
        'Deine lockeren Läufe scheinen dich zu unterfordern. Plan etwas '
        'steigern?',
      ),
      findsOneWidget,
    );
    final before = (await tester.runAsync(plans.history))!.length;
    await _tap(tester, 'plan_underload_yes');
    expect(key('plan_underload_card'), findsNothing);
    expect(
      await tester.runAsync(() => session.settings.get(planUnderloadStageKey)),
      'accepted',
    );
    final history = (await tester.runAsync(plans.history))!;
    expect(history, hasLength(before + 1));
    expect(history.last.reason, planReasonUnderload);
  });

  testWidgets('Frage: „Nein“ → keine neue Fassung', (tester) async {
    final clock = LocalFakeClock(_now);
    final session = (await tester.runAsync(
      () => _withStage(clock, 'question'),
    ))!;
    final plans = (session as PlanStorage).plans;
    await _pump(tester, session, clock);
    final before = (await tester.runAsync(plans.history))!.length;
    await _tap(tester, 'plan_underload_no');
    expect(key('plan_underload_card'), findsNothing);
    expect(
      await tester.runAsync(() => session.settings.get(planUnderloadStageKey)),
      'declined',
    );
    expect((await tester.runAsync(plans.history))!, hasLength(before));
  });
}
