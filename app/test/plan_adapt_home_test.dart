import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/home/home_screen.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';
import 'package:running_app/features/readiness/readiness_service.dart';

import 'app_harness.dart';

// „Heute“ bei „fix“ (FR-0216, PAR-173): unter der Karte „Erholung“ steht bei
// niedrigem Wert und offener harter Einheit nur die Empfehlung mit „Locker
// laufen“; der Plan bleibt, bis der Nutzer ersetzt. Alle Werte sind erfunden.

final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags (UTC, Versatz 0).
final _now = DateTime.utc(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);
final _created = DateTime.utc(2026, 11, 2, 12);

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: const {1, 3, 5},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

Finder _key(String k) => find.byKey(Key(k));

PlanRepository _plans(StorageSession s) => (s as PlanStorage).plans;

/// Speicher vor dem Start: Einrichtung erledigt, Ziel und Plan, Prüfung der
/// Woche erledigt, heute eine Intervalleinheit, Modus [mode].
Future<StorageSession> _preopen(
  Device d,
  PlanAdaptationMode mode, {
  bool warning = false,
}) async {
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
  await _hardToday(s);
  await SettingsPlanAdaptationStore(s.settings).set(mode, at: _now);
  if (warning) {
    await (s as WarningStorage).warning.set(
      WarningSignal(reportedOn: _today, source: WarningSource.manual),
    );
  }
  return s;
}

/// Heute ist eine Intervalleinheit geplant (statt der gespeicherten).
Future<void> _hardToday(StorageSession s) async {
  final plans = _plans(s);
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
              kind: isoDay(u.day) == isoDay(_today)
                  ? PlanUnitKind.intervals
                  : u.kind,
              phase: u.phase,
              weekIndex: u.weekIndex,
              minutes: u.minutes,
              segments: u.segments,
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
}

/// Erweiterte Stufe mit einer Zahl im Band zu [value] für heute.
ReadinessSnapshot _snapshot(int value) => ReadinessSnapshot(
  result: ReadinessResult(
    state: ReadinessState.number,
    value: value,
    band: readinessBandOf(value),
    capped: false,
    factors: const [],
    missing: const [],
    blockers: const [],
    facts: const [],
    markedFacts: const [],
    hasFreshMeasurement: true,
    level: ReadinessLevel.good,
    levelReasons: const [],
    explanation: const ReadinessExplanation(
      code: ReadinessExplanationCode.noDeviation,
      drivers: [],
      used: [],
      missing: [],
      cappedWithoutLoad: false,
    ),
  ),
  developerMode: false,
  extended: true,
  today: _today,
);

/// Die Karte „Erholung“ auf „Heute“ zeigt [value] (statt echter Daten).
void _readiness(int value) {
  HomeScreen.debugWrapReadiness = (_, load) async {
    await load;
    return _snapshot(value);
  };
  addTearDown(() => HomeScreen.debugWrapReadiness = null);
}

Future<PlanUnit> _unitToday(StorageSession s) async =>
    (await _plans(s).unitOn(_today))!;

void main() {
  testWidgets('„fix“, niedriger Wert, harte Einheit heute: Empfehlung; '
      '„Locker laufen“ ersetzt erst nach Bestätigung', (tester) async {
    final d = Device();
    final s = await _preopen(d, PlanAdaptationMode.fixed);
    final versions = (await _plans(s).history()).length;
    _readiness(30);
    await d.start(tester, const Locale('de'));
    expect(_key('plan_adapt_recommendation'), findsOneWidget);
    expect(
      find.text('Für heute wird ein lockerer Lauf empfohlen.'),
      findsOneWidget,
    );
    // Unter der Karte „Erholung“.
    expect(
      tester.getTopLeft(_key('plan_adapt_recommendation')).dy,
      greaterThan(tester.getTopLeft(_key('readiness_card')).dy),
    );
    expect(
      tester.getSize(_key('plan_adapt_easy_run')).height,
      greaterThanOrEqualTo(48),
    );
    // Der Plan bleibt unverändert.
    expect((await _unitToday(s)).kind, PlanUnitKind.intervals);
    expect((await _plans(s).history()).length, versions);
    // Abbrechen ändert nichts.
    await tester.ensureVisible(_key('plan_adapt_easy_run'));
    await tester.tap(_key('plan_adapt_easy_run'));
    await tester.pumpAndSettle();
    expect(_key('home_easy_dialog'), findsOneWidget);
    await tester.tap(_key('home_easy_cancel'));
    await tester.pumpAndSettle();
    expect((await _unitToday(s)).kind, PlanUnitKind.intervals);
    // Bestätigen ersetzt die heutige Einheit.
    await tester.tap(_key('plan_adapt_easy_run'));
    await tester.pumpAndSettle();
    await tester.tap(_key('home_easy_confirm'));
    await tester.pumpAndSettle();
    expect((await _unitToday(s)).kind, PlanUnitKind.easy);
    expect(_key('plan_adapt_recommendation'), findsNothing);
  });

  testWidgets('„fix“, Band „erhöhte Belastung“: Empfehlung', (tester) async {
    final d = Device();
    await _preopen(d, PlanAdaptationMode.fixed);
    _readiness(45);
    await d.start(tester, const Locale('de'));
    expect(_key('plan_adapt_recommendation'), findsOneWidget);
  });

  for (final (name, mode, value, warning) in [
    ('„adaptiv“', PlanAdaptationMode.adaptive, 30, false),
    ('„fix“, normaler Wert', PlanAdaptationMode.fixed, 60, false),
    ('„fix“, Warnsignal', PlanAdaptationMode.fixed, 30, true),
  ]) {
    testWidgets('$name: keine Empfehlung', (tester) async {
      final d = Device();
      final s = await _preopen(d, mode, warning: warning);
      _readiness(value);
      await d.start(tester, const Locale('de'));
      expect(_key('readiness_card'), findsOneWidget);
      expect(_key('plan_adapt_recommendation'), findsNothing);
      // Unter dem Warnsignal ist heute Ruhe (FR-0203), sonst bleibt die
      // harte Einheit.
      expect(
        (await _unitToday(s)).kind,
        warning ? PlanUnitKind.rest : PlanUnitKind.intervals,
      );
    });
  }
}
