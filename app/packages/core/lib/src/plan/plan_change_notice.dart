import '../../ports/storage_plan.dart';
import '../hints/explanations.dart';
import 'plan_unit.dart';
import 'walk_run_program.dart';
import 'walk_run_units.dart';
import 'weekly_time.dart';

/// Ist die Fassung eine größere Änderung nach PAR-204 (Wochenzeit mindestens
/// 10 % anders, oder eine Einheit wechselt zwischen hart, locker und Ruhetag
/// oder entfällt)? Das Alt-Neu-Bild stammt aus dem Vergleich beim Schreiben
/// (`summarizeChange`, `plans.summary`). Die erste Fassung ist keine
/// Änderung. Kleinere Änderungen stehen nur im Verlauf.
bool isLargerPlanChange(PlanVersionRecord v) =>
    v.trigger != PlanTrigger.create && v.summary['larger'] == true;

/// Die zu zeigende größere Änderung der Karte „Plan angepasst“ (FR-0170):
/// Fassung und ihre Erklärung. Der Satz entsteht in der Oberfläche aus dem
/// Code der [explanation] ([explainPlanChange]).
class PlanChangeNotice {
  const PlanChangeNotice({required this.version, required this.explanation});

  /// Kennung der Fassung: das „gesehen“ der Karte.
  int get planId => version.id;
  final PlanVersionRecord version;
  final Explanation explanation;
}

/// Die jüngste größere Änderung in [history] (nach Anlage geordnet), die
/// nach [seenPlanId] liegt, oder `null`: keine Karte. Ohne Verschiebung von
/// Terminen (OQ-0011): die Karte erklärt nur.
PlanChangeNotice? planChangeNotice(
  List<PlanVersionRecord> history, {
  int? seenPlanId,
}) {
  for (final v in history.reversed) {
    if (seenPlanId != null && v.id <= seenPlanId) return null;
    if (isLargerPlanChange(v)) {
      return PlanChangeNotice(version: v, explanation: explainPlanChange(v));
    }
  }
  return null;
}

/// Grund-Code der Fassung nach dem Annehmen von „Woche wiederholen“ (PAR-140).
const String walkRunRepeatReason = 'walkRunRepeat';

/// Vorschlag „Woche wiederholen“ für die zuletzt beendete Programmwoche.
class WalkRunWeekProposal {
  const WalkRunWeekProposal({
    required this.suggestion,
    required this.lastDay,
    required this.doneCount,
    required this.sessionCount,
  });

  /// PAR-140; für [applyWalkRunRepeat].
  final WalkRunRepeatSuggestion suggestion;

  /// Programmwoche ab 0.
  int get programWeek => suggestion.position.week;

  /// Letzter Tag der Woche: Kennung der Antwort („nicht wiederholen“).
  final DateTime lastDay;

  /// Absolvierte und geplante Einheiten der Programmwoche.
  final int doneCount;
  final int sessionCount;
}

/// Sucht nach PAR-140 den Vorschlag „Woche wiederholen“. [units] sind die
/// Einheiten seit dem Anker der neuesten Fassung ab Position [start]
/// (`PlanInputs.walkRunStart`); die Geh-Lauf-Einheiten stehen in der
/// Reihenfolge der Abfolge, ein Wiederholen beginnt mit neuem Anker neu.
/// Betrachtet wird die letzte Programmwoche, deren Einheiten alle vor [today]
/// liegen und nach der noch keine Einheit der nächsten Woche absolviert ist.
/// [rpeByRunId]: Anstrengung je Lauf. Nur aus gespeicherten Einheiten und
/// Läufen, `null` ohne Vorschlag. [from]: erster Tag der Abfolge
/// (`walkRunFrom` der Fassung); frühere Geh-Lauf-Einheiten der Woche gehören
/// nicht zur Abfolge und zählen nicht als [start].
WalkRunWeekProposal? walkRunWeekProposal({
  required List<PlanUnit> units,
  required WalkRunPosition start,
  required Map<int, int> rpeByRunId,
  required DateTime today,
  WalkRunProgram? program,
  DateTime? from,
}) {
  final prog = program ?? walkRunProgram;
  final order = prog.orderedSessions;
  final first = order.indexWhere(
    (s) => s.week == start.week && s.session >= start.session,
  );
  if (first < 0) return null;
  final seq = [
    for (final u in units)
      if (u.kind == PlanUnitKind.walkRun &&
          (from == null || !planDay(u.day).isBefore(planDay(from))))
        u,
  ]..sort((a, b) => a.day.compareTo(b.day));
  final t = planDay(today);
  final byWeek = <int, List<PlanUnit>>{};
  for (var i = 0; i < seq.length && first + i < order.length; i++) {
    byWeek.putIfAbsent(order[first + i].week, () => []).add(seq[i]);
  }
  final weeks = byWeek.keys.toList()..sort();
  int? finished;
  for (final w in weeks) {
    if (byWeek[w]!.every((u) => planDay(u.day).isBefore(t))) finished = w;
  }
  if (finished == null) {
    return _sessionProposal(weeks, byWeek, start, null, prog, rpeByRunId);
  }
  final laterRun = weeks.any(
    (w) => w > finished! && byWeek[w]!.any((u) => u.runId != null),
  );
  final us = byWeek[finished]!;
  final s = laterRun
      ? null
      : suggestWalkRunRepeat(
          programWeek: finished,
          outcomes: [
            for (final u in us)
              WalkRunOutcome(
                done: u.runId != null,
                rpe: u.runId == null ? null : rpeByRunId[u.runId],
              ),
          ],
          weekOver: true,
          program: prog,
        );
  if (s == null) {
    return _sessionProposal(weeks, byWeek, start, finished, prog, rpeByRunId);
  }
  return WalkRunWeekProposal(
    suggestion: s,
    lastDay: planDay(us.last.day),
    doneCount: us.where((u) => u.runId != null).length,
    sessionCount: us.length,
  );
}

/// Vor Woche 5, Lauf 3 (PAR-140): Lauf 2 hatte RPE >= 6, dann schlägt die App
/// vor, Lauf 2 zu wiederholen. Betrachtet wird die erste Woche nach der zuletzt
/// beendeten [finished] (ohne beendete Woche die erste). Beginnt die Abfolge
/// mitten in der Woche (nach einem Wiederholen), fehlen die früheren
/// Einheiten und gelten als nicht absolviert. `null` ohne Vorschlag.
WalkRunWeekProposal? _sessionProposal(
  List<int> weeks,
  Map<int, List<PlanUnit>> byWeek,
  WalkRunPosition start,
  int? finished,
  WalkRunProgram prog,
  Map<int, int> rpeByRunId,
) {
  final next = weeks.where((w) => finished == null || w > finished);
  if (next.isEmpty) return null;
  final w = next.first;
  final units = byWeek[w]!;
  final lead = w == start.week ? start.session : 0;
  final outcomes = [
    for (var i = 0; i < lead; i++) const WalkRunOutcome(done: false),
    for (final u in units)
      WalkRunOutcome(
        done: u.runId != null,
        rpe: u.runId == null ? null : rpeByRunId[u.runId],
      ),
  ];
  final s = suggestWalkRunRepeat(
    programWeek: w,
    outcomes: outcomes,
    weekOver: false,
    program: prog,
  );
  if (s == null) return null;
  final at = s.position.session - lead;
  if (at < 0 || at >= units.length) return null;
  return WalkRunWeekProposal(
    suggestion: s,
    lastDay: planDay(units[at].day),
    doneCount: units.where((u) => u.runId != null).length,
    sessionCount: units.length,
  );
}
