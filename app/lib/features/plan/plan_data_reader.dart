import 'package:core/core.dart';

/// Lädt die Kennzahlen der beendeten Läufe (für Tests ersetzbar).
typedef RunFiguresLoader = Future<List<RunFigures>> Function();

/// Lese-Adapter für [buildPlanInputs] (WP22 Punkt 7, ADR-0010 Punkt 2):
/// sammelt aus dem Speicher die Läufe, die RPE je Lauf, die Zuordnung der
/// Läufe zu Plan-Einheiten, die aktive Referenz, Puls und Zonen des Profils
/// und die VO₂max samt Güte (PAR-081). Gerechnet wird nur in `core`.
class PlanDataReader {
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

  Future<List<RunFigures>> _runs() async {
    final custom = loadRuns;
    if (custom != null) return custom();
    final overviews = await RunOverviewService(
      session: session,
      clock: clock,
      offload: offload,
    ).load();
    return [
      for (final o in overviews)
        if (!o.readFailed) o.toFigures(),
    ];
  }

  /// Eingaben für [goal] am Ortstag [today]. Die Zuordnung „locker“/„andere“
  /// kommt aus allen Einheiten mit Lauf ([plannedRunIds]); RPE nur aus der
  /// Rückmeldung zum Lauf.
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
  /// freie), die geplanten Minuten der Woche (`null` ohne gespeicherte
  /// Einheiten), die RPE der lockeren Läufe (zugeordnet zu lockerer oder
  /// langer Einheit, ältester zuerst, `null` ohne Angabe) und gemeldete
  /// Ermüdung (PAR-188: Befinden 1 oder 2 beim letzten Lauf, höchstens
  /// 3 Tage alt).
  Future<WeekEvidence> weekEvidence(DateTime today) async {
    final t = planDay(today);
    final thisMonday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    final runs = await _runs();
    final units = await _plans.unitsBetween(
      DateTime.utc(1, 1, 1),
      planFarFuture,
    );
    final easyIds = plannedRunIds(units).easy;
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
}

/// Belege der Wochenprüfung ([PlanDataReader.weekEvidence]).
class WeekEvidence {
  const WeekEvidence({
    required this.doneMinutes,
    required this.plannedMinutes,
    required this.recentEasyRpe,
    required this.fatigueReported,
  });

  final double doneMinutes;
  final int? plannedMinutes;
  final List<int?> recentEasyRpe;
  final bool fatigueReported;
}

DateTime? _parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
