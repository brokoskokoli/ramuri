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

/// Schalter „Plananpassung an Erholung: adaptiv / fix“ (FR-0216) auf der
/// Plan-Seite; Lockerung nach PAR-173. Synthetische Daten: Ziel, Plan und
/// Readiness-Bänder sind ausgedacht.

final Uint8List _k = Uint8List.fromList(List.generate(32, (i) => i));
final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));

Finder key(String k) => find.byKey(Key(k));

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

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

class _Env {
  _Env(this.session, this.hardDay)
    : clock = FakeClock(_day(hardDay).add(const Duration(hours: 12)));

  final StorageSession session;

  /// Erster Tag ab morgen mit einer harten Einheit im Plan.
  final int hardDay;
  final FakeClock clock;

  /// Was die Readiness-Quelle für den Tag liefert; `null`: kein Wert.
  PlanReadinessDay? Function(DateTime day) readiness = (_) => null;
  int readinessCalls = 0;

  PlanRepository get plans => (session as PlanStorage).plans;

  /// Plan mit hoher Start-Wochenzeit (jede Woche mit harter Einheit),
  /// angelegt am Mittwoch [_d0].
  static Future<_Env> open() async {
    final s = await FakeStorage().open(_k);
    await (s as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: (s as PlanStorage).plans,
      settings: s.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: _day(0).add(const Duration(hours: 8)),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
      warning: (s as WarningStorage).warning,
    );
    for (var n = 1; n < 28; n++) {
      final u = await (s as PlanStorage).plans.unitOn(_day(n));
      if (u != null && u.isHard) return _Env(s, n);
    }
    fail('keine harte Einheit');
  }

  PlanController controller() => PlanController(
    session: session,
    clock: clock,
    reader: PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => const [],
    ),
    readinessToday: (day) async {
      readinessCalls++;
      return readiness(day);
    },
  );

  Future<int> versions() async => (await plans.history()).length;
}

PlanReadinessDay _low(DateTime day) => PlanReadinessDay(
  day: day,
  band: ReadinessBand.recoveryAdvised,
  drivers: const [ReadinessFactorId.hrv],
);

