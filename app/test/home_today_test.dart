import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/run/run_flow_screen.dart';

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

/// Schreibt die heutige Fassung neu: Einheiten ab heute über [unit] (sonst
/// unverändert), Eingaben über [inputs] (JSON, sonst unverändert).
Future<void> _rewritePlan(
  StorageSession s, {
  PlanUnit Function(PlanUnit u)? unit,
  Map<String, Object?> Function(Map<String, Object?> json)? inputs,
}) async {
  final plans = (s as PlanStorage).plans;
  final last = (await plans.history()).last;
  final all = await plans.unitsBetween(
    planDay(last.inputs.anchor),
    DateTime.utc(2028),
  );
  final json = jsonDecode(last.inputsJson) as Map<String, Object?>;
  await plans.writeVersion(
    PlanVersionDraft(
      createdAt: _now,
      validFrom: _today,
      trigger: last.trigger,
      reason: last.reason,
      version: last.version,
      inputs: PlanInputs.fromJson(inputs == null ? json : inputs(json)),
      summary: last.summary,
      units: [
        for (final u in all)
          if (!u.day.isBefore(_today))
            (unit ?? (u) => u)(
              PlanUnit(
                day: u.day,
                kind: u.kind,
                phase: u.phase,
                weekIndex: u.weekIndex,
                minutes: u.minutes,
                segments: u.segments,
              ),
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
}

/// Heute ist eine Ruhetag-Einheit (`PlanUnitKind.rest`).
Future<void> _restToday(StorageSession s) => _rewritePlan(
  s,
  unit: (u) => isoDay(u.day) == isoDay(_today)
      ? PlanUnit(
          day: u.day,
          kind: PlanUnitKind.rest,
          phase: u.phase,
          weekIndex: u.weekIndex,
          minutes: 0,
          segments: const [],
        )
      : u,
);

HomeScreen _home(WidgetTester tester) =>
    tester.widget<HomeScreen>(find.byType(HomeScreen, skipOffstage: false));

/// Startet über [start], läuft 30 s und bestätigt das Ende; die Abschluss-
/// ansicht bleibt offen.
Future<void> _runToSummary(Device d, WidgetTester tester, String start) async {
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
    // Nachfrage (Maintainer 2026-11-10): ohne Antwort keine Zuordnung.
    expect(key('home_assign_ask'), findsOneWidget);
    expect((await _unitToday(d.session))!.runId, isNull);
    await tester.tap(key('home_assign_no'));
    await tester.pumpAndSettle();
    expect(key('home_assign_ask'), findsNothing);
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

  group('Nachbesserung D', () {
    testWidgets('„Fertig“ vor dem Ende der Berechnung: Zuordnung danach, '
        'Datenmeldung erst nach der Zuordnung', (tester) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      final home = _home(tester);
      final gate = Completer<void>();
      unawaited(home.recalculation.exclusive(() => gate.future));
      await _runToSummary(d, tester, 'home_start_unit');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(key('sum_loading'), findsOneWidget);
      var changed = 0;
      home.changes.addListener(() => changed++);
      await tester.tap(key('run_done_close'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final run = (await d.session.runs.list()).single;
      expect(run.state, RunState.finished);
      // Die Berechnung steht noch an; die Zuordnung wartet dahinter, die
      // Datenmeldung wartet auf die Zuordnung.
      expect((await _unitToday(d.session))!.runId, isNull);
      expect(changed, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect((await _unitToday(d.session))!.runId, run.id);
      expect(changed, greaterThan(0));
      expect(key('home_today_done'), findsOneWidget);
      expect(
        await d.session.settings.get(SettingKeys.planStartedUnit),
        isEmpty,
      );
    });

    testWidgets('Frei laufen, „Fertig“ vor dem Ende der Berechnung, Ja: '
        'Lauf zählt zur Einheit, Termin bleibt', (tester) async {
      final d = Device();
      final s = await _preopen(d, days: {1, 3, 5});
      final before = await _unitToday(s);
      await d.start(tester, const Locale('de'));
      final gate = Completer<void>();
      unawaited(_home(tester).recalculation.exclusive(() => gate.future));
      await _runToSummary(d, tester, 'home_start_run');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(key('sum_loading'), findsOneWidget);
      await tester.tap(key('run_done_close'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(key('home_assign_ask'), findsOneWidget);
      expect(text('home_assign_ask_title'), 'Zur heutigen Einheit zählen?');
      await tester.tap(key('home_assign_yes'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect((await _unitToday(d.session))!.runId, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      final unit = (await _unitToday(d.session))!;
      expect(unit.runId, run.id);
      expect(unit.day, before!.day);
      expect(unit.pinned, before.pinned);
      expect(key('home_today_done'), findsOneWidget);
    });

    testWidgets('Frei laufen ohne Plan: keine Nachfrage (en)', (tester) async {
      final d = Device();
      await _preopen(d);
      await d.start(tester, const Locale('en'));
      await _runAndFinish(d, tester, 'home_start_run');
      expect((await d.session.runs.list()).single.state, RunState.finished);
      expect(key('home_assign_ask'), findsNothing);
    });

    testWidgets('Frei laufen am Ruhetag (Tag ohne Einheit): keine Nachfrage', (
      tester,
    ) async {
      final d = Device();
      await _preopen(d, days: {1, 5});
      await d.start(tester, const Locale('de'));
      await _runAndFinish(d, tester, 'home_start_run');
      expect(key('home_assign_ask'), findsNothing);
    });

    testWidgets('Ruhetag-Einheit: Ruhetag auf Heute, keine Nachfrage', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d, days: {1, 3, 5});
      await _restToday(s);
      expect((await _unitToday(s))!.kind, PlanUnitKind.rest);
      await d.start(tester, const Locale('de'));
      expect(text('home_today_rest'), 'Heute ist Ruhetag.');
      expect(key('home_start_unit'), findsNothing);
      await _runAndFinish(d, tester, 'home_start_run');
      expect(key('home_assign_ask'), findsNothing);
      expect((await _unitToday(d.session))!.runId, isNull);
    });

    testWidgets('Einheit schon erledigt: zweiter, freier Lauf ohne Nachfrage', (
      tester,
    ) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      await _runAndFinish(d, tester, 'home_start_unit');
      final first = (await _unitToday(d.session))!.runId;
      expect(first, isNotNull);
      await _runAndFinish(d, tester, 'home_start_run');
      expect(key('home_assign_ask'), findsNothing);
      expect((await _unitToday(d.session))!.runId, first);
    });

    testWidgets('Einheit gestartet, App beendet, Fortsetzen: Lauf an der '
        'Einheit', (tester) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
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
      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect((await _unitToday(d.session))!.runId, run.id);
      expect(
        await d.session.settings.get(SettingKeys.planStartedUnit),
        isEmpty,
      );
    });

    testWidgets('Einheit gestartet, App beendet, Speichern: Lauf an der '
        'Einheit', (tester) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 20);
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect((await _unitToday(d.session))!.runId, run.id);
    });

    testWidgets('Einheit beendet, App vor der Zuordnung beendet: Zuordnung '
        'beim nächsten Start', (tester) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      await _runToSummary(d, tester, 'home_start_unit');
      await tester.pumpAndSettle();
      expect((await _unitToday(d.session))!.runId, isNull);
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      final run = (await d.session.runs.list()).single;
      expect((await _unitToday(d.session))!.runId, run.id);
      expect(key('home_today_done'), findsOneWidget);
    });

    for (final rest in [false, true]) {
      testWidgets(
        rest
            ? 'Einheit während des Laufs durch Ruhetag ersetzt: Hinweis, '
                  'keine Zuordnung'
            : 'Einheit während des Laufs neu angelegt (neue Kennung): '
                  'Zuordnung zur Einheit desselben Tags',
        (tester) async {
          final d = Device();
          final s = await _preopen(d, days: {1, 3, 5});
          final old = (await _unitToday(s))!.id;
          await d.start(tester, const Locale('de'));
          await tester.tap(key('home_start_unit'));
          await tester.pumpAndSettle();
          await (rest ? _restToday(s) : _rewritePlan(s));
          final now = (await _unitToday(s))!;
          expect(now.id, isNot(old));
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
          final run = (await d.session.runs.list()).single;
          if (rest) {
            expect(key('home_assign_failed'), findsOneWidget);
            expect(
              find.textContaining('nicht zugeordnet werden'),
              findsOneWidget,
            );
            expect((await _unitToday(d.session))!.runId, isNull);
          } else {
            expect(key('home_assign_failed'), findsNothing);
            expect((await _unitToday(d.session))!.runId, run.id);
          }
        },
      );
    }

    testWidgets('Zuordnung gespeichert, nur die Neuberechnung scheitert: '
        'Hinweis nennt die Zuordnung, Merker bleibt', (tester) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_unit'));
      await tester.pumpAndSettle();
      // Eingaben der letzten Fassung unlesbar: `assignRun` schreibt die
      // Zuordnung, die Neuberechnung danach scheitert (`failed`).
      final versions = d.storage.data.planVersions;
      final last = versions.values.reduce((a, b) => a.id > b.id ? a : b);
      versions[last.id] = PlanVersionRecord(
        id: last.id,
        goalId: last.goalId,
        createdAt: last.createdAt,
        validFrom: last.validFrom,
        trigger: last.trigger,
        reason: last.reason,
        version: last.version,
        inputsJson: 'kaputt',
        summaryJson: last.summaryJson,
      );
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
      final run = (await d.session.runs.list()).single;
      expect((await _unitToday(d.session))!.runId, run.id);
      expect(key('home_assign_failed'), findsNothing);
      expect(key('home_assign_not_recalculated'), findsOneWidget);
      expect(find.textContaining('ist der Einheit zugeordnet'), findsOneWidget);
      // `failed` lässt den Merker stehen: der nächste Start rechnet nach.
      expect(
        await d.session.settings.get(SettingKeys.planStartedUnit),
        isNotEmpty,
      );
    });

    testWidgets('onFinished meldet genau einmal, schon beim Ende', (
      tester,
    ) async {
      final d = Device();
      await _preopen(d);
      await d.start(tester, const Locale('de'));
      final h = _home(tester);
      final calls = <int>[];
      unawaited(
        Navigator.of(tester.element(key('home_screen'))).push<void>(
          MaterialPageRoute(
            builder: (_) => RunFlowScreen(
              session: h.session,
              clock: h.clock,
              ports: h.runPorts,
              permissions: h.permissions,
              serialize: h.recalculation.exclusive,
              onFinished: calls.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 20);
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
      final run = (await d.session.runs.list()).single;
      expect(calls, [run.id]);
      await tester.tap(key('run_done_close'));
      await tester.pumpAndSettle();
      expect(calls, [run.id]);
    });

    testWidgets('Grenze des Plans: letzter Plantag gehört dazu, der Tag '
        'danach nicht', (tester) async {
      final d = Device();
      final s = await _preopen(d, days: {1, 3, 5});
      // Ende der Planwochen, wie Heute sie am Tag [day] sieht.
      Future<DateTime> end(DateTime day) async {
        d.clock.set(day.add(const Duration(hours: 12)));
        final c = PlanController(session: s, clock: d.clock);
        await c.reload();
        final weeks = c.state.hints!.weeks;
        c.dispose();
        return planDay(weeks.last.start).add(const Duration(days: 7));
      }

      final first = await end(_today);
      final lastDay = first.subtract(const Duration(days: 1));
      expect(await end(lastDay), first);
      d.clock.set(lastDay.add(const Duration(hours: 12)));
      await d.start(tester, const Locale('de'));
      expect(key('home_today_plan'), findsOneWidget);
      expect(key('home_today_none'), findsNothing);
      await d.stop(tester);
      d.clock.set(first.add(const Duration(hours: 12)));
      await d.start(tester, const Locale('de'));
      expect(key('home_today_none'), findsOneWidget);
    });

    testWidgets('bekanntes lockeres Tempo: „ca. N km“ auf Heute', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d, days: {1, 3, 5});
      await _rewritePlan(
        s,
        inputs: (j) => {...j, 'easyPaceSecondsPerKm': 360.0, 'easyRunCount': 5},
      );
      final unit = (await _unitToday(s))!;
      await d.start(tester, const Locale('de'));
      expect(
        text('home_today_duration'),
        endsWith(' · ca. ${(unit.minutes / 6).round()} km'),
      );
      expect(text('home_week_goal_km'), contains('ca. '));
    });
  });
}
