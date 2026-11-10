import '../goals/training_goal.dart';
import 'plan_course.dart';
import 'plan_inputs.dart';
import 'plan_move.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'target_intensity.dart';
import 'week_units.dart';
import 'weekly_time.dart';

/// Arten, die der Nutzer beim Ersetzen wählen kann (FR-0173). Geh-Lauf gibt
/// es nur in der Abfolge, ein Ruhetag ist „Ruhetag festlegen“.
const List<PlanUnitKind> planReplaceKinds = [
  PlanUnitKind.easy,
  PlanUnitKind.long,
  PlanUnitKind.intervals,
  PlanUnitKind.tempo,
  PlanUnitKind.progressive,
];

/// Warum eine Einheit nicht ersetzt werden kann (wie der Speicher bei
/// `PlanRepository.replaceUnit` ablehnt, dazu die fachlichen Gründe).
enum PlanReplaceBlock {
  /// Die Einheit hat einen Lauf (absolviert, eingefroren).
  unitHasRun,

  /// Die Einheit liegt vor heute (vergangen, eingefroren).
  unitPast,

  /// Ruhetag oder Geh-Lauf-Einheit der Abfolge: nicht ersetzbar.
  unitNotReplaceable,

  /// Die gewählte Art ist keine aus [planReplaceKinds].
  kindNotAllowed,

  /// Die Einheit hat diese Art schon.
  sameKind,

  /// Die harte Form passt nicht in die maximale Zeit je Einheit (PAR-198).
  exceedsMaxSession,
}

/// Ergebnis der Prüfung beim Ersetzen. Die Prüfung ändert nichts; die Art
/// ändert nur die Bestätigung des Nutzers.
class PlanReplaceCheck {
  const PlanReplaceCheck({
    required this.kind,
    this.blocked,
    this.unit,
    this.spacingDays = const [],
    this.otherHardDays = const [],
  });

  /// Die gewählte Art.
  final PlanUnitKind kind;

  /// Gesetzt, wenn nicht ersetzt werden kann.
  final PlanReplaceBlock? blocked;

  /// Die Einheit mit neuer Art, Dauer, Abschnitten und Zielintensität (wie
  /// sie gespeichert würde); `null`, wenn [blocked].
  final PlanUnit? unit;

  /// Tage intensiver Einheiten ohne vollen Kalendertag Abstand (PAR-059,
  /// PAR-060): Hinweis, keine Sperre.
  final List<DateTime> spacingDays;

  /// Tage weiterer harter Einheiten derselben Woche (PAR-198: höchstens eine
  /// je Woche): Hinweis, keine Sperre.
  final List<DateTime> otherHardDays;

  bool get allowed => blocked == null;
  bool get hasSpacingConflict => spacingDays.isNotEmpty;
  bool get hasSecondHard => otherHardDays.isNotEmpty;
}

DateTime _monday(DateTime d) =>
    d.subtract(Duration(days: d.weekday - DateTime.monday));

