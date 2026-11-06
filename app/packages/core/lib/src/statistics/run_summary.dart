import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import '../preprocessing/preprocessing_parameters.dart';
import '../preprocessing/run_preprocessor.dart';
import '../recalculation/run_analysis.dart';
import '../recalculation/run_load_values.dart';
import 'best_pace.dart';
import 'classification.dart';
import 'offload.dart';
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
    required this.load,
    required this.bestPace,
    required this.classification,
    required this.vo2max,
    this.manualPauses = const [],
  });

  final StoredRun run;

  /// Strecke, Zeiten, Puls, Bestpace, Runden, TRIMP und Zonen (Teile `null`,
  /// wenn nicht verfügbar).
  final RunFigures figures;
  final RunPreprocessing preprocessing;
  final List<StoredLap> laps;

  /// Zonenzeiten und TRIMP, wie am Lauf gespeichert (Entscheidung 2026-11-06),
  /// nie mit dem aktuellen Profil neu gerechnet.
  final StoredRunLoad load;
  final BestPace bestPace;
  final RunClassification classification;

  /// Gespeicherter Laufwert der VO₂max-Schätzung (WP09), `null`, wenn (noch)
  /// keiner vorliegt. Trägt bei „nicht bestimmbar“ den Grund.
  final ComputedValue? vo2max;

  /// Manuelle Pausen des Laufs (für die Zeichnung der Lücken).
  final List<TimeSpan> manualPauses;

  /// Anstieg in Metern; `null` ohne Höhendaten.
  double? get ascentMeters => preprocessing.altitude.ascentMeters;

  /// Anzahl Positionslücken (FR-0194).
  int get positionGapCount => preprocessing.position.gaps.length;
}

/// Liest und rechnet alles für die Zusammenfassung eines beendeten Laufs aus
/// den Rohdaten (ADR-0004 Punkt 1); Zonenzeiten und TRIMP kommen aus den am
/// Lauf gespeicherten Werten.
class RunSummaryService {
  RunSummaryService({
    required this.session,
    required this.clock,
    this.preprocessing = const PreprocessingParameters.v4(),
    this.statistics = const StatisticsParameters(),
    this.offload = inlineOffload,
  });

  final StorageSession session;
  final Clock clock;
  final PreprocessingParameters preprocessing;
  final StatisticsParameters statistics;

  /// Wo die reine Wiedergabe der Rohdaten rechnet (in der App ein eigener
  /// Isolate); Lesen und Speichern bleiben im aufrufenden Isolate.
  final Offload offload;

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
    final pre = await offload(replayJob, (
      run: run,
      end: end,
      raw: raw,
      gaps: gaps,
      parameters: preprocessing,
    ));
    final values = await session.values.read(ValueOwner.run(runId));
    final load = StoredRunLoad.fromValues({
      for (final v in values)
        if (runLoadValueKeys.contains(v.current.key)) v.current.key: v.current,
    });
    final figures = RunFigures.fromRun(
      run: run,
      preprocessing: pre,
      laps: laps,
      load: load,
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
    ComputedValue? vo2;
    for (final v in values) {
      if (v.current.key == vo2maxRunValueKey) vo2 = v.current;
    }
    return RunSummary(
      run: run,
      figures: figures,
      preprocessing: pre,
      laps: laps,
      load: load,
      bestPace: bestPace(pre.pace.segments, parameters: statistics),
      classification: classifyRun(figures, others, parameters: statistics),
      vo2max: vo2,
      manualPauses: [
        for (final g in gaps)
          if (g.kind == RunGapKind.manualPause)
            TimeSpan(start: g.start, end: g.end ?? end),
      ],
    );
  }
}
