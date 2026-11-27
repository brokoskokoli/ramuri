import '../../ports/storage_derived.dart';
import 'best_pace.dart';
import '../preprocessing/gap_moving_time.dart'
    show movingTimeWithHeartRate, positionLossSpans;
import '../preprocessing/run_preprocessor.dart';
import '../recording/belt_track.dart';

/// Kennung der gespeicherten Kurzfassung (`PreprocessingSummary.method`).
const String runOverviewMethod = 'run-overview';

/// Version 2 (WP10): trägt zusätzlich Bestpace, Rundenzahl und die Zeit mit
/// Puls; gespeicherte Kurzfassungen der Version 1 werden beim Lesen neu
/// gerechnet. Ändert sich ein Parameter der Bestpace
/// ([StatisticsParameters.bestPaceDistanceMeters]), ist die Version anzuheben.
///
/// Version 3 (WP25): Laufbandläufe tragen Strecke und Bewegungszeit aus den
/// Bandeinstellungen; ältere Kurzfassungen (Strecke 0 m) werden neu gerechnet.
///
/// Version 4 (M2-Abschluss): die Spannen `positionGap` tragen auch die Wartezeit
/// auf den ersten Punkt eines Abschnitts (bis PAR-004); ältere Kurzfassungen
/// rechnen die Pace-Zeit ohne sie und werden neu gerechnet.
const int runOverviewMethodVersion = 4;

/// Die Kurzfassung eines Laufs für Listen und Vergleiche, abgeleitet aus der
/// Vorverarbeitung (ADR-0004 Punkt 1: jederzeit aus den Rohdaten neu
/// berechenbar). Gespeichert werden die Zusammenfassung und die Spannen
/// `moving` und `positionGap`; Messwert-Zeilen nicht.
StoredPreprocessing overviewOf(
  RunPreprocessing pre, {
  required DateTime computedAt,
  int? lapCount,
  BeltTrack? belt,
  bool isRunning = true,
}) {
  final beltSpans = belt == null
      ? null
      : [
          for (final p in belt.pieces)
            if (p.isMoving) p.span,
        ];
  return StoredPreprocessing(
    summary: PreprocessingSummary(
      method: runOverviewMethod,
      methodVersion: runOverviewMethodVersion,
      parameterVersion: pre.parameterVersion,
      computedAt: computedAt,
      totalTime: pre.movement.totalTime,
      // Bandlauf (FR-0196): Strecke und Bewegungszeit aus den Einstellungen,
      // keine überbrückte Strecke, keine Bestpace (nur eingestellt, K57).
      movingTime: belt?.moving ?? pre.movement.movingTime,
      // Andere Sportart (FR-0221): keine Strecke und keine Pace.
      distanceMeters: !isRunning
          ? null
          : belt?.meters ?? pre.position.distanceMeters,
      bridgedDistanceMeters: !isRunning
          ? null
          : belt == null
          ? pre.position.bridgedDistanceMeters
          : 0,
      averageBpm: pre.heartRate.averageBpm,
      maxBpm: pre.heartRate.maxBpm,
      bestPaceSecondsPerKm: belt != null || !isRunning
          ? null
          : bestPace(pre.pace.segments).secondsPerKm,
      lapCount: lapCount,
      heartRateTime: movingTimeWithHeartRate(pre, movingIntervals: beltSpans),
    ),
    spans: [
      for (final m in beltSpans ?? pre.movement.movingIntervals)
        PreprocessedSpan(
          kind: PreprocessedSpanKind.moving,
          start: m.start,
          end: m.end,
        ),
      for (final g in belt == null ? positionLossSpans(pre) : const [])
        PreprocessedSpan(
          kind: PreprocessedSpanKind.positionGap,
          start: g.start,
          end: g.end,
        ),
    ],
  );
}
