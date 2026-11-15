import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Morgenmessungen (FR-0215) und ihre Gurt-RR (K61). Gehören keinem Lauf:
/// kein Fremdschlüssel auf `runs`, nur die Gurt-RR hängt an ihrer Messung.
class DriftMorningStore implements MorningStore {
  DriftMorningStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<int> add(
    MorningMeasurement measurement, {
    List<RrPacket> beltPackets = const [],
    MorningRawSignal? rawSignal,
  }) => guarded(() async {
    checkMorningForStorage(
      measurement,
      beltPackets: beltPackets,
      rawSignal: rawSignal,
    );
    return _db.transaction(() async {
      final id = await _db
          .into(_db.morningMeasurements)
          .insert(
            d.MorningMeasurementsCompanion.insert(
              measuredAtUs: usOf(measurement.measuredAt),
              utcOffsetS: measurement.utcOffset.inSeconds,
              posture: measurement.posture.storageValue,
              deviceManufacturer: measurement.deviceManufacturer,
              deviceModel: measurement.deviceModel,
              method: measurement.method,
              methodVersion: measurement.methodVersion,
              quality: measurement.quality.name,
              restingHrBpm: Value(measurement.roundedRestingHr),
              rmssdMs: Value(measurement.rmssdMs),
              timingNoiseMs: Value(measurement.timingNoiseMs),
              sleepBand: Value(measurement.sleepBand?.code),
              beforeValidation: measurement.beforeValidation,
              outsideWindow: measurement.outsideWindow,
              cameraIbi: encodeCameraIntervals(measurement.cameraIntervalsMs),
              windowStartS: Value(measurement.windowStartS),
              windowEndS: Value(measurement.windowEndS),
              restSkippedAfterS: Value(measurement.restSkippedAfterS),
              unusableReason: Value(measurement.unusableReason?.name),
            ),
          );
      if (rawSignal != null) {
        await _db
            .into(_db.morningRawSignals)
            .insert(
              d.MorningRawSignalsCompanion.insert(
                measurementId: Value(id),
                frameCount: rawSignal.frames.length,
                frames: encodeRawFrames(rawSignal.frames),
                exposureTimeNs: Value(rawSignal.exposureTimeNs),
                iso: Value(rawSignal.iso),
                timestampSource: Value(rawSignal.timestampSource?.code),
                rollingShutterSkewNs: Value(rawSignal.rollingShutterSkewNs),
                torchStrength: Value(rawSignal.torchStrength),
                frameGapCount: rawSignal.frameGapCount,
                frameGapTotalS: rawSignal.frameGapTotalS,
                saturatedFraction: Value(rawSignal.saturatedFraction),
              ),
            );
      }
      await _db.batch((b) {
        for (final p in beltPackets) {
          b.insert(
            _db.morningRrPackets,
            d.MorningRrPacketsCompanion.insert(
              measurementId: id,
              timeUs: usOf(p.time),
              source: p.source,
              rr: encodeRrIntervals(p.intervals),
            ),
          );
        }
      });
      return id;
    });
  });

  @override
  Future<List<StoredMorningMeasurement>> list() => guarded(() async {
    final rows =
        await (_db.select(_db.morningMeasurements)..orderBy([
              (t) => OrderingTerm.asc(t.measuredAtUs),
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return [for (final r in rows) StoredMorningMeasurement(r.id, _read(r))];
  });

  @override
  Future<void> setSleepBand(int measurementId, SleepBand? band) =>
      guarded(() async {
        final n =
            await (_db.update(
              _db.morningMeasurements,
            )..where((t) => t.id.equals(measurementId))).write(
              d.MorningMeasurementsCompanion(sleepBand: Value(band?.code)),
            );
        if (n == 0) throw const StorageException(StorageFailure.notFound);
      });

  @override
  Future<MorningRawSignal?> rawSignal(int measurementId) => guarded(() async {
    await _requireMeasurement(measurementId);
    final r = await (_db.select(
      _db.morningRawSignals,
    )..where((t) => t.measurementId.equals(measurementId))).getSingleOrNull();
    if (r == null) return null;
    final source = r.timestampSource == null
        ? null
        : CameraTimestampSource.fromCode(r.timestampSource);
    if (r.timestampSource != null && source == null) {
      throw const StorageException(StorageFailure.failed);
    }
    final frames = decodeRawFrames(r.frames);
    if (frames.length != r.frameCount) {
      throw const StorageException(StorageFailure.failed);
    }
    return MorningRawSignal(
      frames: frames,
      exposureTimeNs: r.exposureTimeNs,
      iso: r.iso,
      timestampSource: source,
      rollingShutterSkewNs: r.rollingShutterSkewNs,
      torchStrength: r.torchStrength,
      frameGapCount: r.frameGapCount,
      frameGapTotalS: r.frameGapTotalS,
      saturatedFraction: r.saturatedFraction,
    );
  });

  Future<void> _requireMeasurement(int measurementId) async {
    final exists =
        await (_db.selectOnly(_db.morningMeasurements)
              ..addColumns([_db.morningMeasurements.id])
              ..where(_db.morningMeasurements.id.equals(measurementId)))
            .getSingleOrNull();
    if (exists == null) throw const StorageException(StorageFailure.notFound);
  }

  @override
  Future<List<StoredRrPacket>> beltPackets(int measurementId) =>
      guarded(() async {
        await _requireMeasurement(measurementId);
        final rows =
            await (_db.select(_db.morningRrPackets)
                  ..where((t) => t.measurementId.equals(measurementId))
                  ..orderBy([
                    (t) => OrderingTerm.asc(t.timeUs),
                    (t) => OrderingTerm.asc(t.id),
                  ]))
                .get();
        return [
          for (final r in rows)
            StoredRrPacket(
              r.id,
              RrPacket(
                time: timeOf(r.timeUs),
                source: r.source,
                intervals: decodeRrIntervals(r.rr),
              ),
            ),
        ];
      });

  static MorningMeasurement _read(d.MorningMeasurementRow r) {
    final posture = RestingPosture.fromStorage(r.posture);
    final quality = PpgQuality.values.where((q) => q.name == r.quality);
    final band = SleepBand.fromCode(r.sleepBand);
    final reasons = PpgQualityReason.values.where(
      (q) => q.name == r.unusableReason,
    );
    if (posture == null ||
        quality.isEmpty ||
        (r.sleepBand != null && band == null) ||
        (r.unusableReason != null && reasons.isEmpty)) {
      throw const StorageException(StorageFailure.failed);
    }
    return MorningMeasurement(
      measuredAt: timeOf(r.measuredAtUs),
      utcOffset: Duration(seconds: r.utcOffsetS),
      posture: posture,
      deviceManufacturer: r.deviceManufacturer,
      deviceModel: r.deviceModel,
      method: r.method,
      methodVersion: r.methodVersion,
      quality: quality.first,
      restingHrBpm: r.restingHrBpm,
      rmssdMs: r.rmssdMs,
      timingNoiseMs: r.timingNoiseMs,
      sleepBand: band,
      cameraIntervalsMs: decodeCameraIntervals(r.cameraIbi),
      beforeValidation: r.beforeValidation,
      outsideWindow: r.outsideWindow,
      windowStartS: r.windowStartS,
      windowEndS: r.windowEndS,
      restSkippedAfterS: r.restSkippedAfterS,
      unusableReason: reasons.isEmpty ? null : reasons.first,
    );
  }
}