void main() {
  group('Controller', () {
    test('Vorgabe „fix“; der Wechsel wird gespeichert', () async {
      final e = await _Env.open();
      final c = e.controller();
      await c.reload();
      expect(c.state.adaptation, PlanAdaptationMode.fixed);
      expect(
        await c.setAdaptation(PlanAdaptationMode.adaptive),
        PlanActionResult.done,
      );
      expect(await e.session.settings.get(planAdaptationKey), 'adaptive');
      expect(c.state.adaptation, PlanAdaptationMode.adaptive);
      expect(
        await c.setAdaptation(PlanAdaptationMode.fixed),
        PlanActionResult.done,
      );
      expect(await e.session.settings.get(planAdaptationKey), 'fixed');
      expect(c.state.adaptation, PlanAdaptationMode.fixed);
      c.dispose();
    });

    test('Wechsel auf „adaptiv“ ohne harte Einheit heute: keine neue '
        'Fassung, auch bei niedrigem Wert', () async {
      final e = await _Env.open();
      // Ein Tag ohne harte Einheit: der Tag vor der ersten harten.
      e.clock.advance(const Duration(days: -1));
      final today = _day(e.hardDay - 1);
      final u = await e.plans.unitOn(today);
      expect(u == null || !u.isHard, isTrue);
      e.readiness = _low;
      final before = await e.versions();
      final c = e.controller();
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      expect(await e.versions(), before);
      expect(await e.session.settings.get(planAdaptationKey), 'adaptive');
      c.dispose();
    });

    test('Wechsel auf „adaptiv“ mit harter Einheit heute und niedrigem '
        'Wert: genau eine neue Fassung, heute locker, Vortage '
        'unverändert', () async {
      final e = await _Env.open();
      final today = _day(e.hardDay);
      final hard = (await e.plans.unitOn(today))!;
      final past = [
        for (final u in await e.plans.unitsBetween(_day(-30), _day(400)))
          if (u.day.isBefore(today)) _sig(u),
      ];
      e.readiness = _low;
      final before = await e.versions();
      final c = e.controller();
      expect(
        await c.setAdaptation(PlanAdaptationMode.adaptive),
        PlanActionResult.done,
      );
      expect(await e.versions(), before + 1);
      final v = (await e.plans.history()).last;
      expect(v.trigger, PlanTrigger.feedback);
      expect(v.reason, planReasonReadiness);
      final now = (await e.plans.unitOn(today))!;
      expect(now.kind, PlanUnitKind.easy);
      expect(now.minutes, hard.minutes);
      expect([
        for (final u in await e.plans.unitsBetween(_day(-30), _day(400)))
          if (u.day.isBefore(today)) _sig(u),
      ], past);
      // Derselbe Modus noch einmal: nichts.
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      expect(await e.versions(), before + 1);
      c.dispose();
    });

    for (final (name, source)
        in <(String, PlanReadinessDay? Function(DateTime))>[
          ('ohne Wert', (_) => null),
          ('Wert ohne Zahl', (d) => PlanReadinessDay(day: d, band: null)),
          (
            'normaler Wert',
            (d) => PlanReadinessDay(day: d, band: ReadinessBand.normal),
          ),
          (
            'Wert eines anderen Tags',
            (d) => _low(d.subtract(const Duration(days: 1))),
          ),
          ('Fehler beim Laden', (_) => throw StateError('x')),
        ]) {
      test('Wechsel auf „adaptiv“ mit harter Einheit heute, $name: keine '
          'neue Fassung', () async {
        final e = await _Env.open();
        e.readiness = source;
        final before = await e.versions();
        final c = e.controller();
        expect(
          await c.setAdaptation(PlanAdaptationMode.adaptive),
          PlanActionResult.done,
        );
        expect(e.readinessCalls, 1);
        expect(await e.versions(), before);
        expect((await e.plans.unitOn(_day(e.hardDay)))!.isHard, isTrue);
        c.dispose();
      });
    }

    test('Wechsel auf „fix“ nach Lockerung heute: genau eine neue Fassung, '
        'die harte Einheit kehrt zurück; ohne Lockerung keine', () async {
      final e = await _Env.open();
      final today = _day(e.hardDay);
      final hard = (await e.plans.unitOn(today))!;
      e.readiness = _low;
      final c = e.controller();
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      final eased = await e.versions();
      expect(
        await c.setAdaptation(PlanAdaptationMode.fixed),
        PlanActionResult.done,
      );
      expect(await e.versions(), eased + 1);
      final v = (await e.plans.history()).last;
      expect(v.reason, planReasonAdaptationFixed);
      expect((await e.plans.unitOn(today))!.kind, hard.kind);
      // Ohne heutige Lockerung: kein Wechsel erzeugt eine Fassung.
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      final n = await e.versions();
      e.readiness = (_) => null;
      await c.setAdaptation(PlanAdaptationMode.fixed);
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      await c.setAdaptation(PlanAdaptationMode.fixed);
      // Der erste Wechsel auf „fix“ nimmt die zweite Lockerung zurück.
      expect(await e.versions(), n + 1);
      c.dispose();
    });

    test('Wechsel am Folgetag ändert den gelockerten Vortag nicht '
        '(nicht rückwirkend)', () async {
      final e = await _Env.open();
      final today = _day(e.hardDay);
      e.readiness = _low;
      final c = e.controller();
      await c.setAdaptation(PlanAdaptationMode.adaptive);
      expect((await e.plans.unitOn(today))!.kind, PlanUnitKind.easy);
      c.dispose();
      e.clock.advance(const Duration(days: 1));
      final c2 = e.controller();
      final before = await e.versions();
      await c2.setAdaptation(PlanAdaptationMode.fixed);
      expect(await e.versions(), before);
      expect((await e.plans.unitOn(today))!.kind, PlanUnitKind.easy);
      c2.dispose();
    });
  });

  group('Plan-Seite', () {
    Future<void> pump(WidgetTester tester, _Env e, PlanController c) async {
      tester.view.physicalSize = const Size(411, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = await tester.runAsync(
        () => AppSettings.load(e.session.settings, e.clock),
      );
      final holder = AppSettingsHolder()..attach(settings!);
      await tester.pumpWidget(
        OffloadScope(
          offload: inlineOffload,
          child: AppSettingsScope(
            holder: holder,
            child: localizedApp(
              locale: const Locale('de'),
              home: PlanScreen(
                session: e.session,
                clock: e.clock,
                controller: c,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('Schalter mit Erklärung, Vorgabe „fix“; „adaptiv“ wird '
        'gespeichert', (tester) async {
      final e = (await tester.runAsync(_Env.open))!;
      final c = e.controller();
      addTearDown(c.dispose);
      await pump(tester, e, c);
      // Der Schalter steht nach der Woche.
      await tester.scrollUntilVisible(
        key('plan_adapt_card'),
        200,
        scrollable: find
            .descendant(of: key('plan_list'), matching: find.byType(Scrollable))
            .first,
      );
      expect(key('plan_adapt_card'), findsOneWidget);
      expect(find.text('Plan an Gesundheitsdaten anpassen'), findsOneWidget);
      expect(find.textContaining('Bei „adaptiv“'), findsOneWidget);
      final sw = tester.widget<SegmentedButton<PlanAdaptationMode>>(
        key('plan_adapt_switch'),
      );
      expect(sw.selected, {PlanAdaptationMode.fixed});
      await tester.ensureVisible(key('plan_adapt_adaptive'));
      await tester.tap(key('plan_adapt_adaptive'));
      await settle(tester);
      expect(
        await tester.runAsync(() => e.session.settings.get(planAdaptationKey)),
        'adaptive',
      );
      expect(
        tester
            .widget<SegmentedButton<PlanAdaptationMode>>(
              key('plan_adapt_switch'),
            )
            .selected,
        {PlanAdaptationMode.adaptive},
      );
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
