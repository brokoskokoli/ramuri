import 'dart:convert';

import '../../ports/file_handoff.dart';
import '../../ports/storage.dart';
import '../../ports/storage_raw.dart';
import '../../ports/storage_runs.dart';
import '../statistics/offload.dart';
import 'export_run.dart';
import 'fit_encoder.dart';
import 'gpx_encoder.dart';
import 'tcx_encoder.dart';

/// Exportformate eines Laufs (FR-0182, Vertrag `docs/contracts/file-export.md`).
enum ExportFormat {
  gpx('gpx', 'application/gpx+xml', exportMillisecond),
  tcx('tcx', 'application/vnd.garmin.tcx+xml', exportMillisecond),
  fit('fit', 'application/vnd.ant.fit', exportSecond);

  const ExportFormat(this.extension, this.mimeType, this.resolution);

  final String extension;
  final String mimeType;

  /// Zeitauflösung des Formats (FIT: ganze Sekunden).
  final Duration resolution;
}

/// Baut aus einem gespeicherten Lauf die Datei eines Formats; die Übergabe
/// an das System macht [FileHandoff].
class RunFileExportService {
  RunFileExportService({required this.session, this.offload = inlineOffload});

  final StorageSession session;

  /// Wo Abbildung und Kodierung rechnen (in der App ein eigener Isolate);
  /// das Lesen bleibt im aufrufenden Isolate.
  final Offload offload;

  /// `null` für einen unbekannten oder nicht beendeten Lauf. Wirft
  /// [StorageException] bei Lesefehlern.
  Future<ExportFile?> build(int runId, ExportFormat format) async {
    final run = await session.runs.get(runId);
    if (run == null || run.state != RunState.finished || run.endedAt == null) {
      return null;
    }
    return offload(exportFileJob, (
      run: run,
      raw: await session.rawData.read(runId),
      gaps: await session.markers.gaps(runId),
      laps: await session.markers.laps(runId),
      format: format,
    ));
  }
}

/// Eingabe von [exportFileJob]: alles Gelesene, sendbar an einen Isolate.
typedef ExportFileInput = ({
  StoredRun run,
  StoredRawData raw,
  List<StoredGap> gaps,
  List<StoredLap> laps,
  ExportFormat format,
});

/// Reine Rechnung für [Offload]: Abbildung und Kodierung eines beendeten
/// Laufs.
ExportFile exportFileJob(ExportFileInput input) => exportFileOf(
  buildExportRun(
    run: input.run,
    raw: input.raw,
    gaps: input.gaps,
    laps: input.laps,
    resolution: input.format.resolution,
  ),
  input.format,
);

/// Kodiert [run] im [format]. [run] muss mit `format.resolution` gebaut sein
/// (FIT wirft sonst [ArgumentError]). GPX und TCX als UTF-8.
ExportFile exportFileOf(ExportRun run, ExportFormat format) => ExportFile(
  fileName: run.fileName(format.extension),
  mimeType: format.mimeType,
  bytes: switch (format) {
    ExportFormat.gpx => utf8.encode(encodeGpx(run)),
    ExportFormat.tcx => utf8.encode(encodeTcx(run)),
    ExportFormat.fit => encodeFit(run),
  },
);
