import 'dart:convert';

import 'package:core/core.dart';
import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        ComparableExpr,
        OrderingTerm,
        Value,
        innerJoin;
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'access_support.dart';
import 'app_database.dart' as d;
import 'goal_access.dart';

/// Der gespeicherte Plan (ADR-0010): Fassungen in `plans`, Einheiten in
/// `plan_units`. Geschrieben wird eine Fassung samt Ersatz der offenen
/// künftigen Einheiten in einer Transaktion.
class DriftPlanRepository implements PlanRepository {
  DriftPlanRepository(this._db, {@visibleForTesting this.beforeUnitInsert});
  final d.AppDatabase _db;

  /// Nur für Tests: wird vor dem Einfügen der Einheit mit diesem Index
  /// aufgerufen und kann mitten im Schreiben scheitern.
  final Future<void> Function(int index)? beforeUnitInsert;

  @override
  Future<TrainingGoal?> currentGoal() => DriftGoalStore(_db).goal();

  @override
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      guarded(() async {
        final a = isoDay(planDay(from)), b = isoDay(planDay(to));
        return _units(
          (u, p) =>
              u.day.isBiggerOrEqualValue(a) & u.day.isSmallerOrEqualValue(b),
        );
      });

  @override
  Future<PlanUnit?> unitOn(DateTime day) => guarded(() async {
    final t = isoDay(planDay(day));
    final l = await _units((u, p) => u.day.equals(t));
    return l.isEmpty ? null : l.first;
  });

  Future<List<PlanUnit>> _units(
    dynamic Function(d.PlanUnits u, d.Plans p) where,
  ) async {
    final q =
        _db.select(_db.planUnits).join([
            innerJoin(_db.plans, _db.plans.id.equalsExp(_db.planUnits.planId)),
          ])
          ..where(where(_db.planUnits, _db.plans))
          ..orderBy([
            OrderingTerm.asc(_db.planUnits.day),
            OrderingTerm.asc(_db.planUnits.id),
          ]);
    final rows = await q.get();
    return [
      for (final r in rows)
        _unit(r.readTable(_db.planUnits), r.readTable(_db.plans)),
    ];
  }

