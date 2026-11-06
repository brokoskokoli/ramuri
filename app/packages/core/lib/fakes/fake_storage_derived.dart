import '../ports/storage.dart';
import '../ports/storage_derived.dart';
import '../ports/storage_values.dart';
import '../src/preprocessing/position_processor.dart' show PositionGap;
import '../src/preprocessing/section_quality.dart';
import 'fake_storage_data.dart';

DateTime _utc(DateTime t) => t.toUtc();
DateTime? _utcOrNull(DateTime? t) => t?.toUtc();

class FakePreprocessingStore implements PreprocessingStore {
  FakePreprocessingStore(this._d);
  final FakeStorageData _d;

  @override
  Future<void> replace(int runId, StoredPreprocessing result) async {
    _d.requireRun(runId);
    final s = result.summary;
    _d.preprocessing[runId] = StoredPreprocessing(
      summary: PreprocessingSummary(
        method: s.method,
        methodVersion: s.methodVersion,
        parameterVersion: s.parameterVersion,
        computedAt: _utc(s.computedAt),
        totalTime: s.totalTime,
        movingTime: s.movingTime,
        distanceMeters: s.distanceMeters,
        bridgedDistanceMeters: s.bridgedDistanceMeters,
        averageBpm: s.averageBpm,
        maxBpm: s.maxBpm,
        medianBpm: s.medianBpm,
      ),
      samples:
          [
            for (final p in result.samples)
              PreprocessedSample(
                channel: p.channel,
                rawId: p.rawId,
                time: _utc(p.time),
                state: p.state,
                discardReason: p.discardReason,
              ),
          ]..sort((a, b) {
            final c = a.channel.index.compareTo(b.channel.index);
            return c != 0 ? c : a.time.compareTo(b.time);
          }),
      spans:
          [
            for (final p in result.spans)
              PreprocessedSpan(
                kind: p.kind,
                start: _utc(p.start),
                end: _utcOrNull(p.end),
              ),
          ]..sort((a, b) {
            final c = a.kind.index.compareTo(b.kind.index);
            return c != 0 ? c : a.start.compareTo(b.start);
          }),
    );
  }

  @override
  Future<StoredPreprocessing?> read(int runId) async => _d.preprocessing[runId];
}

class FakeRatedSectionStore implements RatedSectionStore {
  FakeRatedSectionStore(this._d);
  final FakeStorageData _d;

  @override
  Future<void> replace(int runId, List<RatedSection> sections) async {
    _d.requireRun(runId);
    _d.sections[runId] = [
      for (final s in sections)
        RatedSection(
          assessedAt: _utc(s.assessedAt),
          quality: _normalized(s.quality),
        ),
    ];
  }

  @override
  Future<List<RatedSection>> read(int runId) async =>
      [...?_d.sections[runId]]
        ..sort((a, b) => a.quality.from.compareTo(b.quality.from));

  /// Wie im Adapter: Zeiten auf UTC (Mikrosekunden), Lücken mit Ende und open.
  static SectionQuality _normalized(SectionQuality q) => SectionQuality(
    parameterVersion: q.parameterVersion,
    from: _utc(q.from),
    to: _utc(q.to),
    heartRateCounts: q.heartRateCounts,
    positionCounts: q.positionCounts,
    missingHeartRateShare: q.missingHeartRateShare,
    longestHeartRateGap: q.longestHeartRateGap,
    meetsHeartRateGapRule: q.meetsHeartRateGapRule,
    settlingOverlap: q.settlingOverlap,
    settlingShare: q.settlingShare,
    gpsGaps: [
      for (final g in q.gpsGaps)
        PositionGap(start: _utc(g.start), end: _utc(g.end), open: g.open),
    ],
  );
}

class FakeComputedValueStore implements ComputedValueStore {
  FakeComputedValueStore(this._d);
  final FakeStorageData _d;

  void _checkOwner(ValueOwner o) {
    final id = o.runId;
    if (id != null) _d.requireRun(id);
  }

  static void _noDuplicates(List<ComputedValue> vs) {
    if (vs.map((v) => v.key).toSet().length != vs.length) {
      throw const StorageException(StorageFailure.rejected);
    }
  }

  /// Wie die CHECK-Regeln der Tabelle `value_sections`.
  static void _validate(List<ComputedValue> vs) {
    for (final v in vs) {
      for (final s in v.sections) {
        final bad =
            s.end.isBefore(s.start) ||
            s.weight < 0 ||
            s.lateFactor < 0 ||
            (s.gpsMedianAccuracyMeters ?? 0) < 0;
        if (bad) throw const StorageException(StorageFailure.rejected);
      }
    }
  }

  static ValueSection _normSection(ValueSection s) => ValueSection(
    start: _utc(s.start),
    end: _utc(s.end),
    weight: s.weight,
    lateFactor: s.lateFactor,
    status: s.status,
    reasons: s.reasons,
    gpsMedianAccuracyMeters: s.gpsMedianAccuracyMeters,
    discard: s.discard,
    oxygenDemand: s.oxygenDemand,
    estimate: s.estimate,
  );

  static ComputedValue _norm(ComputedValue v) => ComputedValue(
    key: v.key,
    value: v.value,
    unit: v.unit,
    computedAt: _utc(v.computedAt),
    measurementCount: v.measurementCount,
    sources: List.unmodifiable(v.sources),
    method: v.method,
    methodVersion: v.methodVersion,
    parameterVersion: v.parameterVersion,
    quality: v.quality,
    dataFrom: _utcOrNull(v.dataFrom),
    dataTo: _utcOrNull(v.dataTo),
    sections: List.unmodifiable(v.sections.map(_normSection)),
  );

  @override
  Future<void> createOriginals(
    ValueOwner owner,
    List<ComputedValue> values,
  ) async {
    _checkOwner(owner);
    _noDuplicates(values);
    _validate(values);
    final existing = _d.values[owner];
    if (existing != null && values.any((v) => existing.containsKey(v.key))) {
      throw const StorageException(StorageFailure.rejected);
    }
    final target = _d.values.putIfAbsent(owner, () => {});
    for (final v in values) {
      final n = _norm(v);
      target[v.key] = ValuePair(original: n, current: n);
    }
  }

  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) async {
    _checkOwner(owner);
    _noDuplicates(values);
    _validate(values);
    final target = _d.values[owner] ?? const <String, ValuePair>{};
    if (values.any((v) => !target.containsKey(v.key))) {
      throw const StorageException(StorageFailure.notFound);
    }
    for (final v in values) {
      _d.values[owner]![v.key] = ValuePair(
        original: target[v.key]!.original,
        current: _norm(v),
      );
    }
  }

  @override
  Future<List<ValuePair>> read(ValueOwner owner) async =>
      (_d.values[owner]?.values.toList() ?? <ValuePair>[])
        ..sort((a, b) => a.original.key.compareTo(b.original.key));
}
