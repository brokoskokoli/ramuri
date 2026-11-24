import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'helpers/local_clock.dart';

/// Eine andere Sportart (FR-0221) zählt nicht für Trainingsstand (PAR-192),
/// lockeres Tempo (PAR-205) und Wochenminuten des Plans (DEC-0056).
/// Synthetische Daten (SEC-0001 bis SEC-0010).
final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags Ortszeit.
final _now = DateTime(2026, 11, 11, 12);
final _today = DateTime.utc(2026, 11, 11);

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
  currentWeeklySeconds: 60 * 60.0,
);

/// Beendete Einheit [ago] Tage vor heute, 8 bis 9 Uhr UTC.
Future<void> _unit(StorageSession s, int ago, {OtherSport? sport}) async {
  final start = _today
      .subtract(Duration(days: ago))
      .add(const Duration(hours: 8));
  final r = await s.runs.create(
    startedAt: start,
    mode: sport == null ? RunMode.gps : RunMode.sport,
    sport: sport,
  );
  await s.runs.setState(
    r.id,
    RunState.finished,
    endedAt: start.add(const Duration(hours: 1)),
    endedUtcOffset: Duration.zero,
  );
}

Future<PlanDataReader> _reader({required bool withSport}) async {
  final s = await FakeStorage().open(_key);
  // Läufe in der Vorwoche und davor; Sporteinheiten an denselben Tagen.
  for (final ago in [3, 8, 10, 16, 23]) {
    await _unit(s, ago);
    if (withSport) {
      await _unit(s, ago, sport: OtherSport.values[ago % 4]);
    }
  }
  if (withSport) await _unit(s, 9, sport: OtherSport.rope);
  return PlanDataReader(session: s, clock: LocalFakeClock(_now));
}

void main() {
  test('Wochenminuten des Plans ohne Sporteinheiten', () async {
    final without = await (await _reader(withSport: false))
        .weekEvidence(_today);
    final with_ = await (await _reader(withSport: true)).weekEvidence(_today);
    expect(without.doneMinutes, greaterThan(0));
    expect(with_.doneMinutes, without.doneMinutes);
  });

  test('Trainingsstand und lockeres Tempo ohne Sporteinheiten', () async {
    final without = await (await _reader(withSport: false))
        .read(goal: _goal(), today: _today);
    final with_ = await (await _reader(withSport: true))
        .read(goal: _goal(), today: _today);
    expect(with_.goal.currentWeeklySeconds, without.goal.currentWeeklySeconds);
    expect(without.goal.currentWeeklySeconds, isNot(60 * 60.0));
    expect(with_.inputs.toJson(), without.inputs.toJson());
  });
}
