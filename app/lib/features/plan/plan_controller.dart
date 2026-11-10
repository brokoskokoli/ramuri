import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'plan_data_reader.dart';

enum PlanLoadPhase { loading, ready, failed }

/// Ergebnis einer Aktion des [PlanController]. Der Inhalt eines Fehlers wird
/// nie gezeigt (Gesundheitsdaten).
enum PlanActionResult {
  /// Ausgeführt.
  done,

  /// Vom Speicher abgelehnt (ungültiges Ziel, Termin vor heute, belegter Tag,
  /// Einheit mit Lauf, …); nichts geändert.
  rejected,

  /// Einheit, Lauf oder Ziel fehlt.
  notFound,

  /// Speicher nicht erreichbar oder Rechnung gescheitert.
  failed,
}

/// Stand der Plan-Seite (WP22). Nur Daten, keine Texte.
class PlanViewState {
  const PlanViewState.loading()
    : phase = PlanLoadPhase.loading,
      goal = null,
      version = null,
      hints = null,
      lastChange = null,
      weekUnits = const [],
      assessment = null;

  const PlanViewState.failed()
    : phase = PlanLoadPhase.failed,
      goal = null,
      version = null,
      hints = null,
      lastChange = null,
      weekUnits = const [],
      assessment = null;

  const PlanViewState.ready({
    required this.goal,
    required this.version,
    required this.hints,
    required this.lastChange,
    required this.weekUnits,
    this.assessment,
  }) : phase = PlanLoadPhase.ready;

  final PlanLoadPhase phase;

  /// Das gespeicherte Ziel oder `null` (leerer Zustand).
  final TrainingGoal? goal;

  /// Die neueste Fassung oder `null` ohne Plan.
  final PlanVersionRecord? version;

  /// Hinweise zum Plan: [GeneratedPlan.pinnedConflicts],
  /// [GeneratedPlan.droppedDaysByWeek], [GeneratedPlan.hardOmissions],
  /// [GeneratedPlan.hardFit] (inkl. `partialAtPeak`),
  /// [GeneratedPlan.walkRunStaysAtWeek], [GeneratedPlan.walkRunNoWeekFits],
  /// [GeneratedPlan.weeks]. Nach einer Neuberechnung in dieser Sitzung deren
  /// Ergebnis, sonst eine Vorschau ([previewPlan]) aus der neuesten Fassung;
  /// gespeichert werden die Hinweise nicht. `null` ohne Plan.
  final GeneratedPlan? hints;

  /// Alt-Neu-Bild der letzten Neuberechnung dieser Sitzung (PAR-204), sonst
  /// `null`. Die gespeicherte Fassung trägt es in [PlanVersionRecord.summary].
  final PlanChangeSummary? lastChange;

  /// Einheiten der Kalenderwoche (Montag bis Sonntag) von heute.
  final List<PlanUnit> weekUnits;

  /// Einschätzung des Ziels nach PAR-206 ([assessGoal]) mit den Eingaben der
  /// neuesten Fassung und heute; nie gespeichert. `null` ohne Plan oder wenn
  /// sie sich nicht rechnen ließ (die Seite lässt die Zeile dann weg).
  final GoalAssessment? assessment;

  bool get hasPlan => version != null;

  /// Die neueste Fassung stammt aus einer älteren Regelversion (ADR-0010
  /// Punkt 7); die nächste wöchentliche Prüfung rechnet mit `ruleVersion`.
  bool get ruleVersionPending => version != null && !version!.version.isCurrent;
}

/// Liest und ändert Ziel und Plan (WP22 Punkt 7). Gerechnet wird in `core`
/// ([buildPlanInputs], [recalculatePlan], [previewPlan]); „heute“ ist der
/// Ortstag der [clock] und geht an jeden Schreiber.
///
/// Alle Aktionen und Neuberechnungen laufen nacheinander (eine Warteschlange):
/// Eine Zuordnung oder Terminbestätigung schiebt sich nie zwischen Lesen und
/// Schreiben einer Neuberechnung. Termine ändern sich nur über
/// [confirmMove] (Bestätigung des Nutzers); automatische Neuberechnungen
/// halten die Tage (ADR-0010 Punkt 8, in [recalculatePlan]).
class PlanController extends ChangeNotifier {
  PlanController({
    required this.session,
    required this.clock,
    PlanDataReader? reader,
    this.parameters = const PlanParameters(),
    this.onChanged,
  }) : reader =
           reader ??
           PlanDataReader(
             session: session,
             clock: clock,
             parameters: parameters,
           );

