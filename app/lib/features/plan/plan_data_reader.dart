import 'package:core/core.dart';

/// Lädt die Kennzahlen der beendeten Läufe (für Tests ersetzbar).
typedef RunFiguresLoader = Future<List<RunFigures>> Function();

/// Lese-Adapter für [buildPlanInputs] (WP22 Punkt 7, ADR-0010 Punkt 2):
/// sammelt aus dem Speicher die Läufe, die RPE je Lauf, die Zuordnung der
/// Läufe zu Plan-Einheiten, die aktive Referenz, Puls und Zonen des Profils
/// und die VO₂max samt Güte (PAR-081). Gerechnet wird nur in `core`.
class PlanDataReader implements PlanWorkflowReader {
  PlanDataReader({
    required this.session,
    required this.clock,
    this.offload = inlineOffload,
    this.parameters = const PlanParameters(),
    this.intensityParameters = const IntensityParameters(),
    this.loadRuns,
  });

  final StorageSession session;
  final Clock clock;
  final Offload offload;
  final PlanParameters parameters;
  final IntensityParameters intensityParameters;

  /// Ersetzt das Lesen der Läufe (Tests); ohne: [RunOverviewService].
  final RunFiguresLoader? loadRuns;

  PlanRepository get _plans => (session as PlanStorage).plans;

  /// Die beendeten Läufe mit ihren Kennzahlen, wie in der Laufliste
  /// ([RunOverviewService]; Laufband mit der Strecke des Bands, FR-0196).
  Future<List<RunOverview>> runOverviews() => RunOverviewService(
    session: session,
    clock: clock,
    offload: offload,
  ).load();

  /// Alle beendeten Einheiten mit Kennzahlen, Läufe und andere Sportart.
  Future<List<RunFigures>> _figures() async {
    final custom = loadRuns;
    if (custom != null) return custom();
    return [
      for (final o in await runOverviews())
        if (!o.readFailed) o.toFigures(),
    ];
  }

  /// Nur Läufe: Eine andere Sportart (FR-0221) zählt nie für Trainingsstand,
  /// lockeres Tempo und längste Einheit; für Wochenzeit und RPE-Regel zählt
  /// sie nur als ersetzte lockere Einheit (PAR-233, DEC-0056).
  Future<List<RunFigures>> _runs() async => [
    for (final r in await _figures())
      if (r.isRunning) r,
  ];

  /// Kennzahlen der Sporteinheit [runId] (`null` ohne oder bei einem Lauf),
  /// für die Prüfung des Ersatzes (PAR-233).
  @override
  Future<RunFigures?> sportFigures(int runId) async {
    for (final r in await _figures()) {
      if (r.runId == runId) return r.isRunning ? null : r;
    }
    return null;
  }

  /// Eingaben für [goal] am Ortstag [today]. Die Zuordnung „locker“/„andere“
  /// kommt aus allen Einheiten mit Lauf ([plannedRunIds]); RPE nur aus der
  /// Rückmeldung zum Lauf.
  @override
  Future<BuiltPlanInputs> read({
    required TrainingGoal goal,
    required DateTime today,
  }) async {
    final day = planDay(today);
    final runs = await _runs();
    final planned = plannedRunIds(
      await _plans.unitsBetween(DateTime.utc(1, 1, 1), planFarFuture),
    );
    final rpe = <int, int>{
      for (final e in (await session.subjective.readAll()).entries)
        if (e.value.subjective.rpe case final int r) e.key: r,
    };
    final reference = await (session as PredictionStorage).prediction
        .activeReference();
    final heartRate = resolveHeartRate(
      await session.profile.read(),
      currentYear: clock.now().year,
    ).basis;
    final percents = await ReserveZoneSettings.load(session.settings);
    final (vo2max, grade) = await _vo2max(day);
    return buildPlanInputs(
      goal: goal,
      today: day,
      runs: runs,
      easyPlannedRunIds: planned.easy,
      otherPlannedRunIds: planned.other,
      rpeByRunId: rpe,
      reference: reference,
      heartRate: heartRate,
      zoneBounds: [for (final p in percents) p / 100],
      vo2max: vo2max,
      vo2maxGrade: grade,
      parameters: parameters,
      intensityParameters: intensityParameters,
    );
  }

