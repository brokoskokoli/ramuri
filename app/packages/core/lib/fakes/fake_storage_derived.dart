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
        bestPaceSecondsPerKm: s.bestPaceSecondsPerKm,
        lapCount: s.lapCount,
        heartRateTime: s.heartRateTime,
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

  @override
  Future<Map<int, StoredPreprocessing>> readOverviews() async => {
    for (final e in _d.preprocessing.entries)
      e.key: StoredPreprocessing(
        summary: e.value.summary,
        spans: [
          for (final s in e.value.spans)
            if (s.kind == PreprocessedSpanKind.moving ||
                s.kind == PreprocessedSpanKind.positionGap)
              s,
        ]..sort(comparePreprocessedSpans),
      ),
  };
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
    unavailableReason: v.unavailableReason,
    heartRateBasis: v.heartRateBasis,
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

  void _checkCreate(ValueOwner owner, List<ComputedValue> values) {
    _checkOwner(owner);
    _noDuplicates(values);
    final existing = _d.values[owner];
    if (existing != null && values.any((v) => existing.containsKey(v.key))) {
      throw const StorageException(StorageFailure.rejected);
    }
    requireStorableValues(values);
  }

  void _create(ValueOwner owner, List<ComputedValue> values) {
    final target = _d.values.putIfAbsent(owner, () => {});
    for (final v in values) {
      final n = _norm(v);
      target[v.key] = ValuePair(original: n, current: n);
    }
  }

  @override
  Future<void> createOriginals(
    ValueOwner owner,
    List<ComputedValue> values,
  ) async {
    _checkCreate(owner, values);
    _create(owner, values);
  }

  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) =>
      swapCurrentAll({owner: values});

  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> changes) =>
      writeAll(swap: changes);

  void _checkSwap(ValueOwner owner, List<ComputedValue> values) {
    _checkOwner(owner);
    _noDuplicates(values);
    final target = _d.values[owner] ?? const <String, ValuePair>{};
    if (values.any((v) => !target.containsKey(v.key))) {
      throw const StorageException(StorageFailure.notFound);
    }
    requireStorableValues(values);
  }

  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) async {
    // Erst alles prüfen, dann schreiben: bei einem Fehler ändert sich nichts.
    for (final e in swap.entries) {
      _checkSwap(e.key, e.value);
    }
    for (final e in create.entries) {
      _checkCreate(e.key, e.value);
    }
    for (final e in create.entries) {
      _create(e.key, e.value);
    }
    for (final e in swap.entries) {
      final target = _d.values[e.key]!;
      for (final v in e.value) {
        target[v.key] = ValuePair(
          original: target[v.key]!.original,
          current: _norm(v),
        );
      }
    }
  }

  @override
  Future<List<ValuePair>> read(ValueOwner owner) async =>
      (_d.values[owner]?.values.toList() ?? <ValuePair>[])
        ..sort((a, b) => a.original.key.compareTo(b.original.key));

  static ComputedValue _withoutSections(ComputedValue v) => ComputedValue(
    key: v.key,
    value: v.value,
    unavailableReason: v.unavailableReason,
    heartRateBasis: v.heartRateBasis,
    unit: v.unit,
    computedAt: v.computedAt,
    dataFrom: v.dataFrom,
    dataTo: v.dataTo,
    measurementCount: v.measurementCount,
    sources: v.sources,
    method: v.method,
    methodVersion: v.methodVersion,
    parameterVersion: v.parameterVersion,
    quality: v.quality,
  );

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(
    Set<String> keys,
  ) async => {
    for (final e in _d.values.entries)
      if (e.key.runId != null)
        if ({
              for (final p in e.value.values)
                if (keys.contains(p.current.key))
                  p.current.key: _withoutSections(p.current),
            }
            case final found when found.isNotEmpty)
          e.key.runId!: found,
  };

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) async => {
    for (final e in _d.values.entries)
      if (e.key.day != null)
        if ({
              for (final p in e.value.values)
                if (keys.contains(p.current.key))
                  p.current.key: _withoutSections(p.current),
            }
            case final found when found.isNotEmpty)
          e.key.day!: found,
  };
}
