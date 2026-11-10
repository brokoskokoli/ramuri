import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'weekly_time.dart' show planDay;

/// Warum eine Einheit nicht auf den gewünschten Tag kann (wie der Speicher
/// bei `PlanRepository.confirmMove` ablehnt; vorher geprüft, damit die
/// Oberfläche nichts anbietet, was abgelehnt würde).
enum PlanMoveBlock {
  /// Die Einheit hat einen Lauf (absolviert, eingefroren).
  unitHasRun,

  /// Die Einheit liegt vor heute (vergangen, eingefroren).
  unitPast,

  /// Der gewünschte Tag liegt vor heute.
  dayPast,

  /// Der gewünschte Tag ist der bisherige.
  sameDay,

  /// Auf dem gewünschten Tag liegt schon eine Einheit.
  dayTaken,
}

/// Ergebnis der Prüfung beim Verschieben (FR-0177, FR-0178, PAR-060). Die
/// Prüfung ändert nichts; den Termin ändert nur die Bestätigung des Nutzers
/// (FR-0176, OQ-0011).
class PlanMoveCheck {
  const PlanMoveCheck({
    required this.day,
    this.blocked,
    this.spacingDays = const [],
    this.weekMinutes = 0,
    this.weekCapMinutes = 0,
    this.alternatives = const [],
  });

  /// Der geprüfte Tag.
  final DateTime day;

  /// Gesetzt, wenn der Speicher die Verschiebung ablehnen würde.
  final PlanMoveBlock? blocked;

  /// Tage intensiver Einheiten ohne vollen Kalendertag Abstand zum neuen Tag
  /// (PAR-059, PAR-060). Nicht leer: Konflikt; der Nutzer darf trotzdem
  /// bestätigen.
  final List<DateTime> spacingDays;

  /// Summe der Minuten der Woche des neuen Tags nach der Verschiebung.
  final int weekMinutes;

  /// Regler in Minuten (PAR-196).
  final int weekCapMinutes;

  /// Freie Tage der Woche des neuen oder des bisherigen Tags ab heute, auf denen die Einheit ohne
  /// Abstandskonflikt und innerhalb des Reglers läge, nächster zuerst
  /// (FR-0178). Nur bei einem Konflikt oder überschrittenem Regler belegt.
  final List<DateTime> alternatives;

  bool get allowed => blocked == null;

  /// Abstandskonflikt (FR-0177): anzeigen, nicht sperren (PAR-060).
  bool get hasSpacingConflict => spacingDays.isNotEmpty;

  /// Woche über dem Regler: Hinweis statt Sperre (PAR-060).
  bool get overRegulator => weekMinutes > weekCapMinutes;
}

/// Prüft, ob [unit] auf [newDay] verschoben werden kann (FR-0177, PAR-060).
///
/// [units] sind die gespeicherten Einheiten mindestens der Wochen (Montag bis
/// Sonntag) von [newDay] und vom bisherigen Tag, je mit `minGapDays - 1`
/// Tagen davor und danach;
/// [unit] darf darin enthalten sein. [weeklyCapSeconds] ist der Regler des
/// Ziels (PAR-196), [today] der Ortstag „heute“.
///
/// - Eingefroren (Lauf zugeordnet oder vor heute), Tag vor heute, gleicher
///   oder belegter Tag: [PlanMoveCheck.blocked].
/// - Ist [unit] intensiv (PAR-058) und liegt eine andere intensive Einheit
///   näher als `minGapDays` am neuen Tag: Konflikt mit deren Tagen (PAR-059).
/// - Wochensumme über dem Regler: [PlanMoveCheck.overRegulator].
/// - Bei Konflikt oder Regler: Alternativtage der Woche des neuen und des
///   bisherigen Tags (frei, ab heute, nicht der bisherige Tag, ohne Konflikt,
///   im Regler). Lauftage des Ziels ([runDays], `DateTime.weekday`) zuerst,
///   danach jeweils dem gewünschten Tag nächster zuerst.
///
/// [completedIntensiveDays] sind Ortstage absolvierter Läufe, die nach
/// PAR-058 als intensiv gelten (auch ohne Einheit); sie zählen für den
/// Abstand wie intensive Einheiten (PAR-059).
PlanMoveCheck checkPlanMove({
  required List<PlanUnit> units,
  required PlanUnit unit,
  required DateTime newDay,
  required DateTime today,
  required double weeklyCapSeconds,
  Iterable<DateTime> completedIntensiveDays = const [],
  Set<int> runDays = const {},
  PlanParameters parameters = const PlanParameters(),
}) {
  final t = planDay(today);
  final day = planDay(newDay);
  final from = planDay(unit.day);
  final cap = weeklyCapSeconds ~/ 60;
  final others = [
    for (final u in units)
      if (!(u.id != null && u.id == unit.id) &&
          !(u.id == null && planDay(u.day) == from))
        u,
  ];
  bool taken(DateTime d) => others.any((u) => planDay(u.day) == d);

  PlanMoveBlock? blocked;
  if (unit.runId != null) {
    blocked = PlanMoveBlock.unitHasRun;
  } else if (from.isBefore(t)) {
    blocked = PlanMoveBlock.unitPast;
  } else if (day.isBefore(t)) {
    blocked = PlanMoveBlock.dayPast;
  } else if (day == from) {
    blocked = PlanMoveBlock.sameDay;
  } else if (taken(day)) {
    blocked = PlanMoveBlock.dayTaken;
  }
  if (blocked != null) {
    return PlanMoveCheck(day: day, blocked: blocked, weekCapMinutes: cap);
  }

  final intensiveDays = {
    for (final u in others)
      if (u.isIntensive) planDay(u.day),
    for (final r in completedIntensiveDays) planDay(r),
  };
  List<DateTime> spacing(DateTime d) => [
    if (unit.isIntensive)
      for (final x in intensiveDays)
        if (x.difference(d).inDays.abs() < parameters.minGapDays) x,
  ]..sort();

  DateTime monday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - DateTime.monday));

  int weekSum(DateTime d) {
    final m = monday(d);
    final end = m.add(const Duration(days: 7));
    var sum = unit.minutes;
    for (final u in others) {
      final ud = planDay(u.day);
      if (!ud.isBefore(m) && ud.isBefore(end)) sum += u.minutes;
    }
    return sum;
  }

  final conflicts = spacing(day);
  final minutes = weekSum(day);
  final alternatives = <DateTime>[];
  if (conflicts.isNotEmpty || minutes > cap) {
    final weeks = {monday(day), monday(from)};
    final candidates = [
      for (final m in weeks)
        for (var i = 0; i < 7; i++) m.add(Duration(days: i)),
    ].where((d) => d != day && d != from && !d.isBefore(t) && !taken(d));
    for (final d in candidates) {
      if (spacing(d).isEmpty && weekSum(d) <= cap) alternatives.add(d);
    }
    alternatives.sort((a, b) {
      final ra = runDays.contains(a.weekday), rb = runDays.contains(b.weekday);
      if (ra != rb) return ra ? -1 : 1;
      final da = a.difference(day).inDays.abs();
      final db = b.difference(day).inDays.abs();
      return da != db ? da.compareTo(db) : a.compareTo(b);
    });
  }
  return PlanMoveCheck(
    day: day,
    spacingDays: conflicts,
    weekMinutes: minutes,
    weekCapMinutes: cap,
    alternatives: alternatives,
  );
}
