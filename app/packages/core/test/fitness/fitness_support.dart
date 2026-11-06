import 'package:core/core.dart';

final fitT0 = DateTime.utc(2026, 1, 1, 10);
DateTime fitAt(int s) => fitT0.add(Duration(seconds: s));
TimeSpan fitSpan(int a, int b) => TimeSpan(start: fitAt(a), end: fitAt(b));
RawHeartRate fitHr(int s, int bpm) =>
    RawHeartRate(time: fitAt(s), source: 'x', bpm: bpm);
HeartRateGap fitGap(int a, int b) =>
    HeartRateGap(start: fitAt(a), end: fitAt(b), open: false);

/// Dichte Serie: ein Wert alle [step] Sekunden in `[from, to]`.
List<RawHeartRate> fitDense(int from, int to, int bpm, {int step = 1}) => [
  for (var s = from; s <= to; s += step) fitHr(s, bpm),
];

/// Pulsergebnis aus bereits bewerteten Werten (wie ihn der Prozessor liefert:
/// akzeptierte Werte als `present`, [discarded] als verworfen).
HeartRateResult fitHeartRate(
  List<RawHeartRate> accepted, {
  List<HeartRateGap> gaps = const [],
  List<RawHeartRate> discarded = const [],
  int version = currentParameterVersion,
}) {
  final processed = [
    for (final h in accepted)
      ProcessedHeartRate(input: h, state: MeasurementState.present),
    for (final h in discarded)
      ProcessedHeartRate(
        input: h,
        state: MeasurementState.discarded,
        reason: DiscardReason.heartRateOutlier,
      ),
  ]..sort((a, b) => a.input.time.compareTo(b.input.time));
  return HeartRateResult(
    parameterVersion: version,
    processed: processed,
    acceptedValues: accepted,
    gaps: gaps,
    averageBpm: null,
    maxBpm: null,
    medianBpm: null,
    medianSeries: const [],
  );
}

MovementResult fitMovement(
  List<TimeSpan> moving, {
  int version = currentParameterVersion,
}) => MovementResult(
  parameterVersion: version,
  totalTime: Duration.zero,
  movingTime: Duration.zero,
  movingIntervals: moving,
  autoPauseState: AutoPauseState.moving,
  manuallyPaused: false,
  resumedAt: const [],
);
