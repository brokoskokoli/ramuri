import 'generate_plan.dart' show PinnedConflict, PinnedConflictKind;
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'target_intensity.dart' show IntensityParameters;
import 'weekly_time.dart' show planDay;

/// Ein beendeter Lauf, so wie ihn die Regel der Abweichung braucht
/// (PAR-235, PAR-058): Ortstag, Bewegungszeit und die Angaben, nach denen er
/// als intensiv gilt. Keine Messreihe, nur diese Kennzahlen.
class PlanRunFacts {
  const PlanRunFacts({
    required this.runId,
    required this.day,
    this.movingSeconds,
    this.rpe,
    this.highHrMinutes,
  });

  final int runId;

  /// Ortstag des Laufs.
  final DateTime day;

  /// Bewegungszeit in Sekunden; `null`, wenn sie fehlt.
  final int? movingSeconds;

  /// RPE-Angabe des Nutzers (0 bis 10) oder `null`.
  final int? rpe;

  /// Minuten bei mindestens 80 % HFmax (PAR-058) oder `null` ohne Puls bzw.
  /// HFmax.
  final double? highHrMinutes;

  /// Intensiv nach PAR-058 ([PlanParameters.completedIntensive]).
  bool intensive(PlanParameters p) =>
      p.completedIntensive(rpe: rpe, highHrMinutes: highHrMinutes);
}

/// Ergebnis von [detectPlanDeviation].
class PlanDeviation {
  const PlanDeviation({
    this.muchMore = false,
    this.intensiveInsteadOfEasy = false,
  });

  /// „Deutlich mehr“ (PAR-235): Bewegungszeit oder RPE weit über der Vorgabe.
  final bool muchMore;

  /// „Intensiv statt locker“ (PAR-235): locker geplant, nach PAR-058
  /// intensiv gelaufen.
  final bool intensiveInsteadOfEasy;
}

/// Obergrenze der Vorgabe-RPE einer Einheit der Art [kind] (PAR-105); beim
/// progressiven Lauf die des härtesten Abschnitts (Endblock). `null` beim
/// Ruhetag.
int? planUnitRpeUpper(
  PlanUnitKind kind, {
  IntensityParameters intensity = const IntensityParameters(),
}) => switch (kind) {
  PlanUnitKind.easy => intensity.rpeEasy.max,
  PlanUnitKind.long => intensity.rpeLong.max,
  PlanUnitKind.intervals => intensity.rpeInterval.max,
  PlanUnitKind.tempo => intensity.rpeTempo.max,
  PlanUnitKind.progressive => intensity.rpeEndBlock.max,
  PlanUnitKind.walkRun => intensity.rpeWalkRun.max,
  PlanUnitKind.rest => null,
};

/// Abweichung des Laufs [run] von der erledigten Einheit [unit] (PAR-235).
/// Rein, ohne Speicher.
///
/// * „Deutlich mehr“: Bewegungszeit mindestens
///   [PlanParameters.deviationTimeFactor] × geplante Dauer, oder RPE
///   mindestens Obergrenze der Vorgabe ([planUnitRpeUpper]) +
///   [PlanParameters.deviationRpeSteps]. Bei einer Obergrenze ab 8 ist das
///   über die RPE (Skala bis 10) nicht erreichbar; ohne RPE zählt nur die
///   Zeit.
/// * „Intensiv statt locker“: Einheit der Art locker, lang oder Geh-Lauf und
///   Lauf nach PAR-058 intensiv.
PlanDeviation detectPlanDeviation(
  PlanUnit unit,
  PlanRunFacts run, {
  PlanParameters parameters = const PlanParameters(),
  IntensityParameters intensity = const IntensityParameters(),
}) {
  if (unit.kind == PlanUnitKind.rest) return const PlanDeviation();
  final seconds = run.movingSeconds;
  final byTime =
      seconds != null &&
      unit.minutes > 0 &&
      seconds >= parameters.deviationTimeFactor * unit.minutes * 60;
  final upper = planUnitRpeUpper(unit.kind, intensity: intensity);
  final rpe = run.rpe;
  final byRpe =
      rpe != null &&
      upper != null &&
      rpe >= upper + parameters.deviationRpeSteps;
  final easyKind =
      unit.kind == PlanUnitKind.easy ||
      unit.kind == PlanUnitKind.long ||
      unit.kind == PlanUnitKind.walkRun;
  return PlanDeviation(
    muchMore: byTime || byRpe,
    intensiveInsteadOfEasy: easyKind && run.intensive(parameters),
  );
}

