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

/// WP23 Teil C2: Karte „Plan angepasst“ (PAR-204, FR-0170), Verlauf der
/// Änderungen und Vorschlag „Woche wiederholen“ (PAR-140).

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _now = DateTime.utc(2026, 11, 11, 12); // Mittwoch

Finder key(String k) => find.byKey(Key(k));

TrainingGoal _goal({ContinuousRun30 canRun30 = ContinuousRun30.yes}) =>
    TrainingGoal(
      type: GoalType.distance,
      distance: GoalDistance.tenKilometers,
      targetDate: DateTime.utc(2027, 3, 14),
      runDays: const {2, 4, 6},
      maxSessionSeconds: 7200,
      weeklyCapSeconds: 240 * 60.0,
      createdAt: DateTime.utc(2026, 11, 1),
      hardSessionEnabled: false,
      canRun30: canRun30,
    );

PlanController _controller(StorageSession s, Clock c) => PlanController(
  session: s,
  clock: c,
  reader: PlanDataReader(session: s, clock: c, loadRuns: () async => const []),
);

Future<(StorageSession, FakeClock)> _withPlan({
  ContinuousRun30 canRun30 = ContinuousRun30.yes,
}) async {
  final session = await FakeStorage().open(_k);
  final clock = FakeClock(_now);
  final c = _controller(session, clock);
  expect(await c.saveGoal(_goal(canRun30: canRun30)), PlanActionResult.done);
  c.dispose();
  return (session, clock);
}

