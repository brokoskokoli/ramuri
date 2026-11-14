import 'package:drift/drift.dart';

import '../health/health_connect_port.dart';
import 'access_support.dart';
import 'app_database.dart' as d;

/// Speicher der aus Health Connect importierten Daten (WP32 Teil B, FR-0200,
/// SEC-0001 bis SEC-0007). Je Datenart ([HealthDataKind]) getrennt: schreiben
/// (Upsert), lesen nach Zeitraum, löschen. Die Health-Connect-ID ([HealthRecord.id])
/// ist je Tabelle eindeutig: derselbe Datensatz wird überschrieben, nie doppelt
/// gespeichert; in Health Connect gelöschte Einträge bleiben hier stehen, bis der
/// Nutzer sie löscht (kein Abgleich). Das Löschen berührt nie
/// `manual_trainings` (übernommene Trainings, Nachtrag nach FR-0199).
///
/// Gelesene Sätze haben die Form des Ports: Einzelwerte tragen die Zeit in
/// `start` und `end` (gleich). Keine Werte in Fehlern oder Logs.
class DriftHealthStore {
  DriftHealthStore(this._db);
  final d.AppDatabase _db;

  static const _valueKinds = {
    HealthDataKind.hrvRmssd,
    HealthDataKind.restingHeartRate,
    HealthDataKind.vo2Max,
  };