/// Was die Regel der Abweichung an einer Einheit geändert hat (PAR-235).
enum PlanRunChange {
  /// Bei „adaptiv“: Die harte Einheit wurde locker, ein intensiv gelaufener
  /// lockerer Lauf zählt als harte Einheit der Woche.
  eased,

  /// Bei „adaptiv“: Die Einheit wurde gekürzt, weil ein Lauf der Woche
  /// deutlich länger oder härter war.
  shortened,

  /// Bei „fix“: Die Einheit hat den Tag mit [PlanRunNote.otherDay] getauscht,
  /// damit die harte Einheit den Abstand (PAR-059) zum intensiven Lauf hält.
  swapped,
}

/// Schlüssel im `summary` einer Fassung: die Begründungen an den Einheiten,
/// die die Regel der Abweichung geändert hat ([PlanRunNote]). Fehlt er, hat
/// die Fassung nichts geändert.
const String planRunNotesKey = 'runDeviation';

/// Begründung an einer Einheit (PAR-235): Tag und Art der Einheit nach der
/// Änderung, was geändert wurde und der Tag des auslösenden Laufs.
class PlanRunNote {
  const PlanRunNote({
    required this.day,
    required this.kind,
    required this.change,
    required this.runDay,
    this.otherDay,
  });

  final DateTime day;
  final PlanUnitKind kind;
  final PlanRunChange change;

  /// Ortstag des Laufs, der die Änderung ausgelöst hat.
  final DateTime runDay;

  /// Bei [PlanRunChange.swapped]: der Tag, mit dem getauscht wurde.
  final DateTime? otherDay;

  Map<String, Object?> toJson() => {
    'day': _iso(day),
    'kind': kind.name,
    'change': change.name,
    'runDay': _iso(runDay),
    if (otherDay case final o?) 'otherDay': _iso(o),
  };

  static PlanRunNote? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = _parse(json['day']);
    final runDay = _parse(json['runDay']);
    final kind = PlanUnitKind.values.asNameMap()[json['kind']];
    final change = PlanRunChange.values.asNameMap()[json['change']];
    if (day == null || runDay == null || kind == null || change == null) {
      return null;
    }
    return PlanRunNote(
      day: day,
      kind: kind,
      change: change,
      runDay: runDay,
      otherDay: _parse(json['otherDay']),
    );
  }
}

/// Die Begründungen aus dem `summary` einer Fassung; unlesbare Einträge
/// entfallen.
List<PlanRunNote> planRunNotesFromSummary(Map<String, Object?> summary) {
  final raw = summary[planRunNotesKey];
  if (raw is! List) return const [];
  return [for (final e in raw) ?PlanRunNote.fromJson(e)];
}

/// Die Begründung für die Einheit [unit] aus [notes], `null` ohne: gleicher
/// Tag und gleiche Art, Einheit offen.
PlanRunNote? planRunNoteFor(PlanUnit unit, Iterable<PlanRunNote> notes) {
  if (unit.runId != null) return null;
  final day = planDay(unit.day);
  for (final n in notes) {
    if (n.day == day && n.kind == unit.kind) return n;
  }
  return null;
}

/// Ortstage der nach PAR-058 intensiven Läufe aus [runs] von
/// `minGapDays - 1` Tagen vor dem Montag der Woche von [today] bis [today]:
/// die Läufe, zu denen die harte Einheit dieser Woche Abstand halten muss
/// (PAR-059).
Set<DateTime> planIntensiveRunDays(
  Iterable<PlanRunFacts> runs,
  DateTime today, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final t = planDay(today);
  final from = _mondayOf(t).subtract(Duration(days: parameters.minGapDays - 1));
  return {
    for (final r in runs)
      if (!planDay(r.day).isBefore(from) &&
          !planDay(r.day).isAfter(t) &&
          r.intensive(parameters))
        planDay(r.day),
  };
}

/// Die nächste offene harte Einheit der Woche von [today] in [units] (Tag ab
/// heute, ohne Lauf), `null` ohne.
PlanUnit? _nextOpenHard(List<PlanUnit> units, DateTime today) {
  final t = planDay(today);
  final end = _mondayOf(t).add(const Duration(days: 7));
  PlanUnit? next;
  for (final u in units) {
    final d = planDay(u.day);
    if (u.runId != null || !u.isHard || d.isBefore(t) || !d.isBefore(end)) {
      continue;
    }
    if (next == null || d.isBefore(planDay(next.day))) next = u;
  }
  return next;
}

bool _tooClose(DateTime day, Iterable<DateTime> others, int gap) =>
    others.any((o) => planDay(day).difference(o).inDays.abs() < gap);