/// Prüft, ob [unit] die Art [kind] bekommen kann, und rechnet die Einheit
/// mit dieser Art (Dauer und Abschnitte über [planSegmentsForKind] mit der
/// Woche des Plans aus [goal] und [inputs], Zielintensität über
/// [applyTargetIntensities]).
///
/// [units] sind die gespeicherten Einheiten mindestens der Woche von [unit]
/// mit `minGapDays - 1` Tagen davor und danach; [completedIntensiveDays]
/// wie bei [checkPlanMove].
PlanReplaceCheck checkPlanReplace({
  required List<PlanUnit> units,
  required PlanUnit unit,
  required PlanUnitKind kind,
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  Iterable<DateTime> completedIntensiveDays = const [],
  PlanParameters parameters = const PlanParameters(),
}) {
  final t = planDay(today);
  final day = planDay(unit.day);
  PlanReplaceBlock? blocked;
  if (unit.runId != null) {
    blocked = PlanReplaceBlock.unitHasRun;
  } else if (day.isBefore(t)) {
    blocked = PlanReplaceBlock.unitPast;
  } else if (unit.kind == PlanUnitKind.rest ||
      unit.kind == PlanUnitKind.walkRun) {
    blocked = PlanReplaceBlock.unitNotReplaceable;
  } else if (!planReplaceKinds.contains(kind)) {
    blocked = PlanReplaceBlock.kindNotAllowed;
  } else if (kind == unit.kind) {
    blocked = PlanReplaceBlock.sameKind;
  }
  if (blocked != null) return PlanReplaceCheck(kind: kind, blocked: blocked);

  final setup = planCourseSetup(goal, inputs, parameters: parameters);
  final maxSession = setup.maxSessionMinutes;
  final week = _weekOf(setup, day, t);
  final short = week == null
      ? true
      : planWeekHasShortHardForm(week, parameters: parameters);
  if (!planKindFitsMaxSession(
    kind,
    minutes: unit.minutes,
    short: short,
    maxSessionMinutes: maxSession,
    parameters: parameters,
  )) {
    return PlanReplaceCheck(
      kind: kind,
      blocked: PlanReplaceBlock.exceedsMaxSession,
    );
  }
  final c = planSegmentsForKind(
    kind,
    minutes: unit.minutes,
    short: short,
    maxSessionMinutes: maxSession,
    parameters: parameters,
  );
  final raw = PlanUnit(
    id: unit.id,
    day: day,
    kind: kind,
    phase: unit.phase,
    weekIndex: unit.weekIndex,
    minutes: c.minutes,
    segments: c.segments,
    pinned: true,
    fixed: PlanUnitFixed.kind,
    method: unit.method,
    methodVersion: unit.methodVersion,
  );
  final replaced = applyTargetIntensities([
    raw,
  ], (inputs.intensity ?? IntensityInputs()).withAgeAt(t)).single;

  final others = [
    for (final u in units)
      if (!(u.id != null && u.id == unit.id) &&
          !(u.id == null && planDay(u.day) == day))
        u,
  ];
  final intensive = {
    for (final u in others)
      if (u.isIntensive) planDay(u.day),
    for (final r in completedIntensiveDays) planDay(r),
  };
  final m = _monday(day);
  return PlanReplaceCheck(
    kind: kind,
    unit: replaced,
    spacingDays: [
      if (replaced.isIntensive)
        for (final x in intensive)
          if (x.difference(day).inDays.abs() < parameters.minGapDays) x,
    ]..sort(),
    otherHardDays: [
      if (replaced.isHard)
        for (final u in others)
          if (u.isHard && _monday(planDay(u.day)) == m) planDay(u.day),
    ]..sort(),
  );
}

PlanWeek? _weekOf(PlanCourseSetup setup, DateTime day, DateTime today) {
  for (final w in setup.course(today: today).weeks) {
    if (!day.isBefore(w.start) &&
        day.isBefore(w.start.add(const Duration(days: 7)))) {
      return w;
    }
  }
  return null;
}

/// Warum ein Tag nicht Ruhetag werden kann.
enum PlanRestDayBlock {
  /// Der Tag liegt vor heute.
  dayPast,

  /// Die Einheit des Tags hat einen Lauf (absolviert, eingefroren).
  unitHasRun,

  /// Der Tag ist schon Ruhetag.
  alreadyRest,
}

/// Ergebnis der Prüfung beim Festlegen eines Ruhetags. Liegt auf dem Tag
/// eine Einheit ([unit]), bietet der Dialog [alternatives] an (Tage derselben
/// Woche, geprüft wie beim Verschieben); ohne passenden Tag entfällt die
/// Einheit nach Bestätigung.
class PlanRestDayCheck {
  const PlanRestDayCheck({
    required this.day,
    this.blocked,
    this.unit,
    this.alternatives = const [],
  });

  final DateTime day;
  final PlanRestDayBlock? blocked;

  /// Die offene Einheit auf dem Tag oder `null`.
  final PlanUnit? unit;

