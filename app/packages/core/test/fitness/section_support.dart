import 'package:core/core.dart';

final selT0 = DateTime.utc(2030, 1, 1, 12);
DateTime selAt(num sec) =>
    selT0.add(Duration(microseconds: (sec * 1e6).round()));

const double _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Voller Bereich der Grenzen bei HFmax 190, HFRuhe 60 (Reserve 130 bpm):
/// r = 0,55 bei 131,5 bpm, r = 0,85 bei 170,5 bpm.
const selBasis = HeartRateBasis(maxBpm: 190, restingBpm: 60);

/// Ein synthetischer Lauf im Sekundentakt. [speed] gilt für das Segment, das
/// in Sekunde `s` endet.
class SelScenario {
  const SelScenario({
    required this.seconds,
    this.speed = _fast,
    this.accuracy = _five,
    this.bpm = _bpm150,
    this.altitude = _flat,
    this.verticalAccuracy = 3,
    this.dropPositions = const {},
    this.pauses = const [],
  });

  final int seconds;
  final double Function(int s) speed;
  final double? Function(int s) accuracy;
  final int? Function(int s) bpm;

  /// Höhe aus Sekunde und zurückgelegten Metern; `null` lässt den Wert weg.
  final double? Function(int s, double meters) altitude;
  final double? verticalAccuracy;
  final Set<int> dropPositions;
  final List<(int, int)> pauses;

  /// 3 m/s = 180 m/min, deutlich über PAR-030.
  static double _fast(int s) => 3.0;
  static double? _five(int s) => 5;
  static int? _bpm150(int s) => 150;
  static double? _flat(int s, double m) => 100;
}

bool _paused(SelScenario sc, int s) =>
    sc.pauses.any((p) => s > p.$1 && s < p.$2);

RunPreprocessing buildRun(SelScenario sc) {
  final pre = RunPreprocessor(start: selT0);
  var north = 0.0;
  final pauseAt = {for (final p in sc.pauses) p.$1};
  final resumeAt = {for (final p in sc.pauses) p.$2};
  for (var s = 0; s <= sc.seconds; s++) {
    if (s > 0) north += sc.speed(s);
    final inPause = _paused(sc, s);
    if (resumeAt.contains(s)) pre.resume(selAt(s));
    if (inPause) continue;
    if (!sc.dropPositions.contains(s)) {
      pre.addPosition(
        RawPosition(
          time: selAt(s),
          source: 'test',
          latitude: 10 + north / _metersPerDegree,
          longitude: 20,
          accuracyMeters: sc.accuracy(s),
        ),
      );
    }
    final bpm = sc.bpm(s);
    if (bpm != null) {
      pre.addHeartRate(
        RawHeartRate(
          time: selAt(s),
          source: 'test',
          bpm: bpm,
          contact: SensorContact.good,
        ),
      );
    }
    final h = sc.altitude(s, north);
    if (h != null) {
      pre.addAltitude(
        RawAltitude(
          time: selAt(s),
          source: 'test',
          meters: h,
          verticalAccuracyMeters: sc.verticalAccuracy,
        ),
      );
    }
    if (pauseAt.contains(s)) pre.pause(selAt(s));
  }
  return pre.result(at: selAt(sc.seconds));
}

SectionSelection selectSections(
  SelScenario sc, {
  Duration? runStartOffset,
  HeartRateBasis basis = selBasis,
  FitnessParameters parameters = const FitnessParameters.v3(),
}) => Vo2maxSectionSelector(parameters: parameters).select(
  run: buildRun(sc),
  basis: basis,
  runStart: selT0.subtract(runStartOffset ?? Duration.zero),
  until: selAt(sc.seconds),
);

/// Lauf, der nach der Einschwingzeit (180 s) genau [usable] Sekunden nutzbar ist.
SelScenario steady(
  int usable, {
  double Function(int s)? speed,
  double? Function(int s)? accuracy,
  int? Function(int s)? bpm,
  double? Function(int s, double m)? altitude,
  double? verticalAccuracy = 3,
  Set<int> dropPositions = const {},
}) => SelScenario(
  seconds: 180 + usable,
  speed: speed ?? (s) => 3.0,
  accuracy: accuracy ?? (s) => 5,
  bpm: bpm ?? (s) => 150,
  altitude: altitude ?? (s, m) => 100,
  verticalAccuracy: verticalAccuracy,
  dropPositions: dropPositions,
);

/// Rules der verletzten Regeln eines Abschnitts.
Set<SectionRule> rulesOf(EvaluatedSection s) => {
  for (final v in s.violations) v.rule,
};
