import '../goals/training_goal.dart';
import 'plan_course.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'target_intensity.dart';
import 'week_units.dart';
import 'weekly_time.dart';

/// Warum ein vom Nutzer verschobener Termin nicht oder nur mit Konflikt
/// übernommen wurde.
enum PinnedConflictKind {
  /// Der Abstand zwischen intensiven Einheiten (FR-0152, PAR-060) ist
  /// verletzt. Die Einheit liegt trotzdem auf dem Pinned-Tag; der Nutzer
  /// entscheidet.
  spacing,

  /// Der Tag trägt schon eine eingefrorene Einheit; die Einheit blieb auf
  /// ihrem Tag.
  dayTaken,

  /// Keine erzeugte Einheit in der Woche übrig (andere Zahl der Läufe,
  /// Woche außerhalb des Plans oder Tag vor heute); der Termin wurde nicht
  /// übernommen.
  noMatchingUnit,
}

/// Konflikt eines Pinned-Termins, nur gemeldet, nie automatisch gelöst.
class PinnedConflict {
  const PinnedConflict({required this.kind, required this.day, this.otherDay});

  final PinnedConflictKind kind;

  /// Tag des Pinned-Termins.
  final DateTime day;

  /// Bei [PinnedConflictKind.spacing]: Tag der zu nahen intensiven Einheit.
  final DateTime? otherDay;
}

/// Ergebnis von [generatePlan].
class GeneratedPlan {
  const GeneratedPlan({
    required this.version,
    required this.weeks,
    required this.units,
    required this.frozenUnits,
    required this.unplacedByWeek,
    required this.hardOmissions,
    this.droppedDaysByWeek = const {},
    this.pinnedConflicts = const [],
    this.walkRunStaysAtWeek,
    this.walkRunNoWeekFits = false,
  });

  final PlanVersion version;

  /// Verlauf der Wochenzeit ab der Woche von „heute“.
  final List<PlanWeek> weeks;

  /// Die neuen künftigen Einheiten (Tag ab heute, ohne feste Einheit auf dem
  /// Tag), nach Tag sortiert.
  final List<PlanUnit> units;

  /// Die übergebenen eingefrorenen Einheiten, unverändert, nach Tag sortiert.
  final List<PlanUnit> frozenUnits;

  /// Wochenzeit, die wegen der maximalen Zeit je Einheit keinen Platz fand
  /// (gemeldet, nicht verworfen).
  int get unplacedMinutes => unplacedByWeek.values.fold(0, (a, b) => a + b);

  /// Nicht untergebrachte Minuten je Woche (Nummer ab Anker), nur Wochen mit
  /// künftigen Einheiten und Rest > 0.
  final Map<int, int> unplacedByWeek;

  /// Wochen (Nummer ab Anker), in denen eine gewünschte harte Einheit fehlt.
  final Map<int, HardOmission> hardOmissions;

  /// Tage geplanter Einheiten, die still entfielen, je Woche (Nummer ab
  /// Anker): die Wochenzeit ließ nach den eingefrorenen Einheiten keinen
  /// Platz, oder eine Einheit wäre 0 min lang gewesen. Der Aufrufer zeigt
  /// das an; die Zahl der Läufe der Woche sinkt dann.
  final Map<int, List<DateTime>> droppedDaysByWeek;

  /// Konflikte der übergebenen Pinned-Einheiten (leer, wenn alle ohne
  /// Verletzung übernommen sind).
  final List<PinnedConflict> pinnedConflicts;

  /// Die Geh-Lauf-Abfolge bleibt bei dieser Programmwoche (ab 0), weil die
  /// nächste nicht in die maximale Zeit je Einheit passt (PAR-141); der
  /// Aufrufer zeigt das an. `null`: sie läuft durch oder fehlt.
  final int? walkRunStaysAtWeek;

  /// Zu [walkRunStaysAtWeek]: schon die erste Einheit passt nicht.
  final bool walkRunNoWeekFits;

  /// Kopie mit anderen neuen Einheiten und Konflikten (für den Dienst, der
  /// den Zeitplan festhält).
  GeneratedPlan copyWith({
    List<PlanUnit>? units,
    List<PinnedConflict>? pinnedConflicts,
  }) => GeneratedPlan(
    version: version,
    weeks: weeks,
    units: units ?? this.units,
    frozenUnits: frozenUnits,
    unplacedByWeek: unplacedByWeek,
    hardOmissions: hardOmissions,
    droppedDaysByWeek: droppedDaysByWeek,
    pinnedConflicts: pinnedConflicts ?? this.pinnedConflicts,
    walkRunStaysAtWeek: walkRunStaysAtWeek,
    walkRunNoWeekFits: walkRunNoWeekFits,
  );

