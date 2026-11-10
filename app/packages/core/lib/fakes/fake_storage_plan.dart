import '../ports/storage.dart';
import '../ports/storage_plan.dart';
import '../src/goals/training_goal.dart';
import '../src/plan/plan_move.dart' show planMovedFixed;
import '../src/plan/plan_replace.dart' show planReplacedFixed;
import '../src/plan/plan_unit.dart';
import '../src/plan/weekly_time.dart' show planDay;
import 'fake_storage_data.dart';

class FakePlanRepository implements PlanRepository {
  FakePlanRepository(this._d);
  final FakeStorageData _d;

  PlanUnit _read(int id) {
    final v = _d.planVersions[_d.planUnitPlan[id]]!;
    final u = _d.planUnits[id]!;
    final (method, methodVersion) = v.version.unitMethod(
      walkRun: u.kind == PlanUnitKind.walkRun,
    );
    return u.copyWith(method: method, methodVersion: methodVersion);
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
    if (u.runId != null ||
        taken ||
        day.isBefore(planDay(today)) ||
        u.day.isBefore(planDay(today))) {
      throw const StorageException(StorageFailure.rejected);
    }
    _d.planUnits[unitId] = u.copyWith(
      day: day,
      weekIndex: movedWeekIndex(u, day),
      pinned: true,
      fixed: planMovedFixed(u, day),
    );
  }

  @override
  Future<void> replaceUnit(
    int unitId,
    PlanUnit replacement, {
    required DateTime today,
  }) async {
    final u = _d.planUnits[unitId];
    if (u == null) throw const StorageException(StorageFailure.notFound);
    if (!planReplaceAllowed(u, replacement, today)) {
      throw const StorageException(StorageFailure.rejected);
    }
    _d.planUnits[unitId] = PlanUnit(
      id: unitId,
      day: u.day,
      kind: replacement.kind,
      phase: u.phase,
      weekIndex: u.weekIndex,
      minutes: replacement.minutes,
      segments: replacement.segments,
      pinned: true,
      fixed: planReplacedFixed(u, replacement.kind),
    );
  }

  @override
  Future<void> setRestDay(
    PlanUnit rest, {
    required DateTime today,
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) async {
    if (_d.planVersions.isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    final day = planDay(rest.day);
    final onDay = _d.planUnits.entries
        .where((e) => e.value.day == day)
        .firstOrNull;
    if (!planRestDayAllowed(
      rest,
      onDay?.value,
      today,
      moveUnitTo,
      (d) => _d.planUnits.values.any((u) => u.day == d),
      expectedUnitId: expectedUnitId,
    )) {
      throw const StorageException(StorageFailure.rejected);
    }
    if (onDay != null) {
      if (moveUnitTo != null) {
        final to = planDay(moveUnitTo);
        _d.planUnits[onDay.key] = onDay.value.copyWith(
          day: to,
          weekIndex: movedWeekIndex(onDay.value, to),
          pinned: true,
        );
      } else {
        _d.planUnits.remove(onDay.key);
        _d.planUnitPlan.remove(onDay.key);
      }
    }
    final id = _d.nextPlanUnitId++;
    _d.planUnits[id] = PlanUnit(
      id: id,
      day: day,
      kind: PlanUnitKind.rest,
      phase: rest.phase,
      weekIndex: rest.weekIndex,
      minutes: 0,
      segments: const [],
      pinned: true,
      fixed: PlanUnitFixed.day,
    );
    _d.planUnitPlan[id] = _d.planVersions.keys.reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<void> clearRestDay(DateTime day, {required DateTime today}) async {
    final d = planDay(day);
    final hit = _d.planUnits.entries
        .where((e) => e.value.day == d && e.value.isRestDay)
        .firstOrNull;
    if (hit == null) throw const StorageException(StorageFailure.notFound);
    if (d.isBefore(planDay(today))) {
      throw const StorageException(StorageFailure.rejected);
    }
    _d.planUnits.remove(hit.key);
    _d.planUnitPlan.remove(hit.key);
  }

  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft) async {
    if (_d.goal == null) throw const StorageException(StorageFailure.notFound);
    checkPlanDraftForStorage(draft);
    // Hat sich der Plan seit dem Lesen geändert, rechnet der Aufrufer neu.
    final now = await unitsBetween(draft.inputs.anchor, planFarFuture);
    if (planUnitsFingerprint(now) != draft.readState) {
      throw const StorageException(StorageFailure.rejected);
    }
    // Ein Tag, der schon eine Einheit mit Lauf trägt (Lauf kam nach dem Lesen
    // des Dienstes dazu), darf keine zweite bekommen.
    final runDays = {
      for (final u in _d.planUnits.values)
        if (u.runId != null && !u.day.isBefore(draft.validFrom)) u.day,
    };
    if (draft.units.any((u) => runDays.contains(planDay(u.day)))) {
      throw const StorageException(StorageFailure.rejected);
    }
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
