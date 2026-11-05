import 'package:core/core.dart';

import 'support.dart';

RawHeartRate hr(
  num sec,
  int bpm, {
  SensorContact contact = SensorContact.good,
  MeasurementState state = MeasurementState.present,
}) => RawHeartRate(
  time: at(sec),
  source: 'test',
  bpm: bpm,
  contact: contact,
  state: state,
);

/// Werte im Sekundentakt von [from] bis [to] (beide inklusive).
List<RawHeartRate> beat(int from, int to, int bpm) => [
  for (var s = from; s <= to; s++) hr(s, bpm),
];

HeartRateResult runHr(
  List<RawHeartRate> values, {
  PreprocessingParameters p = const PreprocessingParameters.v3(),
  num until = 0,
  DateTime? sectionStart,
}) {
  final proc = HeartRateProcessor(p, sectionStart: sectionStart);
  values.forEach(proc.add);
  final last = values.isEmpty ? 0 : values.last.time.difference(t0).inSeconds;
  return proc.result(at: at(until == 0 ? last : until));
}

/// Zustände und Gründe je Eingabe, kurz.
List<String> verdicts(HeartRateResult r) => [
  for (final p in r.processed) '${p.state.name}/${p.reason?.name}',
];

String hrFingerprint(HeartRateResult r) => [
  r.method,
  r.methodVersion,
  r.parameterVersion,
  r.averageBpm,
  r.maxBpm,
  r.medianBpm,
  verdicts(r).join(','),
  r.medianSeries.map((s) => '${s.time}/${s.bpm}').join(','),
  r.gaps.map((g) => '${g.start}-${g.end}-${g.open}').join(','),
].join('|');
