import '../ports/storage.dart';
import '../ports/storage_plan.dart';
import '../src/goals/training_goal.dart';
import '../src/plan/plan_unit.dart';
import '../src/plan/weekly_time.dart' show planDay;
import 'fake_storage_data.dart';

class FakePlanRepository implements PlanRepository {
  FakePlanRepository(this._d);
  final FakeStorageData _d;

  PlanUnit _read(int id) {
    final v = _d.planVersions[_d.planUnitPlan[id]]!;
    return _d.planUnits[id]!.copyWith(
      method: v.version.method,
      methodVersion: v.version.methodVersion,
    );
  }

  List<PlanUnit> _sorted(Iterable<int> ids) {
    final l = ids.toList()
      ..sort((a, b) {
        final c = _d.planUnits[a]!.day.compareTo(_d.planUnits[b]!.day);
        return c != 0 ? c : a.compareTo(b);
      });
    return [for (final id in l) _read(id)];
  }

  @override
  Future<TrainingGoal?> currentGoal() async => _d.goal;

  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) async {
    final a = planDay(from), b = planDay(to);
    return _sorted([
      for (final e in _d.planUnits.entries)
        if (!e.value.day.isBefore(a) && !e.value.day.isAfter(b)) e.key,
    ]);
  }

  @override
  Future<PlanUnit?> unitOn(DateTime day) async {
    final l = await unitsBetween(day, day);
    return l.isEmpty ? null : l.first;
  }

  @override
  Future<List<PlanVersionRecord>> history() async =>
      (_d.planVersions.values.toList()..sort((a, b) => a.id.compareTo(b.id)));

  @override
  Future<void> assignRun(int unitId, int? runId) async {
    final u = _d.planUnits[unitId];
    if (u == null || (runId != null && !_d.runs.containsKey(runId))) {
      throw const StorageException(StorageFailure.notFound);
    }
    _d.planUnits[unitId] = runId == null
        ? u.copyWith(clearRun: true)
        : u.copyWith(runId: runId);
  }

  @override
  Future<void> confirmMove(
    int unitId,
    DateTime newDay, {
    required DateTime today,
  }) async {
    final u = _d.planUnits[unitId];
    if (u == null) throw const StorageException(StorageFailure.notFound);
    final day = planDay(newDay);
    final taken = _d.planUnits.entries.any(
      (e) => e.key != unitId && e.value.day == day,
    );
    if (u.runId != null || taken || day.isBefore(planDay(today))) {
      throw const StorageException(StorageFailure.rejected);
    }
    _d.planUnits[unitId] = u.copyWith(
      day: day,
      weekIndex: movedWeekIndex(u, day),
      pinned: true,
    );
  }

  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft) async {
    if (_d.goal == null) throw const StorageException(StorageFailure.notFound);
    checkPlanDraftForStorage(draft);
    // Alles in dieser Methode ist ab hier ohne Fehlerquelle; die Prüfung
    // steht davor, damit der alte Plan bei Ablehnung unverändert bleibt.
    final record = PlanVersionRecord(
      id: _d.nextPlanId++,
      goalId: 1,
      createdAt: draft.createdAt,
      validFrom: draft.validFrom,
      trigger: draft.trigger,
      reason: draft.reason,
      version: draft.version,
      inputsJson: draft.inputsJson,
      summaryJson: draft.summaryJson,
    );
    _d.planVersions[record.id] = record;
    for (final id in _d.planUnits.keys.toList()) {
      final u = _d.planUnits[id]!;
      if (u.runId == null && !u.day.isBefore(draft.validFrom)) {
        _d.planUnits.remove(id);
        _d.planUnitPlan.remove(id);
      }
    }
    for (final u in draft.units) {
      final id = _d.nextPlanUnitId++;
      _d.planUnits[id] = u.copyWith(id: id, day: planDay(u.day));
      _d.planUnitPlan[id] = record.id;
    }
    return record;
  }
}
