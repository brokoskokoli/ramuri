import '../../ports/storage_runs.dart';
import '../run_day/run_day.dart' show runStartLocalDay;
import 'plan_unit.dart';
import 'weekly_time.dart' show planDay;

/// Ein beendeter Lauf als Kandidat für die Zuordnung zu einer Plan-Einheit
/// (PAR-231).
class PlanRunCandidate {
  const PlanRunCandidate({
    required this.runId,
    required this.day,
    required this.startedAt,
    required this.movingTime,
  });

  /// Kandidat aus einem gespeicherten Lauf; `null`, wenn er nicht beendet
  /// ist. [movingTime] ist die Bewegungszeit aus der Kurzfassung (GPS und
  /// Laufband gleich); fehlt sie, zählt die Dauer von Beginn bis Ende.
  static PlanRunCandidate? of(StoredRun run, {required Duration? movingTime}) {
    final end = run.endedAt;
    if (run.state != RunState.finished || end == null) return null;
    // Eine andere Sportart (FR-0221) zählt für den Plan nur über den Ersatz
    // einer lockeren Einheit (DEC-0056), nie über die Zuordnung eines Laufs.
    if (!run.mode.isRunning) return null;
    return PlanRunCandidate(
      runId: run.id,
      day: planRunStartDay(run),
      startedAt: run.startedAt,
      movingTime: movingTime ?? end.difference(run.startedAt),
    );
  }

  final int runId;

  /// Ortstag des Laufbeginns (UTC-Mitternacht wie [PlanUnit.day]).
  final DateTime day;
  final DateTime startedAt;
  final Duration movingTime;
}

/// Ortstag des Laufbeginns (PAR-231, PAR-237): dieselbe Rechnung wie für
/// alle anderen Tage eines Laufs ([runStartLocalDay]); ohne gespeicherten
/// UTC-Versatz (alte Läufe) der UTC-Tag wie bei `dayOfRun`.
DateTime planRunStartDay(StoredRun run) => runStartLocalDay(run);

/// Eine Zuordnung, die [planAutoAssignments] vorschlägt.
class PlanRunAssignment {
  const PlanRunAssignment({required this.unitId, required this.runId});

  final int unitId;
  final int runId;

  @override
  bool operator ==(Object other) =>
      other is PlanRunAssignment &&
      other.unitId == unitId &&
      other.runId == runId;

  @override
  int get hashCode => Object.hash(unitId, runId);

  @override
  String toString() => 'PlanRunAssignment($unitId ← $runId)';
}

/// Zuordnung von Läufen zu Einheiten (PAR-231): Jede offene Einheit (kein
/// Ruhetag, ohne Lauf, mit Kennung) des aktiven Plans, deren Tag zwischen
/// [from] und [today] liegt (beide eingeschlossen; nach einem Verschieben
/// zählt der aktuelle Tag), bekommt einen beendeten Lauf desselben Ortstags,
/// der noch keiner Einheit zugeordnet ist. Von mehreren zählt der mit der
/// längsten Bewegungszeit, bei Gleichstand der frühere. Keine Prüfung von
/// Dauer oder Intensität.
///
/// [units] sind alle Einheiten (auch außerhalb des Zeitraums): Ein Lauf, der
/// irgendwo zugeordnet ist, zählt nie ein zweites Mal. Bestehende
/// Zuordnungen bleiben. Reine Funktion; auf ihr Ergebnis angewendet liefert
/// sie nichts mehr (idempotent).
List<PlanRunAssignment> planAutoAssignments({
  required List<PlanUnit> units,
  required List<PlanRunCandidate> runs,
  required DateTime today,
  required DateTime from,
}) {
  final first = planDay(from), last = planDay(today);
  final taken = <int>{
    for (final u in units)
      if (u.runId != null) u.runId!,
  };
  final open =
      [
        for (final u in units)
          if (u.id != null &&
              u.runId == null &&
              u.kind != PlanUnitKind.rest &&
              !planDay(u.day).isBefore(first) &&
              !planDay(u.day).isAfter(last))
            u,
      ]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.id!.compareTo(b.id!);
      });
  final result = <PlanRunAssignment>[];
  for (final unit in open) {
    final day = planDay(unit.day);
    PlanRunCandidate? best;
    for (final r in runs) {
      if (taken.contains(r.runId) || r.day != day) continue;
      if (best == null || _better(r, best)) best = r;
    }
    if (best == null) continue;
    taken.add(best.runId);
    result.add(PlanRunAssignment(unitId: unit.id!, runId: best.runId));
  }
  return result;
}

/// Längere Bewegungszeit gewinnt, bei Gleichstand der frühere Beginn, dann
/// die kleinere Kennung (feste Reihenfolge).
bool _better(PlanRunCandidate a, PlanRunCandidate b) {
  final byTime = a.movingTime.compareTo(b.movingTime);
  if (byTime != 0) return byTime > 0;
  final byStart = a.startedAt.compareTo(b.startedAt);
  if (byStart != 0) return byStart < 0;
  return a.runId < b.runId;
}