  /// Grundlage der Einschätzung eines Zeitziels (PAR-206, FR-0129,
  /// FR-0130): die allgemeine Schätzung der Zielstrecke aus Referenz und
  /// letzten Läufen ([predictPerformance], wie die Prognosekarte) und die
  /// Zahl der Läufe in den letzten 4 Wochen bis [today]. Andere Ziele: leer.
  @override
  Future<TimeGoalBasis> timeGoalBasis({
    required TrainingGoal goal,
    required DateTime today,
    FeasibilityParameters feasibility = const FeasibilityParameters(),
  }) async {
    final distance = goal.distance;
    if (goal.type != GoalType.time || distance == null) {
      return const TimeGoalBasis();
    }
    final references = [
      for (final s
          in await (session as PredictionStorage).prediction.references())
        s.reference,
    ];
    final runs = await PredictionRunReader(
      session: session,
      clock: clock,
      offload: offload,
    ).load(withPaceSamples: false);
    final prediction = predictPerformance(
      now: clock.now(),
      references: references,
      runs: runs,
    );
    final target = switch (distance) {
      GoalDistance.fiveKilometers => PredictionDistance.fiveKilometers,
      GoalDistance.tenKilometers => PredictionDistance.tenKilometers,
      GoalDistance.halfMarathon => PredictionDistance.halfMarathon,
    };
    final day = planDay(today);
    final inWindow = runs.where((r) {
      // Beide sind Kalendertage (UTC-Mitternacht), ohne Ortszeit-Umrechnung.
      final d = day
          .difference(DateTime.utc(r.date.year, r.date.month, r.date.day))
          .inDays;
      return d >= 0 && d < feasibility.runWindowDays;
    }).length;
    return TimeGoalBasis(
      currentSeconds: prediction.of(target).seconds,
      runsInWindow: inWindow,
    );
  }

