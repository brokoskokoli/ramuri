import 'package:core/core.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, Value;

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
                cameraId: Value(rawSignal.cameraId),
                physicalCameraId: Value(rawSignal.physicalCameraId),
                focalLengthMm: Value(rawSignal.focalLengthMm),
                ispFrames: Value(
                  rawSignal.ispFrames == null
                      ? null
                      : encodeIspFrames(rawSignal.ispFrames!),
                ),
                diagNoiseReductionOff: Value(
                  rawSignal.diagnostics.contains(
                    PpgCameraDiagnostic.noiseReductionOff,
                  ),
                ),
                diagEdgeOff: Value(
                  rawSignal.diagnostics.contains(PpgCameraDiagnostic.edgeOff),
                ),
                diagAwbFixed: Value(
                  rawSignal.diagnostics.contains(PpgCameraDiagnostic.awbFixed),
                ),
                diagTonemapLinear: Value(
                  rawSignal.diagnostics.contains(
                    PpgCameraDiagnostic.tonemapLinear,
                  ),
                ),
                diagShadingOff: Value(
                  rawSignal.diagnostics.contains(
                    PpgCameraDiagnostic.shadingOff,
                  ),
                ),
                diagAwbVariant: Value(rawSignal.awbVariant?.wire),
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
  Future<void> clearSleepBands(Iterable<int> measurementIds) =>
      guarded(() async {
        final ids = measurementIds.toSet();
        if (ids.isEmpty) return;
        await _db.transaction(() async {
          for (final id in ids) {
            final n =
                await (_db.update(
                  _db.morningMeasurements,
                )..where((t) => t.id.equals(id))).write(
                  const d.MorningMeasurementsCompanion(sleepBand: Value(null)),
                );
            // Abbruch rollt die schon gelöschten Stufen zurück.
            if (n == 0) {
              throw const StorageException(StorageFailure.notFound);
            }
          }
        });
      });

  @override
  Future<void> choose(int measurementId) async {
    // Nicht wählbar: Abbruch der Transaktion (Rollback), danach als
    // ArgumentError gemeldet; `guarded` übersetzt sonst jeden Fehler in eine
    // StorageException.
    var notChoosable = false;
    try {
      await guarded(
        () => _db.transaction(() async {
          final c = morningChoice(await list(), measurementId);
          // Zuerst die Wahl an den anderen löschen, dann die Zielzeile
          // schreiben: Ist sie nicht wählbar, rollt der Abbruch das Löschen
          // zurück (ganz oder gar nicht).
          if (c.unchoose.isNotEmpty) {
            await (_db.update(
              _db.morningMeasurements,
            )..where((t) => t.id.isIn(c.unchoose))).write(
              const d.MorningMeasurementsCompanion(chosen: Value(false)),
            );
          }
          final n =
              await (_db.update(_db.morningMeasurements)..where(
                    (t) =>
                        t.id.equals(measurementId) &
                        t.quality.isNotValue(PpgQuality.unusable.name) &
                        t.outsideWindow.equals(false),
                  ))
                  .write(
                    d.MorningMeasurementsCompanion(
                      chosen: const Value(true),
                      sleepBand: Value(c.sleepBand?.code),
                    ),
                  );
          if (n == 0) {
            notChoosable = true;
            throw const StorageException(StorageFailure.rejected);
          }
        }),
      );
    } on StorageException {
      if (notChoosable) throw morningNotChoosable(measurementId);
      rethrow;
    }
  }

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
    final isp = r.ispFrames == null ? null : decodeIspFrames(r.ispFrames!);
    if (isp != null && isp.length != r.frameCount) {
      throw const StorageException(StorageFailure.failed);
    }
    final awb = r.diagAwbVariant == null
        ? null
        : PpgAwbVariant.fromWire(r.diagAwbVariant);
    if (r.diagAwbVariant != null && awb == null) {
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
      cameraId: r.cameraId,
      physicalCameraId: r.physicalCameraId,
      focalLengthMm: r.focalLengthMm,
      ispFrames: isp,
      diagnostics: Set.unmodifiable({
        if (r.diagNoiseReductionOff) PpgCameraDiagnostic.noiseReductionOff,
        if (r.diagEdgeOff) PpgCameraDiagnostic.edgeOff,
        if (r.diagAwbFixed) PpgCameraDiagnostic.awbFixed,
        if (r.diagTonemapLinear) PpgCameraDiagnostic.tonemapLinear,
        if (r.diagShadingOff) PpgCameraDiagnostic.shadingOff,
      }),
      awbVariant: awb,
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
    final reason = MorningUnusableReason.fromName(r.unusableReason);
    if (posture == null ||
        quality.isEmpty ||
        (r.sleepBand != null && band == null) ||
        (r.unusableReason != null && reason == null)) {
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
      unusableReason: reason,
      chosen: r.chosen,
    );
  }
}
