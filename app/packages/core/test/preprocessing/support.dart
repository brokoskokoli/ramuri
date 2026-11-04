import 'dart:math' as math;

import 'package:core/core.dart';

final DateTime t0 = DateTime.utc(2030, 1, 1, 12);

const double _metersPerDegree = earthRadiusMeters * math.pi / 180;

/// Synthetischer Punkt: [sec] nach t0, [north] Meter nördlich eines
/// erfundenen Nullpunkts bei (10, 20).
RawPosition pos(
  num sec,
  num north, {
  double? acc = 5,
  MeasurementState state = MeasurementState.present,
}) => RawPosition(
  time: t0.add(Duration(microseconds: (sec * 1e6).round())),
  source: 'test',
  latitude: 10 + north / _metersPerDegree,
  longitude: 20,
  accuracyMeters: acc,
  state: state,
);

DateTime at(num sec) => t0.add(Duration(microseconds: (sec * 1e6).round()));

/// Abstand zweier Testpunkte nach der Produktformel.
double dist(RawPosition a, RawPosition b) =>
    haversineMeters(a.latitude, a.longitude, b.latitude, b.longitude);

PositionProcessor processor([
  PreprocessingParameters p = const PreprocessingParameters.v2(),
]) => PositionProcessor(p);

PositionResult run(
  List<RawPosition> points, {
  PreprocessingParameters p = const PreprocessingParameters.v2(),
  num? until,
}) {
  final proc = PositionProcessor(p);
  points.forEach(proc.add);
  return proc.result(
    at: at(until ?? points.last.time.difference(t0).inSeconds),
  );
}

/// Vergleichbarer Abdruck eines Ergebnisses.
String fingerprint(PositionResult r) => [
  r.method,
  r.methodVersion,
  r.parameterVersion,
  r.distanceMeters,
  r.bridgedDistanceMeters,
  r.positions
      .map(
        (p) => '${p.state.name}/${p.reason?.name}/${p.countedDistanceMeters}',
      )
      .join(','),
  r.gaps.map((g) => '${g.start}-${g.end}-${g.open}').join(','),
].join('|');
