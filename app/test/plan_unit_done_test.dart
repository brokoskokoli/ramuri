import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_detail_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/plan/plan_unit_screen.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, text;
import 'run_treadmill_display_test.dart' show seedBeltRun;

// Erledigte Einheit zeigt den zugeordneten Lauf (FR-0171): Bewegungszeit und
// Strecke, „locker“/„intensiv“ nach PAR-058, darunter klein die Vorgabe;
// Tipp führt über „Lauf öffnen“ ins Laufdetail. Alle Werte sind erfunden.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

/// Lauf von 52 min mit 9,1 km (9100 m in 3120 s).
const _speed = 9100 / 3120;

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

/// Speicher vor dem Start: Einrichtung erledigt, Ziel mit Plan; die heutige
/// Einheit ist [kind] mit 30 min (bzw. Ruhetag).
Future<StorageSession> _preopen(
  Device d, {
  bool miles = false,
  PlanUnitKind kind = PlanUnitKind.easy,
}) async {
  d.clock.set(_now);
  final s = await d.storage.open(_appKey);
  await s.settings.set(SettingKeys.setupDone, '1', at: DateTime.utc(2026));
  if (miles) {
    await s.settings.set(
      SettingKeys.distanceUnit,
      DistanceUnit.miles.storageValue,
      at: DateTime.utc(2026),
    );
  }
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
      inputs: PlanInputs.fromJson(
        jsonDecode(last.inputsJson) as Map<String, Object?>,
      ),
      summary: last.summary,
      units: [
        for (final u in all)
          if (!u.day.isBefore(_today))
            PlanUnit(
              day: u.day,
              kind: isoDay(u.day) == isoDay(_today) ? kind : u.kind,
              phase: u.phase,
              weekIndex: u.weekIndex,
              minutes: isoDay(u.day) == isoDay(_today)
                  ? (kind == PlanUnitKind.rest ? 0 : 30)
                  : u.minutes,
              segments: isoDay(u.day) == isoDay(_today) ? const [] : u.segments,
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
  return s;
}

/// Ordnet [runId] der heutigen Einheit zu.
Future<void> _assign(StorageSession s, int runId) async {
  final plans = (s as PlanStorage).plans;
  final unit = (await plans.unitOn(_today))!;
  await plans.assignRun(unit.id!, runId);
}

/// Lauf von 52 min / 9,1 km heute früh, zugeordnet; mit [rpe] und
/// [highHrMinutes] (Laufwert Zeit bei ≥ 80 % HFmax).
Future<int> _seedAssigned(
  StorageSession s, {
  int? bpm = 150,
  int? rpe,
  double? highHrMinutes,
}) async {
  final id = await seedRun(
    s,
    DateTime(2026, 11, 11, 7),
    minutes: 52,
    speed: _speed,
    bpm: bpm,
  );
  if (rpe != null) {
    await s.subjective.save(id, RunSubjective(rpe: rpe));
  }
  if (highHrMinutes != null) {
    await s.values.createOriginals(ValueOwner.run(id), [
      ComputedValue(
        key: highHeartRateTimeValueKey,
        value: highHrMinutes,
        unit: minutesUnit,
        computedAt: DateTime.utc(2026, 11, 11, 8),
        measurementCount: 600,
        sources: const ['strap'],
        method: HighHeartRateTime.methodId,
        methodVersion: 1,
        parameterVersion: 1,
        quality: ValueQuality.good,
      ),
    ]);
  }
  await _assign(s, id);
  return id;
}

Finder get _todayCard => key('plan_day_${isoDay(_today)}');

Finder _inToday(String k) => find.descendant(of: _todayCard, matching: key(k));

/// Startet die App und öffnet die Plan-Woche.
Future<void> _openPlan(
  Device d,
  WidgetTester tester, {
  String lang = 'de',
}) async {
  await d.start(tester, Locale(lang));
  await tester.tap(key('home_plan'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_todayCard);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Woche: Lauf 52 min / 9,1 km, „locker“ und „geplant: Locker '
      '30 min“ (FR-0171)', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    await _seedAssigned(s, rpe: 3);
    await _openPlan(d, tester);
    expect(text('plan_day_run'), '52 min · 9,1 km');
    expect(_inToday('plan_day_run'), findsOneWidget);
    expect(text('plan_day_run_intensity'), 'locker');
    expect(text('plan_day_planned'), 'geplant: Locker 30 min');
    // Haken bleibt, die Zielsetzung der offenen Einheit entfällt.
    expect(
      find.descendant(
        of: _todayCard,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(_inToday('plan_day_purpose'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Woche mit Meilen: Strecke in mi', (tester) async {
    final d = Device();
    final s = await _preopen(d, miles: true);
    await _seedAssigned(s, rpe: 3);
    await _openPlan(d, tester);
    // 9100 m = 5,65 mi.
    expect(text('plan_day_run'), '52 min · 5,7 mi');
  });

  testWidgets('englisch: „easy“ und „planned: Easy 30 min“', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    await _seedAssigned(s, rpe: 3);
    await _openPlan(d, tester, lang: 'en');
    expect(text('plan_day_run'), '52 min · 9.1 km');
    expect(text('plan_day_run_intensity'), 'easy');
    expect(text('plan_day_planned'), startsWith('planned: '));
    expect(text('plan_day_planned'), endsWith(' 30 min'));
  });

  group('Kennzeichen nach PAR-058', () {
    testWidgets('RPE 8 → „intensiv“', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, rpe: 8);
      await _openPlan(d, tester);
      expect(text('plan_day_run_intensity'), 'intensiv');
    });

    testWidgets('10 min bei ≥ 80 % HFmax ohne RPE → „intensiv“', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, highHrMinutes: 10);
      await _openPlan(d, tester);
      expect(text('plan_day_run_intensity'), 'intensiv');
    });

    testWidgets('9 min bei ≥ 80 % HFmax ohne RPE → „locker“', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, highHrMinutes: 9);
      await _openPlan(d, tester);
      expect(text('plan_day_run_intensity'), 'locker');
    });

    testWidgets('ohne Puls und ohne RPE → kein Kennzeichen', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, bpm: null);
      await _openPlan(d, tester);
      expect(text('plan_day_run'), '52 min · 9,1 km');
      expect(key('plan_day_run_intensity'), findsNothing);
      expect(text('plan_day_planned'), 'geplant: Locker 30 min');
    });
  });

  testWidgets('Laufband: Strecke des Bands und „Laufband“ wie in der '
      'Laufliste (FR-0196)', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    final id = await seedBeltRun(s, DateTime(2026, 11, 11, 7));
    await _assign(s, id);
    await _openPlan(d, tester);
    expect(text('plan_day_run'), '10 min · 1,8 km · Laufband');
  });

  testWidgets('Semantik der Karte nennt Lauf und Vorgabe', (tester) async {
    final handle = tester.ensureSemantics();
    final d = Device();
    final s = await _preopen(d);
    await _seedAssigned(s, rpe: 8);
    await _openPlan(d, tester);
    final label = tester.getSemantics(key('plan_day_done_semantics')).label;
    expect(label, contains('Erledigt'));
    expect(label, contains('52 min · 9,1 km'));
    expect(label, contains('intensiv'));
    expect(label, contains('geplant: Locker 30 min'));
    handle.dispose();
  });

  testWidgets('Tipp auf erledigte Einheit → „Gelaufen“ → „Lauf öffnen“ → '
      'Laufdetail des zugeordneten Laufs', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    // Ein zweiter Lauf am Vortag, damit die Zuordnung zählt.
    await seedRun(s, DateTime(2026, 11, 10, 7));
    final id = await _seedAssigned(s, rpe: 8);
    await _openPlan(d, tester);
    await tester.tap(_todayCard);
    await tester.pumpAndSettle();
    expect(find.byType(PlanUnitScreen), findsOneWidget);
    expect(text('plan_unit_run'), '52 min · 9,1 km');
    expect(text('plan_unit_run_intensity'), 'intensiv');
    await tester.ensureVisible(key('plan_unit_open_run'));
    await tester.tap(key('plan_unit_open_run'));
    await tester.pumpAndSettle();
    final detail = tester.widget<RunDetailScreen>(find.byType(RunDetailScreen));
    expect(detail.runId, id);
  });

  testWidgets('Lauf im Laufdetail gelöscht: Einheit schließt, die Woche '
      'zeigt sie wieder offen (ADR-0010)', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    final id = await _seedAssigned(s, rpe: 8);
    await _openPlan(d, tester);
    await tester.tap(_todayCard);
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('plan_unit_open_run'));
    await tester.tap(key('plan_unit_open_run'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(key('detail_delete'));
    await tester.tap(key('detail_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    expect(await s.runs.get(id), isNull);
    expect(find.byType(RunDetailScreen), findsNothing);
    expect(find.byType(PlanUnitScreen), findsNothing);
    await tester.ensureVisible(_todayCard);
    await tester.pumpAndSettle();
    expect(_inToday('plan_day_run'), findsNothing);
    expect(_inToday('plan_day_purpose'), findsOneWidget);
    // Wieder offen: ohne Haken, mit „Start“.
    expect(
      find.descendant(
        of: _todayCard,
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsNothing,
    );
    expect(_inToday('plan_day_start'), findsOneWidget);
  });

  testWidgets('Tipp auf offene Einheit zeigt die Vorgabe ohne „Gelaufen“ '
      '(FR-0143)', (tester) async {
    final d = Device();
    await _preopen(d);
    await _openPlan(d, tester);
    expect(_inToday('plan_day_run'), findsNothing);
    expect(_inToday('plan_day_purpose'), findsOneWidget);
    await tester.tap(_todayCard);
    await tester.pumpAndSettle();
    expect(find.byType(PlanUnitScreen), findsOneWidget);
    expect(key('plan_unit_run'), findsNothing);
    expect(key('plan_unit_open_run'), findsNothing);
  });

  group('doppelter Tipp öffnet die Einheit genau einmal (FR-0143)', () {
    /// Zwei Tipps ohne Frame dazwischen, dann ein Zurück.
    Future<void> doubleTapAndBack(WidgetTester tester) async {
      await tester.tap(_todayCard);
      await tester.tap(_todayCard);
      await tester.pumpAndSettle();
      expect(find.byType(PlanUnitScreen), findsOneWidget);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.byType(PlanUnitScreen), findsNothing);
      expect(_todayCard, findsOneWidget);
    }

    testWidgets('erledigte Einheit', (tester) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, rpe: 8);
      await _openPlan(d, tester);
      await doubleTapAndBack(tester);
    });

    testWidgets('offene Einheit', (tester) async {
      final d = Device();
      await _preopen(d);
      await _openPlan(d, tester);
      await doubleTapAndBack(tester);
    });
  });

  testWidgets('Tipp auf erledigte Einheit nimmt den Lauf der Woche, ohne die '
      'Übersichten erneut zu lesen (FR-0171)', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    await _seedAssigned(s, rpe: 8);
    await _openPlan(d, tester);
    expect(text('plan_day_run'), '52 min · 9,1 km');
    final reads = d.storage.data.overviewReads;
    expect(reads, greaterThan(0));
    await tester.tap(_todayCard);
    await tester.pumpAndSettle();
    expect(find.byType(PlanUnitScreen), findsOneWidget);
    expect(text('plan_unit_run'), '52 min · 9,1 km');
    expect(text('plan_unit_run_intensity'), 'intensiv');
    expect(key('plan_unit_open_run'), findsOneWidget);
    expect(d.storage.data.overviewReads, reads);
  });

  testWidgets('gelöschter Lauf: Einheit wieder offen, keine Laufzeile '
      '(ADR-0010)', (tester) async {
    final d = Device();
    final s = await _preopen(d);
    final id = await _seedAssigned(s, rpe: 8);
    await s.deleteRun(id);
    await _openPlan(d, tester);
    expect(key('plan_day_run'), findsNothing);
    expect(key('plan_day_planned'), findsNothing);
    expect(_inToday('plan_day_purpose'), findsOneWidget);
  });

  testWidgets('Ruhetag mit Lauf: unverändert ohne Laufzeile', (tester) async {
    final d = Device();
    final s = await _preopen(d, kind: PlanUnitKind.rest);
    await _seedAssigned(s, rpe: 8);
    await _openPlan(d, tester);
    expect(key('plan_day_run'), findsNothing);
    expect(key('plan_day_planned'), findsNothing);
    expect(_inToday('plan_day_done_semantics'), findsNothing);
  });

  testWidgets('doneRuns liest nur die zugeordneten Läufe, ohne Ruhetag', (
    tester,
  ) async {
    final d = Device();
    final s = await _preopen(d);
    final other = await seedRun(s, DateTime(2026, 11, 10, 7));
    final id = await _seedAssigned(s, rpe: 8, highHrMinutes: 3);
    final c = PlanController(
      session: s,
      clock: d.clock,
      reader: PlanDataReader(
        session: s,
        clock: d.clock,
        loadRuns: () async => const [],
      ),
    );
    addTearDown(c.dispose);
    final unit = (await (s as PlanStorage).plans.unitOn(_today))!;
    final runs = await tester.runAsync(() => c.doneRuns([unit]));
    expect(runs!.keys, [id]);
    expect(runs[id]!.intensive, isTrue);
    expect(runs[id]!.treadmill, isFalse);
    expect(runs.containsKey(other), isFalse);
    final rest = PlanUnit(
      day: unit.day,
      kind: PlanUnitKind.rest,
      phase: unit.phase,
      weekIndex: unit.weekIndex,
      minutes: 0,
      segments: const [],
      runId: id,
    );
    expect(await tester.runAsync(() => c.doneRuns([rest])), isEmpty);
  });

  group('Startseite (FR-0025)', () {
    testWidgets('„Heute erledigt.“ mit Bewegungszeit und Strecke', (
      tester,
    ) async {
      final d = Device();
      final s = await _preopen(d);
      await _seedAssigned(s, rpe: 3);
      // Ein späterer, nicht zugeordneter Lauf am selben Tag zählt nicht.
      await seedRun(s, DateTime(2026, 11, 11, 10));
      await d.start(tester, const Locale('de'));
      expect(key('home_today_done'), findsOneWidget);
      expect(text('home_today_done_run'), '52 min · 9,1 km');
    });

    testWidgets('Ruhetag mit Lauf: ohne Laufzeile', (tester) async {
      final d = Device();
      final s = await _preopen(d, kind: PlanUnitKind.rest);
      await _seedAssigned(s, rpe: 3);
      await d.start(tester, const Locale('de'));
      expect(key('home_today_done'), findsOneWidget);
      expect(key('home_today_done_run'), findsNothing);
    });
  });
}
