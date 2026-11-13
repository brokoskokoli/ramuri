import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/run/guided_segments.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/plan/plan_started_unit.dart';
import 'package:running_app/features/run/run_flow_screen.dart';
import 'package:running_app/features/summary/plan_origin_note.dart';

import 'app_harness.dart';
import 'run_detail_page_test.dart' show pumpDetail;
import 'run_detail_test.dart' show seedDetailRun;
import 'run_test.dart' show walk;

// WP24 Auftrag 3: Umschalter „Geplante Einheit“ | „Freier Lauf“, Karte mit
// Abschnitten, Hauptschalter „Ansagen“, Einzelschalter, „Aus dem Plan“.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

Future<StorageSession> _open(Device d, {bool plan = true}) async {
  d.clock.set(_now);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  if (plan) {
    final c = PlanController(
      session: s,
      clock: d.clock,
      reader: PlanDataReader(
        session: s,
        clock: d.clock,
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
  }
  return s;
}

String _text(String k) => (key(k).evaluate().single.widget as Text).data!;

List<PlanSegment>? _guided(WidgetTester t) =>
    t.widget<LiveRunView>(find.byType(LiveRunView)).controller.guidedSegments;

bool _planSelected(WidgetTester t) =>
    t.widget<SegmentedButton<bool>>(key('guided_toggle')).selected.single;

PlanUnit _easyWithWarm() => PlanUnit(
  id: 1,
  day: _today,
  kind: PlanUnitKind.easy,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: 40,
  segments: const [
    PlanSegment(kind: PlanSegmentKind.warmUp, minutes: 10),
    PlanSegment(
      kind: PlanSegmentKind.easy,
      minutes: 25,
      intensity: PlanTargetIntensity(hrMinBpm: 128, hrMaxBpm: 145),
    ),
    PlanSegment(kind: PlanSegmentKind.coolDown, minutes: 5),
  ],
);

/// Öffnet „Lauf vorbereiten“ direkt, mit [unit] als offener Einheit.
Future<void> _openFlow(
  WidgetTester tester,
  Device d, {
  PlanUnit? unit,
  bool startPlanned = false,
  Locale locale = const Locale('de'),
}) async {
  await d.start(tester, locale);
  final h = tester.widget<HomeScreen>(
    find.byType(HomeScreen, skipOffstage: false),
  );
  Navigator.of(tester.element(key('home_screen'))).push<void>(
    MaterialPageRoute(
      builder: (_) => RunFlowScreen(
        session: h.session,
        clock: h.clock,
        ports: h.runPorts,
        permissions: h.permissions,
        serialize: h.recalculation.exclusive,
        plannedUnit: unit,
        startPlanned: startPlanned,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('lockere Einheit: keine Auf-/Abwärmabschnitte (PAR-119)', () {
    final s = guidedSegmentsOf(_easyWithWarm());
    expect(s.map((e) => e.kind), [PlanSegmentKind.easy]);
    // PAR-119: Auf- und Abwärmen zählen zur Dauer (10 + 25 + 5 = 40 min).
    expect(s.fold<int>(0, (a, e) => a + e.durationSeconds), 40 * 60);
    expect(s.single.intensity?.hrMaxBpm, 145);
    // Lange Einheit wie die lockere.
    final long = PlanUnit(
      day: _today,
      kind: PlanUnitKind.long,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 40,
      segments: _easyWithWarm().segments,
    );
    final l = guidedSegmentsOf(long);
    expect(l.map((e) => e.kind), [PlanSegmentKind.easy]);
    expect(l.single.durationSeconds, 40 * 60);
    // Intensive Einheit behält sie.
    final hard = PlanUnit(
      day: _today,
      kind: PlanUnitKind.tempo,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 30,
      segments: _easyWithWarm().segments,
    );
    expect(guidedSegmentsOf(hard).length, 3);
    // Ohne Abschnitte: ein lockerer über die Dauer.
    final empty = PlanUnit(
      day: _today,
      kind: PlanUnitKind.easy,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 40,
      segments: const [],
    );
    expect(guidedSegmentsOf(empty).single.minutes, 40);
  });

  group('Ablauf bis zur Zusammenfassung', () {
    testWidgets('„Einheit starten“, Lauf, Beenden: Zusammenfassung zeigt '
        '„Aus dem Plan“ sofort (Review 2, M2)', (tester) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40; i++) {
        d.clock.advance(const Duration(seconds: 10));
        d.location.emit(
          LocationSample(
            time: d.clock.now(),
            latitude: 50 + i * 0.0001,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(key('sum_trimp'), findsOneWidget);
      expect(key('sum_from_plan'), findsOneWidget);
      expect(_text('sum_from_plan_unit'), isNotEmpty);
    });

    testWidgets('Absturz, Fortsetzen, Beenden: Zusammenfassung zeigt „Aus dem '
        'Plan“, der Lauf wird nach dem Schließen zugeordnet (NB4)', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 20);
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      await walk(d, tester, 10, from: 20);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(key('sum_trimp'), findsOneWidget);
      expect(key('sum_from_plan'), findsOneWidget);
      expect(_text('sum_from_plan_unit'), isNotEmpty);
      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      final unit = await (d.session as PlanStorage).plans.unitOn(_today);
      expect(unit!.runId, run.id);
    });

    // Absturz, Fortsetzen und Beenden; [beforeResume] richtet den Merker her.
    // Gibt zurück, ob „Aus dem Plan“ in der Zusammenfassung steht.
    Future<bool> crashResumeFinish(
      WidgetTester tester,
      Device d, {
      required Finder start,
      Future<void> Function()? beforeResume,
    }) async {
      await tester.tap(start);
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 20);
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      await beforeResume?.call();
      await tester.tap(key('recover_resume'));
      await tester.pumpAndSettle();
      await walk(d, tester, 10, from: 20);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      expect(key('sum_trimp'), findsOneWidget);
      return key('sum_from_plan').evaluate().isNotEmpty;
    }

    testWidgets('Freier Lauf, Absturz, Fortsetzen: kein „Aus dem Plan“ (NB5)', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      expect(
        await crashResumeFinish(tester, d, start: key('home_start_run')),
        isFalse,
      );
    });

    testWidgets('Lauf begann vor dem Merker: kein „Aus dem Plan“ (NB5)', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      final unit = (await (d.session as PlanStorage).plans.unitOn(_today))!;
      final shown = await crashResumeFinish(
        tester,
        d,
        start: key('home_start_run'),
        beforeResume: () async {
          // Ein Merker, der jünger ist als der offene Lauf (z. B. weil das
          // Löschen bei „Frei laufen“ scheiterte und später neu gemerkt wurde).
          d.clock.advance(const Duration(minutes: 5));
          await PlanStartedUnitStore(
            session: d.session,
            clock: d.clock,
          ).remember(unit.id!, '2026-11-11');
        },
      );
      expect(shown, isFalse);
    });

    testWidgets('Einheit durch Neuberechnung ersetzt (neue Kennung): '
        '„Aus dem Plan“ wie die Zuordnung in der Datenbank (NB5)', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      final unit = (await (d.session as PlanStorage).plans.unitOn(_today))!;
      final shown = await crashResumeFinish(
        tester,
        d,
        start: key('home_start_unit'),
        beforeResume: () async {
          // Der Merker trägt die alte Kennung, am Tag steht die neue Einheit.
          final old = (await PlanStartedUnitStore(
            session: d.session,
            clock: d.clock,
          ).read())!;
          await d.session.settings.set(
            SettingKeys.planStartedUnit,
            PlanStartedUnit(
              unitId: unit.id! + 1000,
              day: old.day,
              since: old.since,
            ).encode(),
            at: d.clock.now(),
          );
        },
      );
      expect(shown, isTrue);
      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      expect(
        (await (d.session as PlanStorage).plans.unitOn(_today))!.runId,
        run.id,
      );
    });
  });

  group('Umschalter auf „Lauf vorbereiten“', () {
    testWidgets('„Einheit starten“: geplant gewählt, Karte mit Abschnitten', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      expect(_planSelected(tester), isTrue);
      expect(key('guided_card'), findsOneWidget);
      expect(key('guided_segment_0'), findsOneWidget);
      expect(key('guided_no_unit'), findsNothing);
      expect(_text('guided_duration'), isNotEmpty);
    });

    testWidgets('„Frei laufen“: frei gewählt, Einheit wählbar; Wahl wird '
        'gemerkt und der Wechsel auf frei hebt den Merker auf', (tester) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(_planSelected(tester), isFalse);
      expect(key('guided_card'), findsNothing);
      await tester.tap(key('guided_toggle_plan'));
      await tester.pumpAndSettle();
      expect(key('guided_card'), findsOneWidget);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(
        await d.session.settings.get(SettingKeys.planStartedUnit),
        isNotEmpty,
      );
      expect(_guided(tester), isNotEmpty);
    });

    testWidgets('„Einheit starten“, dann „Freier Lauf“: kein Merker', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      await tester.tap(key('guided_toggle_free'));
      await tester.pumpAndSettle();
      expect(key('guided_card'), findsNothing);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(
        await d.session.settings.get(SettingKeys.planStartedUnit) ?? '',
        isEmpty,
      );
      expect(_guided(tester), isNull);
    });

    testWidgets('ohne Plan: nur „Freier Lauf“ mit einem Satz', (tester) async {
      final d = Device();
      await _open(d, plan: false);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(key('guided_no_unit'), findsOneWidget);
      await tester.tap(key('guided_toggle_plan'));
      await tester.pumpAndSettle();
      expect(_planSelected(tester), isFalse);
      expect(key('guided_card'), findsNothing);
    });

    testWidgets('Ruhetag (so steht auch das Warnsignal): nur „Freier Lauf“', (
      tester,
    ) async {
      final d = Device();
      final s = await _open(d);
      final plans = (s as PlanStorage).plans;
      final unit = (await plans.unitOn(_today))!;
      await plans.setRestDay(
        PlanUnit(
          day: _today,
          kind: PlanUnitKind.rest,
          phase: unit.phase,
          weekIndex: unit.weekIndex,
          minutes: 0,
          segments: const [],
        ),
        today: _today,
        expectedUnitId: unit.id,
      );
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(key('guided_no_unit'), findsOneWidget);
      expect(_planSelected(tester), isFalse);
    });

    testWidgets('Warnsignal gemeldet: eigener Satz statt „ohne Plan“', (
      tester,
    ) async {
      final d = Device();
      final s = await _open(d);
      final w = WarningService(
        plans: (s as PlanStorage).plans,
        settings: s.settings,
        warning: (s as WarningStorage).warning,
      );
      await w.report(
        source: WarningSource.runFeedback,
        today: _today,
        now: _now,
      );
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      expect(_planSelected(tester), isFalse);
      expect(_text('guided_no_unit'), contains('Warnsignal'));
    });

    testWidgets('lockere Einheit zeigt nur den Hauptteil, Ziel Puls', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await _openFlow(tester, d, unit: _easyWithWarm(), startPlanned: true);
      expect(key('guided_segment_0'), findsOneWidget);
      expect(key('guided_segment_1'), findsNothing);
      expect(find.text('Aufwärmen'), findsNothing);
      expect(_text('guided_target'), contains('128'));
    });

    testWidgets('englisch und dunkel, Umschalter mindestens 48 dp', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _openFlow(
        tester,
        d,
        unit: _easyWithWarm(),
        startPlanned: true,
        locale: const Locale('en'),
      );
      expect(find.text('Planned session'), findsOneWidget);
      expect(find.text('Free run'), findsOneWidget);
      expect(find.text('Announcements'), findsOneWidget);
      for (final k in ['guided_toggle_plan', 'guided_toggle_free']) {
        final button = find.ancestor(
          of: key(k),
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(button.first).height, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getSize(key('guided_voice')).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('Ansagen', () {
    testWidgets('Hauptschalter wird gemerkt und beim nächsten Öffnen gelesen', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await _openFlow(tester, d);
      expect(tester.widget<SwitchListTile>(key('guided_voice')).value, isTrue);
      await tester.tap(key('guided_voice'));
      await tester.pumpAndSettle();
      expect(await d.session.settings.get(SettingKeys.guidanceEnabled), '0');
      Navigator.of(tester.element(key('guided_voice'))).pop();
      await tester.pumpAndSettle();
      final h = tester.widget<HomeScreen>(
        find.byType(HomeScreen, skipOffstage: false),
      );
      Navigator.of(tester.element(key('home_screen'))).push<void>(
        MaterialPageRoute(
          builder: (_) => RunFlowScreen(
            session: h.session,
            clock: h.clock,
            ports: h.runPorts,
            permissions: h.permissions,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(key('guided_voice')).value, isFalse);
    });

    testWidgets('Einzelschalter in den Einstellungen, Vorgabe an', (
      tester,
    ) async {
      final d = Device();
      await _open(d, plan: false);
      await d.start(tester, const Locale('de'));
      await openOverview(tester);
      await tester.tap(key('home_settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        key('guided_set_heart_rate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      for (final k in [
        'guided_set_kilometer',
        'guided_set_heart_rate',
        'guided_set_segments',
      ]) {
        expect(tester.widget<SwitchListTile>(key(k)).value, isTrue);
      }
      await tester.tap(key('guided_set_heart_rate'));
      await tester.pumpAndSettle();
      expect(await d.session.settings.get(SettingKeys.guidanceHeartRate), '0');
      expect(
        await d.session.settings.get(SettingKeys.guidanceKilometer),
        isNull,
      );
      expect(await d.session.settings.get(SettingKeys.guidanceEnabled), isNull);
    });
  });

  group('„Aus dem Plan“ in der Zusammenfassung', () {
    testWidgets('Detailseite der Historie zeigt „Aus dem Plan“ (NB4)', (
      tester,
    ) async {
      final d = Device();
      await _open(d);
      await d.start(tester, const Locale('de'));
      final id = await seedDetailRun(d.session, _now);
      final unit = (await (d.session as PlanStorage).plans.unitOn(_today))!;
      await (d.session as PlanStorage).plans.assignRun(unit.id!, id);
      await pumpDetail(tester, d, id);
      expect(key('sum_from_plan'), findsOneWidget);
      expect(_text('sum_from_plan_unit'), isNotEmpty);
    });

    for (final locale in [const Locale('de'), const Locale('en')]) {
      testWidgets(
        'zugeordneter Lauf zeigt die Einheit (${locale.languageCode})',
        (tester) async {
          final d = Device();
          final s = await _open(d);
          final unit = (await (s as PlanStorage).plans.unitOn(_today))!;
          final run = await s.runs.create(startedAt: _now);
          await (s as PlanStorage).plans.assignRun(unit.id!, run.id);
          await tester.pumpWidget(
            localizedApp(
              locale: locale,
              brightness: Brightness.dark,
              home: Scaffold(
                body: PlanOriginNote(session: s, runId: run.id),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(key('sum_from_plan'), findsOneWidget);
          expect(
            find.text(
              locale.languageCode == 'de' ? 'Aus dem Plan' : 'From the plan',
            ),
            findsOneWidget,
          );
          expect(_text('sum_from_plan_unit'), isNotEmpty);
        },
      );
    }

    testWidgets('freier Lauf: nichts', (tester) async {
      final d = Device();
      final s = await _open(d);
      final run = await s.runs.create(startedAt: _now);
      await tester.pumpWidget(
        localizedApp(
          home: Scaffold(
            body: PlanOriginNote(session: s, runId: run.id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('sum_from_plan'), findsNothing);
    });
  });
}
