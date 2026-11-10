import 'package:core/core.dart';
import 'package:drift/drift.dart' show Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Das Trainingsziel (FR-0135 bis FR-0137): eine Zeile mit `id = 1`.
class DriftGoalStore implements GoalStore {
  DriftGoalStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<TrainingGoal?> goal() => guarded(() async {
    final r = await _db.select(_db.goals).getSingleOrNull();
    if (r == null) return null;
    return TrainingGoal(
      type: enumOf(GoalType.values, r.type, (v) => v.name),
      distance: r.distance == null
          ? null
          : enumOf(GoalDistance.values, r.distance!, (v) => v.name),
      targetSeconds: r.targetS,
      targetDate: r.targetDate == null ? null : DateTime.parse(r.targetDate!),
      runDays: daysOfMask(r.runDays),
      maxSessionSeconds: r.maxSessionS,
      weeklyCapSeconds: r.weeklyCapS,
      createdAt: timeOf(r.createdAtUs),
      hardSessionEnabled: r.hardSession,
      currentWeeklySeconds: r.currentWeeklyS,
      canRun30: enumOf(ContinuousRun30.values, r.canRun30, (v) => v.name),
    );
  });

  @override
  Future<void> save(TrainingGoal goal) => guarded(() async {
    checkGoalForStorage(goal);
    final date = goal.targetDate;
    await _db
        .into(_db.goals)
        .insertOnConflictUpdate(
          d.GoalsCompanion.insert(
            id: const Value(1),
            type: goal.type.name,
            distance: Value(goal.distance?.name),
            targetS: Value(goal.targetSeconds),
            targetDate: Value(date == null ? null : isoDay(calendarDay(date))),
            runDays: maskOfDays(goal.runDays),
            maxSessionS: goal.maxSessionSeconds,
            weeklyCapS: goal.weeklyCapSeconds,
            currentWeeklyS: Value(goal.currentWeeklySeconds),
            canRun30: goal.canRun30.name,
            hardSession: goal.hardSessionEnabled,
            createdAtUs: usOf(goal.createdAt),
          ),
        );
  });

  @override
  Future<void> delete() => guarded(() async {
    final n = await _db.delete(_db.goals).go();
    if (n == 0) throw const StorageException(StorageFailure.notFound);
  });
}

/// Wochentage 1..7 als Bitmaske (Bit 0 = Montag).
int maskOfDays(Set<int> days) => days.fold(0, (m, day) => m | (1 << (day - 1)));

/// Gegenstück zu [maskOfDays].
Set<int> daysOfMask(int mask) => {
  for (var day = 1; day <= 7; day++)
    if (mask & (1 << (day - 1)) != 0) day,
};
