import 'plan_unit.dart';
import 'weekly_time.dart' show planDay;

/// Schlüssel im `summary` einer Planfassung, die unter einem Warnsignal
/// entstand (FR-0203, K58): die Einheiten, die das Warnsignal zu Ruhetagen
/// gemacht hat (Art, `fixed`, `pinned`), damit Art und Festlegungen nach dem
/// Aufheben wiederkehren. Eine leere Liste heißt: Fassung unter Warnsignal,
/// nichts zu halten. Fehlt der Schlüssel, entstand die Fassung
/// ohne Warnsignal.
const String planWarningKey = 'warningHeld';

/// Grund-Code ([PlanVersionDraft.reason]) der Fassung bei gemeldetem Warnsignal.
const String planReasonWarning = 'warning';

/// Grund-Code der Fassung nach dem Aufheben.
const String planReasonWarningLifted = 'warningLifted';

/// Tage ohne Erinnerung: Nach so vielen Tagen ab Meldung ist sie fällig
/// (FR-0203, K58).
const int warningReminderDays = 7;

/// Festlegung einer Einheit, die das Warnsignal überdeckt.
class WarningHeld {
  const WarningHeld({
    required this.day,
    required this.kind,
    required this.fixed,
    required this.pinned,
  });

  final DateTime day;
  final PlanUnitKind kind;
  final PlanUnitFixed fixed;
  final bool pinned;

  Map<String, Object?> toJson() => {
    'day': _iso(day),
    'kind': kind.name,
    'fixed': fixed.name,
    'pinned': pinned,
  };

  static WarningHeld? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = DateTime.tryParse('${json['day']}');
    final kind = PlanUnitKind.values.asNameMap()[json['kind']];
    final fixed = PlanUnitFixed.values.asNameMap()[json['fixed']];
    final pinned = json['pinned'];
    if (day == null || kind == null || fixed == null || pinned is! bool) {
      return null;
    }
    return WarningHeld(
      day: planDay(day),
      kind: kind,
      fixed: fixed,
      pinned: pinned,
    );
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Alle künftigen, nicht absolvierten Einheiten [future] (Tag ab [today],
/// ohne Lauf) als Ruhetage; Tag, Woche, Phase, `pinned` und `fixed` bleiben
/// (die Festlegung wird nicht gelöscht, [warningHeldOf] hält die Art).
/// Eingefrorene Einheiten (Tag vor [today] oder mit Lauf) bleiben unverändert.
List<PlanUnit> applyWarningRest(List<PlanUnit> future, DateTime today) {
  final todayDay = planDay(today);
  return [
    for (final u in future)
      if (u.day.isBefore(todayDay) ||
          u.runId != null ||
          u.kind == PlanUnitKind.rest)
        u
      else
        PlanUnit(
          id: u.id,
          day: u.day,
          kind: PlanUnitKind.rest,
          phase: u.phase,
          weekIndex: u.weekIndex,
          minutes: 0,
          segments: const [],
          pinned: u.pinned,
          fixed: u.fixed,
          method: u.method,
          methodVersion: u.methodVersion,
        ),
  ];
}

/// Die Einheiten [units] (vor [applyWarningRest]), die ein Ruhetag ersetzt:
/// alle künftigen offenen Läufe mit Art, `pinned` und `fixed`. Auch
/// nicht festgelegte Einheiten werden gehalten: Die Rechnung der
/// automatischen Auslöser hält die Tage und ordnet über die Art zu.
List<WarningHeld> warningHeldOf(List<PlanUnit> units, DateTime today) {
  final todayDay = planDay(today);
  return [
    for (final u in units)
      if (!u.day.isBefore(todayDay) &&
          u.runId == null &&
          u.kind != PlanUnitKind.rest)
        WarningHeld(
          day: planDay(u.day),
          kind: u.kind,
          fixed: u.fixed,
          pinned: u.pinned,
        ),
  ];
}

/// Die gehaltenen Festlegungen aus dem `summary` einer Fassung; `null`, wenn
/// die Fassung nicht unter einem Warnsignal entstand. Unlesbare Einträge
/// entfallen.
List<WarningHeld>? warningHeldFromSummary(Map<String, Object?> summary) {
  final raw = summary[planWarningKey];
  if (raw is! List) return null;
  return [for (final e in raw) ?WarningHeld.fromJson(e)];
}

/// Stellt in [units] (eine Fassung unter Warnsignal) die Art der gehaltenen
/// Festlegungen [held] wieder her: Einheiten auf deren Tagen, die ein
/// Ruhetag ersetzt hat, bekommen Art, `fixed` und `pinned` zurück (Dauer und
/// Abschnitte rechnet die Neuberechnung). Nur Ruhetage, die noch die
/// Überlagerung sind (`pinned` und `fixed` wie gehalten): Eine Festlegung, die
/// der Nutzer unter dem Warnsignal neu getroffen hat (z. B. Ruhetag), gilt
/// weiter (ADR-0010).
List<PlanUnit> restoreWarningHeld(
  List<PlanUnit> units,
  List<WarningHeld> held,
) {
  final byDay = {for (final h in held) h.day: h};
  return [
    for (final u in units)
      if (_isOverlay(u, byDay[planDay(u.day)]))
        _restored(u, byDay[planDay(u.day)]!)
      else
        u,
  ];
}

bool _isOverlay(PlanUnit u, WarningHeld? h) =>
    h != null &&
    u.kind == PlanUnitKind.rest &&
    u.pinned == h.pinned &&
    u.fixed == h.fixed;

PlanUnit _restored(PlanUnit u, WarningHeld h) => PlanUnit(
  id: u.id,
  day: u.day,
  kind: h.kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: 0,
  segments: const [],
  runId: u.runId,
  pinned: h.pinned,
  fixed: h.fixed,
  method: u.method,
  methodVersion: u.methodVersion,
);

/// Erinnerung fällig (FR-0203): [warningReminderDays] Tage nach der Meldung
/// [reportedOn]. Nur Anzeige in der App, keine Benachrichtigung.
bool warningReminderDue({
  required DateTime reportedOn,
  required DateTime today,
}) =>
    planDay(today).difference(planDay(reportedOn)).inDays >=
    warningReminderDays;