  /// Freie Tage derselben Woche ab heute, auf denen [unit] ohne
  /// Abstandskonflikt und innerhalb des Reglers läge ([checkPlanMove]);
  /// Lauftage des Ziels zuerst, dann dem Ruhetag nächster zuerst.
  final List<DateTime> alternatives;

  bool get allowed => blocked == null;

  /// Die Einheit entfällt, wenn der Nutzer keinen Alternativtag wählt.
  bool get unitDropsWithoutMove => unit != null && alternatives.isEmpty;
}

/// Prüft, ob [day] Ruhetag werden kann (Festlegungen WP22, „Ersetzen und
/// Ruhetag“). [units] wie bei [checkPlanMove] für die Woche von [day].
PlanRestDayCheck checkPlanRestDay({
  required List<PlanUnit> units,
  required DateTime day,
  required DateTime today,
  required double weeklyCapSeconds,
  Iterable<DateTime> completedIntensiveDays = const [],
  Set<int> runDays = const {},
  PlanParameters parameters = const PlanParameters(),
}) {
  final t = planDay(today);
  final d = planDay(day);
  PlanUnit? unit;
  for (final u in units) {
    if (planDay(u.day) == d) unit = u;
  }
  if (d.isBefore(t)) {
    return PlanRestDayCheck(day: d, blocked: PlanRestDayBlock.dayPast);
  }
  if (unit != null && unit.runId != null) {
    return PlanRestDayCheck(day: d, blocked: PlanRestDayBlock.unitHasRun);
  }
  if (unit != null && unit.kind == PlanUnitKind.rest) {
    return PlanRestDayCheck(day: d, blocked: PlanRestDayBlock.alreadyRest);
  }
  if (unit == null) return PlanRestDayCheck(day: d);

  final m = _monday(d);
  final alternatives = <DateTime>[];
  for (var i = 0; i < 7; i++) {
    final c = m.add(Duration(days: i));
    if (c == d) continue;
    final check = checkPlanMove(
      units: units,
      unit: unit,
      newDay: c,
      today: t,
      weeklyCapSeconds: weeklyCapSeconds,
      completedIntensiveDays: completedIntensiveDays,
      runDays: runDays,
      parameters: parameters,
    );
    if (check.allowed && !check.hasSpacingConflict && !check.overRegulator) {
      alternatives.add(c);
    }
  }
  alternatives.sort((a, b) {
    final ra = runDays.contains(a.weekday), rb = runDays.contains(b.weekday);
    if (ra != rb) return ra ? -1 : 1;
    final da = a.difference(d).inDays.abs();
    final db = b.difference(d).inDays.abs();
    return da != db ? da.compareTo(db) : a.compareTo(b);
  });
  return PlanRestDayCheck(day: d, unit: unit, alternatives: alternatives);
}

/// Die Ruhetag-Einheit für [day] (`rest`, 0 min, Termin bestätigt,
/// [PlanUnitFixed.day]); Woche und Phase aus dem Plan zu [goal] und
/// [inputs] (Woche ab dem Anker; außerhalb des Verlaufs die Phase der
/// letzten Woche).
PlanUnit planRestDayUnit({
  required DateTime day,
  required TrainingGoal goal,
  required PlanInputs inputs,
  required DateTime today,
  PlanParameters parameters = const PlanParameters(),
}) {
  final d = planDay(day);
  final t = planDay(today);
  final setup = planCourseSetup(goal, inputs, parameters: parameters);
  final weeks = setup.course(today: t).weeks;
  final week = _weekOf(setup, d, t);
  final anchor = planDay(inputs.anchor);
  final index = d.isBefore(anchor) ? 0 : d.difference(anchor).inDays ~/ 7;
  return PlanUnit(
    day: d,
    kind: PlanUnitKind.rest,
    phase: week?.phase ?? (weeks.isEmpty ? PlanPhase.entry : weeks.last.phase),
    weekIndex: week?.index ?? index,
    minutes: 0,
    segments: const [],
    pinned: true,
    fixed: PlanUnitFixed.day,
  );
}