  /// Eingefrorene und neue Einheiten, nach Tag sortiert.
  List<PlanUnit> get allUnits => _byDay([...frozenUnits, ...units]);
}

List<PlanUnit> _byDay(List<PlanUnit> l) {
  // Stabil: gleicher Tag behält die Reihenfolge.
  final idx = {for (var i = 0; i < l.length; i++) l[i]: i};
  return [...l]..sort((a, b) {
    final c = a.day.compareTo(b.day);
    return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
  });
}

/// Plan ab heute (ADR-0010 Punkt 2, 3, 6; PAR-192 bis PAR-199, FR-0141 bis
/// FR-0152). Rein: kein `DateTime.now()`, kein Zufall, kein Speicher.
///
/// [frozenUnits] (Tag vor heute oder Lauf zugeordnet) bleiben unverändert, ihre
/// Minuten zählen zur Wochenzeit ihrer Woche. Tage vor [today] ohne Einheit
/// gelten als ausgefallen und werden nicht nachgeholt (PAR-201). Weicht die
/// Summe der eingefrorenen Einheiten einer Woche von der Planung ab, gleichen
/// die künftigen lockeren und langen Einheiten dieser Woche den Unterschied
/// aus; harte Einheiten bleiben unverändert.
///
/// [pinnedUnits] sind künftige, vom Nutzer verschobene Termine (ADR-0010
/// Punkt 4): Die erzeugte Einheit derselben Rolle (langer Lauf, harte
/// Einheit, lockerer Lauf) in der Woche liegt auf dem Pinned-Tag und trägt
/// `pinned`; ihr Inhalt wird neu gerechnet, die Zahl der Läufe bleibt. Ein
/// Tausch mit einer anderen erzeugten Einheit füllt den frei gewordenen Tag.
/// Verletzt das den Abstand, bleibt der Termin und der Konflikt steht in
/// [GeneratedPlan.pinnedConflicts].
GeneratedPlan generatePlan(
  TrainingGoal goal,
  PlanInputs inputs,
  List<PlanUnit> frozenUnits,
  DateTime today, {
  List<PlanUnit> pinnedUnits = const [],
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final todayDay = planDay(today);
  final setup = planCourseSetup(goal, inputs, parameters: p);
  final maxSession = setup.maxSessionMinutes;
  final walkRun = setup.walkRun;
  final course = setup.course(today: todayDay);

  final frozen = _byDay([...frozenUnits]);
  final firstStart = course.weeks.isEmpty ? null : course.weeks.first.start;
  var hardOrdinal = firstStart == null
      ? 0
      : frozen.where((u) => u.isHard && u.day.isBefore(firstStart)).length;

  // Einheiten je Woche (Montag -> Einheiten), eingefroren und neu, für den
  // Abstand über den Wochenwechsel.
  final byWeek = <DateTime, List<PlanUnit>>{};
  for (final u in frozen) {
    final m = u.day.subtract(Duration(days: u.day.weekday - 1));
    (byWeek[m] ??= []).add(u);
  }

  final pinnedLeft = <PlanUnit>[
    for (final u in pinnedUnits)
      if (u.runId == null && !planDay(u.day).isBefore(todayDay)) u,
  ];
  final conflicts = <PinnedConflict>[
    for (final u in pinnedUnits)
      if (u.runId != null || planDay(u.day).isBefore(todayDay))
        PinnedConflict(
          kind: PinnedConflictKind.noMatchingUnit,
          day: planDay(u.day),
        ),
  ];

  final created = <PlanUnit>[];
  final omissions = <int, HardOmission>{};
  final unplaced = <int, int>{};
  final dropped = <int, List<DateTime>>{};

  for (final week in course.weeks) {
    final start = week.start;
    final end = start.add(const Duration(days: 7));
    final frozenWeek = [
      for (final u in frozen)
        if (!u.day.isBefore(start) && u.day.isBefore(end)) u,
    ];
    final frozenDays = {for (final u in frozenWeek) u.day};
    final frozenHard = frozenWeek.any((u) => u.isHard);

    int? prevWeekday;
    final prevUnits = byWeek[start.subtract(const Duration(days: 7))];
    if (prevUnits != null) {
      for (final u in prevUnits) {
        if (u.isIntensive &&
            (prevWeekday == null || u.day.weekday > prevWeekday)) {
          prevWeekday = u.day.weekday;
        }
      }
    }

    final walkPlan = walkRun?.plan(week.index, week);
    final planned = walkPlan != null
        ? PlannedWeek(
            units: walkPlan.units,
            unplacedMinutes: 0,
            hardOmission: null,
          )
        : planWeekUnits(
            week: week,
            runDays: goal.runDays,
            maxSessionMinutes: maxSession,
            hardEnabled: goal.hardSessionEnabled,
            continuous30: canRunContinuous30(
              goal,
              weekIndex: week.index,
              walkRunWeeks: setup.walkRunWeeks,
              parameters: p,
            ),
            hardOrdinal: hardOrdinal,
            previousIntensiveWeekday: prevWeekday,
            parameters: p,
          );

    // Eingefrorene Einheiten der Woche haben Vorrang (FR-0152, PAR-196,
    // PAR-198): Höchstens eine harte Einheit und ein langer Lauf je Woche, und
    // zu einer eingefrorenen intensiven Einheit hält jede neue intensive den
    // Abstand ([PlanParameters.minGapDays]). Sonst wird die geplante Einheit
    // ein lockerer Lauf gleicher Dauer. Das gilt auch, wenn der Nutzer die
    // Lauftage geändert hat und die eingefrorenen Einheiten auf anderen Tagen
    // liegen als die neu geplanten.
    final frozenLong = frozenWeek.any((u) => u.kind == PlanUnitKind.long);
    final frozenIntensive = [
      for (final u in frozenWeek)
        if (u.isIntensive) u.day,
    ];
    bool tooClose(PlanUnit u) => frozenIntensive.any(
      (d) => u.day.difference(d).inDays.abs() < p.minGapDays,
    );
    var future = <PlanUnit>[
      for (final u in planned.units)
        if (!u.day.isBefore(todayDay) && !frozenDays.contains(u.day))
          (frozenHard && u.isHard) ||
                  (frozenLong && u.kind == PlanUnitKind.long) ||
                  (u.isIntensive && tooClose(u))
              ? _asEasy(u)
              : u,
    ];

    // Wochenminuten der eingefrorenen Einheiten anrechnen: Unterschied zur
    // Planung auf diesen Tagen.
    var deviation = 0;
    var frozenMinutes = 0;
    for (final u in frozenWeek) {
      deviation += u.minutes;
      frozenMinutes += u.minutes;
    }
    for (final u in planned.units) {
      if (frozenDays.contains(u.day)) deviation -= u.minutes;
    }
    if (deviation != 0 && walkPlan == null) {
      future = _absorb(future, -deviation, maxSession);
    }
    // Die Woche liegt nie über der Wochenzeit (Regler): Reicht der Rest nach
    // den eingefrorenen Einheiten nicht für jede Einheit mindestens 1 min,
    // entfallen die letzten lockeren, zuletzt die langen und harten.
    final weekMinutes = week.minutes;
    if (weekMinutes != null && walkPlan == null) {
      final fitted = _fitBudget(future, weekMinutes - frozenMinutes);
      future = fitted.kept;
      if (fitted.droppedDays.isNotEmpty) {
        (dropped[week.index] ??= []).addAll(fitted.droppedDays);
      }
    }
    if (walkPlan != null) {
      // Geh-Lauf-Woche: Die Zahl der Einheiten der Abfolge gilt für die ganze
      // Woche, eingefrorene Einheiten (auf anderen Tagen, etwa nach geänderten
      // Lauftagen) zählen mit; was darüber liegt, entfällt (letzte zuerst).
      final allowed = walkPlan.units.length - frozenWeek.length;
      if (future.length > allowed) {
        final keep = allowed < 0 ? 0 : allowed;
        (dropped[week.index] ??= []).addAll([
          for (final u in future.skip(keep)) u.day,
        ]);
        future = future.take(keep).toList();
      }
    }
    final zero = [
      for (final d in planned.droppedDays)
        if (!d.isBefore(todayDay) && !frozenDays.contains(d)) d,
    ];
    if (zero.isNotEmpty) (dropped[week.index] ??= []).addAll(zero);

    final weekPinned = [
      for (final u in pinnedLeft)
        if (!planDay(u.day).isBefore(start) && planDay(u.day).isBefore(end)) u,
    ];
    pinnedLeft.removeWhere(weekPinned.contains);
    final moved = <DateTime>{};
    if (weekPinned.isNotEmpty) {
      final r = _applyPinned(future, weekPinned, frozenDays);
      future = r.units;
      conflicts.addAll(r.conflicts);
      moved.addAll(r.movedDays);
    }

    if (future.isNotEmpty) {
      if (planned.unplacedMinutes > 0) {
        unplaced[week.index] = planned.unplacedMinutes;
      }
      final om = planned.hardOmission;
      if (om != null) omissions[week.index] = om;
    }
    created.addAll(future);
    byWeek[start] = [...frozenWeek, ...future];
    if (byWeek[start]!.any((u) => u.isHard)) hardOrdinal++;
    if (moved.isNotEmpty) {
      conflicts.addAll(
        _spacingConflicts(
          [
            ...?byWeek[start.subtract(const Duration(days: 7))],
            ...byWeek[start]!,
          ],
          moved,
          p.minGapDays,
        ),
      );
    }
  }
  // Pinned-Termine außerhalb des Plans (kein Verlauf für ihre Woche).
  for (final u in pinnedLeft) {
    conflicts.add(
      PinnedConflict(
        kind: PinnedConflictKind.noMatchingUnit,
        day: planDay(u.day),
      ),
    );
  }

  // Zielintensität nur für die neuen Einheiten; eingefrorene behalten ihre
  // Werte (FR-0153, ADR-0010 Punkt 11).
  final withIntensity = applyTargetIntensities(
    _byDay(created),
    (inputs.intensity ?? IntensityInputs()).withAgeAt(todayDay),
  );

  return GeneratedPlan(
    version: PlanVersion.current,
    weeks: course.weeks,
    units: withIntensity,
    walkRunStaysAtWeek: walkRun?.stayWeek,
    walkRunNoWeekFits: walkRun?.noWeekFits ?? false,
    frozenUnits: frozen,
    unplacedByWeek: unplaced,
    hardOmissions: omissions,
    droppedDaysByWeek: {
      for (final e in dropped.entries) e.key: (e.value..sort()),
    },
    pinnedConflicts: conflicts,
  );
}

int _role(PlanUnit u) => u.isHard
    ? 2
    : u.kind == PlanUnitKind.long
    ? 1
    : 0;

PlanUnit _moved(PlanUnit u, DateTime day, {required bool pinned}) => PlanUnit(
  day: day,
  kind: u.kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: u.minutes,
  segments: u.segments,
  id: u.id,
  runId: u.runId,
  pinned: pinned,
  method: u.method,
  methodVersion: u.methodVersion,
);

class _Pinned {
  const _Pinned(this.units, this.conflicts, this.movedDays);
  final List<PlanUnit> units;
  final List<PinnedConflict> conflicts;
  final Set<DateTime> movedDays;
}

/// Legt die Pinned-Tage auf die erzeugten Einheiten der Woche: je Pinned-Tag
/// die Einheit derselben Rolle (sonst eine übrige). Erzeugte Einheiten auf
/// einem Pinned-Tag weichen auf die frei gewordenen Tage aus.
_Pinned _applyPinned(
  List<PlanUnit> future,
  List<PlanUnit> pinned,
  Set<DateTime> frozenDays,
) {
  final conflicts = <PinnedConflict>[];
  final out = [...future];
  final assigned = <int, DateTime>{}; // Index -> Pinned-Tag
  final byDay = [...pinned]..sort((a, b) => a.day.compareTo(b.day));
  final todo = <PlanUnit>[];
  final seenDays = <DateTime>{};
  for (final u in byDay) {
    final d = planDay(u.day);
    if (frozenDays.contains(d)) {
      conflicts.add(PinnedConflict(kind: PinnedConflictKind.dayTaken, day: d));
    } else if (seenDays.add(d)) {
      todo.add(u);
    }
  }
  for (var pass = 0; pass < 2; pass++) {
    final rest = <PlanUnit>[];
    for (final u in todo) {
      var hit = -1;
      for (var i = 0; i < out.length; i++) {
        if (assigned.containsKey(i)) continue;
        if (pass == 1 || _role(out[i]) == _role(u)) {
          hit = i;
          break;
        }
      }
      if (hit < 0) {
        rest.add(u);
      } else {
        assigned[hit] = planDay(u.day);
      }
    }
    todo
      ..clear()
      ..addAll(rest);
  }
  for (final u in todo) {
    conflicts.add(
      PinnedConflict(
        kind: PinnedConflictKind.noMatchingUnit,
        day: planDay(u.day),
      ),
    );
  }
  if (assigned.isEmpty) return _Pinned(out, conflicts, const {});

  final pinnedDays = assigned.values.toSet();
  final freed = [
    for (final i in assigned.keys)
      if (!pinnedDays.contains(out[i].day)) out[i].day,
  ]..sort();
  final movedDays = <DateTime>{};
  for (var i = 0; i < out.length; i++) {
    final target = assigned[i];
    if (target != null) {
      out[i] = _moved(out[i], target, pinned: true);
      movedDays.add(target);
    } else if (pinnedDays.contains(out[i].day) && freed.isNotEmpty) {
      out[i] = _moved(out[i], freed.removeAt(0), pinned: out[i].pinned);
    }
  }
  out.sort((a, b) => a.day.compareTo(b.day));
  return _Pinned(out, conflicts, movedDays);
}

/// Meldet aufeinanderfolgende intensive Einheiten (langer Lauf, harte
/// Einheit) mit weniger als [gap] Tagen Abstand, wenn eine davon ein
/// übernommener Pinned-Termin ist (FR-0152, PAR-060).
List<PinnedConflict> _spacingConflicts(
  List<PlanUnit> units,
  Set<DateTime> pinnedDays,
  int gap,
) {
  final intensive = [
    for (final u in units)
      if (u.isIntensive) u,
  ]..sort((a, b) => a.day.compareTo(b.day));
  final out = <PinnedConflict>[];
  for (var i = 1; i < intensive.length; i++) {
    final a = intensive[i - 1], b = intensive[i];
    if (b.day.difference(a.day).inDays >= gap) continue;
    if (pinnedDays.contains(b.day)) {
      out.add(
        PinnedConflict(
          kind: PinnedConflictKind.spacing,
          day: b.day,
          otherDay: a.day,
        ),
      );
    }
    if (pinnedDays.contains(a.day)) {
      out.add(
        PinnedConflict(
          kind: PinnedConflictKind.spacing,
          day: a.day,
          otherDay: b.day,
        ),
      );
    }
  }
  return out;
}

/// Lässt Einheiten entfallen (zuerst lockere, dann lange, zuletzt harte; je
/// Rolle die späteste), bis ihre Summe höchstens [budget] ist.
({List<PlanUnit> kept, List<DateTime> droppedDays}) _fitBudget(
  List<PlanUnit> units,
  int budget,
) {
  final out = [...units];
  final droppedDays = <DateTime>[];
  int sum() => out.fold(0, (a, u) => a + u.minutes);
  while (out.isNotEmpty && sum() > budget) {
    var drop = 0;
    for (var i = 1; i < out.length; i++) {
      final a = _role(out[i]), b = _role(out[drop]);
      if (a < b || (a == b && out[i].day.isAfter(out[drop].day))) drop = i;
    }
    droppedDays.add(out.removeAt(drop).day);
  }
  return (kept: out, droppedDays: droppedDays);
}

PlanUnit _asEasy(PlanUnit u) => PlanUnit(
  day: u.day,
  kind: PlanUnitKind.easy,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: u.minutes,
  segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: u.minutes)],
  pinned: u.pinned,
  method: u.method,
  methodVersion: u.methodVersion,
);

/// Verteilt [delta] Minuten (auch negativ) gleichmäßig auf die nicht harten
/// Einheiten; Reste auf die früheren. Jede Einheit bleibt zwischen 1 min und
/// der maximalen Zeit.
List<PlanUnit> _absorb(List<PlanUnit> units, int delta, int maxSession) {
  final idx = [
    for (var i = 0; i < units.length; i++)
      if (!units[i].isHard) i,
  ];
  if (idx.isEmpty) return units;
  final out = [...units];
  final base = delta ~/ idx.length; // zur Null hin gerundet
  var rest = delta - base * idx.length;
  final step = rest < 0 ? -1 : 1;
  for (final i in idx) {
    var d = base;
    if (rest != 0) {
      d += step;
      rest -= step;
    }
    final u = out[i];
    var m = u.minutes + d;
    if (m < 1) m = 1;
    if (m > maxSession) m = maxSession;
    if (m == u.minutes) continue;
    out[i] = PlanUnit(
      day: u.day,
      kind: u.kind,
      phase: u.phase,
      weekIndex: u.weekIndex,
      minutes: m,
      segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: m)],
      pinned: u.pinned,
      method: u.method,
      methodVersion: u.methodVersion,
    );
  }
  return out;
}
