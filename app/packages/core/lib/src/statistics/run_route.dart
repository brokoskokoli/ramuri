import '../../ports/storage.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import '../preprocessing/preprocessing_parameters.dart';
import '../recalculation/run_analysis.dart';
import 'offload.dart';
import 'run_detail.dart';

/// Höchstzahl der Punkte einer Route für die Miniatur (WP13 D): sie ist klein, mehr Punkte sind nicht zu sehen.
const int runRouteThumbnailMaxPoints = 300;

/// [buildRunRoute] als Auftrag für einen anderen Isolate: Wiedergabe und Route in einem Zug, damit nur die kleine
/// Route zurückgeht und nicht die ganze Vorverarbeitung.
List<List<RoutePoint>> runRouteJob(
  ({
    StoredRun run,
    DateTime end,
    StoredRawData raw,
    List<StoredGap> gaps,
    PreprocessingParameters parameters,
    int maxPoints,
  })
  a,
) => buildLiveRoute(
  replayJob((
    run: a.run,
    end: a.end,
    raw: a.raw,
    gaps: a.gaps,
    parameters: a.parameters,
  )),
  pauses: [
    for (final g in a.gaps)
      if (g.kind == RunGapKind.manualPause)
        TimeSpan(start: g.start, end: g.end ?? a.end),
  ],
  maxPoints: a.maxPoints,
);

/// Liest die Route eines beendeten Laufs, wenn sie gebraucht wird (Miniatur im Verlauf): Positionen, an Pausen und
/// Lücken geteilt, auf [maxPoints] ausgedünnt. Nichts bleibt im Speicher; der Aufrufer hält höchstens die kleine
/// Route. Leer für einen Lauf ohne Positionen (Laufband), einen unbekannten oder nicht beendeten Lauf. Wirft
/// [StorageException] bei Lesefehlern.
Future<List<List<RoutePoint>>> loadRunRoute(
  StorageSession session,
  int runId, {
  Offload offload = inlineOffload,
  PreprocessingParameters parameters = const PreprocessingParameters.v4(),
  int maxPoints = runRouteThumbnailMaxPoints,
}) async {
  final run = await session.runs.get(runId);
  final end = run?.endedAt;
  if (run == null || run.state != RunState.finished || end == null) {
    return const [];
  }
  final raw = await session.rawData.read(runId);
  if (raw.positions.isEmpty) return const [];
  final gaps = await session.markers.gaps(runId);
  return offload(runRouteJob, (
    run: run,
    end: end,
    raw: raw,
    gaps: gaps,
    parameters: parameters,
    maxPoints: maxPoints,
  ));
}