Future<void> _pump(
  WidgetTester tester,
  StorageSession session,
  Clock clock, {
  Brightness brightness = Brightness.light,
  String locale = 'de',
  double scale = 1,
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final settings = await AppSettings.load(session.settings, clock);
  final holder = AppSettingsHolder()..attach(settings);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    OffloadScope(
      offload: inlineOffload,
      child: AppSettingsScope(
        holder: holder,
        child: localizedApp(
          locale: Locale(locale),
          brightness: brightness,
          home: PlanScreen(session: session, clock: clock),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _report(WidgetTester tester) async {
  await tester.tap(key('plan_menu'));
  await tester.pumpAndSettle();
  await tester.tap(key('plan_menu_report'));
  await tester.pumpAndSettle();
  await tester.tap(key('plan_warning_confirm'));
  await _settle(tester);
  // Die Rückmeldung (Snackbar) verdeckt sonst die Karte.
  await tester.pump(const Duration(seconds: 8));
  await tester.pumpAndSettle();
}

/// Eine kleinere Fassung (ohne „larger“) direkt im Speicher.
Future<PlanVersionRecord> _writeMinor(
  PlanRepository plans, {
  required DateTime at,
  PlanTrigger trigger = PlanTrigger.weekly,
  PlanInputs? inputs,
  bool larger = false,
}) async {
  final last = (await plans.history()).last;
  final use = inputs ?? last.inputs.copyWith(today: at);
  return plans.writeVersion(
    PlanVersionDraft(
      createdAt: at,
      validFrom: at,
      trigger: trigger,
      reason: trigger.name,
      version: last.version,
      inputs: use,
      summary: {'larger': larger, 'changedUnitCount': larger ? 2 : 0},
      units: const [],
      readState: planUnitsFingerprint(
        await plans.unitsBetween(use.anchor, planFarFuture),
      ),
    ),
  );
}

void main() {
  group('Karte „Plan angepasst“', () {
    testWidgets('erst bei größerer Änderung, bis „Verstanden“, dann wieder '
        'bei einer neuen', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      // Die erste Fassung ist keine Änderung.
      expect(key('plan_change_card'), findsNothing);

      await _report(tester);
      expect(key('plan_change_card'), findsOneWidget);
      expect(
        find.text(
          'Du hast Beschwerden gemeldet, deshalb sind die kommenden Tage '
          'vorerst Ruhetage.',
        ),
        findsOneWidget,
      );
      // Ohne Terminverschiebung: nur Verstanden und Verlauf.
      expect(key('plan_change_seen'), findsOneWidget);
      expect(
        tester.getSize(key('plan_change_seen')).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(key('plan_change_seen'));
      await _settle(tester);
      expect(key('plan_change_card'), findsNothing);
      final seen = await tester.runAsync(
        () => WarningState(session.settings).planChangeSeen(),
      );
      expect(seen, (await tester.runAsync(plans.history))!.last.id);

      // Neuer Aufbau: bleibt weg.
      await _pump(tester, session, clock);
      expect(key('plan_change_card'), findsNothing);

      // Eine neue größere Änderung (Aufheben) zeigt sie wieder.
      await tester.ensureVisible(key('plan_warning_lift'));
      await tester.tap(key('plan_warning_lift'));
      await _settle(tester);
      expect(key('plan_change_card'), findsOneWidget);
      expect(
        find.text(
          'Du hast die Meldung aufgehoben, deshalb gilt dein Plan wieder.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('eine kleinere Fassung zeigt keine Karte, steht aber im '
        'Verlauf', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await tester.runAsync(() => _writeMinor(plans, at: _now));
      await _pump(tester, session, clock);
      expect(key('plan_change_card'), findsNothing);

      await tester.tap(key('plan_menu'));
      await tester.pumpAndSettle();
      await tester.tap(key('plan_menu_history'));
      await _settle(tester);
      expect(key('plan_history'), findsOneWidget);
      final h = (await tester.runAsync(plans.history))!;
      expect(h, hasLength(2));
      for (final v in h) {
        expect(key('plan_history_${v.id}'), findsOneWidget);
      }
      // Weder die erste noch die kleinere Fassung gilt als größere Änderung.
      expect(find.text('Größere Änderung'), findsNothing);
      expect(find.text('Der Plan wurde angelegt.'), findsOneWidget);
      expect(
        find.text('Die wöchentliche Prüfung hat den Plan angepasst.'),
        findsOneWidget,
      );
    });

    testWidgets('Verlauf: größere Änderung gekennzeichnet, Öffnen gilt als '
        'gesehen', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      await _pump(tester, session, clock);
      await _report(tester);
      expect(key('plan_change_card'), findsOneWidget);
      await tester.tap(key('plan_change_history'));
      await _settle(tester);
      final h = (await tester.runAsync(
        (session as PlanStorage).plans.history,
      ))!;
      expect(key('plan_history_larger_${h.last.id}'), findsOneWidget);
      expect(key('plan_history_larger_${h.first.id}'), findsNothing);
      expect(find.textContaining('Wochenzeit'), findsWidgets);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await _settle(tester);
      expect(key('plan_history'), findsNothing);
      expect(key('plan_change_card'), findsNothing);
    });

    testWidgets('Anteil der Wochenzeit nur, wenn die Fassung ihn selbst '
        'gesetzt hat', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      final first = (await tester.runAsync(plans.history))!.first;
      final monday = DateTime.utc(2026, 11, 9);
      final own = first.inputs.copyWith(
        anchor: monday,
        today: _now,
        lastWeekMinutes: 100,
        achievedShare: 0.4,
      );
      await tester.runAsync(
        () => _writeMinor(plans, at: _now, inputs: own, larger: true),
      );
      await _pump(tester, session, clock);
      expect(key('plan_change_card'), findsOneWidget);
      expect(
        find.textContaining('Du hast 40 % der geplanten Wochenzeit geschafft'),
        findsOneWidget,
      );
      // Veralteter Anteil (Anker einer früheren Woche): kein Prozentsatz.
      final stale = own.copyWith(anchor: DateTime.utc(2026, 11, 2));
      await tester.runAsync(
        () => _writeMinor(plans, at: _now, inputs: stale, larger: true),
      );
      await _pump(tester, session, clock);
      expect(find.textContaining('geschafft'), findsNothing);
      expect(
        find.text('Die wöchentliche Prüfung hat den Plan angepasst.'),
        findsOneWidget,
      );
    });

    for (final (name, brightness, locale, scale, width) in [
      ('dunkel, 320 dp, Schrift 2.0', Brightness.dark, 'de', 2.0, 320.0),
      ('hell, en', Brightness.light, 'en', 1.0, 411.0),
    ]) {
      testWidgets('Karte und Verlauf: $name', (tester) async {
        final (session, clock) =
            await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
        await _pump(
          tester,
          session,
          clock,
          brightness: brightness,
          locale: locale,
          scale: scale,
          width: width,
        );
        await _report(tester);
        expect(key('plan_change_card'), findsOneWidget);
        await tester.ensureVisible(key('plan_change_history'));
        for (final k in ['plan_change_seen', 'plan_change_history']) {
          expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
        await tester.tap(key('plan_change_history'));
        await _settle(tester);
        expect(key('plan_history'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (locale == 'en') {
          expect(find.text('History of changes'), findsWidgets);
        }
      });
    }
  });

  group('Geh-Lauf: Woche wiederholen (PAR-140)', () {
    Future<(StorageSession, FakeClock)> walkRun(WidgetTester tester) async {
      final r = await tester.runAsync(
        () => _withPlan(canRun30: ContinuousRun30.no),
      ) as (StorageSession, FakeClock);
      // Programmwoche 1 (3 Einheiten Do, Sa, Di) liegt hinter uns.
      r.$2.advance(const Duration(days: 7));
      return r;
    }

    testWidgets('Woche vorbei, zu wenig absolviert: Vorschlag, Annahme '
        'beginnt die Woche neu', (tester) async {
      final (session, clock) = await walkRun(tester);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      expect(key('plan_walk_repeat_card'), findsOneWidget);
      expect(
        find.textContaining('Woche 1 der Geh-Lauf-Abfolge'),
        findsOneWidget,
      );
      expect(find.textContaining('0 von 3'), findsOneWidget);
      final before = (await tester.runAsync(plans.history))!;

      await tester.ensureVisible(key('plan_walk_repeat_yes'));
      expect(
        tester.getSize(key('plan_walk_repeat_yes')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(key('plan_walk_repeat_yes'));
      await _settle(tester);
      final h = (await tester.runAsync(plans.history))!;
      expect(h, hasLength(before.length + 1));
      expect(h.last.reason, 'walkRunRepeat');
      expect(h.last.inputs.walkRunStart, const WalkRunPosition(0));
      final today = DateTime.utc(2026, 11, 18);
      final units = (await tester.runAsync(
        () => plans.unitsBetween(today, planFarFuture),
      ))!;
      final walk = [
        for (final u in units)
          if (u.kind == PlanUnitKind.walkRun) u,
      ];
      expect(walk, isNotEmpty);
      // Die erste neue Einheit ist wieder Einheit 1 von Woche 1.
      final first = (await tester.runAsync(
        () => plans.unitsBetween(
          DateTime.utc(2026, 11, 12),
          DateTime.utc(2026, 11, 12),
        ),
      ))!;
      expect(first.single.kind, PlanUnitKind.walkRun);
      expect(walk.first.segments.length, first.single.segments.length);
      expect(walk.first.minutes, first.single.minutes);
      // Danach kein weiterer Vorschlag für dieselbe Woche.
      expect(key('plan_walk_repeat_card'), findsNothing);
    });

    testWidgets('Ablehnen ändert den Plan nicht und bleibt gemerkt', (
      tester,
    ) async {
      final (session, clock) = await walkRun(tester);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final before = (await tester.runAsync(plans.history))!.length;
      await tester.ensureVisible(key('plan_walk_repeat_no'));
      await tester.tap(key('plan_walk_repeat_no'));
      await _settle(tester);
      expect(key('plan_walk_repeat_card'), findsNothing);
      expect((await tester.runAsync(plans.history))!.length, before);
      await _pump(tester, session, clock);
      expect(key('plan_walk_repeat_card'), findsNothing);
    });

    testWidgets('mitten in der Woche und ohne Geh-Lauf: kein Vorschlag', (
      tester,
    ) async {
      final (session, clock) = await tester.runAsync(
        () => _withPlan(canRun30: ContinuousRun30.no),
      ) as (StorageSession, FakeClock);
      await _pump(tester, session, clock);
      expect(key('plan_walk_repeat_card'), findsNothing);
      final (s2, c2) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      c2.advance(const Duration(days: 7));
      await _pump(tester, s2, c2);
      expect(key('plan_walk_repeat_card'), findsNothing);
    });
  });
}
