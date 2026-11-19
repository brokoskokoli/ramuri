import 'package:adapters/adapters.dart';
import 'package:adapters/src/storage/goal_access.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zieldatum als lokaler Kalendertag (FR-0136): Gespeichert wird genau der
/// gewählte Tag, geladen wird er als lokale Mitternacht desselben Tags – in
/// jeder Zeitzone (etwa `TZ=America/Los_Angeles`, `TZ=Pacific/Kiritimati`).
TrainingGoal _goal(DateTime targetDate) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: targetDate,
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime(2026, 11, 1, 9),
  hardSessionEnabled: false,
  canRun30: ContinuousRun30.yes,
);

void main() {
  late AppDatabase db;
  late DriftGoalStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftGoalStore(db);
  });
  tearDown(() => db.close());

  Future<String?> stored() async =>
      (await db.select(db.goals).getSingle()).targetDate;

  test('Zieldatum 14.11. (lokaler Kalendertag): in der Datenbank '
      '2026-11-14, geladen als lokaler 14.11.', () async {
    await store.save(
      _goal(DateTime(2026, 11, 14)),
      today: DateTime(2026, 11, 1, 9),
    );
    expect(await stored(), '2026-11-14');

    final loaded = (await store.goal())!.targetDate!;
    expect(loaded.isUtc, isFalse);
    expect((loaded.year, loaded.month, loaded.day), (2026, 11, 14));
    expect(calendarDay(loaded), DateTime.utc(2026, 11, 14));
  });

  test('Laden und erneut Speichern verschiebt den Tag nicht', () async {
    await store.save(
      _goal(DateTime(2026, 11, 14)),
      today: DateTime(2026, 11, 1, 9),
    );
    final loaded = (await store.goal())!;
    await store.save(loaded, today: DateTime(2026, 11, 1, 9));
    expect(await stored(), '2026-11-14');
  });
}
