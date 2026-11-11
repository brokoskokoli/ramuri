import 'package:core/core.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, ComparableExpr, OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

StoredRun _run(d.Run r) => StoredRun(
  id: r.id,
  state: enumOf(RunState.values, r.state, (v) => v.name),
  startedAt: timeOf(r.startedAtUs),
  endedAt: timeOfOrNull(r.endedAtUs),
  endedUtcOffset: r.endedUtcOffsetS == null
      ? null
      : Duration(seconds: r.endedUtcOffsetS!),
);

class DriftRunStore implements RunStore {
  DriftRunStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<StoredRun> create({required DateTime startedAt}) => guarded(() async {
    final id = await _db
        .into(_db.runs)
        .insert(
          d.RunsCompanion.insert(
            state: RunState.active.name,
            startedAtUs: usOf(startedAt),
          ),
        );
    return StoredRun(
      id: id,
      state: RunState.active,
      startedAt: timeOf(usOf(startedAt)),
    );
  });

  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) => guarded(() async {
    requireRunEnd(state, endedAt, endedUtcOffset);
    final n = await (_db.update(_db.runs)..where((t) => t.id.equals(runId)))
        .write(
          d.RunsCompanion(
            state: Value(state.name),
            endedAtUs: Value(usOfOrNull(endedAt)),
            endedUtcOffsetS: Value(endedUtcOffset?.inSeconds),
          ),
        );
    if (n == 0) throw const StorageException(StorageFailure.notFound);
  });

  @override
  Future<StoredRun?> get(int runId) => guarded(() async {
    final r = await (_db.select(
      _db.runs,
    )..where((t) => t.id.equals(runId))).getSingleOrNull();
    return r == null ? null : _run(r);
  });

  @override
  Future<List<StoredRun>> list() => guarded(() async {
    final rows =
        await (_db.select(_db.runs)..orderBy([
              (t) => OrderingTerm.desc(t.startedAtUs),
              (t) => OrderingTerm.desc(t.id),
            ]))
            .get();
    return rows.map(_run).toList();
  });

  @override
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to) =>
      guarded(() async {
        final rows =
            await (_db.select(_db.runs)
                  ..where(
                    (t) =>
                        t.state.equals(RunState.finished.name) &
                        t.endedAtUs.isBiggerOrEqualValue(usOf(from)) &
                        t.endedAtUs.isSmallerThanValue(usOf(to)),
                  )
                  ..orderBy([
                    (t) => OrderingTerm.asc(t.endedAtUs),
                    (t) => OrderingTerm.asc(t.id),
                  ]))
                .get();
        return rows.map(_run).toList();
      });

  @override
  Future<List<StoredRun>> unfinished() => guarded(() async {
    final rows =
        await (_db.select(_db.runs)
              ..where((t) => t.state.equals(RunState.finished.name).not())
              ..orderBy([
                (t) => OrderingTerm.asc(t.startedAtUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows.map(_run).toList();
  });
}

class DriftRunMarkerStore implements RunMarkerStore {
  DriftRunMarkerStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<void> addLap(int runId, StoredLap lap) => guarded(
    () => _db.transaction(() async {
      await requireRun(_db, runId);
      final dup =
          await (_db.select(_db.laps)..where(
                (t) => t.runId.equals(runId) & t.lapIndex.equals(lap.index),
              ))
              .getSingleOrNull();
      if (dup != null) throw const StorageException(StorageFailure.rejected);
      await _db
          .into(_db.laps)
          .insert(
            d.LapsCompanion.insert(
              runId: runId,
              lapIndex: lap.index,
              markedAtUs: usOf(lap.markedAt),
              lapTimeS: secondsOf(lap.lapTime),
            ),
          );
    }),
  );

  @override
  Future<List<StoredLap>> laps(int runId) => guarded(() async {
    final rows =
        await (_db.select(_db.laps)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([(t) => OrderingTerm.asc(t.lapIndex)]))
            .get();
    return [
      for (final r in rows)
        StoredLap(
          index: r.lapIndex,
          markedAt: timeOf(r.markedAtUs),
          lapTime: durationOf(r.lapTimeS),
        ),
    ];
  });

  @override
  Future<int> openGap(int runId, RunGapKind kind, DateTime start) => guarded(
    () => _db.transaction(() async {
      await requireRun(_db, runId);
      return _db
          .into(_db.runGaps)
          .insert(
            d.RunGapsCompanion.insert(
              runId: runId,
              kind: snake(kind.name),
              startUs: usOf(start),
            ),
          );
    }),
  );

  @override
  Future<void> closeGap(int gapId, DateTime end) => guarded(
    () => _db.transaction(() async {
      final gap = await (_db.select(
        _db.runGaps,
      )..where((t) => t.id.equals(gapId))).getSingleOrNull();
      if (gap == null) throw const StorageException(StorageFailure.notFound);
      if (gap.endUs != null) {
        throw const StorageException(StorageFailure.rejected);
      }
      await (_db.update(_db.runGaps)..where((t) => t.id.equals(gapId))).write(
        d.RunGapsCompanion(endUs: Value(usOf(end))),
      );
    }),
  );

  @override
  Future<List<StoredGap>> gaps(int runId) => guarded(() async {
    final rows =
        await (_db.select(_db.runGaps)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.startUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return [
      for (final r in rows)
        StoredGap(
          id: r.id,
          kind: enumOf(RunGapKind.values, r.kind, (v) => snake(v.name)),
          start: timeOf(r.startUs),
          end: timeOfOrNull(r.endUs),
        ),
    ];
  });
}
