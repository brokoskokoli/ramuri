/// Bewegungszeit einer anderen Sportart (FR-0221, PAR-232): Aufzeichnungszeit
/// ohne die Zeiten mit Pause-Taste (und ohne Unterbrechungen nach einem
/// Prozessende, FR-0193). Keine Autopause, keine Stillstandserkennung; Pausen
/// zwischen Runden ohne Pause-Taste zählen mit. Reine Werte, ohne Flutter.
library;

import '../../ports/storage_runs.dart';
import 'treadmill.dart';

/// Zeit von [start] bis [end] ohne die Vereinigung der [pauses] (jeweils auf
/// den Bereich beschnitten; überlappende Pausen zählen einmal). Nie negativ.
Duration activeTimeWithoutPauses({
  required DateTime start,
  required DateTime end,
  required List<(DateTime, DateTime)> pauses,
}) {
  if (!end.isAfter(start)) return Duration.zero;
  final cuts = [
    for (final (ps, pe) in pauses)
      if (pe.isAfter(start) && ps.isBefore(end) && pe.isAfter(ps))
        (ps.isBefore(start) ? start : ps, pe.isAfter(end) ? end : pe),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  var paused = Duration.zero;
  DateTime? curStart;
  DateTime? curEnd;
  for (final (ps, pe) in cuts) {
    if (curEnd != null && !ps.isAfter(curEnd)) {
      if (pe.isAfter(curEnd)) curEnd = pe;
      continue;
    }
    if (curStart != null) paused += curEnd!.difference(curStart);
    curStart = ps;
    curEnd = pe;
  }
  if (curStart != null) paused += curEnd!.difference(curStart);
  return end.difference(start) - paused;
}

/// Bewegungszeit einer beendeten Sporteinheit aus den gespeicherten Lücken
/// (PAR-232); `null`, wenn [run] keine andere Sportart ist.
Duration? sportMovingTimeOfRun(
  StoredRun run,
  DateTime end,
  List<StoredGap> gaps,
) {
  if (run.mode != RunMode.sport) return null;
  return activeTimeWithoutPauses(
    start: run.startedAt,
    end: end,
    pauses: [
      for (final g in gaps)
        if (g.kind == RunGapKind.manualPause ||
            g.kind == RunGapKind.interruption)
          (g.start, g.end ?? end),
    ],
  );
}
