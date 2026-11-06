import 'package:core/core.dart';

final DateTime sBase = DateTime.utc(2030, 1, 1, 8);

/// Segment von Sekunde [a] bis [b] (seit [sBase]) mit [meters] Strecke.
MotionSegment seg(num a, num b, num meters, {bool gap = false}) =>
    MotionSegment(
      start: sBase.add(Duration(microseconds: (a * 1e6).round())),
      end: sBase.add(Duration(microseconds: (b * 1e6).round())),
      meters: gap ? 0 : meters.toDouble(),
      isGap: gap,
    );

/// Aneinander anschließende Segmente: je (Dauer s, Strecke m), ab [from] s.
List<MotionSegment> chain(List<(num, num)> legs, {num from = 0}) {
  final out = <MotionSegment>[];
  var t = from;
  for (final (d, m) in legs) {
    out.add(seg(t, t + d, m));
    t += d;
  }
  return out;
}

/// Lauf mit gegebenen Kennzahlen; Tag und Ende aus [day] (UTC-Mittag).
RunFigures figures(
  int id,
  String day, {
  double? km,
  int? movingSec,
  int? paceSec,
  double? best,
  int? laps,
  double? hrAvg,
  int hrCount = 0,
  int? hrMax,
  double? trimp,
  bool trimpIncomplete = false,
  List<int>? zonesSec,
  int? belowSec,
  int hour = 12,
}) => RunFigures(
  runId: id,
  endedAt: DateTime.parse('${day}T${hour.toString().padLeft(2, '0')}:00:00Z'),
  day: day,
  distanceMeters: km == null ? null : km * 1000,
  movingTime: movingSec == null ? null : Duration(seconds: movingSec),
  totalTime: movingSec == null ? null : Duration(seconds: movingSec + 60),
  paceTime: paceSec == null ? null : Duration(seconds: paceSec),
  bestPaceSecondsPerKm: best,
  lapCount: laps,
  heartRateAverageBpm: hrAvg,
  heartRateSampleCount: hrCount,
  heartRateMaxBpm: hrMax,
  trimpPoints: trimp,
  trimpIncomplete: trimpIncomplete,
  zoneTimes: zonesSec == null
      ? null
      : [for (final s in zonesSec) Duration(seconds: s)],
  belowZone1Time: belowSec == null ? null : Duration(seconds: belowSec),
);
