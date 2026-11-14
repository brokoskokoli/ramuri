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

  /// Der Nutzer hat die Art der Einheit ersetzt ([PlanUnitFixed.keepsKind]), die
  /// Woche ist aber eine Geh-Lauf-Woche: Die Abfolge hat Vorrang, der Termin
  /// bleibt, die ersetzte Art entfällt.
  walkRunFirst,
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
    this.hardFit = HardFitStatus.notApplicable,
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

  /// Zeitziel mit harter Einheit: ob der Plan bis zur Passform-Wochenzeit
  /// steigt oder warum nicht ([HardFitStatus.regulatorBelowFit],
  /// [HardFitStatus.partialAtPeak], [HardFitStatus.neverFits]); der Aufrufer zeigt den Grund an.
  final HardFitStatus hardFit;

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
    hardFit: hardFit,
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
///
/// [heldDays] sind die Tage der bisherigen künftigen Einheiten, die ein
/// automatischer Auslöser hält (ADR-0010 Punkt 8), bis [heldUntil]
/// (exklusiv): Dort entstehen nicht mehr Einheiten als gehaltene Tage. Eine
/// erzeugte Einheit auf einem nicht gehaltenen Tag entfällt (zuerst die
/// lockeren, dann die späteren). Ihre geplanten Minuten gelten als abgedeckt
/// vom absolvierten Lauf auf einem verschobenen Tag (eingefroren, `pinned`,
/// Tag ohne geplante Einheit; je Lauf eine Einheit, auch eine schon
/// vergangene): Die Wochenzeit bleibt erhalten.
GeneratedPlan generatePlan(
  TrainingGoal goal,
  PlanInputs inputs,
  List<PlanUnit> frozenUnits,
  DateTime today, {
  List<PlanUnit> pinnedUnits = const [],
  Set<DateTime>? heldDays,
  DateTime? heldUntil,
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final todayDay = planDay(today);
  final setup = planCourseSetup(goal, inputs, parameters: p);
  final maxSession = setup.maxSessionMinutes;
  final walkRun = setup.walkRun;
  final course = setup.course(today: todayDay);

  final frozen = _byDay([...frozenUnits]);
  // Rotation der harten Formen (PAR-198): Sie rückt in jeder Woche weiter, in
  // der eine harte Einheit vorgesehen war, auch wenn die Form wegen der
  // maximalen Zeit zum lockeren Lauf wurde. Für die Wochen vor dem Verlauf
  // (eingefroren) zählen die Wochen, in denen das Ziel sie vorsieht; so setzt
  // die Neuberechnung die Rotation des ursprünglichen Plans fort.
  var hardOrdinal = 0;
  if (course.weeks.isNotEmpty &&
      goal.hardSessionEnabled &&
      goal.runDays.length >= p.hardMinRunDays) {
    for (var i = 0; i < course.weeks.first.index; i++) {
      final inProgram = walkRun != null && i < setup.walkRunWeeks;
      if (!inProgram &&
          planCanRunContinuous30(
            goal,
            inputs,
            weekIndex: i,
            walkRunWeeks: setup.walkRunWeeks,
            parameters: p,
          )) {
        hardOrdinal++;
      }
    }
  }

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
    // Eine vom Nutzer zum lockeren Lauf ersetzte harte Einheit (easyForHard)
    // zählt auch eingefroren als harte Einheit der Woche.
    final frozenReplaced = frozenWeek.any(
      (u) => u.fixed == PlanUnitFixed.easyForHard,
    );
    final frozenHard = frozenReplaced || frozenWeek.any((u) => u.isHard);

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
            continuous30: planCanRunContinuous30(
              goal,
              inputs,
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
    // Nach Ermüdung (PAR-201) oder Pause (PAR-202) keine harte Einheit bis
    // [PlanInputs.noHardUntil]: sie wird ein lockerer Lauf gleicher Dauer.
    final noHardUntil = inputs.noHardUntil;
    bool noHard(PlanUnit u) =>
        noHardUntil != null && !u.day.isAfter(noHardUntil);
    var future = <PlanUnit>[
      for (final u in planned.units)
        if (!u.day.isBefore(todayDay) && !frozenDays.contains(u.day))
          (frozenHard && u.isHard) ||
                  (frozenLong && u.kind == PlanUnitKind.long) ||
                  (u.isIntensive && tooClose(u)) ||
                  (u.isHard && noHard(u))
              ? _asEasy(u)
              : u,
    ];

    // Wochenminuten der eingefrorenen Einheiten anrechnen: Unterschied zur
    // Planung auf diesen Tagen.
    var deviation = 0;
    var frozenMinutes = 0;
    if (heldDays != null &&
        heldUntil != null &&
        start.isBefore(heldUntil) &&
        walkPlan == null) {
      // Ein vom Nutzer verschobener und absolvierter Lauf (eingefroren,
      // `pinned`) auf einem Tag ohne geplante Einheit ersetzt eine geplante
      // Einheit der Woche (F1): Deren Minuten gelten als abgedeckt, sie sind
      // keine Abweichung. Das gilt höchstens je so einen Lauf, zuerst für die
      // Einheit, die schon vor heute liegt und entfallen ist, dann für die
      // künftige auf einem nicht gehaltenen Tag, die nicht mehr entsteht.
      final plannedDays = {for (final u in planned.units) planDay(u.day)};
      var quota = frozenWeek
          .where((u) => u.pinned && !plannedDays.contains(planDay(u.day)))
          .length;
      for (final u in planned.units) {
        if (quota == 0) break;
        if (planDay(u.day).isBefore(todayDay) &&
            !frozenDays.contains(u.day) &&
            !heldDays.contains(planDay(u.day))) {
          deviation -= u.minutes;
          quota--;
        }
      }
      final free = heldDays
          .where(
            (d) =>
                !d.isBefore(start) &&
                d.isBefore(end) &&
                !frozenDays.contains(d),
          )
          .length;
      var surplus = future.length - free;
      while (surplus > 0) {
        var pick = -1;
        for (var i = 0; i < future.length; i++) {
          if (heldDays.contains(planDay(future[i].day))) continue;
          if (pick < 0 ||
              _role(future[i]) < _role(future[pick]) ||
              (_role(future[i]) == _role(future[pick]) &&
                  future[i].day.isAfter(future[pick].day))) {
            pick = i;
          }
        }
        if (pick < 0) break;
        if (quota > 0) {
          deviation -= future[pick].minutes;
          quota--;
        }
        future = [...future]..removeAt(pick);
        surplus--;
      }
    }
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
      // Lauftagen) zählen mit. Die Abfolge ist schon um die eingefrorenen
      // Einheiten vorgerückt: Es bleiben die noch fehlenden, also die letzten
      // der Woche (etwa der Dauerlauf in Woche 5); die ersten entfallen.
      // Einheiten vor dem Start der Abfolge ([PlanInputs.walkRunFrom], etwa
      // nach „Lauf wiederholen“ mitten in der Woche) gehören nicht zu ihr.
      final from = inputs.walkRunFrom;
      final inSequence = frozenWeek
          .where((u) => from == null || !planDay(u.day).isBefore(from))
          .length;
      final allowed = walkPlan.units.length - inSequence;
      if (future.length > allowed) {
        final keep = allowed < 0 ? 0 : allowed;
        final cut = future.length - keep;
        (dropped[week.index] ??= []).addAll([
          for (final u in future.take(cut)) u.day,
        ]);
        future = future.skip(cut).toList();
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
    var hardReplaced = false;
    if (weekPinned.isNotEmpty) {
      final r = _applyPinned(
        future,
        weekPinned,
        frozenDays,
        short: planWeekHasShortHardForm(week, parameters: p),
        maxSession: maxSession,
        parameters: p,
      );
      future = r.units;
      conflicts.addAll(r.conflicts);
      moved.addAll(r.movedDays);
      hardReplaced = r.hardReplaced;
    }

    if (future.isNotEmpty) {
      if (planned.unplacedMinutes > 0) {
        unplaced[week.index] = planned.unplacedMinutes;
      }
      final om = hardReplaced || frozenReplaced
          ? HardOmission.replacedByUser
          : planned.hardOmission;
      if (om != null) omissions[week.index] = om;
    }
    created.addAll(future);
    byWeek[start] = [...frozenWeek, ...future];
    if (planned.hardIntended) hardOrdinal++;
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
    droppedDaysByWeek: planDroppedWithoutRestDays({
      for (final e in dropped.entries) e.key: (e.value..sort()),
    }, created),
    pinnedConflicts: conflicts,
    hardFit: setup.hardFit,
  );
}

/// Die entfallenen Tage je Woche ([GeneratedPlan.droppedDaysByWeek]) ohne
/// die Tage, die in [units] ein Ruhetag des Nutzers sind
/// ([PlanUnit.isRestDay]): Dort entfällt kein Lauftag, der Nutzer hat den
/// Ruhetag festgelegt. Wochen ohne übrige Tage fallen weg. Gilt für die
/// Rechnung ([generatePlan], der Ruhetag landet erst nach der Kürzung auf
/// dem Tag) und für gespeicherte Hinweise ([planHintsFromSummary], der
/// Ruhetag wird ohne Neuberechnung festgelegt).
Map<int, List<DateTime>> planDroppedWithoutRestDays(
  Map<int, List<DateTime>> dropped,
  Iterable<PlanUnit> units,
) {
  final rest = {
    for (final u in units)
      if (u.isRestDay) planDay(u.day),
  };
  if (rest.isEmpty) return dropped;
  return {
    for (final e in dropped.entries)
      if (e.value.any((d) => !rest.contains(planDay(d))))
        e.key: [
          for (final d in e.value)
            if (!rest.contains(planDay(d))) d,
        ],
  };
}

int _role(PlanUnit u) => u.isHard
    ? 2
    : u.kind == PlanUnitKind.long
    ? 1
    : 0;

PlanUnit _moved(
  PlanUnit u,
  DateTime day, {
  required bool pinned,
  PlanUnitFixed? fixed,
}) => PlanUnit(
  day: day,
  kind: u.kind,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: u.minutes,
  segments: u.segments,
  id: u.id,
  runId: u.runId,
  pinned: pinned,
  fixed: fixed ?? u.fixed,
  method: u.method,
  methodVersion: u.methodVersion,
);

/// Die erzeugte Einheit [u] mit der vom Nutzer festgelegten Art [kind]
/// ([PlanUnitFixed.kind]): Dauer und Abschnitte neu, ohne Zielintensität
/// (die setzt [applyTargetIntensities] danach).
PlanUnit _withKind(
  PlanUnit u,
  PlanUnitKind kind, {
  required bool short,
  required int maxSession,
  required PlanParameters parameters,
  PlanUnitFixed fixed = PlanUnitFixed.kind,
}) {
  final c = planSegmentsForKind(
    kind,
    minutes: u.minutes,
    short: short,
    maxSessionMinutes: maxSession,
    parameters: parameters,
  );
  return PlanUnit(
    day: u.day,
    kind: kind,
    phase: u.phase,
    weekIndex: u.weekIndex,
    minutes: c.minutes,
    segments: c.segments,
    id: u.id,
    runId: u.runId,
    pinned: u.pinned,
    fixed: fixed,
    method: u.method,
    methodVersion: u.methodVersion,
  );
}

class _Pinned {
  const _Pinned(
    this.units,
    this.conflicts,
    this.movedDays, {
    this.hardReplaced = false,
  });
  final List<PlanUnit> units;
  final List<PinnedConflict> conflicts;
  final Set<DateTime> movedDays;

  /// Der Nutzer hat die harte Einheit der Woche durch einen lockeren Lauf
  /// ersetzt; sie wird nicht auf einen anderen Tag verlegt.
  final bool hardReplaced;
}

/// Legt die Pinned-Tage auf die erzeugten Einheiten der Woche: je Pinned-Tag
/// die Einheit derselben Rolle (sonst eine übrige). Erzeugte Einheiten auf
/// einem Pinned-Tag weichen auf die frei gewordenen Tage aus.
///
/// Ruhetage des Nutzers ([PlanUnit.isRestDay]) nehmen keine erzeugte Einheit
/// auf: Sie bleiben als Ruhetag im Plan, und eine erzeugte Einheit auf dem
/// Tag weicht auf einen frei gewordenen Tag aus oder entfällt (der Nutzer
/// hat das beim Festlegen bestätigt). Hat der Nutzer die Art ersetzt
/// ([PlanUnitFixed.kind]), bekommt die Einheit auf dem Tag diese Art; Dauer
/// und Abschnitte rechnet [planSegmentsForKind] neu.
///
/// Hat der Nutzer eine harte Einheit zum lockeren Lauf gemacht
/// ([PlanUnitFixed.easyForHard], Festlegung WP22), nimmt diese Einheit die
/// harte Einheit ihrer Woche auf, unabhängig vom Tag (auch nach Verschieben,
/// geänderten Lauftagen oder wenn die Rechnung die harte Einheit anders
/// legt): Die Woche hat dann keine harte Einheit, sie wird nicht auf einen
/// anderen Tag verlegt. Eine ersetzte harte Art übernimmt
/// dagegen über die Rolle die harte Einheit der Woche (deren Tag wird
/// locker). In einer Geh-Lauf-Woche hat die Abfolge Vorrang: Der Termin
/// bleibt, die ersetzte Art entfällt ([PinnedConflictKind.walkRunFirst]).
_Pinned _applyPinned(
  List<PlanUnit> future,
  List<PlanUnit> pinned,
  Set<DateTime> frozenDays, {
  required bool short,
  required int maxSession,
  required PlanParameters parameters,
}) {
  final conflicts = <PinnedConflict>[];
  final out = [...future];
  final assigned = <int, PlanUnit>{}; // Index -> Pinned-Einheit
  final byDay = [...pinned]..sort((a, b) => a.day.compareTo(b.day));
  final todo = <PlanUnit>[];
  final restUnits = <PlanUnit>[];
  final seenDays = <DateTime>{};
  for (final u in byDay) {
    final d = planDay(u.day);
    if (frozenDays.contains(d)) {
      conflicts.add(PinnedConflict(kind: PinnedConflictKind.dayTaken, day: d));
    } else if (seenDays.add(d)) {
      (u.isRestDay ? restUnits : todo).add(u);
    }
  }
  final restDays = {for (final u in restUnits) planDay(u.day)};
  var hardReplaced = false;
  for (final u in [...todo]) {
    if (u.fixed != PlanUnitFixed.easyForHard) continue;
    final i = out.indexed
        .where((e) => e.$2.isHard && !assigned.containsKey(e.$1))
        .firstOrNull
        ?.$1;
    if (i != null) {
      assigned[i] = u;
      todo.remove(u);
      hardReplaced = true;
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
        assigned[hit] = u;
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
  if (assigned.isEmpty && restUnits.isEmpty) {
    return _Pinned(out, conflicts, const {});
  }

  final pinnedDays = {for (final u in assigned.values) planDay(u.day)};
  final freed = [
    for (final i in assigned.keys)
      if (!pinnedDays.contains(out[i].day) && !restDays.contains(out[i].day))
        out[i].day,
  ]..sort();
  final movedDays = <DateTime>{};
  final kept = <PlanUnit>[];
  for (var i = 0; i < out.length; i++) {
    final target = assigned[i];
    if (target != null) {
      final day = planDay(target.day);
      final walkRunFirst =
          target.fixed.keepsKind && out[i].kind == PlanUnitKind.walkRun;
      if (walkRunFirst) {
        conflicts.add(
          PinnedConflict(kind: PinnedConflictKind.walkRunFirst, day: day),
        );
      }
      final placed = _moved(
        out[i],
        day,
        pinned: true,
        fixed: walkRunFirst ? PlanUnitFixed.none : target.fixed,
      );
      kept.add(
        target.fixed.keepsKind && !walkRunFirst
            ? _withKind(
                placed,
                target.kind,
                short: short,
                maxSession: maxSession,
                parameters: parameters,
                fixed: target.fixed,
              )
            : placed,
      );
      movedDays.add(day);
    } else if (pinnedDays.contains(out[i].day) ||
        restDays.contains(out[i].day)) {
      // Weicht auf einen frei gewordenen Tag aus. Ohne Ruhetag gibt es immer
      // einen (jede zugeordnete Einheit macht ihren Tag frei); ein Ruhetag
      // macht keinen Tag frei, dann entfällt die Einheit (eine Einheit
      // weniger in der Woche, wie beim Festlegen bestätigt).
      if (freed.isNotEmpty) {
        kept.add(_moved(out[i], freed.removeAt(0), pinned: out[i].pinned));
      }
    } else {
      kept.add(out[i]);
    }
  }
  for (final u in restUnits) {
    kept.add(
      PlanUnit(
        day: planDay(u.day),
        kind: PlanUnitKind.rest,
        phase: u.phase,
        weekIndex: u.weekIndex,
        minutes: 0,
        segments: const [],
        pinned: true,
        fixed: PlanUnitFixed.day,
      ),
    );
  }
  kept.sort((a, b) => a.day.compareTo(b.day));
  return _Pinned(
    kept,
    conflicts,
    movedDays,
    hardReplaced: hardReplaced && !kept.any((u) => u.isHard),
  );
}

/// Abstandskonflikte der Termine im gespeicherten Plan [units] (für die
/// Anzeige, ohne Rechnung): wie in [generatePlan] je offener künftiger
/// Termin (`pinned`, Tag ab [today], ohne Lauf), der als intensive Einheit
/// näher als `minGapDays` an der vorigen oder nächsten intensiven Einheit
/// liegt (FR-0152, PAR-060), ein [PinnedConflictKind.spacing].
List<PinnedConflict> planSpacingConflicts(
  List<PlanUnit> units,
  DateTime today, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final t = planDay(today);
  return _spacingConflicts(units, {
    for (final u in units)
      if (u.pinned && u.runId == null && !planDay(u.day).isBefore(t)) u.day,
  }, parameters.minGapDays);
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
  fixed: u.fixed,
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
