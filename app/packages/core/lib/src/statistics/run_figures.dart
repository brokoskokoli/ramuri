import '../../ports/storage_runs.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recalculation/run_load_values.dart';
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import '../preprocessing/gap_moving_time.dart';
import 'best_pace.dart';
import 'statistics_parameters.dart';

/// Einheit: Meter je Kilometer, Mikrosekunden je Sekunde.
const double _metersPerKilometer = 1000;
const double _microsPerSecond = 1e6;

/// Die Kennzahlen eines beendeten Laufs, die in die Statistik eingehen. Was
/// fehlt, ist `null` (nie 0): ein Lauf ohne Puls hat weder Durchschnitt noch
/// Maximum, ein Lauf ohne Strecke keine Pace.
class RunFigures {
  RunFigures({
    required this.runId,
    required this.endedAt,
    required this.day,
    this.distanceMeters,
    this.movingTime,
    this.totalTime,
    this.paceTime,
    this.bestPaceSecondsPerKm,
    this.lapCount,
    this.heartRateAverageBpm,
    this.heartRateSampleCount = 0,
    this.heartRateMaxBpm,
    this.trimpPoints,
    this.trimpIncomplete = false,
    List<Duration>? zoneTimes,
    this.belowZone1Time,
  }) : zoneTimes = zoneTimes == null ? null : List.unmodifiable(zoneTimes);

  final int runId;
  final DateTime endedAt;

  /// Lokaler Kalendertag des Laufendes, `JJJJ-MM-TT` (K21, `dayOfRun`).
  final String day;

  final double? distanceMeters;
  final Duration? movingTime;
  final Duration? totalTime;

  /// Zeit, die zur Durchschnittspace zählt: Bewegungszeit ohne die Zeit in
  /// Positionslücken (K20).
  final Duration? paceTime;
  final double? bestPaceSecondsPerKm;
  final int? lapCount;

  /// Mittel der akzeptierten Pulswerte und deren Anzahl (Gewicht im Zeitraum).
  final double? heartRateAverageBpm;
  final int heartRateSampleCount;
  final int? heartRateMaxBpm;

  /// Edwards-TRIMP-Punkte und ob der Puls die Bewegungszeit nicht voll abdeckte.
  final double? trimpPoints;
  final bool trimpIncomplete;

  /// Zeit je Herzfrequenzzone (Index 0 = Zone 1) und unter Zone 1 (FR-0063).
  final List<Duration>? zoneTimes;
  final Duration? belowZone1Time;

  /// Durchschnittspace in s/km; `null` ohne Strecke oder Zeit.
  double? get averagePaceSecondsPerKm {
    final d = distanceMeters;
    final t = paceTime;
    if (d == null || t == null || !(d > 0) || t <= Duration.zero) return null;
    return t.inMicroseconds / _microsPerSecond / (d / _metersPerKilometer);
  }

  /// Aus einem beendeten Lauf und seiner Vorverarbeitung (Wiedergabe der
  /// Rohdaten, `replayRunPreprocessing`). Zonen und TRIMP kommen aus den am
  /// Lauf gespeicherten Werten [load], nie aus dem aktuellen Profil; ohne sie
  /// fehlen sie (`null`). Wirft
  /// [ArgumentError], wenn der Lauf nicht beendet ist.
  factory RunFigures.fromRun({
    required StoredRun run,
    required RunPreprocessing preprocessing,
    required List<StoredLap> laps,
    StoredRunLoad load = StoredRunLoad.none,
    StatisticsParameters parameters = const StatisticsParameters(),
  }) {
    final end = run.endedAt;
    if (run.state != RunState.finished || end == null) {
      throw ArgumentError.value(run.id, 'run', 'Lauf ist nicht beendet');
    }
    final movement = preprocessing.movement;
    final hr = preprocessing.heartRate;
    final distance = preprocessing.position.distanceMeters;
    final lossTime = movingTimeInPositionGaps(preprocessing);
    final paceTime = movement.movingTime - lossTime;
    return RunFigures(
      runId: run.id,
      endedAt: end,
      day: dayOfRun(run),
      distanceMeters: distance,
      movingTime: movement.movingTime,
      totalTime: movement.totalTime,
      paceTime: paceTime > Duration.zero ? paceTime : null,
      bestPaceSecondsPerKm: bestPace(
        preprocessing.pace.segments,
        parameters: parameters,
      ).secondsPerKm,
      lapCount: laps.length,
      heartRateAverageBpm: hr.averageBpm,
      heartRateSampleCount: hr.acceptedValues.length,
      heartRateMaxBpm: hr.maxBpm,
      trimpPoints: load.trimpPoints,
      trimpIncomplete: load.trimpIncomplete,
      zoneTimes: load.zoneTimes,
      belowZone1Time: load.belowZone1Time,
    );
  }
}
