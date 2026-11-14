import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Angaben zum Lauf samt sRPE (FR-0038, FR-0095). Die Grenzen prüfen das
/// Domänenmodell und die CHECK-Bedingungen der Tabelle.
class DriftRunSubjectiveStore implements RunSubjectiveStore {
  DriftRunSubjectiveStore(this._db);
  final d.AppDatabase _db;

  static StoredRunSubjective _fromRow(d.RunFeedbackRow r) {
    final points = r.srpePoints;
    return StoredRunSubjective(
      subjective: RunSubjective(
        rpe: r.rpe,
        wellbeing: r.wellbeing,
        complaints: r.complaints,
        warningAnswer: r.warningAnswer == null
            ? null
            : enumOf(WarningAnswer.values, r.warningAnswer!, (v) => v.name),
        note: r.note,
      ),
      srpe: points == null
          ? null
          : SrpeLoad.restore(
              points: points,
              duration: durationOf(r.srpeDurationS!),
              rpe: r.rpe!,
              method: r.srpeMethod!,
              version: r.srpeMethodVersion!,
            ),
    );
  }

  @override
  Future<StoredRunSubjective?> read(int runId) => guarded(() async {
    final r = await (_db.select(
      _db.runFeedback,
    )..where((t) => t.runId.equals(runId))).getSingleOrNull();
    return r == null ? null : _fromRow(r);
  });

  @override
  Future<Map<int, StoredRunSubjective>> readAll() => guarded(() async {
    final rows = await _db.select(_db.runFeedback).get();
    return {for (final r in rows) r.runId: _fromRow(r)};
  });

  @override
  Future<void> save(int runId, RunSubjective subjective, {SrpeLoad? srpe}) =>
      guarded(() async {
        await _db.transaction(() async {
          await requireRun(_db, runId);
          if (srpe != null && srpe.rpe != subjective.rpe) {
            throw const StorageException(StorageFailure.rejected);
          }
          if (subjective.isEmpty) {
            await (_db.delete(
              _db.runFeedback,
            )..where((t) => t.runId.equals(runId))).go();
            return;
          }
          await _db
              .into(_db.runFeedback)
              .insertOnConflictUpdate(
                d.RunFeedbackCompanion(
                  runId: Value(runId),
                  rpe: Value(subjective.rpe),
                  wellbeing: Value(subjective.wellbeing),
                  complaints: Value(subjective.complaints),
                  warningAnswer: Value(subjective.warningAnswer?.name),
                  note: Value(subjective.note),
                  srpePoints: Value(srpe?.points),
                  srpeDurationS: Value(secondsOfOrNull(srpe?.duration)),
                  srpeMethod: Value(srpe?.method),
                  srpeMethodVersion: Value(srpe?.version),
                ),
              );
        });
      });

  @override
  Future<bool> setSrpe(
    int runId,
    SrpeLoad? srpe, {
    required int? expectedRpe,
  }) => guarded(() async {
    if (srpe != null && srpe.rpe != expectedRpe) {
      throw const StorageException(StorageFailure.rejected);
    }
    // Eine einzige UPDATE-Anweisung: Bedingung und Schreiben sind atomar, die
    // übrigen Spalten werden nicht angefasst.
    final n =
        await (_db.update(_db.runFeedback)
              ..where((t) => t.runId.equals(runId))
              ..where(
                (t) => expectedRpe == null
                    ? t.rpe.isNull()
                    : t.rpe.equals(expectedRpe),
              ))
            .write(
              d.RunFeedbackCompanion(
                srpePoints: Value(srpe?.points),
                srpeDurationS: Value(secondsOfOrNull(srpe?.duration)),
                srpeMethod: Value(srpe?.method),
                srpeMethodVersion: Value(srpe?.version),
              ),
            );
    return n > 0;
  });
}

/// Nachgetragene Trainings (FR-0199) in eigener Tabelle.
class DriftManualTrainingStore implements ManualTrainingStore {
  DriftManualTrainingStore(this._db);
  final d.AppDatabase _db;

  static StoredManualTraining _fromRow(d.ManualTrainingRow r) =>
      StoredManualTraining(
        id: r.id,
        training: ManualTraining(
          day: DateTime.parse('${r.day}T00:00:00Z'),
          kind: enumOf(ManualTrainingKind.values, r.kind, (v) => v.name),
          duration: Duration(seconds: r.durationS),
          rpe: r.rpe,
          hcId: r.hcId,
        ),
      );

  d.ManualTrainingsCompanion _companion(ManualTraining t) =>
      d.ManualTrainingsCompanion(
        day: Value(t.isoDay),
        kind: Value(t.kind.name),
        durationS: Value(t.duration.inSeconds),
        rpe: Value(t.rpe),
        hcId: Value(t.hcId),
      );

  @override
  Future<StoredManualTraining> add(ManualTraining training) =>
      guarded(() async {
        final id = await _db
            .into(_db.manualTrainings)
            .insert(_companion(training));
        return StoredManualTraining(id: id, training: training);
      });

  @override
  Future<void> update(int id, ManualTraining training) => guarded(() async {
    final n = await (_db.update(
      _db.manualTrainings,
    )..where((t) => t.id.equals(id))).write(_companion(training));
    if (n == 0) throw const StorageException(StorageFailure.notFound);
  });

  @override
  Future<void> delete(int id) => guarded(() async {
    final n = await (_db.delete(
      _db.manualTrainings,
    )..where((t) => t.id.equals(id))).go();
    if (n == 0) throw const StorageException(StorageFailure.notFound);
  });

  @override
  Future<StoredManualTraining?> get(int id) => guarded(() async {
    final r = await (_db.select(
      _db.manualTrainings,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _fromRow(r);
  });

  @override
  Future<List<StoredManualTraining>> list() => guarded(() async {
    final rows =
        await (_db.select(_db.manualTrainings)..orderBy([
              (t) => OrderingTerm.desc(t.day),
              (t) => OrderingTerm.desc(t.id),
            ]))
            .get();
    return [for (final r in rows) _fromRow(r)];
  });
}
