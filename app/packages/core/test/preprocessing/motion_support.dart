import 'package:core/core.dart';

import 'support.dart';

/// Punkte im Takt [dt] s ab Sekunde [from] und [north] m. Jede Strecke
/// (Dauer in s, Tempo in m/s) liefert Punkte an ihrem Ende; der Startpunkt
/// steht bei [from], wenn [first] gesetzt ist.
List<RawPosition> track(
  List<(num, num)> legs, {
  num dt = 1,
  num from = 0,
  num north = 0,
  double acc = 5,
  bool first = true,
}) {
  final out = <RawPosition>[if (first) pos(from, north, acc: acc)];
  var k = 0;
  var n = north.toDouble();
  for (final (duration, speed) in legs) {
    final steps = (duration / dt).round();
    for (var i = 0; i < steps; i++) {
      k++;
      n += speed * dt;
      out.add(pos(from + k * dt, n, acc: acc));
    }
  }
  return out;
}

RunPreprocessor feed(
  List<RawPosition> points, {
  PreprocessingParameters p = const PreprocessingParameters.v2(),
}) {
  final r = RunPreprocessor(start: t0, parameters: p);
  points.forEach(r.addPosition);
  return r;
}

double speedOf(PaceDisplay d) => switch (d) {
  PaceValue(:final secondsPerKm) => 1000 / secondsPerKm,
  _ => double.nan,
};

String _pace(PaceDisplay d) => switch (d) {
  PaceValue(:final secondsPerKm) => 'v$secondsPerKm',
  PaceStandstill() => 'stand',
  PaceNoData() => 'nodata',
};

/// Vergleichbarer Abdruck von Tempo und Bewegungszeit.
String motionFingerprint(RunPreprocessing r) => [
  r.pace.method,
  r.pace.methodVersion,
  r.pace.parameterVersion,
  r.pace.liveSpeed,
  _pace(r.pace.livePace),
  r.pace.liveCountedTime,
  r.pace.medianSpeed,
  _pace(r.pace.medianPace),
  r.pace.medianSeries.map((s) => '${s.time}/${s.metersPerSecond}').join(','),
  r.movement.method,
  r.movement.methodVersion,
  r.movement.parameterVersion,
  r.movement.totalTime,
  r.movement.movingTime,
  r.movement.autoPauseState.name,
  r.movement.manuallyPaused,
  r.movement.movingIntervals.map((i) => '${i.start}-${i.end}').join(','),
].join('|');