/// Ergebnis von [applyRunSpacingSwap].
class RunSpacingSwap {
  const RunSpacingSwap(this.units, this.notes);

  final List<PlanUnit> units;

  /// Begründungen an beiden getauschten Einheiten; leer ohne Tausch.
  final List<PlanRunNote> notes;
}

/// Bei „fix“ (FR-0216, PAR-235): Liegt die nächste offene harte Einheit der
/// Woche von [today] in [units] näher als [PlanParameters.minGapDays] an
/// einem intensiven Lauf aus [intensiveRunDays] (PAR-059), tauscht sie den
/// Tag mit der nächsten späteren offenen lockeren Einheit derselben Woche,
/// auf deren Tag sie den Abstand zu allen intensiven Läufen und allen anderen
/// intensiven Einheiten ([units] und [others]) hält. Art und Dauer beider
/// Einheiten bleiben. Eine vom Nutzer bestätigte Verschiebung (`pinned`)
/// wird nicht getauscht, weder als harte noch als lockere Einheit. Gibt es
/// keinen solchen Tag, bleibt alles (den Hinweis zeigt
/// [planRunSpacingConflicts]). Rein.
RunSpacingSwap applyRunSpacingSwap({
  required List<PlanUnit> units,
  required Set<DateTime> intensiveRunDays,
  required DateTime today,
  List<PlanUnit> others = const [],
  PlanParameters parameters = const PlanParameters(),
}) {
  final gap = parameters.minGapDays;
  final hard = _nextOpenHard(units, today);
  if (hard == null ||
      hard.pinned ||
      !_tooClose(hard.day, intensiveRunDays, gap)) {
    return RunSpacingSwap(units, const []);
  }
  final hardDay = planDay(hard.day);
  final end = _mondayOf(hardDay).add(const Duration(days: 7));
  final intensiveUnits = [
    for (final u in [...others, ...units])
      if (u.isIntensive && !identical(u, hard)) planDay(u.day),
  ];
  PlanUnit? partner;
  for (final u in units) {
    final d = planDay(u.day);
    if (u.runId != null ||
        u.pinned ||
        u.kind != PlanUnitKind.easy ||
        !d.isAfter(hardDay) ||
        !d.isBefore(end) ||
        _tooClose(d, intensiveRunDays, gap) ||
        _tooClose(d, intensiveUnits, gap)) {
      continue;
    }
    if (partner == null || d.isBefore(planDay(partner.day))) partner = u;
  }
  if (partner == null) return RunSpacingSwap(units, const []);
  final partnerDay = planDay(partner.day);
  final runDay = intensiveRunDays
      .where((r) => hardDay.difference(r).inDays.abs() < gap)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final movedHard = hard.copyWith(day: partner.day);
  final movedEasy = partner.copyWith(day: hard.day);
  final out = [
    for (final u in units)
      if (identical(u, hard))
        movedEasy
      else if (identical(u, partner))
        movedHard
      else
        u,
  ]..sort((a, b) => a.day.compareTo(b.day));
  return RunSpacingSwap(out, [
    PlanRunNote(
      day: partnerDay,
      kind: hard.kind,
      change: PlanRunChange.swapped,
      runDay: runDay,
      otherDay: hardDay,
    ),
    PlanRunNote(
      day: hardDay,
      kind: partner.kind,
      change: PlanRunChange.swapped,
      runDay: runDay,
      otherDay: partnerDay,
    ),
  ]);
}

/// Hinweis wie beim Verschieben (PAR-060) für die nächste offene harte
/// Einheit der Woche von [today] in [units], die näher als
/// [PlanParameters.minGapDays] an einem intensiven Lauf aus
/// [intensiveRunDays] liegt (PAR-059), etwa weil sie `pinned` ist oder kein
/// Tausch möglich war ([applyRunSpacingSwap]). Leer ohne solche Einheit.
List<PinnedConflict> planRunSpacingConflicts(
  List<PlanUnit> units,
  Set<DateTime> intensiveRunDays,
  DateTime today, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final hard = _nextOpenHard(units, today);
  if (hard == null) return const [];
  final d = planDay(hard.day);
  final close = [
    for (final r in intensiveRunDays)
      if (d.difference(r).inDays.abs() < parameters.minGapDays) r,
  ]..sort();
  if (close.isEmpty) return const [];
  return [
    PinnedConflict(
      kind: PinnedConflictKind.spacing,
      day: d,
      otherDay: close.first,
    ),
  ];
}

DateTime _mondayOf(DateTime d) =>
    d.subtract(Duration(days: d.weekday - DateTime.monday));

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parse(Object? v) {
  if (v is! String) return null;
  final d = DateTime.tryParse(v);
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}