  static int _us(DateTime t) => t.toUtc().microsecondsSinceEpoch;
  static DateTime _t(int us) =>
      DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);

  static void _require(
    Iterable<HealthRecord> records,
    bool Function(HealthDataKind) ok,
  ) {
    for (final r in records) {
      if (!ok(r.kind)) throw ArgumentError.value(r.kind.key, 'kind');
    }
  }

  /// Schlafsitzungen schreiben ([HealthDataKind.sleep]); die Phasen einer
  /// schon bekannten Sitzung werden ersetzt.
  Future<void> upsertSleep(List<HealthRecord> records) {
    _require(records, (k) => k == HealthDataKind.sleep);
    return guarded(
      () => _db.transaction(() async {
        final t = _db.healthSleepSessions;
        for (final r in records) {
          final row = d.HealthSleepSessionsCompanion.insert(
            hcId: r.id,
            origin: r.origin,
            startUs: _us(r.start),
            endUs: _us(r.end),
            offsetS: Value(r.offsetSeconds),
          );
          await _db
              .into(t)
              .insert(row, onConflict: DoUpdate((_) => row, target: [t.hcId]));
          final id =
              await (_db.selectOnly(t)
                    ..addColumns([t.id])
                    ..where(t.hcId.equals(r.id)))
                  .map((x) => x.read(t.id)!)
                  .getSingle();
          await (_db.delete(
            _db.healthSleepStages,
          )..where((s) => s.sessionId.equals(id))).go();
          await _db.batch((b) {
            b.insertAll(_db.healthSleepStages, [
              for (final s in r.stages)
                d.HealthSleepStagesCompanion.insert(
                  sessionId: id,
                  startUs: _us(s.start),
                  endUs: _us(s.end),
                  stage: s.stage,
                ),
            ]);
          });
        }
      }),
    );
  }

  /// Einzelwerte schreiben (HRV, Ruhepuls, VO₂max; [HealthRecord.value] und
  /// [HealthRecord.unit] sind Pflicht).
  Future<void> upsertValues(List<HealthRecord> records) {
    _require(records, _valueKinds.contains);
    for (final r in records) {
      if (r.value == null || r.unit == null) {
        throw ArgumentError.value(r.kind.key, 'value');
      }
    }
    return guarded(
      () => _db.transaction(() async {
        final t = _db.healthValues;
        for (final r in records) {
          final row = d.HealthValuesCompanion.insert(
            hcId: r.id,
            origin: r.origin,
            kind: r.kind.key,
            timeUs: _us(r.start),
            offsetS: Value(r.offsetSeconds),
            value: r.value!,
            unit: r.unit!,
          );
          await _db
              .into(t)
              .insert(row, onConflict: DoUpdate((_) => row, target: [t.hcId]));
        }
      }),
    );
  }

  /// Trainingseinheiten schreiben ([HealthRecord.exerciseType] ist Pflicht).
  /// Schon gespeicherte Pulswerte einer bekannten Einheit bleiben.
  Future<void> upsertExercises(List<HealthRecord> records) {
    _require(records, (k) => k == HealthDataKind.exercise);
    for (final r in records) {
      if (r.exerciseType == null) throw ArgumentError.value('exercise', 'type');
    }
    return guarded(
      () => _db.transaction(() async {
        final t = _db.healthExercises;
        for (final r in records) {
          final row = d.HealthExercisesCompanion.insert(
            hcId: r.id,
            origin: r.origin,
            exerciseType: r.exerciseType!,
            startUs: _us(r.start),
            endUs: _us(r.end),
            offsetS: Value(r.offsetSeconds),
          );
          await _db
              .into(t)
              .insert(row, onConflict: DoUpdate((_) => row, target: [t.hcId]));
        }
      }),
    );
  }

  /// Ersetzt die Pulswerte der Einheit [exerciseHcId]. Liefert `false` und
  /// speichert nichts, wenn die Einheit nicht gespeichert ist.
  Future<bool> replaceExerciseHeartRate(
    String exerciseHcId,
    List<HealthHeartRateSample> samples,
  ) => guarded(
    () => _db.transaction(() async {
      final id = await _exerciseId(exerciseHcId);
      if (id == null) return false;
      await (_db.delete(
        _db.healthExerciseHeartRates,
      )..where((s) => s.exerciseId.equals(id))).go();
      await _db.batch((b) {
        b.insertAll(_db.healthExerciseHeartRates, [
          for (final s in samples)
            d.HealthExerciseHeartRatesCompanion.insert(
              exerciseId: id,
              timeUs: _us(s.time),
              bpm: s.beatsPerMinute,
            ),
        ]);
      });
      return true;
    }),
  );

  Future<int?> _exerciseId(String hcId) async {
    final t = _db.healthExercises;
    return (_db.selectOnly(t)
          ..addColumns([t.id])
          ..where(t.hcId.equals(hcId)))
        .map((x) => x.read(t.id)!)
        .getSingleOrNull();
  }

  /// Schlafsitzungen, die das Fenster [from, to) berühren, nach Beginn, mit Phasen.
  Future<List<HealthRecord>> sleepSessions(DateTime from, DateTime to) =>
      guarded(() async {
        final s = _db.healthSleepSessions;
        final rows =
            await (_db.select(s)
                  ..where(
                    (r) =>
                        r.startUs.isSmallerThanValue(_us(to)) &
                        r.endUs.isBiggerThanValue(_us(from)),
                  )
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.startUs),
                    (r) => OrderingTerm.asc(r.id),
                  ]))
                .get();
        final out = <HealthRecord>[];
        for (final r in rows) {
          final stages =
              await (_db.select(_db.healthSleepStages)
                    ..where((x) => x.sessionId.equals(r.id))
                    ..orderBy([
                      (x) => OrderingTerm.asc(x.startUs),
                      (x) => OrderingTerm.asc(x.id),
                    ]))
                  .get();
          out.add(
            HealthRecord(
              kind: HealthDataKind.sleep,
              id: r.hcId,
              origin: r.origin,
              start: _t(r.startUs),
              end: _t(r.endUs),
              offsetSeconds: r.offsetS,
              stages: [
                for (final x in stages)
                  HealthSleepStage(_t(x.startUs), _t(x.endUs), x.stage),
              ],
            ),
          );
        }
        return out;
      });

  /// Einzelwerte einer Art mit Zeit im Fenster [from, to), nach Zeit.
  Future<List<HealthRecord>> values(
    HealthDataKind kind,
    DateTime from,
    DateTime to,
  ) {
    if (!_valueKinds.contains(kind)) {
      throw ArgumentError.value(kind.key, 'kind');
    }
    return guarded(() async {
      final rows =
          await (_db.select(_db.healthValues)
                ..where(
                  (r) =>
                      r.kind.equals(kind.key) &
                      r.timeUs.isBiggerOrEqualValue(_us(from)) &
                      r.timeUs.isSmallerThanValue(_us(to)),
                )
                ..orderBy([
                  (r) => OrderingTerm.asc(r.timeUs),
                  (r) => OrderingTerm.asc(r.id),
                ]))
              .get();
      return [
        for (final r in rows)
          HealthRecord(
            kind: kind,
            id: r.hcId,
            origin: r.origin,
            start: _t(r.timeUs),
            end: _t(r.timeUs),
            offsetSeconds: r.offsetS,
            value: r.value,
            unit: r.unit,
          ),
      ];
    });
  }

  /// Trainingseinheiten, die das Fenster [from, to) berühren, nach Beginn
  /// (ohne Pulswerte, siehe [exerciseHeartRate]).
  Future<List<HealthRecord>> exercises(DateTime from, DateTime to) =>
      guarded(() async {
        final rows =
            await (_db.select(_db.healthExercises)
                  ..where(
                    (r) =>
                        r.startUs.isSmallerThanValue(_us(to)) &
                        r.endUs.isBiggerThanValue(_us(from)),
                  )
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.startUs),
                    (r) => OrderingTerm.asc(r.id),
                  ]))
                .get();
        return [
          for (final r in rows)
            HealthRecord(
              kind: HealthDataKind.exercise,
              id: r.hcId,
              origin: r.origin,
              start: _t(r.startUs),
              end: _t(r.endUs),
              offsetSeconds: r.offsetS,
              exerciseType: r.exerciseType,
            ),
        ];
      });

  /// Pulswerte der Einheit [exerciseHcId] nach Zeit (leer, wenn unbekannt).
  Future<List<HealthHeartRateSample>> exerciseHeartRate(String exerciseHcId) =>
      guarded(() async {
        final id = await _exerciseId(exerciseHcId);
        if (id == null) return const [];
        final rows =
            await (_db.select(_db.healthExerciseHeartRates)
                  ..where((r) => r.exerciseId.equals(id))
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.timeUs),
                    (r) => OrderingTerm.asc(r.id),
                  ]))
                .get();
        return [
          for (final r in rows) HealthHeartRateSample(_t(r.timeUs), r.bpm),
        ];
      });

  /// Anzahl der gespeicherten Sätze der Art (Pulsverlauf: Pulswerte,
  /// sonst Sitzungen, Einzelwerte, Einheiten).
  Future<int> count(HealthDataKind kind) => guarded(() async {
    final table = switch (kind) {
      HealthDataKind.sleep => 'health_sleep_sessions',
      HealthDataKind.exercise => 'health_exercises',
      HealthDataKind.heartRate => 'health_exercise_heart_rates',
      _ => 'health_values',
    };
    final where = _valueKinds.contains(kind)
        ? " WHERE kind = '${kind.key}'"
        : '';
    final r = await _db
        .customSelect('SELECT COUNT(*) AS n FROM $table$where')
        .getSingle();
    return r.read<int>('n');
  });

  /// Löscht alle importierten Daten einer Art und nur dieser Art
  /// (SEC-0007). Schlaf: Sitzungen und Phasen. Trainingseinheiten: Einheiten
  /// und deren Pulswerte. Pulsverlauf: nur die Pulswerte (die Einheiten
  /// bleiben). `manual_trainings` bleibt immer unberührt.
  Future<void> deleteKind(HealthDataKind kind) => guarded(
    () => _db.transaction(() async {
      // Kinder ausdrücklich zuerst (ohne Verlass auf die Kaskade).
      switch (kind) {
        case HealthDataKind.sleep:
          await _db.delete(_db.healthSleepStages).go();
          await _db.delete(_db.healthSleepSessions).go();
        case HealthDataKind.exercise:
          await _db.delete(_db.healthExerciseHeartRates).go();
          await _db.delete(_db.healthExercises).go();
        case HealthDataKind.heartRate:
          await _db.delete(_db.healthExerciseHeartRates).go();
        case HealthDataKind.hrvRmssd:
        case HealthDataKind.restingHeartRate:
        case HealthDataKind.vo2Max:
          await (_db.delete(
            _db.healthValues,
          )..where((r) => r.kind.equals(kind.key))).go();
      }
    }),
  );
}
