// Andere Sportart hakt eine lockere Einheit ab (FR-0222, PAR-233): die Wege
// über „Einheit starten“ und nach einer freien Sporteinheit, Hinweis beim
// Abhaken und Grund, wenn die Zuordnung nicht erlaubt ist. Synthetische Werte:
// Ziel, Profil, Plan und Puls sind ausgedacht.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/run/run_ports.dart';

import '../app_harness.dart';
import 'other_sport_test.dart' show beat, chooseSport, go;

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

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

/// Speicher vor dem Start: Einrichtung erledigt, Profil mit HFmax 190 und
/// Ruhepuls 60 (Grenze „locker“ nach PAR-111: 151), Plan über den echten
/// Controller; die heutige Einheit wird zur Art [kind] mit 3 min.
Future<void> _preopen(Device d, {PlanUnitKind kind = PlanUnitKind.easy}) async {
  d.clock.set(_now);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  await s.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
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
  final plans = (s as PlanStorage).plans;
  final last = (await plans.history()).last;
  final all = await plans.unitsBetween(
    planDay(last.inputs.anchor),
    DateTime.utc(2028),
  );
  await plans.writeVersion(
    PlanVersionDraft(
      createdAt: _now,
      validFrom: _today,
      trigger: last.trigger,
      reason: last.reason,
      version: last.version,
      inputs: last.inputs,
      summary: last.summary,
      units: [
        for (final u in all)
          if (!u.day.isBefore(_today))
            PlanUnit(
              day: u.day,
              kind: isoDay(u.day) == isoDay(_today) ? kind : u.kind,
              phase: u.phase,
              weekIndex: u.weekIndex,
              minutes: isoDay(u.day) == isoDay(_today) ? 3 : u.minutes,
              segments: isoDay(u.day) == isoDay(_today) ? const [] : u.segments,
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
}

Future<Device> _launch(
  WidgetTester tester, {
  PlanUnitKind kind = PlanUnitKind.easy,
}) async {
  final d = Device()..recordingService = FakeRecordingServicePort();
  d.runViaSensors = true;
  await _preopen(d, kind: kind);
  await d.start(tester, const Locale('de'));
  await d.sensors.connect('h1', name: 'Gurt h1');
  await tester.pump();
  return d;
}

/// Startet über [start] eine Seilspring-Einheit, [seconds] s mit [bpm] und
/// beendet sie über die Abschlussansicht.
Future<void> _sport(
  Device d,
  WidgetTester tester,
  String start, {
  int seconds = 150,
  int bpm = 120,
}) async {
  await tester.tap(key(start));
  await tester.pumpAndSettle();
  await chooseSport(tester, OtherSport.rope);
  await go(tester);
  await beat(d, tester, seconds, bpm: bpm);
  await tester.tap(key('run_pause'));
  await tester.pump();
  await tester.tap(key('run_finish'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_finish_confirm'));
  await tester.pumpAndSettle();
  await tester.tap(key('run_done_close'));
  await tester.pumpAndSettle();
}

Future<PlanUnit?> _unitToday(Device d) =>
    (d.session as PlanStorage).plans.unitOn(_today);

String _dialogText(WidgetTester tester, String dialog) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.descendant(
              of: key(dialog),
              matching: find.byType(DefaultTextStyle),
            ),
            matching: find.byType(Text),
          )
          .at(1),
    )
    .data!;

void main() {
  testWidgets('Einheit starten -> Andere Sportart, locker und lang genug: '
      'abgehakt, Hinweis „Ersetzt den Ausdauerreiz …“', (tester) async {
    final d = await _launch(tester);
    await _sport(d, tester, 'home_start_unit');
    expect(key('other_sport_assign_ask'), findsNothing);
    expect(key('other_sport_replaced'), findsOneWidget);
    expect(
      find.descendant(
        of: key('other_sport_replaced'),
        matching: find.text(
          'Ersetzt den Ausdauerreiz, nicht das Laufen selbst.',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(key('other_sport_dialog_ok'));
    await tester.pumpAndSettle();
    final run = (await d.session.runs.list()).single;
    expect(run.mode, RunMode.sport);
    expect((await _unitToday(d))!.runId, run.id);
    expect(key('home_today_done'), findsOneWidget);
  });

  testWidgets('Freie Sporteinheit: Frage nach der lockeren Einheit, Ja hakt '
      'ab, Hinweis erscheint', (tester) async {
    final d = await _launch(tester);
    await _sport(d, tester, 'home_start_run');
    expect(key('other_sport_assign_ask'), findsOneWidget);
    await tester.tap(key('other_sport_assign_yes'));
    await tester.pumpAndSettle();
    expect(key('other_sport_replaced'), findsOneWidget);
    await tester.tap(key('other_sport_dialog_ok'));
    await tester.pumpAndSettle();
    final run = (await d.session.runs.list()).single;
    expect((await _unitToday(d))!.runId, run.id);
  });

  testWidgets('Freie Sporteinheit, Nein: keine Zuordnung, kein Hinweis', (
    tester,
  ) async {
    final d = await _launch(tester);
    await _sport(d, tester, 'home_start_run');
    await tester.tap(key('other_sport_assign_no'));
    await tester.pumpAndSettle();
    expect(key('other_sport_replaced'), findsNothing);
    expect((await _unitToday(d))!.runId, isNull);
  });

  testWidgets('Puls über der Grenze: nicht abgehakt, Grund „zu intensiv“', (
    tester,
  ) async {
    final d = await _launch(tester);
    await _sport(d, tester, 'home_start_unit', bpm: 170);
    expect(key('other_sport_replaced'), findsNothing);
    expect(key('other_sport_not_assigned_tooIntensive'), findsOneWidget);
    expect(
      _dialogText(tester, 'other_sport_not_assigned_tooIntensive'),
      startsWith('Zu intensiv'),
    );
    await tester.tap(key('other_sport_dialog_ok'));
    await tester.pumpAndSettle();
    expect((await _unitToday(d))!.runId, isNull);
  });

  testWidgets('Frei, zu kurz: keine Frage, Grund „zu kurz“', (tester) async {
    final d = await _launch(tester);
    await _sport(d, tester, 'home_start_run', seconds: 60);
    expect(key('other_sport_assign_ask'), findsNothing);
    expect(key('other_sport_not_assigned_tooShort'), findsOneWidget);
    await tester.tap(key('other_sport_dialog_ok'));
    await tester.pumpAndSettle();
    expect((await _unitToday(d))!.runId, isNull);
  });

  testWidgets('Lange Einheit heute: frei keine Zuordnung, Grund „keine '
      'lockere Einheit“', (tester) async {
    final d = await _launch(tester, kind: PlanUnitKind.long);
    await _sport(d, tester, 'home_start_run');
    expect(key('other_sport_assign_ask'), findsNothing);
    expect(key('other_sport_not_assigned_noEasyUnit'), findsOneWidget);
    await tester.tap(key('other_sport_dialog_ok'));
    await tester.pumpAndSettle();
    expect((await _unitToday(d))!.runId, isNull);
  });
}
