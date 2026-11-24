import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show text;

// Anzeige der Begründung (PAR-235, FR-0216): Hat die Regel der Abweichung
// eine offene Einheit geändert, steht unter ihr in der Plan-Woche, warum.
// Synthetische Daten: Ziel und Plan sind ausgedacht.

/// Derselbe Schlüssel wie im Harness, damit die App den Speicher öffnet.
final Uint8List _appKey = Uint8List.fromList(List.filled(32, 7));

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

/// Montag derselben Woche: Tag des auslösenden Laufs.
final _monday = DateTime.utc(2026, 11, 9);

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

/// Speicher vor dem Start: Plan, dessen heutige Einheit locker (30 min) ist;
/// die letzte Fassung trägt [notes] im `summary`.
Future<void> _preopen(Device d, List<PlanRunNote> notes) async {
  d.clock.set(_now);
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
      summary: {
        ...last.summary,
        planRunNotesKey: [for (final n in notes) n.toJson()],
      },
      units: [
        for (final u in all)
          if (!u.day.isBefore(_today))
            PlanUnit(
              day: u.day,
              kind: isoDay(u.day) == isoDay(_today)
                  ? PlanUnitKind.easy
                  : u.kind,
              phase: u.phase,
              weekIndex: u.weekIndex,
              minutes: isoDay(u.day) == isoDay(_today) ? 30 : u.minutes,
              segments: isoDay(u.day) == isoDay(_today) ? const [] : u.segments,
            ),
      ],
      readState: planUnitsFingerprint(all),
    ),
  );
}

Finder get _todayCard => key('plan_day_${isoDay(_today)}');

Future<void> _openPlan(Device d, WidgetTester tester, String lang) async {
  await d.start(tester, Locale(lang));
  await tester.tap(key('home_plan'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_todayCard);
  await tester.pumpAndSettle();
}

PlanRunNote _note(PlanUnitKind kind) => PlanRunNote(
  day: _today,
  kind: kind,
  change: PlanRunChange.eased,
  runDay: _monday,
);

void main() {
  testWidgets('deutsch: Begründung unter der locker gewordenen Einheit', (
    tester,
  ) async {
    final d = Device();
    await _preopen(d, [_note(PlanUnitKind.easy)]);
    await _openPlan(d, tester, 'de');
    expect(
      find.descendant(of: _todayCard, matching: key('plan_day_deviation')),
      findsOneWidget,
    );
    expect(
      text('plan_day_deviation'),
      'Dein Lauf am Montag war intensiv und zählt als harte Einheit '
      'dieser Woche.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('englisch: Begründung mit Wochentag', (tester) async {
    final d = Device();
    await _preopen(d, [_note(PlanUnitKind.easy)]);
    await _openPlan(d, tester, 'en');
    expect(
      text('plan_day_deviation'),
      "Your run on Monday was intensive and counts as this week's hard "
      'session.',
    );
  });

  testWidgets('andere Art am Tag: keine Begründung', (tester) async {
    final d = Device();
    await _preopen(d, [_note(PlanUnitKind.progressive)]);
    await _openPlan(d, tester, 'de');
    expect(key('plan_day_deviation'), findsNothing);
  });

  testWidgets('ohne Begründung im summary: keine Zeile', (tester) async {
    final d = Device();
    await _preopen(d, const []);
    await _openPlan(d, tester, 'de');
    expect(key('plan_day_deviation'), findsNothing);
  });
}
