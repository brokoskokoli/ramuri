import 'dart:convert';

import 'package:core/core.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

class DriftPreprocessingStore implements PreprocessingStore {
  DriftPreprocessingStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<void> replace(int runId, StoredPreprocessing result) => guarded(
    () => _db.transaction(() async {
      await requireRun(_db, runId);
      await (_db.delete(
        _db.preprocessingResults,
      )..where((t) => t.runId.equals(runId))).go();
      await (_db.delete(
        _db.preprocessedSamples,
      )..where((t) => t.runId.equals(runId))).go();
      await (_db.delete(
        _db.preprocessedSpans,
      )..where((t) => t.runId.equals(runId))).go();
      final s = result.summary;
      await _db
          .into(_db.preprocessingResults)
          .insert(
            d.PreprocessingResultsCompanion.insert(
              runId: runId,
              method: s.method,
              methodVersion: s.methodVersion,
              parameterVersion: s.parameterVersion,
              computedAtUs: usOf(s.computedAt),
              totalTimeS: _v(secondsOfOrNull(s.totalTime)),
              movingTimeS: _v(secondsOfOrNull(s.movingTime)),
              distanceM: _v(s.distanceMeters),
              bridgedDistanceM: _v(s.bridgedDistanceMeters),
              averageBpm: _v(s.averageBpm),
              maxBpm: _v(s.maxBpm),
              medianBpm: _v(s.medianBpm),
              bestPaceSPerKm: _v(s.bestPaceSecondsPerKm),
              lapCount: _v(s.lapCount),
              heartRateTimeS: _v(secondsOfOrNull(s.heartRateTime)),
            ),
          );
      await _db.batch((b) {
        b.insertAll(_db.preprocessedSamples, [
          for (final p in result.samples)
            d.PreprocessedSamplesCompanion.insert(
              runId: runId,
              channel: snake(p.channel.name),
              rawId: p.rawId,
              timeUs: usOf(p.time),
              state: p.state.name,
              discardReason: _v(p.discardReason?.name),
            ),
        ]);
        b.insertAll(_db.preprocessedSpans, [
          for (final p in result.spans)
            d.PreprocessedSpansCompanion.insert(
              runId: runId,
              kind: snake(p.kind.name),
              startUs: usOf(p.start),
              endUs: _v(usOfOrNull(p.end)),
            ),
        ]);
      });
    }),
  );

  @override
  Future<Map<int, StoredPreprocessing>> readOverviews() => guarded(() async {
    // Zwei Abfragen für alle Läufe, keine je Lauf.
    final results = await _db.select(_db.preprocessingResults).get();
    final spans =
        await (_db.select(_db.preprocessedSpans)
              ..where(
                (t) => t.kind.isIn([
                  snake(PreprocessedSpanKind.moving.name),
                  snake(PreprocessedSpanKind.positionGap.name),
                ]),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startUs)]))
            .get();
    final byRun = <int, List<PreprocessedSpan>>{};
    for (final p in spans) {
      byRun
          .putIfAbsent(p.runId, () => [])
          .add(
            PreprocessedSpan(
              kind: enumOf(
                PreprocessedSpanKind.values,
                p.kind,
                (v) => snake(v.name),
              ),
              start: timeOf(p.startUs),
              end: p.endUs == null ? null : timeOf(p.endUs!),
            ),
          );
    }
    return {
      for (final r in results)
        r.runId: StoredPreprocessing(
          summary: _summaryOf(r),
          spans: [...?byRun[r.runId]]..sort(comparePreprocessedSpans),
        ),
    };
  });

  @override
  Future<StoredPreprocessing?> read(int runId) => guarded(() async {
    final r = await (_db.select(
      _db.preprocessingResults,
    )..where((t) => t.runId.equals(runId))).getSingleOrNull();
    if (r == null) return null;
    final samples = await (_db.select(
      _db.preprocessedSamples,
    )..where((t) => t.runId.equals(runId))).get();
    final spans = await (_db.select(
      _db.preprocessedSpans,
    )..where((t) => t.runId.equals(runId))).get();
    return StoredPreprocessing(
      summary: _summaryOf(r),
      samples: [
        for (final p in samples)
          PreprocessedSample(
            channel: enumOf(RawChannel.values, p.channel, (v) => snake(v.name)),
            rawId: p.rawId,
            time: timeOf(p.timeUs),
            state: enumOf(MeasurementState.values, p.state, (v) => v.name),
            discardReason: p.discardReason == null
                ? null
                : enumOf(DiscardReason.values, p.discardReason!, (v) => v.name),
          ),
      ]..sort(comparePreprocessedSamples),
      spans: [
        for (final p in spans)
          PreprocessedSpan(
            kind: enumOf(
              PreprocessedSpanKind.values,
              p.kind,
              (v) => snake(v.name),
            ),
            start: timeOf(p.startUs),
            end: timeOfOrNull(p.endUs),
          ),
      ]..sort(comparePreprocessedSpans),
    );
  });
}

