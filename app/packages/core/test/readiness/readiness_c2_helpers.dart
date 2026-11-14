import 'package:core/core.dart';

final today = DateTime.utc(2026, 11, 14);
final now = DateTime.utc(2026, 11, 14, 8);

DeviationResult dev(
  ReadinessFactor f,
  double z, {
  int ref = 28,
  ReadinessSource source = ReadinessSource.healthConnect,
  MorningSeriesKey? key,
  bool few = false,
}) => DeviationResult(
  factor: f,
  source: source,
  origin: source == ReadinessSource.healthConnect ? 'app.a' : null,
  cameraSeries: key,
  z: z,
  windowCount: 7,
  referenceCount: ref,
  fewMeasurements: few,
);

DeviationResult noZ(
  ReadinessFactor f,
  NoDeviationReason r, {
  int ref = 0,
  ReadinessSource source = ReadinessSource.healthConnect,
}) => DeviationResult(
  factor: f,
  source: source,
  origin: 'app.a',
  reason: r,
  referenceCount: ref,
);

/// Schlafsitzung mit [hours] Schlafzeit; mit [eff] Prozent Effizienz aus
/// Phasen, sonst ohne Phasen (Schätzung).
SleepSession night(double hours, {double? eff}) {
  final sleepMs = (hours * 3600000).round();
  final totalMs = eff == null ? sleepMs : (sleepMs * 100 / eff).round();
  final end = now.subtract(const Duration(hours: 1));
  final start = end.subtract(Duration(milliseconds: totalMs));
  return SleepSession(
    origin: 'app.s',
    start: start,
    end: end,
    stages: eff == null
        ? const []
        : [
            SleepStage(
              kind: SleepStageKind.sleeping,
              start: start,
              end: start.add(Duration(milliseconds: sleepMs)),
            ),
            SleepStage(
              kind: SleepStageKind.awake,
              start: start.add(Duration(milliseconds: sleepMs)),
              end: end,
            ),
          ],
  );
}

ReadinessInputs inputs({
  double? hrvZ,
  double? rhrZ,
  double? hours,
  double? eff,
  SleepBand? band,
  double? tsb,
  int? wellbeing,
  int hrvRef = 28,
  int span = 0,
  bool few = false,
}) => ReadinessInputs(
  today: today,
  now: now,
  hrvHealthConnect: hrvZ == null
      ? null
      : dev(ReadinessFactor.hrv, hrvZ, ref: hrvRef),
  restingHrHealthConnect: rhrZ == null
      ? null
      : dev(ReadinessFactor.restingHeartRate, rhrZ),
  sleepSessions: hours == null ? const [] : [night(hours, eff: eff)],
  sleepBand: band,
  tsbPercent: tsb,
  wellbeing: wellbeing == null
      ? null
      : ReadinessWellbeing(level: wellbeing, day: today),
  hrvSourceSpanDays: span,
);

/// Alle Bedingungen für „gut“ (PAR-150) ohne weitere Abweichungen.
ReadinessInputs goodInputs({
  int hrvRef = 21,
  int span = 28,
  double? eff = 95,
  double? tsb = -5,
  double? rhrZ = 0,
}) => inputs(
  hrvZ: 0,
  rhrZ: rhrZ,
  hours: 7,
  eff: eff,
  tsb: tsb,
  hrvRef: hrvRef,
  span: span,
);