  /// Belege der Wochenprüfung (PAR-201) am Ortstag [today] für die Woche vor
  /// der von [today]: Minuten aller Läufe dieser Woche (zugeordnete und
  /// freie) und der Sporteinheiten, die eine lockere Einheit ersetzen
  /// (PAR-233, Bewegungszeit), die geplanten Minuten der Woche (`null` ohne
  /// gespeicherte Einheiten), die RPE der lockeren Läufe (zugeordnet zu
  /// lockerer oder langer Einheit, auch ersetzte, ältester zuerst, `null`
  /// ohne Angabe) und gemeldete
  /// Ermüdung (PAR-188: Befinden 1 oder 2 beim letzten Lauf, höchstens
  /// 3 Tage alt).
  @override
  Future<WeekEvidence> weekEvidence(DateTime today) async {
    final t = planDay(today);
    final thisMonday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final units = await _plans.unitsBetween(
      DateTime.utc(1, 1, 1),
      planFarFuture,
    );
    final easyIds = plannedRunIds(units).easy;
    // Eine andere Sportart zählt nur als ersetzte lockere Einheit (PAR-233).
    final runs = [
      for (final r in await _figures())
        if (r.isRunning || easyIds.contains(r.runId)) r,
    ];
    final subjective = await session.subjective.readAll();

    var done = 0.0;
    for (final r in runs) {
      final d = _parseDay(r.day);
      if (d == null || d.isBefore(lastMonday) || !d.isBefore(thisMonday)) {
        continue;
      }
      final time = r.movingTime ?? r.totalTime;
      if (time != null && time > Duration.zero) {
        done += time.inMicroseconds / 6e7;
      }
    }
    final week = [
      for (final u in units)
        if (!u.day.isBefore(lastMonday) && u.day.isBefore(thisMonday)) u,
    ];
    final byTime = [...runs]..sort((a, b) => a.endedAt.compareTo(b.endedAt));
    final easyRuns = [
      for (final r in byTime)
        if (easyIds.contains(r.runId) && _before(r, thisMonday)) r,
    ];
    // Läufe der laufenden Woche zählen nicht (NB8 5): Die Prüfung bewertet
    // die Woche davor, ein früher Lauf dieser Woche verdrängte sonst die
    // Läufe der bewerteten Woche aus dem Fenster.
    // Die RPE-Regel zählt nur, wenn mindestens einer der letzten lockeren
    // Läufe (Fenster der Regel) in der bewerteten Woche liegt: Dieselbe alte
    // Bewertung löst nicht jede Woche erneut aus.
    final window = easyRuns.length > parameters.fatigueWindowRuns
        ? easyRuns.sublist(easyRuns.length - parameters.fatigueWindowRuns)
        : easyRuns;
    final windowInWeek = window.any((r) {
      final d = _parseDay(r.day);
      return d != null && !d.isBefore(lastMonday) && d.isBefore(thisMonday);
    });
    final easyRpe = <int?>[
      if (windowInWeek)
        for (final r in easyRuns) subjective[r.runId]?.subjective.rpe,
    ];
    var fatigue = false;
    if (byTime.isNotEmpty) {
      final last = byTime.last;
      final day = _parseDay(last.day);
      final w = subjective[last.runId]?.subjective.wellbeing;
      fatigue =
          day != null && w != null && w <= 2 && t.difference(day).inDays <= 3;
    }
    return WeekEvidence(
      doneMinutes: done,
      plannedMinutes: week.isEmpty
          ? null
          : week.fold<int>(0, (a, u) => a + u.minutes),
      recentEasyRpe: easyRpe,
      fatigueReported: fatigue,
    );
  }

  /// Die beendeten Läufe und Sporteinheiten (eine intensive andere Sportart
  /// zählt für den Abstand, PAR-233; zugeordnet ist sie nur einer lockeren
  /// Einheit) mit Ortstag von
  /// `minGapDays - 1` Tagen vor dem Montag der Woche von [today] bis
  /// [today], so wie sie die Regel der Abweichung braucht (PAR-235): die
  /// Läufe der laufenden Woche und die, zu denen ihre harte Einheit Abstand
  /// halten muss (PAR-059). RPE aus der Rückmeldung, Zeit bei mindestens
  /// 80 % HFmax aus dem Laufwert [highHeartRateTimeValueKey] (PAR-058).
  @override
  Future<List<PlanRunFacts>> runFacts(DateTime today) async {
    final t = planDay(today);
    final monday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final from = monday.subtract(Duration(days: parameters.minGapDays - 1));
    final inWindow = [
      for (final r in await _figures())
        if (_parseDay(r.day) case final d?
            when !d.isBefore(from) && !d.isAfter(t))
          (r, d),
    ];
    if (inWindow.isEmpty) return const [];
    final subjective = await session.subjective.readAll();
    final values = await session.values.readRunValues({
      highHeartRateTimeValueKey,
    });
    return [
      for (final (r, d) in inWindow)
        PlanRunFacts(
          runId: r.runId,
          day: d,
          movingSeconds: r.movingTime?.inSeconds,
          rpe: subjective[r.runId]?.subjective.rpe,
          highHrMinutes: values[r.runId]?[highHeartRateTimeValueKey]?.value,
        ),
    ];
  }