class DriftRatedSectionStore implements RatedSectionStore {
  DriftRatedSectionStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<void> replace(int runId, List<RatedSection> sections) => guarded(
    () => _db.transaction(() async {
      await requireRun(_db, runId);
      await (_db.delete(
        _db.ratedSections,
      )..where((t) => t.runId.equals(runId))).go();
      await _db.batch((b) {
        b.insertAll(_db.ratedSections, [
          for (final s in sections) _companion(runId, s),
        ]);
      });
    }),
  );

  static d.RatedSectionsCompanion _companion(int runId, RatedSection s) {
    final q = s.quality;
    int hr(MeasurementState m) => q.heartRateCounts[m] ?? 0;
    int pos(MeasurementState m) => q.positionCounts[m] ?? 0;
    return d.RatedSectionsCompanion.insert(
      runId: runId,
      startUs: usOf(q.from),
      endUs: usOf(q.to),
      method: q.method,
      methodVersion: q.methodVersion,
      parameterVersion: q.parameterVersion,
      assessedAtUs: usOf(s.assessedAt),
      heartRatePresent: hr(MeasurementState.present),
      heartRateEstimated: hr(MeasurementState.estimated),
      heartRateUnavailable: hr(MeasurementState.unavailable),
      heartRateDiscarded: hr(MeasurementState.discarded),
      positionPresent: pos(MeasurementState.present),
      positionEstimated: pos(MeasurementState.estimated),
      positionUnavailable: pos(MeasurementState.unavailable),
      positionDiscarded: pos(MeasurementState.discarded),
      missingHeartRateShare: q.missingHeartRateShare,
      longestHeartRateGapS: secondsOf(q.longestHeartRateGap),
      meetsHeartRateGapRule: q.meetsHeartRateGapRule,
      settlingOverlapS: secondsOf(q.settlingOverlap),
      settlingShare: q.settlingShare,
      gpsGaps: jsonEncode([
        for (final g in q.gpsGaps) [usOf(g.start), usOf(g.end), g.open ? 1 : 0],
      ]),
    );
  }

  @override
  Future<List<RatedSection>> read(int runId) => guarded(() async {
    final rows =
        await (_db.select(_db.ratedSections)
              ..where((t) => t.runId.equals(runId))
              ..orderBy([
                (t) => OrderingTerm.asc(t.startUs),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return [
      for (final r in rows)
        RatedSection(
          assessedAt: timeOf(r.assessedAtUs),
          quality: SectionQuality(
            parameterVersion: r.parameterVersion,
            from: timeOf(r.startUs),
            to: timeOf(r.endUs),
            heartRateCounts: {
              MeasurementState.present: r.heartRatePresent,
              MeasurementState.estimated: r.heartRateEstimated,
              MeasurementState.unavailable: r.heartRateUnavailable,
              MeasurementState.discarded: r.heartRateDiscarded,
            },
            positionCounts: {
              MeasurementState.present: r.positionPresent,
              MeasurementState.estimated: r.positionEstimated,
              MeasurementState.unavailable: r.positionUnavailable,
              MeasurementState.discarded: r.positionDiscarded,
            },
            missingHeartRateShare: r.missingHeartRateShare,
            longestHeartRateGap: durationOf(r.longestHeartRateGapS),
            meetsHeartRateGapRule: r.meetsHeartRateGapRule,
            settlingOverlap: durationOf(r.settlingOverlapS),
            settlingShare: r.settlingShare,
            gpsGaps: _gapsOf(r.gpsGaps),
          ),
        ),
    ];
  });
}

List<PositionGap> _gapsOf(String json) => [
  for (final g in jsonDecode(json) as List)
    PositionGap(
      start: timeOf((g as List)[0] as int),
      end: timeOf(g[1] as int),
      // Nur 0 und 1 sind gültig; alles andere ist ein Fehler des Speichers
      // (fail-closed), nie "geschlossen". Text ohne Inhalt.
      open: switch (g[2]) {
        0 => false,
        1 => true,
        _ => throw const FormatException('gps_gaps: open'),
      },
    ),
];

Value<T> _v<T>(T x) => Value<T>(x);

PreprocessingSummary _summaryOf(d.PreprocessingResult r) =>
    PreprocessingSummary(
      method: r.method,
      methodVersion: r.methodVersion,
      parameterVersion: r.parameterVersion,
      computedAt: timeOf(r.computedAtUs),
      totalTime: durationOfOrNull(r.totalTimeS),
      movingTime: durationOfOrNull(r.movingTimeS),
      distanceMeters: r.distanceM,
      bridgedDistanceMeters: r.bridgedDistanceM,
      averageBpm: r.averageBpm,
      maxBpm: r.maxBpm,
      medianBpm: r.medianBpm,
      bestPaceSecondsPerKm: r.bestPaceSPerKm,
      lapCount: r.lapCount,
      heartRateTime: durationOfOrNull(r.heartRateTimeS),
    );
