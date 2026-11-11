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

DateTime? _parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
