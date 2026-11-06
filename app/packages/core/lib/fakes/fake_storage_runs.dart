import '../src/preprocessing/measurement.dart';
import '../ports/storage.dart';
import '../ports/storage_raw.dart';
import '../ports/storage_runs.dart';
import 'fake_storage_data.dart';

DateTime _utc(DateTime t) => t.toUtc();

class FakeRunStore implements RunStore {
  FakeRunStore(this._d);
  final FakeStorageData _d;

  @override
  Future<StoredRun> create({required DateTime startedAt}) async {
    final run = StoredRun(
      id: _d.nextRunId++,
      state: RunState.active,
      startedAt: _utc(startedAt),
    );
    _d.runs[run.id] = run;
    return run;
  }

  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) async {
    requireRunEnd(state, endedAt, endedUtcOffset);
    _d.requireRun(runId);
    final old = _d.runs[runId]!;
    _d.runs[runId] = StoredRun(
      id: runId,
      state: state,
      startedAt: old.startedAt,
      endedAt: endedAt == null ? null : _utc(endedAt),
      endedUtcOffset: endedUtcOffset,
    );
  }

  @override
  Future<StoredRun?> get(int runId) async => _d.runs[runId];

  @override
  Future<List<StoredRun>> list() async => _d.runs.values.toList()
    ..sort(
      (a, b) => b.startedAt != a.startedAt
          ? b.startedAt.compareTo(a.startedAt)
          : b.id.compareTo(a.id),
    );

  @override
  Future<List<StoredRun>> unfinished() async =>
      _d.runs.values.where((r) => r.state != RunState.finished).toList()..sort(
        (a, b) => a.startedAt != b.startedAt
            ? a.startedAt.compareTo(b.startedAt)
            : a.id.compareTo(b.id),
      );
}

class FakeRunMarkerStore implements RunMarkerStore {
  FakeRunMarkerStore(this._d);
  final FakeStorageData _d;

  @override
  Future<void> addLap(int runId, StoredLap lap) async {
    _d.requireRun(runId);
    final laps = _d.laps.putIfAbsent(runId, () => []);
    if (laps.any((l) => l.index == lap.index)) {
      throw const StorageException(StorageFailure.rejected);
    }
    laps.add(
      StoredLap(
        index: lap.index,
        markedAt: _utc(lap.markedAt),
        lapTime: lap.lapTime,
      ),
    );
  }

  @override
  Future<List<StoredLap>> laps(int runId) async =>
      [...?_d.laps[runId]]..sort((a, b) => a.index.compareTo(b.index));

  @override
  Future<int> openGap(int runId, RunGapKind kind, DateTime start) async {
    _d.requireRun(runId);
    final id = _d.nextGapId++;
    _d.gaps
        .putIfAbsent(runId, () => [])
        .add(StoredGap(id: id, kind: kind, start: _utc(start)));
    return id;
  }

  @override
  Future<void> closeGap(int gapId, DateTime end) async {
    for (final list in _d.gaps.values) {
      final i = list.indexWhere((g) => g.id == gapId);
      if (i < 0) continue;
      final g = list[i];
      if (g.end != null) {
        throw const StorageException(StorageFailure.rejected);
      }
      list[i] = StoredGap(
        id: g.id,
        kind: g.kind,
        start: g.start,
        end: _utc(end),
      );
      return;
    }
    throw const StorageException(StorageFailure.notFound);
  }

  @override
  Future<List<StoredGap>> gaps(int runId) async => [...?_d.gaps[runId]]
    ..sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.id.compareTo(b.id),
    );
}

/// Nur anhängen und lesen, wie der Port.
class FakeRawDataStore implements RawDataStore {
  FakeRawDataStore(this._d);
  final FakeStorageData _d;

  @override
  Future<void> append(int runId, RawBatch batch) async {
    validateRawBatch(batch);
    _d.requireRun(runId);
    final byChannel = _d.raw.putIfAbsent(runId, () => {});
    void add(RawChannel c, RawSample s) {
      final id = _d.nextRawId[c]!;
      _d.nextRawId[c] = id + 1;
      byChannel.putIfAbsent(c, () => []).add(StoredRaw(id, s));
    }

    for (final p in batch.positions) {
      add(
        RawChannel.position,
        RawPosition(
          time: _utc(p.time),
          source: p.source,
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters: p.accuracyMeters,
          speedMetersPerSecond: p.speedMetersPerSecond,
          speedAccuracyMetersPerSecond: p.speedAccuracyMetersPerSecond,
          verticalAccuracyMeters: p.verticalAccuracyMeters,
          state: p.state,
        ),
      );
    }
    for (final h in batch.heartRates) {
      add(
        RawChannel.heartRate,
        RawHeartRate(
          time: _utc(h.time),
          source: h.source,
          bpm: h.bpm,
          contact: h.contact,
          state: h.state,
        ),
      );
    }
    for (final a in batch.altitudes) {
      add(
        RawChannel.altitude,
        RawAltitude(
          time: _utc(a.time),
          source: a.source,
          meters: a.meters,
          verticalAccuracyMeters: a.verticalAccuracyMeters,
          state: a.state,
        ),
      );
    }
    for (final s in batch.steps) {
      add(
        RawChannel.steps,
        RawSteps(
          time: _utc(s.time),
          source: s.source,
          count: s.count,
          state: s.state,
        ),
      );
    }
    for (final u in batch.unavailable) {
      add(
        u.channel,
        RawUnavailable(
          channel: u.channel,
          time: _utc(u.time),
          source: u.source,
        ),
      );
    }
  }

  @override
  Future<StoredRawData> read(int runId) async {
    final byChannel = _d.raw[runId] ?? const {};
    List<StoredRaw<T>> of<T extends RawSample>(RawChannel c) => [
      for (final r in byChannel[c] ?? const <StoredRaw<RawSample>>[])
        if (r.value is T) StoredRaw<T>(r.id, r.value as T),
    ]..sort(_byTimeThenId);
    final unavailable =
        <StoredRaw<RawUnavailable>>[
          for (final c in RawChannel.values) ...of<RawUnavailable>(c),
        ]..sort((a, b) {
          final t = a.value.time.compareTo(b.value.time);
          if (t != 0) return t;
          final c = a.value.channel.index.compareTo(b.value.channel.index);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
    return StoredRawData(
      positions: of<RawPosition>(RawChannel.position),
      heartRates: of<RawHeartRate>(RawChannel.heartRate),
      altitudes: of<RawAltitude>(RawChannel.altitude),
      steps: of<RawSteps>(RawChannel.steps),
      unavailable: unavailable,
    );
  }

  static int _byTimeThenId(StoredRaw a, StoredRaw b) {
    final t = a.value.time.compareTo(b.value.time);
    return t != 0 ? t : a.id.compareTo(b.id);
  }
}
