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

  /// Nur [PlanController.saveGoal]: das Ziel ist gespeichert, die
  /// Neuberechnung des Plans scheiterte. Der Plan gehört noch zum alten Ziel;
  /// die nächste Neuberechnung (erneutes Speichern, Öffnen, auch nach einem
  /// Neustart, [PlanController.recalculate], [PlanController.assignRun]) holt
  /// die Zieländerung nach: Das Ziel weicht vom Fingerabdruck der neuesten
  /// Fassung ab ([planGoalChangedSince]).
  savedNotPlanned,
}

/// Das Ziel ist gespeichert, die Neuberechnung danach scheiterte.
class _SavedNotPlanned implements Exception {
  const _SavedNotPlanned();
}

/// Prüfung eines Ziels vor dem Speichern ([PlanController.checkGoal]).
class GoalDraftCheck {
  const GoalDraftCheck({required this.assessment, required this.walkRun});

  /// Einschätzung nach PAR-206; [GoalAssessment.fitsFrom] ist das Angebot
  /// eines Datums.
  final GoalAssessment assessment;

  /// Der Plan beginnt mit der Geh-Lauf-Abfolge (PAR-065); vor dem Speichern
  /// steht der Hinweis aus PAR-115.
  final bool walkRun;
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
  /// Ergebnis, sonst die an der neuesten Fassung gespeicherten
  /// ([planHintsFromSummary]); nur für Fassungen ohne gespeicherte Hinweise
  /// eine Vorschau ([previewPlan]). Abstandskonflikte kommen immer aus den
  /// gespeicherten Einheiten ([planSpacingConflicts]), damit eine bestätigte
  /// Verschiebung sofort sichtbar ist. `null` ohne Plan.
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
  /// Weicht das Ziel von dem der neuesten Fassung ab (Neuberechnung nach dem
  /// Speichern gescheitert, [PlanActionResult.savedNotPlanned]), rechnet das
  /// Öffnen sofort mit `goalChange`.
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
    if (planGoalChangedSince(last.summary, goal)) {
      await _recalculate(PlanTrigger.goalChange, goal, last);
      return;
    }
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
    final inputs = _inputsFor(trigger, built, last);
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

  /// Eingaben der Rechnung für [trigger]: beim Anlegen (oder ohne Fassung)
  /// die frischen aus [buildPlanInputs], sonst die der letzten Fassung mit den
  /// heute gemessenen Werten ([refreshMeasuredInputs]). Gemeinsam für das
  /// Speichern ([_recalculate]) und die Einschätzung davor ([checkGoal]).
  static PlanInputs _inputsFor(
    PlanTrigger trigger,
    BuiltPlanInputs built,
    PlanVersionRecord? last,
  ) => (trigger == PlanTrigger.create || last == null)
      ? built.inputs
      : refreshMeasuredInputs(last.inputs, built.inputs);

