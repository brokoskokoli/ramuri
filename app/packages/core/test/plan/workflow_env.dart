import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Gerüst der Tests der Plan-Abläufe ([PlanWorkflowService]). Synthetische
// Daten: Ziel, Läufe und Readiness-Bänder sind ausgedacht.

final Uint8List workflowKey = Uint8List.fromList(List.generate(32, (i) => i));

/// Mittwoch, 11.11.2026, mittags Ortszeit (Zone des Testprozesses).
final workflowNow = DateTime(2026, 11, 11, 12);
final workflowToday = DateTime.utc(2026, 11, 11);
DateTime workflowDay(int n) => workflowToday.add(Duration(days: n));

/// Mittag (oder [hour]) des Kalendertags [d] in Ortszeit.
DateTime workflowLocalAt(DateTime d, [int hour = 12]) =>
    DateTime(d.year, d.month, d.day, hour);

TrainingGoal workflowGoal({DateTime? target}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: target ?? DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String workflowDayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Lese-Port der Tests: Eingaben aus [runs] ([buildPlanInputs]); Belege der
/// Wochenprüfung aus den Minuten der Läufe und Einheiten der Vorwoche. Die
/// Auswahl der Läufe für RPE und Ermüdung prüft der Lese-Adapter der App.
class WorkflowReader implements PlanWorkflowReader {
  WorkflowReader(this.session);

  final StorageSession session;
  List<RunFigures> runs = [];

  /// Hält jedes Lesen an, bis es abgeschlossen ist.
  Completer<void>? gate;

  /// Jedes Lesen wirft (Lesefehler).
  bool fails = false;

  PlanRepository get _plans => (session as PlanStorage).plans;

  Future<void> _wait() async {
    if (fails) throw StateError('Lesefehler');
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Future<BuiltPlanInputs> read({
    required TrainingGoal goal,
    required DateTime today,
  }) async {
    await _wait();
    final planned = plannedRunIds(
      await _plans.unitsBetween(DateTime.utc(1, 1, 1), planFarFuture),
    );
    return buildPlanInputs(
      goal: goal,
      today: planDay(today),
      runs: runs,
      easyPlannedRunIds: planned.easy,
      otherPlannedRunIds: planned.other,
    );
  }

  @override
  Future<WeekEvidence> weekEvidence(DateTime today) async {
    await _wait();
    final t = planDay(today);
    final thisMonday = t.subtract(Duration(days: t.weekday - DateTime.monday));
    final lastMonday = thisMonday.subtract(const Duration(days: 7));
    var done = 0.0;
    for (final r in runs) {
      final d = _parseDay(r.day);
      if (d == null || d.isBefore(lastMonday) || !d.isBefore(thisMonday)) {
        continue;
      }
      final time = r.movingTime ?? r.totalTime;
      if (time != null) done += time.inMicroseconds / 6e7;
    }
    final week = [
      for (final u in await _plans.unitsBetween(lastMonday, thisMonday))
        if (u.day.isBefore(thisMonday)) u,
    ];
    return WeekEvidence(
      doneMinutes: done,
      plannedMinutes: week.isEmpty
          ? null
          : week.fold<int>(0, (a, u) => a + u.minutes),
      recentEasyRpe: const [],
      fatigueReported: false,
    );
  }

  @override
  Future<List<PlanRunFacts>> runFacts(DateTime today) async {
    await _wait();
    return const [];
  }

  /// Sporteinheiten (FR-0221) nach Kennung.
  Map<int, RunFigures> sport = {};

  @override
  Future<RunFigures?> sportFigures(int runId) async => sport[runId];

  /// Ortstage absolvierter intensiver Läufe (PAR-058).
  List<DateTime> intensive = [];

  @override
  Future<List<DateTime>> intensiveDaysBetween(
    DateTime from,
    DateTime to,
  ) async => [
    for (final d in intensive)
      if (!d.isBefore(planDay(from)) && !d.isAfter(planDay(to))) d,
  ];

  /// Läufe für das Muster der Unterforderung (PAR-236).
  List<PlanUnderloadRun> underload = [];

  @override
  Future<List<PlanUnderloadRun>> underloadRuns(DateTime? from) async =>
      underload;

  @override
  Future<TimeGoalBasis> timeGoalBasis({
    required TrainingGoal goal,
    required DateTime today,
  }) async => const TimeGoalBasis();
}

/// Pausenquelle der Tests: der Dienst der Hinweise über die Läufe im
/// Speicher; [WorkflowEnv.pauseOpen] erzwingt eine offene Pausenfrage.
class WorkflowPauses implements PlanPauseSource {
  WorkflowPauses(this.env);

  final WorkflowEnv env;

  HintService get _hints => HintService(session: env.session, clock: env.clock);

  @override
  Future<PauseQuestion?> pauseQuestion() async => env.pauseOpen
      ? PauseQuestion(
          daysSinceTraining: 10,
          lastTrainingDay: workflowDay(-10),
          baseWeekMinutes: 60,
        )
      : _hints.pauseQuestion();

  @override
  Future<PauseQuestion?> pauseRestartDue() => _hints.pauseRestartDue();

  @override
  Future<PauseQuestion?> newStartDue() => _hints.newStartDue();
}

/// Ohne Pause.
class NoPause implements PlanPauseSource {
  const NoPause();

  @override
  Future<PauseQuestion?> pauseQuestion() async => null;

  @override
  Future<PauseQuestion?> pauseRestartDue() async => null;

  @override
  Future<PauseQuestion?> newStartDue() async => null;
}

/// [FakeClock], deren Versatz der Zone des Testprozesses folgt, wie die
/// Systemuhr der App: Der Ortstag über [Clock.utcOffsetAt] (Hinweise,
/// Laufstart) und der über `toLocal()` (Plan) liegen auf demselben Tag.
class LocalClock extends FakeClock {
  LocalClock(super.start);

  @override
  Duration utcOffsetAt(DateTime at) => at.toUtc().toLocal().timeZoneOffset;
}

class WorkflowEnv {
  WorkflowEnv(this.session)
    : clock = LocalClock(workflowNow),
      reader = WorkflowReader(session);

  final StorageSession session;
  final FakeClock clock;
  final WorkflowReader reader;

  bool pauseOpen = false;
  PlanReadinessDay? Function(DateTime day)? readiness;

  late final PlanWorkflowService service = PlanWorkflowService(
    session: session,
    clock: clock,
    reader: reader,
    pauses: WorkflowPauses(this),
    readinessToday: (day) async {
      final r = readiness;
      return r == null ? null : r(day);
    },
  );

  PlanRepository get plans => (session as PlanStorage).plans;
  GoalStore get goals => (session as GoalStorage).goals;
  WarningStore get warning => (session as WarningStorage).warning;

  static Future<WorkflowEnv> open() async =>
      WorkflowEnv(await FakeStorage().open(workflowKey));

  /// Prüfung wie beim Öffnen der Plan-Seite; die Fassungen landen in
  /// [results].
  final results = <PlanRecalculation>[];
  Future<PlanDueCheck> runDue() async {
    final due = await service.dueCheck();
    await service.runDue(due, onResult: results.add);
    return due;
  }

  /// Öffnen wie die Plan-Seite ohne Sperre der Wertberechnung: Neustart zur
  /// Pause, Prüfung, Zuordnung (PAR-231), Unterforderung (PAR-236). Die
  /// Fassungen landen in [results].
  Future<void> openPlan() async {
    final events = PlanWorkflowEvents(onResult: results.add);
    try {
      await service.restartIfDue(events: events);
      await runDue();
    } on Object {
      // Wie die Seite: die Prüfung holt das nächste Öffnen nach.
    }
    await service.autoAssignQuietly(events: events);
    await service.advanceUnderloadQuietly();
  }

  /// Ziel speichern und erste Fassung anlegen (wie das Speichern eines
  /// Ziels ohne Plan).
  Future<void> saveGoal(TrainingGoal goal) async {
    await goals.save(goal, today: planDay(localDay()));
    expect((await runDue()).kind, PlanDueKind.create);
  }

  /// Zieländerung mit bestehender Fassung (Auslöser `goalChange`).
  Future<void> changeGoal(TrainingGoal goal) async {
    await goals.save(goal, today: planDay(localDay()));
    final last = (await plans.history()).last;
    await service.recalculate(PlanTrigger.goalChange, goal, last);
  }

  /// Manuelles Neuberechnen (Auslöser `manual`).
  Future<void> manual() async {
    final goal = (await goals.goal())!;
    await service.recalculate(
      PlanTrigger.manual,
      goal,
      (await plans.history()).last,
    );
  }

  /// Warnsignal melden: Signal setzen, dann die Ruhetag-Fassung.
  Future<void> reportWarning() async {
    await service.markWarning();
    await service.recalculateWarned();
  }

  DateTime localDay() {
    final l = clock.now().toLocal();
    return DateTime.utc(l.year, l.month, l.day);
  }
}

/// Schreibt eine Fassung mit [version] ab [validFrom] direkt.
Future<void> writeWorkflowVersion(
  WorkflowEnv e,
  PlanVersion version,
  DateTime validFrom,
) async {
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: validFrom,
      validFrom: validFrom,
      trigger: PlanTrigger.create,
      reason: 'create',
      version: version,
      inputs: PlanInputs.forNewGoal(workflowGoal(), validFrom),
      summary: const {},
      units: const [],
      readState: planUnitsFingerprint(
        await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
      ),
    ),
  );
}

/// Schreibt die letzte Fassung mit denselben Einheiten, Eingaben und Hinweisen
/// als Fassung einer älteren Regelversion neu (ab heute der Uhr).
Future<void> downgradeLast(WorkflowEnv e) async {
  final last = (await e.plans.history()).last;
  final day = e.localDay();
  await e.plans.writeVersion(
    PlanVersionDraft(
      createdAt: e.clock.now(),
      validFrom: day,
      trigger: PlanTrigger.weekly,
      reason: 'weekly',
      version: const PlanVersion(method: 'alte-methode'),
      inputs: last.inputs,
      summary: last.summary,
      units: await e.plans.unitsBetween(day, planFarFuture),
      readState: planUnitsFingerprint(
        await e.plans.unitsBetween(DateTime.utc(2000), planFarFuture),
      ),
    ),
  );
  expect((await e.plans.history()).last.version.isCurrent, isFalse);
}
