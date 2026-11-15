import '../ports/storage.dart';
import '../ports/storage_morning.dart';
import '../ports/storage_raw.dart';
import '../src/preprocessing/measurement.dart';
import 'fake_storage_data.dart';

/// Fake der Morgenmessungen: speichert, was die Datenbank speichern würde
/// (Ruhepuls gerundet, Schlagabstände als float32).
class FakeMorningStore implements MorningStore {
  FakeMorningStore(this._d);
  final FakeStorageData _d;

  @override
  Future<int> add(
    MorningMeasurement measurement, {
    List<RrPacket> beltPackets = const [],
    MorningRawSignal? rawSignal,
  }) async {
    checkMorningForStorage(
      measurement,
      beltPackets: beltPackets,
      rawSignal: rawSignal,
    );
    final id = _d.nextMorningId++;
    _d.morning[id] = _copy(
      measurement,
      measuredAt: measurement.measuredAt.toUtc(),
      restingHrBpm: measurement.roundedRestingHr,
      sleepBand: measurement.sleepBand,
      cameraIntervalsMs: decodeCameraIntervals(
        encodeCameraIntervals(measurement.cameraIntervalsMs),
      ),
    );
    if (rawSignal != null) {
      _d.morningRaw[id] = MorningRawSignal(
        frames: decodeRawFrames(encodeRawFrames(rawSignal.frames)),
        frameGapCount: rawSignal.frameGapCount,
        frameGapTotalS: rawSignal.frameGapTotalS,
        exposureTimeNs: rawSignal.exposureTimeNs,
        iso: rawSignal.iso,
        timestampSource: rawSignal.timestampSource,
        rollingShutterSkewNs: rawSignal.rollingShutterSkewNs,
        torchStrength: rawSignal.torchStrength,
        saturatedFraction: rawSignal.saturatedFraction,
      );
    }
    _d.morningPackets[id] = [
      for (final p in beltPackets)
        StoredRrPacket(
          _d.nextMorningPacketId++,
          RrPacket(
            time: p.time.toUtc(),
            source: p.source,
            intervals: List.unmodifiable(p.intervals),
          ),
        ),
    ];
    return id;
  }

  @override
  Future<List<StoredMorningMeasurement>> list() async {
    final all = [
      for (final e in _d.morning.entries)
        StoredMorningMeasurement(e.key, e.value),
    ];
    all.sort((a, b) {
      final c = a.value.measuredAt.compareTo(b.value.measuredAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return all;
  }

  @override
  Future<void> setSleepBand(int measurementId, SleepBand? band) async {
    final m = _d.morning[measurementId];
    if (m == null) throw const StorageException(StorageFailure.notFound);
    _d.morning[measurementId] = _copy(m, sleepBand: band);
  }

  /// Kopie mit den gespeicherten Abwandlungen; `sleepBand` und der Rest
  /// kommen sonst von [m] (null bei `sleepBand` heißt: gelöscht).
  static MorningMeasurement _copy(
    MorningMeasurement m, {
    DateTime? measuredAt,
    double? restingHrBpm,
    SleepBand? sleepBand,
    List<double>? cameraIntervalsMs,
  }) => MorningMeasurement(
    measuredAt: measuredAt ?? m.measuredAt,
    utcOffset: m.utcOffset,
    posture: m.posture,
    deviceManufacturer: m.deviceManufacturer,
    deviceModel: m.deviceModel,
    method: m.method,
    methodVersion: m.methodVersion,
    quality: m.quality,
    restingHrBpm: restingHrBpm ?? m.restingHrBpm,
    rmssdMs: m.rmssdMs,
    timingNoiseMs: m.timingNoiseMs,
    sleepBand: sleepBand,
    cameraIntervalsMs: cameraIntervalsMs ?? m.cameraIntervalsMs,
    beforeValidation: m.beforeValidation,
    outsideWindow: m.outsideWindow,
    windowStartS: m.windowStartS,
    windowEndS: m.windowEndS,
    restSkippedAfterS: m.restSkippedAfterS,
    unusableReason: m.unusableReason,
  );

  @override
  Future<MorningRawSignal?> rawSignal(int measurementId) async {
    if (!_d.morning.containsKey(measurementId)) {
      throw const StorageException(StorageFailure.notFound);
    }
    return _d.morningRaw[measurementId];
  }

  @override
  Future<List<StoredRrPacket>> beltPackets(int measurementId) async {
    final p = _d.morningPackets[measurementId];
    if (p == null) throw const StorageException(StorageFailure.notFound);
    final out = [...p];
    out.sort((a, b) {
      final c = a.value.time.compareTo(b.value.time);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return out;
  }
}