  /// Auslöser beim Speichern eines Ziels: `goalChange`, wenn schon ein Ziel
  /// mit Fassung besteht, sonst `create`.
  static PlanTrigger _saveTrigger(
    bool goalExisted,
    List<PlanVersionRecord> history,
  ) => goalExisted && history.isNotEmpty
      ? PlanTrigger.goalChange
      : PlanTrigger.create;

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
    final units = version == null
        ? const <PlanUnit>[]
        : await _plans.unitsBetween(version.inputs.anchor, planFarFuture);
    if (hints == null && goal != null && version != null) {
      final inputs = version.inputs.copyWith(today: today);
      hints =
          planHintsFromSummary(
            version.summary,
            version: version.version,
            units: units,
            today: today,
          ) ??
          previewPlan(
            goal: goal,
            inputs: inputs,
            units: units,
            today: today,
            parameters: parameters,
          );
    }
    // Abstandskonflikte immer aus den gespeicherten Einheiten: Eine bestätigte
    // Verschiebung ändert sie ohne neue Fassung. Die übrigen Konflikte
    // stammen aus der letzten Rechnung, die vor heute fallen weg.
    if (hints != null) {
      hints = hints.copyWith(
        pinnedConflicts: [
          for (final c in hints.pinnedConflicts)
            if (c.kind != PinnedConflictKind.spacing && !c.day.isBefore(today))
              c,
          ...planSpacingConflicts(units, today, parameters: parameters),
        ],
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

  /// Beendete Läufe mit Ortstag (Tag des Laufendes, [dayOfRun]) in
  /// `from <= Tag <= to`, für den Kalender (FR-0171) und die Prüfung beim
  /// Verschieben: [PlanCalendarRun.intensive] nach PAR-058 aus der
  /// RPE-Angabe ([PlanParameters.completedIntensiveMinRpe]).
  ///
  /// Liest nur die Läufe, deren Ende höchstens den größten UTC-Versatz
  /// ([maxRunEndUtcOffset]) außerhalb des Zeitraums liegt, und nur deren
  /// subjektive Angaben (Befund E2-6).
  Future<List<PlanCalendarRun>> runsBetween(DateTime from, DateTime to) async {
    final f = planDay(from), t = planDay(to);
    final result = <PlanCalendarRun>[];
    for (final r in await session.runs.finishedBetween(
      f.subtract(maxRunEndUtcOffset),
      t.add(const Duration(days: 1) + maxRunEndUtcOffset),
    )) {
      final p = DateTime.parse(dayOfRun(r));
      final day = DateTime.utc(p.year, p.month, p.day);
      if (day.isBefore(f) || day.isAfter(t)) continue;
      final value = (await session.subjective.read(r.id))?.subjective.rpe;
      result.add(
        PlanCalendarRun(
          id: r.id,
          day: day,
          intensive:
              value != null && value >= parameters.completedIntensiveMinRpe,
        ),
      );
    }
    return result;
  }

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

  /// Stand aus vorhandenen Läufen (PAR-192: „Vorhandene Läufe in der App
  /// ersetzen die Angabe zum Stand“) als Wochenzeit in Sekunden, `null` ohne
  /// Läufe im Fenster. Für das Zielformular: Mit Läufen entfällt die Frage
  /// nach dem Stand. Gelesen wie bei der Planrechnung ([buildPlanInputs]);
  /// das Ziel dafür ist ein Platzhalter ohne eigenen Stand.
  Future<double?> standFromRuns() async {
    final probe = TrainingGoal(
      type: GoalType.open,
      runDays: const {DateTime.monday},
      maxSessionSeconds: 1,
      weeklyCapSeconds: 1,
      createdAt: clock.now(),
      hardSessionEnabled: false,
    );
    final built = await reader.read(goal: probe, today: _today());
    return built.goal.currentWeeklySeconds;
  }

  /// Einschätzung eines noch nicht gespeicherten Ziels (PAR-206) mit genau
  /// den Eingaben, mit denen [saveGoal] danach rechnen würde: beim Anlegen
  /// die frischen ([buildPlanInputs], Stand ggf. aus Läufen), beim Ändern die
  /// der letzten Fassung mit heute gemessenen Werten (Stand und Geh-Lauf-
  /// Abfolge bleiben, [refreshMeasuredInputs]); dazu, ob der Plan mit einer
  /// Geh-Lauf-Abfolge beginnt (PAR-065, Hinweis PAR-115). Speichert nichts.
  Future<GoalDraftCheck> checkGoal(TrainingGoal draft) async {
    final today = _today();
    final existed = await _goals.goal() != null;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final built = await reader.read(goal: draft, today: today);
    final inputs = _inputsFor(_saveTrigger(existed, history), built, last);
    final assessment = assessGoal(
      goal: built.goal,
      inputs: inputs,
      today: today,
      basis: await reader.timeGoalBasis(goal: built.goal, today: today),
      parameters: parameters,
    );
    final setup = planCourseSetup(built.goal, inputs, parameters: parameters);
    return GoalDraftCheck(
      assessment: assessment,
      walkRun: setup.walkRunWeeks > 0,
    );
  }

  /// Speichert das Ziel (Anlegen oder Ändern, PAR-203) mit „heute“ und
  /// rechnet den Plan ab heute neu (`create` ohne bisheriges Ziel oder ohne
  /// Fassung, sonst `goalChange`), mit dem gespeicherten Ziel. Ungültiges Ziel:
  /// [PlanActionResult.rejected], nichts geändert. Scheitert nur die
  /// Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> saveGoal(TrainingGoal goal) => _act(() async {
    final existed = await _goals.goal() != null;
    await _goals.save(goal, today: _today());
    onChanged?.call();
    try {
      final saved = await _goals.goal();
      if (saved == null) {
        throw const StorageException(StorageFailure.notFound);
      }
      final history = await _plans.history();
      await _recalculate(
        _saveTrigger(existed, history),
        saved,
        history.isEmpty ? null : history.last,
      );
    } on Object {
      throw const _SavedNotPlanned();
    }
  });

