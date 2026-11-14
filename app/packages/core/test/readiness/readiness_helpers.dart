import 'package:core/core.dart';

// Zeitzonenfest: Tage aus lokalen Mitternächten (wie localDayRanges).
final days = localDayRanges(DateTime(2026, 10, 17), 29); // letzter: 14.11.
final todayKey = DateTime.utc(2026, 11, 14);
const p = HealthProcessing();

DateTime at(int dayIdx, int h) {
  final d = DateTime(2026, 10, 17 + dayIdx, h);
  return d.toUtc();
}

/// RHR-Proben: je Tag ein Wert je Quelle; [values] null = Tag fehlt.
List<HealthSample> rhrSamples(String origin, List<double?> values) => [
  for (var i = 0; i < values.length; i++)
    if (values[i] != null)
      HealthSample(time: at(i, 7), value: values[i]!, origin: origin),
];

/// Wertefolge für 29 Tage, deterministisch, Streuung > MAD-Grenze.
List<double?> wave(double base, {int from = 0, int to = 29}) => [
  for (var i = 0; i < 29; i++) i >= from && i < to ? base + (i % 5) * 2 : null,
];

HealthSample hrvSample(String origin, int dayIdx, double v) =>
    HealthSample(time: at(dayIdx, 3), value: v, origin: origin);

SleepSession sleep(String origin, int dayIdx) =>
    SleepSession(origin: origin, start: at(dayIdx - 1, 22), end: at(dayIdx, 6));

MorningMeasurement morning({
  required int dayIdx,
  double hr = 58,
  double? rmssd = 42,
  RestingPosture posture = RestingPosture.lying,
  String model = 'M1',
  PpgQuality quality = PpgQuality.good,
  double? noise = 10,
  bool outside = false,
  bool before = false,
  int hour = 7,
}) => MorningMeasurement(
  measuredAt: DateTime(2026, 10, 17 + dayIdx, hour).toUtc(),
  utcOffset: DateTime(2026, 10, 17 + dayIdx, hour).timeZoneOffset,
  posture: posture,
  deviceManufacturer: 'H',
  deviceModel: model,
  method: 'ppg',
  methodVersion: 1,
  quality: quality,
  restingHrBpm: hr,
  rmssdMs: rmssd,
  timingNoiseMs: noise,
  cameraIntervalsMs: const [],
  beforeValidation: before,
  outsideWindow: outside,
);

DeviationResult hcRhr(List<HealthSample> s) =>
    healthConnectRestingHrDeviation(processing: p, samples: s, days: days);
