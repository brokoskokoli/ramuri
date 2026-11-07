import 'dart:convert';

import '../../ports/file_handoff.dart';
import '../../ports/storage.dart';
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
  RunFileExportService({required StorageSession session})
    : _runs = RunExportService(session: session);

  final RunExportService _runs;

  /// `null` für einen unbekannten oder nicht beendeten Lauf. Wirft
  /// [StorageException] bei Lesefehlern.
  Future<ExportFile?> build(int runId, ExportFormat format) async {
    final run = await _runs.load(runId, resolution: format.resolution);
    if (run == null) return null;
    return exportFileOf(run, format);
  }
}

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
