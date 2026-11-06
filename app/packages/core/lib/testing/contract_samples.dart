import '../core.dart';
import 'contract_support.dart';

/// Zwei Positionen, ein Puls, eine Höhe, Schritte und eine Zeile ohne Wert.
RawBatch sampleBatch() => RawBatch(
  positions: [
    RawPosition(
      time: at(2, 123457),
      source: 'gps',
      latitude: 52.5,
      longitude: 13.25,
      accuracyMeters: 4.5,
    ),
    RawPosition(
      time: at(1),
      source: 'gps',
      latitude: 52.0,
      longitude: 13.0,
      state: MeasurementState.estimated,
    ),
  ],
  heartRates: [
    RawHeartRate(
      time: at(1),
      source: 'strap',
      bpm: 140,
      contact: SensorContact.good,
    ),
  ],
  altitudes: [
    RawAltitude(
      time: at(1),
      source: 'gps',
      meters: 35.5,
      verticalAccuracyMeters: 3.0,
    ),
  ],
  steps: [RawSteps(time: at(1), source: 'phone', count: 12)],
  unavailable: [
    RawUnavailable(channel: RawChannel.heartRate, time: at(3), source: 'strap'),
  ],
);

StoredPreprocessing samplePreprocessing([int version = 1]) =>
    StoredPreprocessing(
      summary: PreprocessingSummary(
        method: 'preprocessing',
        methodVersion: version,
        parameterVersion: 2,
        computedAt: at(60, 5),
        totalTime: const Duration(seconds: 61, microseconds: 500000),
        movingTime: const Duration(seconds: 60),
        distanceMeters: 1000.5,
        maxBpm: 170,
      ),
      samples: [
        PreprocessedSample(
          channel: RawChannel.position,
          rawId: 2,
          time: at(2),
          state: MeasurementState.discarded,
          discardReason: DiscardReason.hardJump,
        ),
        PreprocessedSample(
          channel: RawChannel.position,
          rawId: 1,
          time: at(1),
          state: MeasurementState.present,
        ),
      ],
      spans: [
        PreprocessedSpan(
          kind: PreprocessedSpanKind.settling,
          start: at(1),
          end: at(5),
        ),
        PreprocessedSpan(kind: PreprocessedSpanKind.moving, start: at(5)),
      ],
    );

RatedSection sampleSection(int fromSeconds) => RatedSection(
  assessedAt: at(100, 9),
  quality: SectionQuality(
    parameterVersion: 2,
    from: at(fromSeconds),
    to: at(fromSeconds + 60),
    heartRateCounts: {
      MeasurementState.present: 50,
      MeasurementState.estimated: 1,
      MeasurementState.unavailable: 2,
      MeasurementState.discarded: 3,
    },
    positionCounts: {
      MeasurementState.present: 55,
      MeasurementState.estimated: 0,
      MeasurementState.unavailable: 4,
      MeasurementState.discarded: 1,
    },
    missingHeartRateShare: 0.125,
    longestHeartRateGap: const Duration(seconds: 7, microseconds: 250000),
    meetsHeartRateGapRule: true,
    settlingOverlap: const Duration(seconds: 3),
    settlingShare: 0.05,
    gpsGaps: [
      PositionGap(start: at(1), end: at(2), open: false),
      PositionGap(start: at(5, 7), end: at(9), open: true),
    ],
  ),
);

ComputedValue sampleValue(
  String key,
  double? value, {
  int method = 1,
  ValueQuality quality = ValueQuality.good,
  List<ValueSection> sections = const [],
  UnavailableReason? reason,

  /// Nur für Fehlerfälle: kein Grund, obwohl der Wert fehlt.
  bool withoutReason = false,
}) => ComputedValue(
  key: key,
  value: value,
  unavailableReason:
      reason ??
      (value == null && !withoutReason
          ? UnavailableReason.insufficientData
          : null),
  unit: 'ml/kg/min',
  computedAt: at(200, 3),
  dataFrom: at(0),
  dataTo: at(120, 1),
  measurementCount: 42,
  sources: const ['strap', 'gps'],
  method: 'm',
  methodVersion: method,
  parameterVersion: 2,
  quality: quality,
  sections: sections,
);

/// Zwei Abschnitte: ein verwendeter und ein abgelehnter mit Gründen.
List<ValueSection> sampleValueSections([int seed = 0]) => [
  ValueSection(
    start: at(10 + seed),
    end: at(310 + seed, 5),
    weight: 5.5 + seed,
    lateFactor: 1,
    status: SectionStatus.provisional,
    reasons: const ['limitedSpeed'],
    gpsMedianAccuracyMeters: 4.25,
    oxygenDemand: 40.5,
    estimate: 47.75 + seed,
  ),
  ValueSection(
    start: at(310 + seed),
    end: at(400 + seed),
    weight: 0,
    lateFactor: 0.5,
    status: SectionStatus.rejected,
    reasons: const ['paceVariation', 'gpsGap'],
  ),
  ValueSection(
    start: at(400 + seed),
    end: at(500 + seed),
    weight: 1.5,
    lateFactor: 1,
    status: SectionStatus.eligible,
    discard: EstimateDiscard.implausible,
    oxygenDemand: 80,
    estimate: 120,
  ),
];

String describeSection(ValueSection s) =>
    '${us(s.start)}-${us(s.end)}|${s.duration.inMicroseconds}|${s.gpsMedianAccuracyMeters}|${s.weight}|${s.lateFactor}|${s.status.name}|${s.reasons}|${s.discard?.name}|${s.oxygenDemand}|${s.estimate}';

String describeRun(StoredRun? r) => r == null
    ? 'null'
    : '${r.id}|${r.state.name}|${us(r.startedAt)}|${us(r.endedAt)}';

String describeValue(ComputedValue v) =>
    '${v.key}|${v.value}|${v.unavailableReason?.name}|${v.unit}|${us(v.computedAt)}|${us(v.dataFrom)}|${us(v.dataTo)}|${v.measurementCount}|${v.sources}|${v.method}|${v.methodVersion}|${v.parameterVersion}|${v.quality.name}|sections=${v.sections.map(describeSection).toList()}';

String describePair(ValuePair p) =>
    'O(${describeValue(p.original)}) C(${describeValue(p.current)})';
