import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/edwards_trimp.dart';
import '../fitness/fitness_result.dart';
import '../fitness/heart_rate_reserve.dart';
import '../fitness/reserve_zones.dart';
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';
import '../profile/heart_rate_resolution.dart';
import '../recalculation/run_analysis.dart';
import '../settings/reserve_zone_settings.dart';
import 'best_pace.dart';
import 'classification.dart';
import 'run_figures.dart';
import 'run_overview.dart';
import 'statistics_parameters.dart';

/// Alles, was die Zusammenfassung nach dem Lauf zeigt (FR-0037). Was fehlt, ist
/// `null` beziehungsweise trägt einen Grund; nie 0.
class RunSummary {
  RunSummary({
    required this.run,
    required this.figures,
    required this.preprocessing,
    required this.laps,
    required this.trimp,
    required this.zones,
    required this.bestPace,
    required this.classification,
    required this.vo2max,
  });

  final StoredRun run;

  /// Strecke, Zeiten, Puls, Bestpace, Runden, TRIMP und Zonen (Teile `null`,
  /// wenn nicht verfügbar).
  final RunFigures figures;
  final RunPreprocessing preprocessing;
  final List<StoredLap> laps;
  final FitnessResult<TrimpResult> trimp;
  final FitnessResult<ReserveZoneTimes> zones;
  final BestPace bestPace;
  final RunClassification classification;

  /// Gespeicherter Laufwert der VO₂max-Schätzung (WP09), `null`, wenn (noch)
  /// keiner vorliegt. Trägt bei „nicht bestimmbar“ den Grund.
  final ComputedValue? vo2max;

  /// Anstieg in Metern; `null` ohne Höhendaten.
  double? get ascentMeters => preprocessing.altitude.ascentMeters;

  /// Anzahl Positionslücken (FR-0194).
  int get positionGapCount => preprocessing.position.gaps.length;
}

/// Liest und rechnet alles für die Zusammenfassung eines beendeten Laufs aus
/// den Rohdaten (ADR-0004 Punkt 1). Zonenzeiten werden nicht gespeichert (WP09).
class RunSummaryService {
  RunSummaryService({
    required this.session,
    required this.clock,
    this.preprocessing = const PreprocessingParameters.v4(),
    this.statistics = const StatisticsParameters(),
  });

  final StorageSession session;
  final Clock clock;
  final PreprocessingParameters preprocessing;
  final StatisticsParameters statistics;

  /// `null` für einen unbekannten oder nicht beendeten Lauf. Wirft
  /// [StorageException] bei Lesefehlern.
  Future<RunSummary?> load(int runId) async {
    final run = await session.runs.get(runId);
    final end = run?.endedAt;
    if (run == null || run.state != RunState.finished || end == null) {
      return null;
    }
    final raw = await session.rawData.read(runId);
    final gaps = await session.markers.gaps(runId);
    final laps = await session.markers.laps(runId);
    final pre = replayRunPreprocessing(
      run: run,
      end: end,
      raw: raw,
      gaps: gaps,
      parameters: preprocessing,
    );
    final fitness = await ReserveZoneSettings.loadParameters(session.settings);
    final basis = resolveHeartRate(
      await session.profile.read(),
      currentYear: clock.now().year,
      fitness: fitness,
    ).basis;
    final trimp = const EdwardsTrimp().compute(
      basis: basis,
      heartRate: pre.heartRate,
      movement: pre.movement,
      p: fitness,
    );
    final zones = const ReserveZones(reserve: HeartRateReserve()).timeInZones(
      basis: basis,
      heartRate: pre.heartRate,
      movement: pre.movement,
      p: fitness,
    );
    final figures = RunFigures.fromRun(
      run: run,
      preprocessing: pre,
      laps: laps,
      trimp: trimp is FitnessAvailable<TrimpResult> ? trimp.value : null,
      zones: zones is FitnessAvailable<ReserveZoneTimes> ? zones.value : null,
      parameters: statistics,
    );
    final others = [
      for (final o in await RunOverviewService(
        session: session,
        clock: clock,
        parameters: preprocessing,
      ).load())
        if (o.run.id != runId) o.toFigures(),
    ];
    final values = await session.values.read(ValueOwner.run(runId));
    ComputedValue? vo2;
    for (final v in values) {
      if (v.current.key == vo2maxRunValueKey) vo2 = v.current;
    }
    return RunSummary(
      run: run,
      figures: figures,
      preprocessing: pre,
      laps: laps,
      trimp: trimp,
      zones: zones,
      bestPace: bestPace(pre.pace.segments, parameters: statistics),
      classification: classifyRun(figures, others, parameters: statistics),
      vo2max: vo2,
    );
  }
}
