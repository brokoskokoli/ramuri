import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/home/home_start_row.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_texts.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ramuri_card.dart';
import 'package:running_app/features/run/run_flow_screen.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, text;
import 'run_test.dart' show walk;

// Heute mit Plan (FR-0209, WP22 Teil D): Karte „Heute geplant“, Wochenziel
// als Zeit, Einstieg „Ziel anlegen“ ohne Plan und die Zuordnung eines
// beendeten Laufs zur gestarteten Einheit. Alle Werte sind erfunden.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags Ortszeit (Zone des Testprozesses).
final _now = DateTime(2026, 11, 11, 12);
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

/// Beschriftung des Knopfs [button] als gerendeter Absatz (ohne Symbol).
RenderParagraph _label(WidgetTester tester, String button) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(of: key(button), matching: find.byType(Text)),
        matching: find.byType(RichText),
      ),
    );

/// Der gerenderte Absatz ist einzeilig und zeigt den ganzen Text: Breite und
/// Höhe entsprechen dem ungebrochenen Text, nichts ist abgeschnitten.
void _expectOneLine(RenderParagraph p, String reason) {
  final tp = TextPainter(
    text: p.text,
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
  )..layout();
  expect(p.didExceedMaxLines, isFalse, reason: reason);
  expect(tp.width, lessThanOrEqualTo(p.size.width + 0.01), reason: reason);
  expect(p.size.height, closeTo(tp.height, 0.01), reason: reason);
  tp.dispose();
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
    d.clock.set(DateTime(2027, 5, 5, 12));
    await d.start(tester, const Locale('en'));
    expect(key('home_today_plan'), findsOneWidget);
    expect(text('home_today_none'), 'No session is planned for today.');
    expect(key('home_today_rest'), findsNothing);
    expect(key('home_start_unit'), findsNothing);
    expect(key('home_start_run'), findsOneWidget);
  });

  // Ortstag (PAR-164): Kurz nach Mitternacht Ortszeit liegt der UTC-Tag
  // östlich von UTC noch auf dem Vortag (Pacific/Auckland: 00:30 am 11.11. ist
  // 11:30 UTC am 10.11.). „Heute“ und der Plan zeigen beide den Ortstag.
  testWidgets('00:30 Ortszeit: „Heute“ und Plan zeigen denselben Ortstag, '
      'nicht den UTC-Vortag', (tester) async {
    final d = Device();
    final s = await _preopen(d, days: {1, 3, 5});
    d.clock.set(localAt(_today, 0, 30));
    final unit = (await _unitToday(s))!;
    // Am Dienstag (Vortag) ist keine Einheit geplant.
    expect(
      await (s as PlanStorage).plans.unitOn(
        _today.subtract(const Duration(days: 1)),
      ),
      isNull,
    );
    await d.start(tester, const Locale('de'));
    expect(key('home_today_unit'), findsOneWidget);
    expect(key('home_today_none'), findsNothing);
    expect(key('home_start_unit'), findsOneWidget);
    await tester.tap(key('home_plan'));
    await tester.pumpAndSettle();
    // „Start“ steht nur am heutigen Tag des Plans, und zwar am 11.11.
    final today = key('plan_day_${isoDay(unit.day)}');
    await tester.ensureVisible(today);
    expect(
      find.descendant(of: today, matching: key('plan_day_start')),
      findsOneWidget,
    );
    expect(key('plan_day_start'), findsOneWidget);
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

  testWidgets('Frei laufen an einem Tag mit offener Einheit: kein Dialog, '
      'Einheit danach erledigt (PAR-231, FR-0025)', (tester) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    await _runAndFinish(d, tester, 'home_start_run');
    final run = (await d.session.runs.list()).single;
    expect(run.state, RunState.finished);
    expect(find.byType(AlertDialog), findsNothing);
    expect((await _unitToday(d.session))!.runId, run.id);
    expect(text('home_today_done'), 'Heute erledigt.');
    expect(key('home_start_unit'), findsNothing);
    expect(key('home_assign_failed'), findsNothing);
  });

  testWidgets('Frei laufen, Zuordnung scheitert: Hinweis, Lauf gespeichert, '
      'Einheit offen; nach Neustart nachgeholt (PAR-231)', (tester) async {
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    d.storage.data.failAssignRun = true;
    await d.start(tester, const Locale('de'));
    await _runAndFinish(d, tester, 'home_start_run');
    expect(key('home_assign_failed'), findsOneWidget);
    expect(key('home_assign_not_recalculated'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final run = (await d.session.runs.list()).single;
    expect(run.state, RunState.finished);
    expect((await _unitToday(d.session))!.runId, isNull);
    expect(key('home_today_done'), findsNothing);
    expect(key('home_start_unit'), findsOneWidget);

    // Speicher wieder schreibbar: Beim Öffnen holt die App die Zuordnung nach.
    d.storage.data.failAssignRun = false;
    await d.stop(tester);
    await d.start(tester, const Locale('de'));
    expect((await _unitToday(d.session))!.runId, run.id);
    expect(text('home_today_done'), 'Heute erledigt.');
    expect(key('home_start_unit'), findsNothing);
  });

  for (final rest in [true, false]) {
    testWidgets(
      rest
          ? 'Frei laufen am Ruhetag, Zuordnung würde scheitern: kein Hinweis'
          : 'Frei laufen ohne Plan, Zuordnung würde scheitern: kein Hinweis',
      (tester) async {
        final d = Device();
        final s = await _preopen(d, days: rest ? {1, 3, 5} : null);
        if (rest) await _restToday(s);
        d.storage.data.failAssignRun = true;
        await d.start(tester, const Locale('de'));
        await _runAndFinish(d, tester, 'home_start_run');
        final run = (await d.session.runs.list()).single;
        expect(run.state, RunState.finished);
        expect(key('home_assign_failed'), findsNothing);
        expect(key('home_assign_not_recalculated'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        if (rest) {
          expect((await _unitToday(d.session))!.runId, isNull);
        } else {
          expect(await _unitToday(d.session), isNull);
        }
      },
    );
  }

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

  group('Zuordnung des Laufs zur Einheit von heute', () {
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

    testWidgets('Frei laufen, „Fertig“ vor dem Ende der Berechnung: '
        'Lauf zählt danach zur Einheit, Termin bleibt', (tester) async {
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
      expect(find.byType(AlertDialog), findsNothing);
      // Die Zuordnung wartet auf die Wertberechnung.
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

    testWidgets('Frei laufen ohne Plan: kein Dialog, kein Hinweis (en)', (
      tester,
    ) async {
      final d = Device();
      await _preopen(d);
      await d.start(tester, const Locale('en'));
      await _runAndFinish(d, tester, 'home_start_run');
      expect((await d.session.runs.list()).single.state, RunState.finished);
      expect(find.byType(AlertDialog), findsNothing);
      expect(key('home_assign_failed'), findsNothing);
    });

    testWidgets('Frei laufen am Ruhetag (Tag ohne Einheit): keine Zuordnung', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d, days: {1, 5});
      await d.start(tester, const Locale('de'));
      await _runAndFinish(d, tester, 'home_start_run');
      expect(find.byType(AlertDialog), findsNothing);
      expect(key('home_assign_failed'), findsNothing);
      final run = (await s.runs.list()).single;
      final units = await (s as PlanStorage).plans.unitsBetween(
        DateTime.utc(2000),
        planFarFuture,
      );
      expect(units.where((u) => u.runId == run.id), isEmpty);
    });

    testWidgets('Ruhetag-Einheit: Ruhetag auf Heute, keine Zuordnung', (
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
      expect(find.byType(AlertDialog), findsNothing);
      expect((await _unitToday(d.session))!.runId, isNull);
    });

    testWidgets('Einheit schon erledigt: zweiter, freier Lauf ändert nichts', (
      tester,
    ) async {
      final d = Device();
      await _preopen(d, days: {1, 3, 5});
      await d.start(tester, const Locale('de'));
      await _runAndFinish(d, tester, 'home_start_unit');
      final first = (await _unitToday(d.session))!.runId;
      expect(first, isNotNull);
      await _runAndFinish(d, tester, 'home_start_run');
      expect(find.byType(AlertDialog), findsNothing);
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

    testWidgets('Freier Lauf Sonntag über Mitternacht, App vor der '
        'Zuordnung beendet, Neustart am Montag: der Kalender zeigt den '
        'Sonntag als erledigt, nicht als Lauf ohne Plan (PAR-231)', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d, days: {3, 7});
      final sunday = DateTime.utc(2026, 11, 15);
      expect(sunday.weekday, DateTime.sunday);
      final plans = (s as PlanStorage).plans;
      expect((await plans.unitOn(sunday))?.runId, isNull);
      // Start kurz vor Mitternacht, 30 s Lauf bis in den Montag; die App
      // endet vor dem Beenden (keine Zuordnung nach dem Lauf).
      d.clock.set(localAt(sunday, 23, 59).add(const Duration(seconds: 45)));
      await d.start(tester, const Locale('de'));
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 30);
      await d.stop(tester);
      d.clock.set(localAt(DateTime.utc(2026, 11, 16), 0, 25));
      await d.start(tester, const Locale('de'));
      await tester.tap(key('recover_save'));
      await tester.pumpAndSettle();
      final run = (await s.runs.list()).single;
      expect(run.state, RunState.finished);
      expect(run.startedAt.toLocal().day, 15);
      expect(run.endedAt!.toLocal().day, 16, reason: 'über Mitternacht');
      await tester.tap(key('home_plan'));
      await tester.pumpAndSettle();
      await tester.tap(key('plan_open_calendar'));
      await tester.pumpAndSettle();
      // Die Wochenansicht beginnt mit der Woche der neuen Fassung (Anker
      // Montag); der Monat zeigt den Sonntag davor.
      await tester.tap(key('calendar_mode_month'));
      await tester.pumpAndSettle();
      final label = tester.getSemantics(key('calendar_day_2026-11-15')).label;
      expect(label, contains('erledigt'));
      expect(label, isNot(contains('ausgefallen')));
      expect(label, isNot(contains('Lauf ohne Plan')));
      expect((await plans.unitOn(sunday))!.runId, run.id);
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
        d.clock.set(localAt(day, 12));
        final c = PlanController(session: s, clock: d.clock);
        await c.reload();
        final weeks = c.state.hints!.weeks;
        c.dispose();
        return planDay(weeks.last.start).add(const Duration(days: 7));
      }

      final first = await end(_today);
      final lastDay = first.subtract(const Duration(days: 1));
      expect(await end(lastDay), first);
      d.clock.set(localAt(lastDay, 12));
      await d.start(tester, const Locale('de'));
      expect(key('home_today_plan'), findsOneWidget);
      expect(key('home_today_none'), findsNothing);
      await d.stop(tester);
      d.clock.set(localAt(first, 12));
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

  // Kopf und Kennzahlen der Zusammenfassung nach dem Lauf (FR-0037, FR-0205):
  // „Datum · Uhrzeit · Art“ wie im Design, die vier Kennzahlen ohne Scrollen
  // über „Fertig“.
  group('Zusammenfassung nach dem Lauf', () {
    /// Startet um 07:40 Ortszeit, läuft 30 s und beendet; die
    /// Abschlussseite bleibt offen.
    Future<void> finishAt0740(
      Device d,
      WidgetTester tester,
      String start, {
      void Function()? whileRunning,
    }) async {
      d.clock.set(DateTime(2026, 11, 11, 7, 40));
      await tester.tap(key(start));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      await walk(d, tester, 30);
      whileRunning?.call();
      await tester.tap(key('run_pause'));
      await tester.pump();
      await tester.tap(key('run_finish'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_finish_confirm'));
      await tester.pumpAndSettle();
    }

    for (final locale in ['de', 'en']) {
      for (final fromPlan in [true, false]) {
        testWidgets('Kopf: Datum · Uhrzeit des Starts'
            '${fromPlan ? ' · Art der Einheit' : ', ohne Einheit keine Art'} '
            '($locale)', (tester) async {
          final d = Device();
          final s = await _preopen(d, days: {1, 3, 5});
          final unit = (await _unitToday(s))!;
          // Ohne Einheit: Tag ohne Einheit. Ein freier Lauf an einem Tag mit
          // offener Einheit zählt als sie (PAR-231) und trägt dann ihre Art.
          if (!fromPlan) await _restToday(s);
          await d.start(tester, Locale(locale));
          await finishAt0740(
            d,
            tester,
            fromPlan ? 'home_start_unit' : 'home_start_run',
          );
          final l10n = lookupAppLocalizations(Locale(locale));
          final kind = planKindName(l10n, unit.kind);
          final date = locale == 'de'
              ? 'Mi., 11. Nov. · 07:40'
              : 'Wed, Nov 11 · 7:40 AM';
          expect(text('sum_header'), fromPlan ? '$date · $kind' : date);
          expect(find.text(l10n.runDoneTitle), findsNothing);
          // Überschrift für Bedienungshilfen.
          expect(
            tester.getSemantics(key('sum_header')),
            matchesSemantics(label: text('sum_header'), isHeader: true),
          );
          expect(key('run_done_status'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final size in [const Size(390, 844), const Size(411, 914)]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}, '
          'Schriftfaktor 1,0: Kennzahlen über „Fertig“ ohne Scrollen', (
        tester,
      ) async {
        final d = Device();
        await _preopen(d, days: {1, 3, 5});
        await d.start(tester, const Locale('de'));
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        // Mit Einheit aus dem Plan: der Hinweis „Aus dem Plan“ steht zusätzlich
        // vor den Kacheln (der engste Fall).
        await finishAt0740(d, tester, 'home_start_unit');
        expect(key('sum_from_plan'), findsOneWidget);
        final close = tester.getRect(key('run_done_close'));
        final list = tester.getRect(find.byType(Scrollable).first);
        for (final k in [
          'run_distance',
          'run_moving_time',
          'run_time',
          'run_avg_pace',
        ]) {
          final r = tester.getRect(key(k));
          expect(r.top, greaterThanOrEqualTo(list.top), reason: k);
          expect(r.bottom, lessThanOrEqualTo(list.bottom), reason: k);
          expect(r.bottom, lessThanOrEqualTo(close.top), reason: k);
          expect(r.right, lessThanOrEqualTo(size.width), reason: k);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final dark in [false, true]) {
      testWidgets('360 dp, Schriftfaktor 1,3, ${dark ? 'dunkel' : 'hell'}: '
          'kein Überlauf', (tester) async {
        if (dark) {
          tester.platformDispatcher.platformBrightnessTestValue =
              Brightness.dark;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
        }
        final d = Device();
        await _preopen(d, days: {1, 3, 5});
        await d.start(tester, const Locale('de'));
        // Größe und Schrift erst im Lauf: geprüft wird die Abschlussseite.
        await finishAt0740(
          d,
          tester,
          'home_start_unit',
          whileRunning: () {
            tester.view.physicalSize = const Size(360, 780);
            tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          },
        );
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        expect(key('sum_header'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          key('sum_explain_sources'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // Knopfzeile wie im Design (FR-0209, FR-0205, FR-0208): „Einheit starten“
  // nimmt den Rest der Zeile, „Frei laufen“ nur seine eigene Breite; passt
  // das nicht, stehen beide untereinander.
  for (final width in [360.0, 411.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final locale in ['de', 'en']) {
        testWidgets('Knopfzeile bei $width dp, Schrift $scale ($locale)', (
          tester,
        ) async {
          await loadManrope(tester);
          final d = Device();
          final s = await _preopen(d, days: {1, 3, 5});
          expect(await _unitToday(s), isNotNull);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await d.start(tester, Locale(locale));
          tester.view.physicalSize = Size(width, 2400);
          await tester.pumpAndSettle();
          final tag = '$width dp, $scale, $locale';
          final unit = tester.getRect(key('home_start_unit'));
          final free = tester.getRect(key('home_start_run'));
          _expectOneLine(_label(tester, 'home_start_unit'), 'unit $tag');
          _expectOneLine(_label(tester, 'home_start_run'), 'run $tag');
          expect(unit.height, greaterThanOrEqualTo(48), reason: tag);
          expect(free.height, greaterThanOrEqualTo(48), reason: tag);
          final row = tester.renderObject<RenderHomeStartRow>(
            key('home_start_row'),
          );
          if (scale == 1.0) {
            // Nebeneinander, Abstand 10, „Frei laufen“ schmaler.
            expect(row.stacked, isFalse, reason: tag);
            expect(free.left - unit.right, closeTo(10, 0.01), reason: tag);
            expect(free.width, lessThan(unit.width), reason: tag);
            expect(unit.center.dy, closeTo(free.center.dy, 0.01));
          } else if (row.stacked) {
            // Untereinander: „Einheit starten“ oben, ohne Überlappung.
            expect(free.top - unit.bottom, closeTo(10, 0.01), reason: tag);
          } else {
            expect(free.left - unit.right, closeTo(10, 0.01), reason: tag);
          }
          expect(tester.takeException(), isNull, reason: tag);
          await tester.tap(key('home_start_unit'));
          await tester.pumpAndSettle();
          expect(key('run_start_ready'), findsOneWidget, reason: tag);
        });
      }
    }
  }

  _headerLinesMain();
}

/// Alle Einheiten ab heute in der Reduktion vor dem Wettkampf, Woche 12:
/// längster Text der Kopfzeile „Heute geplant“.
Future<void> _reductionWeek12(StorageSession s) => _rewritePlan(
  s,
  unit: (u) => PlanUnit(
    day: u.day,
    kind: u.kind,
    phase: PlanPhase.reduction,
    weekIndex: 11,
    minutes: u.minutes,
    segments: u.segments,
  ),
);

/// Gerenderter Absatz des Texts mit Schlüssel [k].
RenderParagraph _paragraph(WidgetTester tester, String k) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: key(k), matching: find.byType(RichText)),
    );

/// Rechteck der Karte, in der der Text mit Schlüssel [k] steht.
Rect _cardOf(WidgetTester tester, String k) => tester.getRect(
  find.ancestor(of: key(k), matching: find.byType(RamuriCard)).first,
);

void _headerLinesMain() {
  // Kopfzeilen „Heute geplant“ und „Wochenziel“ (FR-0209, FR-0205, FR-0148):
  // passt der rechte Teil nicht neben den Titel, steht er vollständig darunter.
  for (final scale in [1.3, 2.0]) {
    for (final locale in ['de', 'en']) {
      testWidgets('Kopfzeilen bei 360 dp, Schrift $scale ($locale): '
          'kein Überlauf, nichts abgeschnitten', (tester) async {
        await loadManrope(tester);
        final d = Device();
        final s = await _preopen(d, days: {1, 3, 5});
        await _reductionWeek12(s);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await d.start(tester, Locale(locale));
        tester.view.physicalSize = const Size(360, 2400);
        await tester.pumpAndSettle();
        final tag = '$scale, $locale';
        expect(tester.takeException(), isNull, reason: tag);
        final week = tester.widget<Text>(key('home_today_week')).data!;
        expect(week, contains('12'), reason: tag);
        expect(
          week,
          contains(locale == 'de' ? 'Reduktion vor Wettkampf' : 'Taper'),
          reason: tag,
        );
        expect(
          tester.widget<Text>(key('home_week_goal_time')).data,
          startsWith('0 '),
          reason: tag,
        );
        for (final k in ['home_today_week', 'home_week_goal_time']) {
          final card = _cardOf(tester, k);
          final r = tester.getRect(key(k));
          expect(r.right, lessThanOrEqualTo(card.right + 0.01), reason: k);
          expect(r.left, greaterThanOrEqualTo(card.left - 0.01), reason: k);
          expect(_paragraph(tester, k).didExceedMaxLines, isFalse, reason: k);
        }
        if (scale == 2.0) {
          expect(
            tester.getRect(key('home_today_week')).top,
            greaterThanOrEqualTo(
              tester.getRect(key('home_today_title')).bottom - 0.01,
            ),
            reason: tag,
          );
        }
      });
    }
  }

  testWidgets('Kopfzeilen bei 411 dp, Schrift 1,0 (de): Titel und Wert in '
      'einer Zeile, Wert rechtsbündig', (tester) async {
    await loadManrope(tester);
    final d = Device();
    await _preopen(d, days: {1, 3, 5});
    await d.start(tester, const Locale('de'));
    tester.view.physicalSize = const Size(411, 2400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final (title, value) in [
      ('home_today_title', 'home_today_week'),
      ('home_week_goal_title', 'home_week_goal_time'),
    ]) {
      final t = tester.getRect(key(title));
      final v = tester.getRect(key(value));
      final card = _cardOf(tester, value);
      expect(t.center.dy, closeTo(v.center.dy, 0.01), reason: value);
      expect(v.left, greaterThan(t.right), reason: value);
      // Rechtsbündig: rechter Rand des Werts am rechten Innenrand der Karte.
      expect(
        card.right - v.right,
        closeTo(t.left - card.left, 0.01),
        reason: value,
      );
    }
  });
}
