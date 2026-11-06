import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Nur anhängen und lesen. Es gibt hier absichtlich kein UPDATE und kein
/// DELETE; die Trigger im Schema sind die zweite Linie (ADR-0004 Punkt 1).
class DriftRawDataStore implements RawDataStore {
  DriftRawDataStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<void> append(int runId, RawBatch batch) => guarded(() async {
    validateRawBatch(batch);
    await _db.transaction(() async {
      await requireRun(_db, runId);
      await _db.batch((b) {
        for (final p in batch.positions) {
          b.insert(
            _db.rawPositions,
            d.RawPositionsCompanion.insert(
              runId: runId,
              timeUs: usOf(p.time),
              source: p.source,
              state: p.state.name,
              latitudeDeg: Value(p.latitude),
              longitudeDeg: Value(p.longitude),
              accuracyM: Value(p.accuracyMeters),
            ),
          );
        }
        for (final h in batch.heartRates) {
          b.insert(
            _db.rawHeartRates,
            d.RawHeartRatesCompanion.insert(
              runId: runId,
              timeUs: usOf(h.time),
              source: h.source,
              state: h.state.name,
              bpm: Value(h.bpm),
              contact: h.contact.name,
            ),
          );
        }
        for (final a in batch.altitudes) {
          b.insert(
            _db.rawAltitudes,
            d.RawAltitudesCompanion.insert(
              runId: runId,
              timeUs: usOf(a.time),
              source: a.source,
              state: a.state.name,
              altitudeM: Value(a.meters),
              verticalAccuracyM: Value(a.verticalAccuracyMeters),
            ),
          );
        }
        for (final s in batch.steps) {
          b.insert(
            _db.rawSteps,
            d.RawStepsCompanion.insert(
              runId: runId,
              timeUs: usOf(s.time),
              source: s.source,
              state: s.state.name,
              stepCount: Value(s.count),
            ),
          );
        }
        for (final u in batch.unavailable) {
          final time = usOf(u.time);
          final state = MeasurementState.unavailable.name;
          switch (u.channel) {
            case RawChannel.position:
              b.insert(
                _db.rawPositions,
                d.RawPositionsCompanion.insert(
                  runId: runId,
                  timeUs: time,
                  source: u.source,
                  state: state,
                ),
              );
            case RawChannel.heartRate:
              b.insert(
                _db.rawHeartRates,
                d.RawHeartRatesCompanion.insert(
                  runId: runId,
                  timeUs: time,
                  source: u.source,
                  state: state,
                  contact: SensorContact.unsupported.name,
                ),
              );
            case RawChannel.altitude:
              b.insert(
                _db.rawAltitudes,
                d.RawAltitudesCompanion.insert(
                  runId: runId,
                  timeUs: time,
                  source: u.source,
                  state: state,
                ),
              );
            case RawChannel.steps:
              b.insert(
                _db.rawSteps,
                d.RawStepsCompanion.insert(
                  runId: runId,
                  timeUs: time,
                  source: u.source,
                  state: state,
                ),
              );
          }
        }
      });
    });
  });

  @override
  Future<StoredRawData> read(int runId) => guarded(() async {
    final unavailable = <StoredRaw<RawUnavailable>>[];
    MeasurementState stateOf(String s) =>
        enumOf(MeasurementState.values, s, (v) => v.name);
    void gap(RawChannel c, int id, int us, String source) => unavailable.add(
      StoredRaw(
        id,
        RawUnavailable(channel: c, time: timeOf(us), source: source),
      ),
    );

    final positions = <StoredRaw<RawPosition>>[];
    for (final r
        in await (_db.select(_db.rawPositions)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.timeUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get()) {
      if (r.latitudeDeg == null || r.longitudeDeg == null) {
        gap(RawChannel.position, r.id, r.timeUs, r.source);
        continue;
      }
      positions.add(
        StoredRaw(
          r.id,
          RawPosition(
            time: timeOf(r.timeUs),
            source: r.source,
            latitude: r.latitudeDeg!,
            longitude: r.longitudeDeg!,
            accuracyMeters: r.accuracyM,
            state: stateOf(r.state),
          ),
        ),
      );
    }
    final heartRates = <StoredRaw<RawHeartRate>>[];
    for (final r
        in await (_db.select(_db.rawHeartRates)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.timeUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get()) {
      if (r.bpm == null) {
        gap(RawChannel.heartRate, r.id, r.timeUs, r.source);
        continue;
      }
      heartRates.add(
        StoredRaw(
          r.id,
          RawHeartRate(
            time: timeOf(r.timeUs),
            source: r.source,
            bpm: r.bpm!,
            contact: enumOf(SensorContact.values, r.contact, (v) => v.name),
            state: stateOf(r.state),
          ),
        ),
      );
    }
    final altitudes = <StoredRaw<RawAltitude>>[];
    for (final r
        in await (_db.select(_db.rawAltitudes)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.timeUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get()) {
      if (r.altitudeM == null) {
        gap(RawChannel.altitude, r.id, r.timeUs, r.source);
        continue;
      }
      altitudes.add(
        StoredRaw(
          r.id,
          RawAltitude(
            time: timeOf(r.timeUs),
            source: r.source,
            meters: r.altitudeM!,
            verticalAccuracyMeters: r.verticalAccuracyM,
            state: stateOf(r.state),
          ),
        ),
      );
    }
    final steps = <StoredRaw<RawSteps>>[];
    for (final r
        in await (_db.select(_db.rawSteps)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.timeUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get()) {
      if (r.stepCount == null) {
        gap(RawChannel.steps, r.id, r.timeUs, r.source);
        continue;
      }
      steps.add(
        StoredRaw(
          r.id,
          RawSteps(
            time: timeOf(r.timeUs),
            source: r.source,
            count: r.stepCount!,
            state: stateOf(r.state),
          ),
        ),
      );
    }
    unavailable.sort((a, b) {
      final t = a.value.time.compareTo(b.value.time);
      if (t != 0) return t;
      final c = a.value.channel.index.compareTo(b.value.channel.index);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return StoredRawData(
      positions: positions,
      heartRates: heartRates,
      altitudes: altitudes,
      steps: steps,
      unavailable: unavailable,
    );
  });
}
