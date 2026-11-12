import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_goal_form.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/offload_scope.dart';

import 'app_harness.dart';

/// WP23 Teil C1: Warnsignal melden und aufheben (FR-0203), Nachfrage
/// (PAR-200) auf der Plan-Seite.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

Finder key(String k) => find.byKey(Key(k));

TrainingGoal _goal({double capMinutes = 240}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: capMinutes * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: false,
  canRun30: ContinuousRun30.yes,
);

PlanController _controller(StorageSession s, Clock c) => PlanController(
  session: s,
  clock: c,
  reader: PlanDataReader(session: s, clock: c, loadRuns: () async => const []),
);

Future<(StorageSession, FakeClock)> _withPlan({
  double capMinutes = 240,
  Duration age = Duration.zero,
}) async {
  final session = await FakeStorage().open(_k);
  final clock = FakeClock(_now);
  final c = _controller(session, clock);
  expect(
    await c.saveGoal(_goal(capMinutes: capMinutes)),
    PlanActionResult.done,
  );
  c.dispose();
  clock.advance(age);
  return (session, clock);
}

Future<void> _pump(
  WidgetTester tester,
  StorageSession session,
  Clock clock, {
  Brightness brightness = Brightness.light,
  String locale = 'de',
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(411, 2400);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final settings = await AppSettings.load(session.settings, clock);
  final holder = AppSettingsHolder()..attach(settings);
  // Frischer Zustand, auch bei mehrfachem Aufruf im selben Test.
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(key('plan_menu'));
  await tester.pumpAndSettle();
}

const _fixedDe =
    'Du hast Beschwerden gemeldet. Wir empfehlen dir, das Training zu '
    'pausieren. Wenn die Beschwerden anhalten oder stark sind, lass sie '
    'ärztlich abklären. Diese App stellt keine Diagnose.';
const _fixedEn =
    'You reported symptoms. We recommend pausing your training. If they '
    'persist or are severe, please see a doctor. This app does not provide a '
    'diagnosis.';

void main() {
  group('Warnsignal melden und aufheben', () {
    testWidgets('Melden nach Rückfrage: Banner mit festem Text, nur Ruhetage, '
        'Abbrechen ändert nichts', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      final store = (session as WarningStorage).warning;
      await _pump(tester, session, clock);
      expect(key('plan_warning_banner'), findsNothing);
      final versions = (await tester.runAsync(plans.history))!.length;

      await _openMenu(tester);
      await tester.tap(key('plan_menu_report'));
      await tester.pumpAndSettle();
      expect(key('plan_warning_dialog'), findsOneWidget);
      await tester.tap(key('plan_warning_cancel'));
      await _settle(tester);
      expect(await tester.runAsync(store.read), isNull);
      expect((await tester.runAsync(plans.history))!, hasLength(versions));

      await _openMenu(tester);
      await tester.tap(key('plan_menu_report'));
      await tester.pumpAndSettle();
      await tester.tap(key('plan_warning_confirm'));
      await _settle(tester);
      final w = (await tester.runAsync(store.read))!;
      expect(w.source, WarningSource.manual);
      expect(w.reportedOn, _today);
      expect(key('plan_warning_banner'), findsOneWidget);
      expect(find.text(_fixedDe), findsOneWidget);
      expect(key('plan_warning_reminder'), findsNothing);
      expect(key('plan_warning_reported'), findsOneWidget);
      final h = (await tester.runAsync(plans.history))!;
      expect(h, hasLength(versions + 1));
      expect(h.last.trigger, PlanTrigger.feedback);
      expect(h.last.reason, 'warning');
      final units = (await tester.runAsync(
        () => plans.unitsBetween(_today, DateTime.utc(2027, 3, 14)),
      ))!;
      expect(units, isNotEmpty);
      expect(units.every((u) => u.kind == PlanUnitKind.rest), isTrue);
      // Melden steht im Menü nicht mehr zur Wahl.
      await _openMenu(tester);
      expect(key('plan_menu_report'), findsNothing);
      expect(key('plan_menu_feedback'), findsOneWidget);
    });

    testWidgets('Aufheben: Banner weg, Plan mit den Festlegungen zurück', (
      tester,
    ) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      final store = (session as WarningStorage).warning;
      final before = (await tester.runAsync(
        () => plans.unitsBetween(_today, DateTime.utc(2026, 12, 31)),
      ))!;
      await _pump(tester, session, clock);
      await _openMenu(tester);
      await tester.tap(key('plan_menu_report'));
      await tester.pumpAndSettle();
      await tester.tap(key('plan_warning_confirm'));
      await _settle(tester);
      await tester.ensureVisible(key('plan_warning_lift'));
      expect(find.text('Meldung aufheben'), findsOneWidget);
      await tester.tap(key('plan_warning_lift'));
      await _settle(tester);
      expect(await tester.runAsync(store.read), isNull);
      expect(key('plan_warning_banner'), findsNothing);
      expect(key('plan_warning_lifted'), findsOneWidget);
      final h = (await tester.runAsync(plans.history))!;
      expect(h.last.reason, 'warningLifted');
      final after = (await tester.runAsync(
        () => plans.unitsBetween(_today, DateTime.utc(2026, 12, 31)),
      ))!;
      expect(
        [for (final u in after) (u.day, u.kind)],
        [for (final u in before) (u.day, u.kind)],
      );
    });

    testWidgets('Erinnerung erst ab dem 7. Tag, nur als Karte', (tester) async {
      for (final (days, due) in [(6, false), (7, true), (12, true)]) {
        final (session, clock) =
            await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
        final store = (session as WarningStorage).warning;
        await tester.runAsync(
          () => store.set(
            WarningSignal(
              reportedOn: _today.subtract(Duration(days: days)),
              source: WarningSource.manual,
            ),
          ),
        );
        await _pump(tester, session, clock);
        expect(key('plan_warning_banner'), findsOneWidget, reason: '$days');
        expect(
          key('plan_warning_reminder'),
          due ? findsOneWidget : findsNothing,
          reason: '$days',
        );
        if (days == 7) {
          expect(
            find.text(
              'Du hast vor 7 Tagen Beschwerden gemeldet. Wenn es dir besser '
              'geht, kannst du die Meldung aufheben.',
            ),
            findsOneWidget,
          );
        }
        // Die Meldung bleibt, bis der Nutzer sie aufhebt.
        expect(await tester.runAsync(store.read), isNotNull);
      }
    });

    testWidgets('englischer Text, dunkel, großer Text: Banner bedienbar', (
      tester,
    ) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final store = (session as WarningStorage).warning;
      await tester.runAsync(
        () => store.set(
          WarningSignal(reportedOn: _today, source: WarningSource.manual),
        ),
      );
      await _pump(
        tester,
        session,
        clock,
        locale: 'en',
        brightness: Brightness.dark,
        scale: 2,
      );
      expect(find.text(_fixedEn), findsOneWidget);
      await tester.ensureVisible(key('plan_warning_lift'));
      final size = tester.getSize(key('plan_warning_lift'));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('gehaltener festgelegter Ruhetag gilt unter Warnsignal nicht '
        'als Nutzer-Ruhetag und ist nicht aufhebbar', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      final c = _controller(session, clock);
      final fri = DateTime.utc(2026, 11, 13);
      final unit = (await tester.runAsync(
        () => plans.unitsBetween(DateTime.utc(2026, 11, 12), fri),
      ))!.first;
      expect(
        (await tester.runAsync(
          () => c.setRestDay(
            fri,
            expectedUnitId: unit.day == fri ? unit.id : null,
          ),
        )),
        PlanActionResult.done,
      );
      c.dispose();
      Future<void> openCalendar() async {
        await tester.tap(key('plan_open_calendar'));
        await tester.pumpAndSettle();
      }

      await _pump(tester, session, clock);
      await openCalendar();
      expect(key('calendar_rest_fixed_2026-11-13'), findsOneWidget);
      final store = (session as WarningStorage).warning;
      await tester.runAsync(
        () => WarningService(
          plans: plans,
          settings: session.settings,
          warning: store,
        ).report(source: WarningSource.manual, today: _today, now: clock.now()),
      );
      await _pump(tester, session, clock);
      await openCalendar();
      expect(key('calendar_rest_fixed_2026-11-13'), findsNothing);
      // Keine Aktionen auf dem überlagerten Tag: Tippen öffnet kein Blatt,
      // nichts lässt sich aufheben, ersetzen, verschieben oder festlegen.
      await tester.tap(key('calendar_day_2026-11-13'), warnIfMissed: false);
      await tester.pumpAndSettle();
      for (final k in [
        'calendar_rest_clear',
        'calendar_rest_set',
        'calendar_move',
        'calendar_replace',
      ]) {
        expect(key(k), findsNothing, reason: k);
      }
      final held = (await tester.runAsync(() => plans.unitOn(fri)))!;
      expect(held.pinned, isTrue);
      // Die Festlegung ist nicht gelöscht: Nach dem Aufheben gilt sie wieder.
      await tester.runAsync(
        () => WarningService(
          plans: plans,
          settings: session.settings,
          warning: store,
        ).lift(today: _today, now: clock.now()),
      );
      await _pump(tester, session, clock);
      await openCalendar();
      expect(key('calendar_rest_fixed_2026-11-13'), findsOneWidget);
    });
  });

  group('Überlagerter Tag ohne Festlegung (FR-0203)', () {
    testWidgets(
      'unter Warnsignal wird dort kein „Ruhetag festlegen“ angeboten',
      (tester) async {
        final (session, clock) =
            await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
        final plans = (session as PlanStorage).plans;
        final store = (session as WarningStorage).warning;
        await tester.runAsync(
          () =>
              WarningService(
                plans: plans,
                settings: session.settings,
                warning: store,
              ).report(
                source: WarningSource.manual,
                today: _today,
                now: clock.now(),
              ),
        );
        // Ein künftiger Tag, den das Warnsignal zur Ruhe-Einheit gemacht hat,
        // ohne Festlegung des Nutzers.
        final units = (await tester.runAsync(
          () => plans.unitsBetween(_today, DateTime.utc(2026, 12, 31)),
        ))!;
        final over = units.firstWhere(
          (u) =>
              u.kind == PlanUnitKind.rest &&
              !u.pinned &&
              u.runId == null &&
              !u.day.isBefore(_today) &&
              u.day.isBefore(_today.add(const Duration(days: 6))),
        );
        await _pump(tester, session, clock);
        await tester.tap(key('plan_open_calendar'));
        await tester.pumpAndSettle();
        final id = over.day.toIso8601String().substring(0, 10);
        await tester.tap(key('calendar_day_$id'), warnIfMissed: false);
        await tester.pumpAndSettle();
        for (final k in ['calendar_rest_set', 'calendar_rest_clear']) {
          expect(key(k), findsNothing, reason: k);
        }
      },
    );
  });

  group('Nachfrage nach PAR-200', () {
    Future<(StorageSession, FakeClock)> due(int days, {double cap = 240}) =>
        _withPlan(
          capMinutes: cap,
          age: Duration(days: days),
        );

    testWidgets('Karte erst ab dem 14. Tag nach der Anlage', (tester) async {
      for (final (days, shown) in [(13, false), (14, true)]) {
        final (session, clock) = await tester.runAsync(
          () => due(days),
        ) as (StorageSession, FakeClock);
        await _pump(tester, session, clock);
        expect(
          key('plan_feedback_card'),
          shown ? findsOneWidget : findsNothing,
          reason: '$days',
        );
      }
    });

    testWidgets('ab der letzten Antwort, nicht ab der Anlage', (tester) async {
      final (session, clock) =
          await tester.runAsync(() => due(20)) as (StorageSession, FakeClock);
      await tester.runAsync(
        () => session.settings.set(
          planFeedbackKey,
          '2026-11-25',
          at: clock.now(),
        ),
      );
      // 20 Tage nach Anlage = 1.12.; letzte Antwort 25.11. + 14 = 9.12.
      await _pump(tester, session, clock);
      expect(key('plan_feedback_card'), findsNothing);
    });

    testWidgets('keine Antwort ändert nichts: Karte bleibt, Menü-Blatt '
        'schließen ändert nichts', (tester) async {
      final (session, clock) =
          await tester.runAsync(() => due(14)) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final versions = (await tester.runAsync(plans.history))!.length;
      final unitsBefore = (await tester.runAsync(
        () => plans.unitsBetween(_today, DateTime.utc(2027, 3, 14)),
      ))!;
      await _openMenu(tester);
      await tester.tap(key('plan_menu_feedback'));
      await tester.pumpAndSettle();
      expect(key('plan_feedback_sheet'), findsOneWidget);
      await tester.tapAt(const Offset(200, 20));
      await _settle(tester);
      expect(key('plan_feedback_sheet'), findsNothing);
      expect(key('plan_feedback_card'), findsOneWidget);
      expect((await tester.runAsync(plans.history))!, hasLength(versions));
      expect(
        await tester.runAsync(() => session.settings.get(planFeedbackKey)),
        isNull,
      );
      final unitsAfter = (await tester.runAsync(
        () => plans.unitsBetween(_today, DateTime.utc(2027, 3, 14)),
      ))!;
      expect(unitsAfter.length, unitsBefore.length);
    });

    testWidgets('„zu schwer“: neue Fassung (feedback), Karte weg, Antwort '
        'gemerkt', (tester) async {
      final (session, clock) =
          await tester.runAsync(() => due(14)) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final versions = (await tester.runAsync(plans.history))!.length;
      await tester.ensureVisible(key('plan_feedback_too_hard'));
      await tester.tap(key('plan_feedback_too_hard'));
      await _settle(tester);
      final h = (await tester.runAsync(plans.history))!;
      expect(h, hasLength(versions + 1));
      expect(h.last.trigger, PlanTrigger.feedback);
      expect(
        await tester.runAsync(() => session.settings.get(planFeedbackKey)),
        '2026-11-25',
      );
      expect(key('plan_feedback_card'), findsNothing);
      expect(key('plan_feedback_done'), findsOneWidget);
    });

    testWidgets('„passt“: keine neue Fassung, Antwort gemerkt', (tester) async {
      final (session, clock) =
          await tester.runAsync(() => due(14)) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final versions = (await tester.runAsync(plans.history))!.length;
      await tester.ensureVisible(key('plan_feedback_fits'));
      await tester.tap(key('plan_feedback_fits'));
      await _settle(tester);
      expect((await tester.runAsync(plans.history))!, hasLength(versions));
      expect(
        await tester.runAsync(() => session.settings.get(planFeedbackKey)),
        '2026-11-25',
      );
      expect(key('plan_feedback_card'), findsNothing);
    });

    testWidgets('jederzeit im Menü, auch ohne Fälligkeit', (tester) async {
      final (session, clock) =
          await tester.runAsync(_withPlan) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      expect(key('plan_feedback_card'), findsNothing);
      final versions = (await tester.runAsync(plans.history))!.length;
      await _openMenu(tester);
      await tester.tap(key('plan_menu_feedback'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: key('plan_feedback_sheet'),
          matching: key('plan_feedback_too_hard'),
        ),
      );
      await _settle(tester);
      final h = (await tester.runAsync(plans.history))!;
      expect(h, hasLength(versions + 1));
      expect(h.last.trigger, PlanTrigger.feedback);
    });

    testWidgets('unter Warnsignal keine Karte', (tester) async {
      final (session, clock) =
          await tester.runAsync(() => due(14)) as (StorageSession, FakeClock);
      await tester.runAsync(
        () => (session as WarningStorage).warning.set(
          WarningSignal(
            reportedOn: _today.add(const Duration(days: 14)),
            source: WarningSource.manual,
          ),
        ),
      );
      await _pump(tester, session, clock);
      expect(key('plan_feedback_card'), findsNothing);
    });

    testWidgets('am Regler: „zu leicht“ fragt nach dem Ziel, ändert nur '
        'nach Bestätigung', (tester) async {
      // Regler so klein, dass die Wochenzeit schon am Regler steht.
      final (session, clock) = await tester.runAsync(
        () => due(14, cap: 30),
      ) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final versions = (await tester.runAsync(plans.history))!.length;
      await tester.ensureVisible(key('plan_feedback_too_easy'));
      await tester.tap(key('plan_feedback_too_easy'));
      await _settle(tester);
      expect(key('plan_feedback_raise_dialog'), findsOneWidget);
      expect(find.text('Ziel (Regler) erhöhen?'), findsOneWidget);
      await tester.tap(key('plan_feedback_raise_no'));
      await _settle(tester);
      expect((await tester.runAsync(plans.history))!, hasLength(versions));
      final goal = await tester.runAsync(
        () => (session as GoalStorage).goals.goal(),
      );
      expect(goal!.weeklyCapSeconds, 30 * 60.0);
      expect(key('plan_feedback_card'), findsNothing);
    });

    testWidgets('am Regler: „Ziel anpassen“ öffnet nur das Zielformular, '
        'der Plan bleibt bis zum Speichern', (tester) async {
      final (session, clock) = await tester.runAsync(
        () => due(14, cap: 30),
      ) as (StorageSession, FakeClock);
      final plans = (session as PlanStorage).plans;
      await _pump(tester, session, clock);
      final versions = (await tester.runAsync(plans.history))!.length;
      await tester.ensureVisible(key('plan_feedback_too_easy'));
      await tester.tap(key('plan_feedback_too_easy'));
      await _settle(tester);
      await tester.tap(key('plan_feedback_raise_yes'));
      await _settle(tester);
      expect(find.byType(PlanGoalFormScreen), findsOneWidget);
      expect((await tester.runAsync(plans.history))!, hasLength(versions));
    });
  });
}