  /// Die einer Einheit zugeordneten, beendeten Läufe (ohne andere Sportart),
  /// die nach [from] endeten
  /// (ohne [from]: alle), für das Muster der Unterforderung
  /// (PAR-236, [planUnderloadPattern]): Art der Einheit, RPE aus der
  /// Rückmeldung und Zeit bei mindestens 80 % HFmax aus dem Laufwert
  /// [highHeartRateTimeValueKey] (PAR-058). Gesundheitsdaten: nie loggen.
  @override
  Future<List<PlanUnderloadRun>> underloadRuns(DateTime? from) async {
    final kinds = <int, PlanUnitKind>{
      for (final u in await _plans.unitsBetween(
        DateTime.utc(1, 1, 1),
        planFarFuture,
      ))
        if (u.runId case final int id) id: u.kind,
    };
    if (kinds.isEmpty) return const [];
    final result = <PlanUnderloadRun>[];
    for (final r in await session.runs.finishedBetween(
      from ?? DateTime.utc(1, 1, 1),
      clock.now().add(const Duration(days: 1)),
    )) {
      final kind = kinds[r.id];
      final ended = r.endedAt;
      // Nur Läufe: Eine Sporteinheit, die nach PAR-233 eine lockere Einheit
      // ersetzt, zählt nicht für das Muster (FR-0222).
      if (kind == null || ended == null || !r.mode.isRunning) continue;
      if (from != null && !ended.isAfter(from)) continue;
      double? highHr;
      for (final v in await session.values.read(ValueOwner.run(r.id))) {
        if (v.current.key == highHeartRateTimeValueKey) {
          highHr = v.current.value;
        }
      }
      result.add(
        PlanUnderloadRun(
          kind: kind,
          endedAt: ended.toUtc(),
          rpe: (await session.subjective.read(r.id))?.subjective.rpe,
          highHrMinutes: highHr,
        ),
      );
    }
    return result;
  }

  bool _before(RunFigures r, DateTime monday) {
    final d = _parseDay(r.day);
    return d != null && d.isBefore(monday);
  }

  /// Langzeitwert des Tages des neuesten Laufs (wie die Statistik) und Güte
  /// nach PAR-081 mit dem letzten Lauf, der einen Wert hat.
  Future<(double?, Vo2maxGrade?)> _vo2max(DateTime today) async {
    final finished = [
      for (final r in await session.runs.list())
        if (r.state == RunState.finished && r.endedAt != null) r,
    ];
    final fitness = await FitnessOverviewService(session: session)
        .load(finished);
    final longTerm = fitness.longTerm;
    RunEstimate? last;
    for (final e in fitness.runEstimates.reversed) {
      if (e.value.value != null) {
        last = e;
        break;
      }
    }
    final grade = vo2maxGradeFor(
      longTerm: longTerm,
      lastRun: last?.value,
      lastRunDay: last == null ? null : _parseDay(last.day),
      today: today,
      parameters: intensityParameters,
    );
    return (longTerm?.value, grade);
  }