  /// Ausdrückliche Neuberechnung durch den Nutzer (`manual`).
  Future<PlanActionResult> recalculate() => _act(() async {
    final goal = await _goals.goal();
    if (goal == null) {
      throw const StorageException(StorageFailure.notFound);
    }
    final history = await _plans.history();
    await _recalculate(
      history.isEmpty
          ? PlanTrigger.create
          : (planGoalChangedSince(history.last.summary, goal)
                ? PlanTrigger.goalChange
                : PlanTrigger.manual),
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
    final last = history.isEmpty ? null : history.last;
    await _recalculate(
      last != null && planGoalChangedSince(last.summary, goal)
          ? PlanTrigger.goalChange
          : PlanTrigger.run,
      goal,
      last,
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

  /// Prüft vor der Bestätigung, ob [unit] die Art [kind] bekommen kann
  /// ([checkPlanReplace] mit Ziel und Eingaben der neuesten Fassung, Einheiten
  /// und absolvierten intensiven Läufen um die Woche, „heute“). `null` ohne
  /// Ziel oder Fassung.
  Future<PlanReplaceCheck?> checkReplace(PlanUnit unit, PlanUnitKind kind) =>
      _serial(() => _replaceCheck(unit, kind, _today()));

  Future<PlanReplaceCheck?> _replaceCheck(
    PlanUnit unit,
    PlanUnitKind kind,
    DateTime today,
  ) async {
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) return null;
    final w = await _weekAround(unit.day);
    return checkPlanReplace(
      units: w.units,
      unit: unit,
      kind: kind,
      goal: goal,
      inputs: history.last.inputs,
      today: today,
      completedIntensiveDays: w.intensive,
      parameters: parameters,
    );
  }

  /// Prüft vor der Bestätigung, ob [day] Ruhetag werden kann
  /// ([checkPlanRestDay]: Alternativtage derselben Woche für eine Einheit
  /// auf dem Tag). `null` ohne Ziel oder Fassung.
  Future<PlanRestDayCheck?> checkRestDay(DateTime day) => _serial(() async {
    final goal = await _goals.goal();
    if (goal == null || (await _plans.history()).isEmpty) return null;
    final w = await _weekAround(day);
    return checkPlanRestDay(
      units: w.units,
      day: day,
      today: _today(),
      weeklyCapSeconds: goal.weeklyCapSeconds,
      completedIntensiveDays: w.intensive,
      runDays: goal.runDays,
      parameters: parameters,
    );
  });

  /// Einheiten und absolvierte intensive Läufe von einer Woche vor bis eine
  /// Woche nach der Woche von [day] (Abstand PAR-059/PAR-060 über die
  /// Wochengrenze).
  Future<({List<PlanUnit> units, List<DateTime> intensive})> _weekAround(
    DateTime day,
  ) async {
    final d = planDay(day);
    final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
    final from = monday.subtract(const Duration(days: 7));
    final to = monday.add(const Duration(days: 13));
    return (
      units: await _plans.unitsBetween(from, to),
      intensive: [
        for (final r in await runsBetween(from, to))
          if (r.intensive) r.day,
      ],
    );
  }

  /// Ersetzt die Art der Einheit nach Bestätigung des Nutzers durch [kind]
  /// (FR-0173, `fixed = kind`): Dauer, Abschnitte und Zielintensität rechnet
  /// [checkPlanReplace] mit „heute“ neu, wie beim Bestätigen gezeigt. Keine
  /// Neuberechnung (wie [confirmMove]). Fehlt die Einheit, das Ziel oder die
  /// Fassung: `notFound`; sperrt die Prüfung (eingefroren, vergangen,
  /// Geh-Lauf, Art passt nicht in die maximale Zeit, …): `rejected`.
  Future<PlanActionResult> replaceUnit(int unitId, PlanUnitKind kind) =>
      _act(() async {
        final today = _today();
        final history = await _plans.history();
        if (history.isEmpty) {
          throw const StorageException(StorageFailure.notFound);
        }
        final unit = (await _plans.unitsBetween(
          history.last.inputs.anchor,
          planFarFuture,
        )).where((u) => u.id == unitId).firstOrNull;
        if (unit == null) throw const StorageException(StorageFailure.notFound);
        final check = await _replaceCheck(unit, kind, today);
        if (check == null) {
          throw const StorageException(StorageFailure.notFound);
        }
        if (!check.allowed) {
          throw const StorageException(StorageFailure.rejected);
        }
        await _plans.replaceUnit(unitId, check.unit!, today: today);
        _fresh = null;
        onChanged?.call();
      });

  /// Legt [day] nach Bestätigung als Ruhetag fest ([planRestDayUnit] mit Ziel
  /// und Eingaben der neuesten Fassung). Eine Einheit auf dem Tag geht auf
  /// [moveUnitTo] (gewählter Alternativtag aus [checkRestDay]) oder entfällt
  /// ohne ihn. [expectedUnitId] ist die Einheit, die [checkRestDay] auf dem
  /// Tag gezeigt hat (`null`: Tag frei); liegt jetzt eine andere dort, ändert
  /// sich nichts (FR-0176). Keine Neuberechnung. Ohne Ziel oder Fassung:
  /// `notFound`; Tag vor heute, Einheit mit Lauf, schon festgelegter Ruhetag, abweichende
  /// Einheit, ungültiger Zieltag: `rejected`.
  Future<PlanActionResult> setRestDay(
    DateTime day, {
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  }) => _act(() async {
    final today = _today();
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    await _plans.setRestDay(
      planRestDayUnit(
        day: day,
        goal: goal,
        inputs: history.last.inputs,
        today: today,
        parameters: parameters,
      ),
      today: today,
      expectedUnitId: expectedUnitId,
      moveUnitTo: moveUnitTo,
    );
    _fresh = null;
    onChanged?.call();
  });

  /// Hebt den Ruhetag an [day] nach Bestätigung auf; die App plant dort erst
  /// bei der nächsten Neuberechnung wieder (OQ-0011). Kein Ruhetag:
  /// `notFound`; Tag vor heute: `rejected`.
  Future<PlanActionResult> clearRestDay(DateTime day) => _act(() async {
    await _plans.clearRestDay(day, today: _today());
    _fresh = null;
    onChanged?.call();
  });

  Future<PlanActionResult> _act(Future<void> Function() action) =>
      _serial(() async {
        PlanActionResult result;
        try {
          await action();
          result = PlanActionResult.done;
        } on _SavedNotPlanned {
          result = PlanActionResult.savedNotPlanned;
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

/// Ein beendeter Lauf im Kalender ([PlanController.runsBetween]).
class PlanCalendarRun {
  const PlanCalendarRun({
    required this.id,
    required this.day,
    required this.intensive,
  });

  final int id;

  /// Ortstag des Laufendes.
  final DateTime day;

  /// Gilt nach PAR-058 als intensiv (RPE-Angabe).
  final bool intensive;
}
