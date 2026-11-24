// Ein Lauf über Mitternacht steht in Kalender (FR-0171), Plan-Einheit
// (PAR-231) und Kalender ohne Einheit am Tag seines Starts (PAR-237). Die
// Läufe tragen den Versatz 0, ihre Tage sind UTC-Mitternacht wie die
// Plan-Tage; die Uhr ist eine Ortszeit-Testuhr, so gilt der Test in jeder
// Zone der Zeitzonen-Matrix.
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_screen.dart';
import 'package:running_app/features/settings/app_settings.dart';
import 'package:running_app/offload_scope.dart';

import 'app_harness.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Freitag, 13.11.2026, mittags; die Woche beginnt am Montag, 9.11.
final _now = DateTime(2026, 11, 13, 12);
final _mon = DateTime.utc(2026, 11, 9);
DateTime _d(int n) => _mon.add(Duration(days: n));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 3, 14),
  runDays: const {1, 2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60,
  createdAt: DateTime.utc(2026, 11, 1),
  canRun30: ContinuousRun30.yes,
  hardSessionEnabled: false,
);

PlanUnit _easy(int day) => PlanUnit(
  day: _d(day),
  kind: PlanUnitKind.easy,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: 30,
  segments: const [PlanSegment(kind: PlanSegmentKind.easy, minutes: 30)],
);

/// Controller ohne wöchentliche Prüfung beim Öffnen.
class _NoCheck extends PlanController {
  _NoCheck(StorageSession session, Clock clock)
    : super(session: session, clock: clock);
  @override
  Future<void> open() => reload();
}

/// Lauf ab Tag [day] 23:30 bis zum Folgetag 00:40 (Versatz 0).
Future<int> _midnightRun(StorageSession s, int day) async {
  final start = _d(day).add(const Duration(hours: 23, minutes: 30));
  final run = await s.runs.create(startedAt: start);
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(const Duration(minutes: 70)),
    endedUtcOffset: Duration.zero,
  );
  return run.id;
}

void main() {
  testWidgets('Kalender und Plan-Einheit zeigen den Lauf über Mitternacht am '
      'Starttag, nicht am Folgetag (FR-0171, PAR-231, PAR-237)', (
    tester,
  ) async {
    final session = await FakeStorage().open(_key);
    final clock = LocalFakeClock(_now);
    await (session as GoalStorage).goals.save(_goal(), today: _d(0));
    final plans = (session as PlanStorage).plans;
    await plans.writeVersion(
      PlanVersionDraft(
        createdAt: _d(0),
        validFrom: _d(0),
        trigger: PlanTrigger.create,
        reason: 'start',
        version: const PlanVersion(),
        inputs: PlanInputs(
          anchor: _mon,
          startWeeklyMinutes: 145,
          today: _d(0),
          easyPaceSecondsPerKm: 360,
          easyRunCount: 4,
        ),
        summary: const {'larger': false, 'changedUnitCount': 1},
        units: [_easy(1)],
        readState: planUnitsFingerprint(
          await plans.unitsBetween(_mon, planFarFuture),
        ),
      ),
    );
    // Dienstag 23:30 bis Mittwoch 00:40: für die Einheit am Dienstag.
    final planned = await _midnightRun(session, 1);
    // Donnerstag 23:30 bis Freitag 00:40, ohne Einheit.
    await _midnightRun(session, 3);
    final controller = _NoCheck(session, clock);
    addTearDown(controller.dispose);
    expect(await controller.autoAssignRuns(since: _mon), PlanActionResult.done);
    expect((await controller.unitOn(_d(1)))!.runId, planned);

    tester.view.physicalSize = const Size(411, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await AppSettings.load(session.settings, clock);
    await tester.pumpWidget(
      OffloadScope(
        offload: inlineOffload,
        child: AppSettingsScope(
          holder: AppSettingsHolder()..attach(settings),
          child: localizedApp(
            locale: const Locale('de'),
            home: PlanScreen(
              session: session,
              clock: clock,
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('plan_open_calendar'));
    await tester.pumpAndSettle();

    Finder inDay(String day, String text) => find.descendant(
      of: key('calendar_day_2026-11-$day'),
      matching: find.textContaining(text),
    );
    // Einheit des Starttags erledigt; der Folgetag hat keinen Lauf.
    expect(inDay('10', 'erledigt'), findsOneWidget);
    expect(inDay('11', 'Lauf ohne Plan'), findsNothing);
    expect(inDay('11', 'Ruhetag'), findsOneWidget);
    // Lauf ohne Einheit am Starttag (Donnerstag), nicht am Freitag.
    expect(inDay('12', 'Lauf ohne Plan'), findsOneWidget);
    expect(inDay('13', 'Lauf ohne Plan'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