  final StorageSession session;
  final Clock clock;
  final PlanDataReader reader;
  final PlanParameters parameters;

  /// Nach jeder Änderung der gespeicherten Daten (Ziel, Plan, Zuordnung).
  final VoidCallback? onChanged;

  GoalStore get _goals => (session as GoalStorage).goals;
  PlanRepository get _plans => (session as PlanStorage).plans;

  PlanViewState _state = const PlanViewState.loading();
  PlanViewState get state => _state;

  GeneratedPlan? _fresh;
  PlanChangeSummary? _lastChange;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  DateTime _today() => calendarDay(clock.now());

  /// Führt [action] nach allen vorher angestoßenen aus.
  Future<T> _serial<T>(Future<T> Function() action) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await action());
      } on Object catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  /// Öffnen der Plan-Seite: wöchentliche Prüfung (FR-0158), falls fällig,
  /// dann laden. Fällig ist sie, wenn `plan.last_check_day` fehlt oder in
  /// einer früheren Kalenderwoche (ab Montag) liegt. Stammt die neueste
  /// Fassung aus einer älteren Regelversion (`!version.isCurrent`), ist der
  /// Auslöser `ruleVersion`, sonst `weekly`; außerhalb der fälligen Prüfung
  /// rechnet das Öffnen nicht (ADR-0010 Punkt 7: keine stille Neuberechnung
  /// beim Start). Ein Ziel ohne Fassung bekommt seine erste (`create`).
  Future<void> open() => _serial(() async {
    _fresh = null;
    try {
      await _checkDue();
    } on Object {
      // Die Prüfung holt der nächste Start nach; die Seite zeigt den
      // gespeicherten Plan.
    }
    await _load();
  });

  /// Lädt den Stand neu (ohne Prüfung).
  Future<void> reload() => _serial(_load);

  Future<void> _checkDue() async {
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    if (history.isEmpty) {
      await _recalculate(PlanTrigger.create, goal, null);
      return;
    }
    final last = history.last;
    final today = _today();
    final checked = await session.settings.get(planLastCheckDayKey);
    if (!weeklyCheckDue(checked, today)) return;
    await _recalculate(
      last.version.isCurrent ? PlanTrigger.weekly : PlanTrigger.ruleVersion,
      goal,
      last,
    );
  }

  /// Rechnet mit Eingaben aus dem Speicher. Anlegen: neue Eingaben aus
  /// [buildPlanInputs]; sonst die der letzten Fassung mit den heute
  /// gemessenen Werten ([refreshMeasuredInputs]).
  Future<void> _recalculate(
    PlanTrigger trigger,
    TrainingGoal goal,
    PlanVersionRecord? last,
  ) async {
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    final inputs = (trigger == PlanTrigger.create || last == null)
        ? built.inputs
        : refreshMeasuredInputs(last.inputs, built.inputs);
    final r = await recalculatePlan(
      plans: _plans,
      settings: session.settings,
      trigger: trigger,
      today: today,
      now: clock.now(),
      inputs: inputs,
      parameters: parameters,
    );
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
  }

  Future<void> _load() async {
    if (_disposed) return;
    PlanViewState next;
    try {
      next = await _compute();
    } on Object {
      next = const PlanViewState.failed();
    }
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<PlanViewState> _compute() async {
    final today = _today();
    final goal = await _goals.goal();
    final history = await _plans.history();
    final version = history.isEmpty ? null : history.last;
    GeneratedPlan? hints = _fresh;
    if (hints == null && goal != null && version != null) {
      final inputs = version.inputs.copyWith(today: today);
      hints = previewPlan(
        goal: goal,
        inputs: inputs,
        units: await _plans.unitsBetween(inputs.anchor, planFarFuture),
        today: today,
        parameters: parameters,
      );
    }
    final monday = today.subtract(Duration(days: today.weekday - 1));
    GoalAssessment? assessment;
    if (goal != null && version != null) {
      try {
        assessment = assessGoal(
          goal: goal,
          inputs: version.inputs.copyWith(today: today),
          today: today,
          basis: await reader.timeGoalBasis(goal: goal, today: today),
          parameters: parameters,
        );
      } on Object {
        // Ohne Einschätzung bleibt die Seite benutzbar; der Inhalt eines
        // Fehlers wird nie gezeigt.
        assessment = null;
      }
    }
    return PlanViewState.ready(
      assessment: assessment,
      goal: goal,
      version: version,
      hints: version == null ? null : hints,
      lastChange: _lastChange,
      weekUnits: version == null
          ? const []
          : await _plans.unitsBetween(
              monday,
              monday.add(const Duration(days: 6)),
            ),
    );
  }

  /// Einheiten mit `from <= Tag <= to` (Ortstage), z. B. für den Kalender.
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to) =>
      _plans.unitsBetween(from, to);

  /// Die Einheit an [day] oder `null`.
  Future<PlanUnit?> unitOn(DateTime day) => _plans.unitOn(day);

  /// Plan-Eingaben für [goal] (ohne: das gespeicherte) aus dem Speicher, für
  /// die Einschätzung ([assessGoal]) vor dem Speichern. Das Ergebnis trägt
  /// mit `goal` den Stand aus Läufen (PAR-192). `null` ohne Ziel.
  Future<BuiltPlanInputs?> inputsFor([TrainingGoal? goal]) async {
    final g = goal ?? await _goals.goal();
    if (g == null) return null;
    return reader.read(goal: g, today: _today());
  }

  /// Speichert das Ziel (Anlegen oder Ändern, PAR-203) mit „heute“ und
  /// rechnet den Plan ab heute neu (`create` ohne bisheriges Ziel, sonst
  /// `goalChange`). Ungültiges Ziel: [PlanActionResult.rejected], nichts
  /// geändert.
  Future<PlanActionResult> saveGoal(TrainingGoal goal) => _act(() async {
    final existed = await _goals.goal() != null;
    await _goals.save(goal, today: _today());
    onChanged?.call();
    final history = await _plans.history();
    await _recalculate(
      existed && history.isNotEmpty
          ? PlanTrigger.goalChange
          : PlanTrigger.create,
      goal,
      history.isEmpty ? null : history.last,
    );
  });

  /// Ausdrückliche Neuberechnung durch den Nutzer (`manual`).
  Future<PlanActionResult> recalculate() => _act(() async {
    final goal = await _goals.goal();
    if (goal == null) {
      throw const StorageException(StorageFailure.notFound);
    }
    final history = await _plans.history();
    await _recalculate(
      history.isEmpty ? PlanTrigger.create : PlanTrigger.manual,
      goal,
      history.isEmpty ? null : history.last,
    );
  });

  /// Ordnet der Einheit den Lauf zu (`null` hebt die Zuordnung auf) und
  /// rechnet danach ab heute neu (Auslöser `run`; die Zuordnung zählt für
  /// „locker“, PAR-205, und friert die Einheit ein).
  Future<PlanActionResult> assignRun(int unitId, int? runId) => _act(() async {
    await _plans.assignRun(unitId, runId);
    _fresh = null;
    onChanged?.call();
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    await _recalculate(
      PlanTrigger.run,
      goal,
      history.isEmpty ? null : history.last,
    );
  });

  /// Verschiebt die Einheit nach Bestätigung des Nutzers auf [day] (setzt
  /// `pinned`, OQ-0011), mit „heute“. Keine Neuberechnung.
  Future<PlanActionResult> confirmMove(int unitId, DateTime day) =>
      _act(() async {
        await _plans.confirmMove(unitId, day, today: _today());
        _fresh = null;
        onChanged?.call();
      });

  Future<PlanActionResult> _act(Future<void> Function() action) =>
      _serial(() async {
        PlanActionResult result;
        try {
          await action();
          result = PlanActionResult.done;
        } on StorageException catch (e) {
          result = switch (e.failure) {
            StorageFailure.rejected => PlanActionResult.rejected,
            StorageFailure.notFound => PlanActionResult.notFound,
            _ => PlanActionResult.failed,
          };
        } on Object {
          result = PlanActionResult.failed;
        }
        await _load();
        return result;
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Ist die wöchentliche Prüfung fällig (FR-0158)? [lastCheckDay] ist der
/// Wert von `plan.last_check_day` (`JJJJ-MM-TT`); fehlt er oder ist er
/// unlesbar, ja; sonst, wenn er in einer früheren Kalenderwoche (ab Montag)
/// als [today] liegt.
bool weeklyCheckDue(String? lastCheckDay, DateTime today) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(lastCheckDay ?? '');
  if (m == null) return true;
  final last = DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
  );
  DateTime monday(DateTime d) {
    final x = planDay(d);
    return x.subtract(Duration(days: x.weekday - DateTime.monday));
  }

  return monday(last).isBefore(monday(today));
}
