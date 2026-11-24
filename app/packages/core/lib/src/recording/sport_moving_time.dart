/// Bewegungszeit einer anderen Sportart (FR-0221, PAR-232): Aufzeichnungszeit
/// ohne die Zeiten mit Pause-Taste (und ohne Unterbrechungen nach einem
/// Prozessende, FR-0193). Keine Autopause, keine Stillstandserkennung; Pausen
/// zwischen Runden ohne Pause-Taste zählen mit. Reine Werte, ohne Flutter.
library;

import '../../ports/storage_runs.dart';
import '../preprocessing/movement_time_processor.dart' show TimeSpan;
import 'treadmill.dart';

/// Aktive Abschnitte von [start] bis [end]: der Bereich ohne die
/// Vereinigung der [pauses] (jeweils auf den Bereich beschnitten), aufsteigend
/// und ohne Überlappung.
List<TimeSpan> activeIntervalsWithoutPauses({
  required DateTime start,
  required DateTime end,
  required List<(DateTime, DateTime)> pauses,
}) {
  if (!end.isAfter(start)) return const [];
  final cuts = [
    for (final (ps, pe) in pauses)
      if (pe.isAfter(start) && ps.isBefore(end) && pe.isAfter(ps))
        (ps.isBefore(start) ? start : ps, pe.isAfter(end) ? end : pe),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <TimeSpan>[];
  var cursor = start;
  for (final (ps, pe) in cuts) {
    if (ps.isAfter(cursor)) spans.add(TimeSpan(start: cursor, end: ps));
    if (pe.isAfter(cursor)) cursor = pe;
  }
  if (end.isAfter(cursor)) spans.add(TimeSpan(start: cursor, end: end));
  return spans;
}

/// Zeit von [start] bis [end] ohne die [pauses] (überlappende Pausen zählen
/// einmal); nie negativ.
Duration activeTimeWithoutPauses({
  required DateTime start,
  required DateTime end,
  required List<(DateTime, DateTime)> pauses,
}) => activeIntervalsWithoutPauses(
  start: start,
  end: end,
  pauses: pauses,
).fold(Duration.zero, (a, s) => a + s.duration);

/// Aktive Abschnitte einer beendeten Sporteinheit aus den gespeicherten
/// Lücken (PAR-232); ihre Summe ist die Bewegungszeit. `null`, wenn [run]
/// keine andere Sportart ist.
List<TimeSpan>? sportMovingIntervalsOfRun(
  StoredRun run,
  DateTime end,
  List<StoredGap> gaps,
) {
  if (run.mode != RunMode.sport) return null;
  return activeIntervalsWithoutPauses(
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