  /// Beendete Läufe mit Ortstag (Tag des Laufbeginns, [dayOfRun], PAR-237) in
  /// `from <= Tag <= to`, für den Kalender (FR-0171) und die Prüfung beim
  /// Verschieben: [PlanCalendarRun.intensive] nach PAR-058
  /// ([PlanParameters.completedIntensive]) aus der Zeit bei mindestens 80 %
  /// HFmax (Laufwert [highHeartRateTimeValueKey]) oder der RPE-Angabe; ohne
  /// verfügbaren Wert zählt nur die RPE-Angabe.
  ///
  /// Liest nur die Läufe, deren Ende im Zeitraum samt Puffer liegt
  /// ([runDayQueryBounds]: größter UTC-Versatz, hinten der Folgetag für einen
  /// Lauf über Mitternacht), und nur deren subjektive Angaben und Laufwerte
  /// (Befund E2-6).
  Future<List<PlanCalendarRun>> runsBetween(DateTime from, DateTime to) async {
    final f = planDay(from), t = planDay(to);
    final result = <PlanCalendarRun>[];
    final bounds = runDayQueryBounds(f, t);
    for (final r in await session.runs.finishedBetween(
      bounds.from,
      bounds.to,
    )) {
      final p = DateTime.parse(dayOfRun(r));
      final day = DateTime.utc(p.year, p.month, p.day);
      if (day.isBefore(f) || day.isAfter(t)) continue;
      final rpe = (await session.subjective.read(r.id))?.subjective.rpe;
      double? highHr;
      for (final p in await session.values.read(ValueOwner.run(r.id))) {
        if (p.current.key == highHeartRateTimeValueKey) {
          highHr = p.current.value;
        }
      }
      result.add(
        PlanCalendarRun(
          id: r.id,
          day: day,
          intensive: parameters.completedIntensive(
            rpe: rpe,
            highHrMinutes: highHr,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<List<DateTime>> intensiveDaysBetween(
    DateTime from,
    DateTime to,
  ) async => [
    for (final r in await runsBetween(from, to))
      if (r.intensive) r.day,
  ];

  /// Die zugeordneten Läufe der erledigten Einheiten in [units] (ohne
  /// Ruhetage) für die Anzeige (FR-0171): Bewegungszeit und Strecke wie in der
  /// Laufliste, das Kennzeichen nach PAR-058
  /// ([PlanParameters.completedIntensity]). Gelesen in je einer Abfrage für
  /// alle Läufe, nicht je Einheit. Ein Lauf, den es nicht (mehr) gibt oder
  /// dessen Daten nicht lesbar sind, fehlt in der Antwort.
  Future<Map<int, PlanDoneRun>> doneRuns(Iterable<PlanUnit> units) async {
    final ids = {
      for (final u in units)
        if (u.kind != PlanUnitKind.rest) ?u.runId,
    };
    if (ids.isEmpty) return const {};
    final overviews = [
      for (final o in await runOverviews())
        if (ids.contains(o.run.id) && !o.readFailed) o,
    ];
    if (overviews.isEmpty) return const {};
    final subjective = await session.subjective.readAll();
    final values = await session.values.readRunValues({
      highHeartRateTimeValueKey,
    });
    return {
      for (final o in overviews)
        o.run.id: PlanDoneRun.of(
          o,
          intensive: parameters.completedIntensity(
            rpe: subjective[o.run.id]?.subjective.rpe,
            highHrMinutes: values[o.run.id]?[highHeartRateTimeValueKey]?.value,
          ),
        ),
    };
  }
}

DateTime? _parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Ein beendeter Lauf oder eine Sporteinheit (FR-0221) im Kalender
/// ([PlanDataReader.runsBetween]).
class PlanCalendarRun {
  const PlanCalendarRun({
    required this.id,
    required this.day,
    required this.intensive,
  });

  final int id;

  /// Tag des Laufs ([dayOfRun], Ortstag des Beginns, PAR-237).
  final DateTime day;

  /// Gilt nach PAR-058 als intensiv (RPE-Angabe).
  final bool intensive;
}

/// Der zugeordnete Lauf einer erledigten Einheit für die Anzeige
/// ([PlanDataReader.doneRuns], FR-0171). Die Einheit selbst (Vorgabe) bleibt
/// unverändert (FR-0156).
class PlanDoneRun {
  const PlanDoneRun({
    required this.id,
    this.movingTime,
    this.distanceMeters,
    this.treadmill = false,
    this.intensive,
  });

  /// Aus der Übersicht des Laufs wie in der Laufliste.
  PlanDoneRun.of(RunOverview o, {this.intensive})
    : id = o.run.id,
      movingTime = o.movingTime,
      distanceMeters = o.distanceMeters,
      treadmill = o.run.mode == RunMode.treadmill;

  final int id;

  /// `null`: nicht verfügbar.
  final Duration? movingTime;

  /// `null`: nicht verfügbar; beim Laufband die Strecke des Bands.
  final double? distanceMeters;

  /// Laufbandlauf (FR-0196).
  final bool treadmill;

  /// PAR-058: `true` intensiv, `false` locker, `null` ohne Puls und RPE
  /// (kein Kennzeichen).
  final bool? intensive;
}