  @override
  Future<List<PlanVersionRecord>> history() => guarded(() async {
    final rows = await (_db.select(
      _db.plans,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    return [for (final r in rows) _record(r)];
  });

  @override
  Future<void> assignRun(int unitId, int? runId) => guarded(() async {
    await _db.transaction(() async {
      await _requireUnit(unitId);
      if (runId != null) await requireRun(_db, runId);
      await (_db.update(_db.planUnits)..where((t) => t.id.equals(unitId)))
          .write(d.PlanUnitsCompanion(runId: Value(runId)));
    });
  });

  @override
  Future<void> confirmMove(
    int unitId,
    DateTime newDay, {
    required DateTime today,
  }) => guarded(() async {
    await _db.transaction(() async {
      final row = await _requireUnit(unitId);
      final day = planDay(newDay);
      final text = isoDay(day);
      final taken = await (_db.select(
        _db.planUnits,
      )..where((t) => t.id.isNotValue(unitId) & t.day.equals(text))).get();
      if (row.runId != null ||
          taken.isNotEmpty ||
          day.isBefore(planDay(today)) ||
          _parseDay(row.day).isBefore(planDay(today))) {
        throw const StorageException(StorageFailure.rejected);
      }
      final week = movedWeekIndex(
        PlanUnit(
          day: _parseDay(row.day),
          kind: PlanUnitKind.easy,
          phase: PlanPhase.entry,
          weekIndex: row.week,
          minutes: 0,
          segments: const [],
        ),
        day,
      );
      await (_db.update(
        _db.planUnits,
      )..where((t) => t.id.equals(unitId))).write(
        d.PlanUnitsCompanion(
          day: Value(text),
          week: Value(week),
          pinned: const Value(true),
        ),
      );
    });
  });

  Future<d.PlanUnitRow> _requireUnit(int unitId) async {
    final row = await (_db.select(
      _db.planUnits,
    )..where((t) => t.id.equals(unitId))).getSingleOrNull();
    if (row == null) throw const StorageException(StorageFailure.notFound);
    return row;
  }

  @override
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft) => guarded(
    () async {
      checkPlanDraftForStorage(draft);
      return _db.transaction(() async {
        final goal = await _db.select(_db.goals).getSingleOrNull();
        if (goal == null) {
          throw const StorageException(StorageFailure.notFound);
        }
        final id = await _db
            .into(_db.plans)
            .insert(
              d.PlansCompanion.insert(
                goalId: goal.id,
                createdAtUs: usOf(draft.createdAt),
                validFrom: isoDay(draft.validFrom),
                trigger: draft.trigger.name,
                reason: draft.reason,
                method: draft.version.method,
                methodVersion: draft.version.methodVersion,
                parameterVersion: draft.version.parameterVersion,
                inputs: draft.inputsJson,
                summary: draft.summaryJson,
              ),
            );
        // Kam nach dem Lesen des Dienstes ein Lauf auf eine Einheit, bliebe
        // sie stehen, und ein Entwurfstag wäre doppelt: ablehnen.
        final kept =
            await (_db.select(_db.planUnits)..where(
                  (t) =>
                      t.day.isBiggerOrEqualValue(isoDay(draft.validFrom)) &
                      t.runId.isNotNull(),
                ))
                .get();
        final keptDays = {for (final r in kept) r.day};
        if (draft.units.any((u) => keptDays.contains(isoDay(planDay(u.day))))) {
          throw const StorageException(StorageFailure.rejected);
        }
        // Offen und künftig: ab dem Beginn der Fassung und ohne Lauf. Alles
        // andere bleibt unter seiner alten Fassung (FR-0158, PAR-203).
        await (_db.delete(_db.planUnits)..where(
              (t) =>
                  t.day.isBiggerOrEqualValue(isoDay(draft.validFrom)) &
                  t.runId.isNull(),
            ))
            .go();
        for (var i = 0; i < draft.units.length; i++) {
          await beforeUnitInsert?.call(i);
          final u = draft.units[i];
          await _db
              .into(_db.planUnits)
              .insert(
                d.PlanUnitsCompanion.insert(
                  planId: id,
                  day: isoDay(planDay(u.day)),
                  week: u.weekIndex,
                  phase: u.phase.name,
                  kind: u.kind.name,
                  minutes: u.minutes,
                  structure: jsonEncode(_structure(u.segments)),
                  pinned: u.pinned,
                ),
              );
        }
        final row = await (_db.select(
          _db.plans,
        )..where((t) => t.id.equals(id))).getSingle();
        return _record(row);
      });
    },
  );
}

DateTime _parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

List<Map<String, Object?>> _structure(List<PlanSegment> segments) => [
  for (final s in segments)
    {
      'kind': s.kind.name,
      'minutes': s.minutes,
      if (s.seconds != null) 'seconds': s.seconds,
      if (s.intensity != null)
        'intensity': {
          'rpeMin': s.intensity!.rpeMin,
          'rpeMax': s.intensity!.rpeMax,
          'paceFast': s.intensity!.paceFastSecondsPerKm,
          'paceSlow': s.intensity!.paceSlowSecondsPerKm,
          'basis': s.intensity!.basisCode,
          'hrMin': s.intensity!.hrMinBpm,
          'hrMax': s.intensity!.hrMaxBpm,
          'estimated': s.intensity!.estimated,
          'maxHrEstimated': s.intensity!.maxHrEstimated,
          'paceIsLimit': s.intensity!.paceIsLimit,
        },
    },
];

List<PlanSegment> _segments(String text) {
  final l = jsonDecode(text);
  if (l is! List) throw const StorageException(StorageFailure.failed);
  return [
    for (final e in l)
      () {
        final m = e as Map<String, Object?>;
        final i = m['intensity'] as Map<String, Object?>?;
        return PlanSegment(
          kind: enumOf(
            PlanSegmentKind.values,
            m['kind'] as String,
            (v) => v.name,
          ),
          minutes: m['minutes'] as int,
          seconds: m['seconds'] as int?,
          intensity: i == null
              ? null
              : PlanTargetIntensity(
                  rpeMin: i['rpeMin'] as int?,
                  rpeMax: i['rpeMax'] as int?,
                  paceFastSecondsPerKm: (i['paceFast'] as num?)?.toDouble(),
                  paceSlowSecondsPerKm: (i['paceSlow'] as num?)?.toDouble(),
                  basisCode: i['basis'] as String?,
                  hrMinBpm: i['hrMin'] as int?,
                  hrMaxBpm: i['hrMax'] as int?,
                  estimated: i['estimated'] as bool? ?? false,
                  maxHrEstimated: i['maxHrEstimated'] as bool? ?? false,
                  paceIsLimit: i['paceIsLimit'] as bool? ?? false,
                ),
        );
      }(),
  ];
}

PlanUnit _unit(d.PlanUnitRow u, d.PlanRow p) {
  final kind = enumOf(PlanUnitKind.values, u.kind, (v) => v.name);
  final (method, methodVersion) = PlanVersion(
    method: p.method,
    methodVersion: p.methodVersion,
    parameterVersion: p.parameterVersion,
  ).unitMethod(walkRun: kind == PlanUnitKind.walkRun);
  return PlanUnit(
    id: u.id,
    day: _parseDay(u.day),
    kind: kind,
    phase: enumOf(PlanPhase.values, u.phase, (v) => v.name),
    weekIndex: u.week,
    minutes: u.minutes,
    segments: _segments(u.structure),
    runId: u.runId,
    pinned: u.pinned,
    method: method,
    methodVersion: methodVersion,
  );
}

PlanVersionRecord _record(d.PlanRow r) => PlanVersionRecord(
  id: r.id,
  goalId: r.goalId,
  createdAt: timeOf(r.createdAtUs),
  validFrom: _parseDay(r.validFrom),
  trigger: enumOf(PlanTrigger.values, r.trigger, (v) => v.name),
  reason: r.reason,
  version: PlanVersion(
    method: r.method,
    methodVersion: r.methodVersion,
    parameterVersion: r.parameterVersion,
  ),
  inputsJson: r.inputs,
  summaryJson: r.summary,
);
