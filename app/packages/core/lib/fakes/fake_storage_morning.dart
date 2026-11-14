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
  }) async {
    checkMorningForStorage(measurement, beltPackets: beltPackets);
    final id = _d.nextMorningId++;
    _d.morning[id] = MorningMeasurement(
      measuredAt: measurement.measuredAt.toUtc(),
      utcOffset: measurement.utcOffset,
      posture: measurement.posture,
      deviceManufacturer: measurement.deviceManufacturer,
      deviceModel: measurement.deviceModel,
      method: measurement.method,
      methodVersion: measurement.methodVersion,
      quality: measurement.quality,
      restingHrBpm: measurement.roundedRestingHr,
      rmssdMs: measurement.rmssdMs,
      timingNoiseMs: measurement.timingNoiseMs,
      sleepBand: measurement.sleepBand,
      cameraIntervalsMs: decodeCameraIntervals(
        encodeCameraIntervals(measurement.cameraIntervalsMs),
      ),
      beforeValidation: measurement.beforeValidation,
      outsideWindow: measurement.outsideWindow,
    );
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
    _d.morning[measurementId] = MorningMeasurement(
      measuredAt: m.measuredAt,
      utcOffset: m.utcOffset,
      posture: m.posture,
      deviceManufacturer: m.deviceManufacturer,
      deviceModel: m.deviceModel,
      method: m.method,
      methodVersion: m.methodVersion,
      quality: m.quality,
      restingHrBpm: m.restingHrBpm,
      rmssdMs: m.rmssdMs,
      timingNoiseMs: m.timingNoiseMs,
      sleepBand: band,
      cameraIntervalsMs: m.cameraIntervalsMs,
      beforeValidation: m.beforeValidation,
      outsideWindow: m.outsideWindow,
    );
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
