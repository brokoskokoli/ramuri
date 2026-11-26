import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_goals.dart';
import '../../ports/storage_plan.dart';
import '../../ports/storage_warning.dart';
import '../goals/training_goal.dart';
import '../prediction/reference_performance.dart' show calendarDay;
import 'build_plan_inputs.dart';
import 'plan_adjust.dart' show evaluateWeekAdjustment;
import 'plan_deviation.dart' show PlanRunFacts;
import 'plan_goal_fingerprint.dart' show planGoalChangedSince;
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_recovery.dart';
import 'plan_warning.dart';
import 'recalculate_plan.dart';
import 'warning_service.dart';
import 'weekly_time.dart' show planDay;

/// Port: Eingaben der Plan-Abläufe aus dem Speicher (App: Lese-Adapter über
/// Läufe, Rückmeldungen, Referenz, Profil und Werte). Gerechnet wird nur in
/// `core`; Gesundheitsdaten nie loggen.
abstract interface class PlanWorkflowReader {
  /// Eingaben für [goal] am Ortstag [today] ([buildPlanInputs]).
  Future<BuiltPlanInputs> read({
    required TrainingGoal goal,
    required DateTime today,
  });

  /// Belege der Wochenprüfung (PAR-201) für die Woche vor der von [today].
  Future<WeekEvidence> weekEvidence(DateTime today);

  /// Läufe für die Regel der Abweichung (PAR-235) bis [today].
  Future<List<PlanRunFacts>> runFacts(DateTime today);
}

/// Belege der Wochenprüfung ([PlanWorkflowReader.weekEvidence]): Minuten der
/// bewerteten Woche (erledigt und geplant, `null` ohne Einheiten), RPE der
/// letzten lockeren Läufe (ältester zuerst) und gemeldete Ermüdung
/// (PAR-188).
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

/// Was die Prüfung beim Öffnen tun muss ([PlanWorkflowService.dueCheck]).
enum PlanDueKind {
  /// Nichts: kein Ziel, Prüfung diese Woche schon gelaufen oder offene
  /// Pausenfrage (PAR-202).
  none,

  /// Ziel ohne Fassung: erste Fassung (`create`).
  create,

  /// Das Ziel weicht von dem der neuesten Fassung ab (`goalChange`).
  goalChange,

  /// Warnsignal-Zeile und neueste Fassung passen nicht zueinander (FR-0203):
  /// Heilung mit `feedback`, ohne Prüftag.
  warningHeal,

  /// Wochenprüfung fällig (FR-0158, PAR-201): `weekly` bzw. `ruleVersion`,
  /// danach die Erholungsprüfung (PAR-173).
  weekly,
}

/// Ergebnis von [PlanWorkflowService.dueCheck]; nur Daten.
class PlanDueCheck {
  const PlanDueCheck._(this.kind, {this.goal, this.last, this.warned = false});

  static const PlanDueCheck none = PlanDueCheck._(PlanDueKind.none);

  final PlanDueKind kind;
  final TrainingGoal? goal;

  /// Neueste Fassung (`null` bei [PlanDueKind.create]).
  final PlanVersionRecord? last;

  /// Nur [PlanDueKind.warningHeal]: das Signal ist gespeichert (der Plan
  /// bekommt die Ruhetage); sonst aufgehoben (der Plan kehrt zurück).
  final bool warned;
}

/// Empfänger jeder Fassung, die ein Ablauf rechnet (auch ohne Änderung):
/// Der Aufrufer übernimmt Vorschau und Änderung in seinen Ansichtszustand.
typedef PlanRecalculationSink = void Function(PlanRecalculation r);

/// Die Abläufe des Plans ohne Oberfläche (ADR-0010): Prüfung beim Öffnen
/// (erste Fassung, Zieländerung, Heilung bei Warnsignal FR-0203,
/// Wochenprüfung PAR-201), Erholungsprüfung (PAR-173, nur bei „adaptiv“,
/// FR-0216) und die gemeinsame Neuberechnung. „Heute“ ist der Ortstag der
/// [clock]. Der Dienst hat keinen eigenen Zustand; die Reihenfolge der
/// Aufrufe sichert der Aufrufer über die Schreibreihe der Sitzung
/// ([PlanWriteQueue]).
class PlanWorkflowService {
  PlanWorkflowService({
    required this.session,
    required this.clock,
    required this.reader,
    required this.pauseQuestionOpen,
    this.parameters = const PlanParameters(),
    this.readinessToday,
  });

  final StorageSession session;
  final Clock clock;
  final PlanWorkflowReader reader;
  final PlanParameters parameters;

  /// Ist die Pausenfrage (PAR-202) offen? Solange rechnet keine
  /// Wochenbewertung.
  final Future<bool> Function() pauseQuestionOpen;

  /// Readiness des Tags für die Lockerung nach PAR-173; `null` oder ein
  /// Fehler: keine Lockerung (fail-closed). Gesundheitsdatum: nie loggen.
  final Future<PlanReadinessDay?> Function(DateTime day)? readinessToday;

  GoalStore get _goals => (session as GoalStorage).goals;
  PlanRepository get _plans => (session as PlanStorage).plans;
  WarningStore? get _warning =>
      session is WarningStorage ? (session as WarningStorage).warning : null;
  SettingsPlanAdaptationStore get _adaptation =>
      SettingsPlanAdaptationStore(session.settings);

  DateTime _today() => calendarDay(clock.now());

  /// Was die Prüfung beim Öffnen tun muss, in dieser Reihenfolge: Ziel ohne
  /// Fassung → `create`; Ziel weicht von der neuesten Fassung ab →
  /// `goalChange`; Warnsignal-Zeile und Fassung passen nicht (das Schreiben
  /// nach dem Setzen oder Aufheben scheiterte) → Heilung; sonst die
  /// Wochenprüfung, wenn `plan.last_check_day` fehlt oder in einer früheren
  /// Kalenderwoche liegt und keine Pausenfrage offen ist (PAR-202).
  Future<PlanDueCheck> dueCheck() async {
    final goal = await _goals.goal();
    if (goal == null) return PlanDueCheck.none;
    final history = await _plans.history();
    if (history.isEmpty) {
      return PlanDueCheck._(PlanDueKind.create, goal: goal);
    }
    final last = history.last;
    if (planGoalChangedSince(last.summary, goal)) {
      return PlanDueCheck._(PlanDueKind.goalChange, goal: goal, last: last);
    }
    final warning = _warning;
    if (warning != null) {
      final warned = await warning.read() != null;
      final held = warningHeldFromSummary(last.summary) != null;
      if (warned != held) {
        return PlanDueCheck._(
          PlanDueKind.warningHeal,
          goal: goal,
          last: last,
          warned: warned,
        );
      }
    }
    final checked = await session.settings.get(planLastCheckDayKey);
    if (!weeklyCheckDue(checked, _today())) return PlanDueCheck.none;
    // Solange die Pausenfrage offen ist, rechnet keine Wochenprüfung: Die
    // Wochenfassung setzte sonst den Anker auf den Montag und die Pausenregel
    // liefe ins Leere.
    if (await pauseQuestionOpen()) return PlanDueCheck.none;
    return PlanDueCheck._(PlanDueKind.weekly, goal: goal, last: last);
  }

  /// Führt [due] aus; jede gerechnete Fassung geht an [onResult]. Die
  /// Wochenprüfung bewertet die Woche (auch unter einer älteren Regelversion,
  /// dann `ruleVersion`) und nimmt danach Erholungsdaten nur über PAR-173
  /// auf ([recheckRecovery]), als eigene Fassung mit Grund `readiness`.
  Future<void> runDue(
    PlanDueCheck due, {
    PlanRecalculationSink? onResult,
  }) async {
    final goal = due.goal;
    if (goal == null) return;
    void take(PlanRecalculation r) => onResult?.call(r);
    switch (due.kind) {
      case PlanDueKind.none:
        return;
      case PlanDueKind.create:
        take(await recalculate(PlanTrigger.create, goal, null));
      case PlanDueKind.goalChange:
        take(await recalculate(PlanTrigger.goalChange, goal, due.last));
      case PlanDueKind.warningHeal:
        take(
          await recalculate(
            PlanTrigger.feedback,
            goal,
            due.last,
            reason: due.warned ? planReasonWarning : planReasonWarningLifted,
            // Die Heilung ist keine Wochenprüfung: der Prüftag bleibt, damit
            // eine fällige Bewertung der Vorwoche beim nächsten Öffnen läuft.
            markChecked: false,
          ),
        );
      case PlanDueKind.weekly:
        final last = due.last!;
        take(
          await recalculate(
            last.version.isCurrent
                ? PlanTrigger.weekly
                : PlanTrigger.ruleVersion,
            goal,
            last,
            adjust: true,
          ),
        );
        final after = await _plans.history();
        if (after.isNotEmpty) {
          final r = await recheckRecovery(goal, after.last);
          if (r != null) take(r);
        }
    }
  }

  /// Rechnet mit Eingaben aus dem Speicher. Anlegen: neue Eingaben aus
  /// [buildPlanInputs]; sonst die der letzten Fassung mit den heute
  /// gemessenen Werten ([refreshMeasuredInputs]).
  ///
  /// [adjust]: die wöchentliche Prüfung bewertet zuerst die letzte Woche
  /// (PAR-201, [evaluateWeekAdjustment]); ergibt sie eine Anpassung, gilt ihr
  /// neuer Anker, der Grund-Code der Fassung nennt die Gründe. Ohne Angabe
  /// bewertet nur eine Zieländerung bei fälliger Prüfung die Vorwoche mit
  /// (nicht bei offener Pausenfrage; dann bleibt auch der Prüftag).
  ///
  /// Lehnt der Speicher die Fassung ab (`rejected`, etwa weil sich der Plan
  /// seit dem Lesen geändert hat, ADR-0010), liest die Rechnung die neueste
  /// Fassung neu und rechnet genau einmal noch. Scheitert auch das, geht die
  /// Ablehnung an den Aufrufer.
  Future<PlanRecalculation> recalculate(
    PlanTrigger trigger,
    TrainingGoal goal,
    PlanVersionRecord? last, {
    bool? adjust,
    String? reason,
    bool markChecked = true,
    Iterable<PlanReadinessDay> readiness = const [],
  }) async {
    Future<PlanRecalculation> once(PlanVersionRecord? from) => _recalculateOnce(
      trigger,
      goal,
      from,
      adjust: adjust,
      reason: reason,
      markChecked: markChecked,
      readiness: readiness,
    );
    try {
      return await once(last);
    } on StorageException catch (e) {
      if (e.failure != StorageFailure.rejected) rethrow;
    }
    final history = await _plans.history();
    return once(history.isEmpty ? null : history.last);
  }

  Future<PlanRecalculation> _recalculateOnce(
    PlanTrigger trigger,
    TrainingGoal goal,
    PlanVersionRecord? last, {
    bool? adjust,
    String? reason,
    bool markChecked = true,
    Iterable<PlanReadinessDay> readiness = const [],
  }) async {
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    var inputs = inputsFor(trigger, built, last);
    // Eine Zieländerung setzt den Prüftag; eine fällige Wochenbewertung der
    // Vorwoche fällt dadurch nicht weg, sie geht in dieselbe Fassung ein
    // (Grund bleibt `goalChange`). Bei offener Pausenfrage (PAR-202) nicht:
    // Die Bewertung setzte den Anker auf den Montag und die Pausenregel liefe
    // danach ins Leere. Dann bleibt auch der Prüftag unberührt: Nach „Nein“
    // läuft die Wochenprüfung beim nächsten Öffnen.
    final dueOnGoalChange =
        adjust == null &&
        trigger == PlanTrigger.goalChange &&
        weeklyCheckDue(await session.settings.get(planLastCheckDayKey), today);
    final skippedForPause = dueOnGoalChange && await pauseQuestionOpen();
    final doAdjust = adjust ?? (dueOnGoalChange && !skippedForPause);
    if (doAdjust && last != null) {
      final evidence = await reader.weekEvidence(today);
      final a = evaluateWeekAdjustment(
        goal: goal,
        inputs: inputs,
        today: today,
        doneMinutes: evidence.doneMinutes,
        plannedMinutes: evidence.plannedMinutes,
        recentEasyRpe: evidence.recentEasyRpe,
        fatigueReported: evidence.fatigueReported,
        parameters: parameters,
      );
      if (a != null) {
        inputs = refreshMeasuredInputs(a.inputs, built.inputs);
        // Bei `goalChange` bleibt der Grund-Code vorn, die Gründe der
        // Bewertung folgen: `goalChange,repeatWeek`.
        final codes = ([
          ...a.reasons,
        ]..sort((x, y) => x.index - y.index)).map((r) => r.name).join(',');
        if (trigger == PlanTrigger.weekly) {
          reason = codes;
        } else if (trigger == PlanTrigger.goalChange) {
          reason = 'goalChange,$codes';
        } else if (trigger == PlanTrigger.ruleVersion) {
          reason = 'ruleVersion,$codes';
        }
      }
    }
    return write(
      trigger: trigger,
      today: today,
      reason: reason,
      inputs: inputs,
      readiness: readiness,
      // `manual` bewertet die Woche nicht (ADR-0010): Der Prüftag bleibt,
      // sonst fiele die fällige Wochenbewertung weg.
      markChecked:
          markChecked && !skippedForPause && trigger != PlanTrigger.manual,
    );
  }

  /// Schreibt die Neuberechnung ([recalculatePlan]) mit den Läufen der
  /// Woche für die Regel der Abweichung (PAR-235): Jede Fassung rechnet mit
  /// ihnen, sonst fielen Kürzung, Lockerung und Tausch beim nächsten Rechnen
  /// zurück. Ohne Wiederholung nach einer Ablehnung (die macht
  /// [recalculate] mit der neuesten Fassung).
  Future<PlanRecalculation> write({
    required PlanTrigger trigger,
    required DateTime today,
    String? reason,
    PlanInputs? inputs,
    bool markChecked = true,
    Iterable<PlanReadinessDay> readiness = const [],
  }) async => recalculatePlan(
    plans: _plans,
    settings: session.settings,
    trigger: trigger,
    today: today,
    now: clock.now(),
    reason: reason,
    inputs: inputs,
    parameters: parameters,
    warning: _warning,
    markChecked: markChecked,
    readiness: readiness,
    runs: await reader.runFacts(today),
    retryRejected: false,
  );

  /// Eingaben der Rechnung für [trigger]: beim Anlegen (oder ohne Fassung)
  /// die frischen aus [buildPlanInputs], sonst die der letzten Fassung mit den
  /// heute gemessenen Werten ([refreshMeasuredInputs]).
  static PlanInputs inputsFor(
    PlanTrigger trigger,
    BuiltPlanInputs built,
    PlanVersionRecord? last,
  ) => (trigger == PlanTrigger.create || last == null)
      ? built.inputs
      : refreshMeasuredInputs(last.inputs, built.inputs);

  /// Erholungsprüfung für heute (FR-0157, Teil „3 (Erholung)“): nach neuen
  /// Gesundheitsdaten und nach einer Morgenmessung. Liest Ziel und neueste
  /// Fassung; ohne beide `null`. Sonst wie [recheckRecovery].
  Future<PlanRecalculation?> recheckRecoveryToday() async {
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) return null;
    return recheckRecovery(goal, history.last);
  }

  /// Lockerung der heutigen harten Einheit nach PAR-173: nur bei „adaptiv“
  /// (FR-0216) und nur, wenn heute eine harte Einheit offen ist
  /// ([recoveryEasable]) und der heutige Wert in einem Band liegt; dann eine
  /// Fassung (`feedback`, Grund `readiness`), in der genau diese Einheit
  /// locker ist. Sonst `null` (nichts gerechnet). Der Wert anderer Tage zählt
  /// nicht.
  Future<PlanRecalculation?> recheckRecovery(
    TrainingGoal goal,
    PlanVersionRecord last,
  ) async {
    if (await _adaptation.read() != PlanAdaptationMode.adaptive) return null;
    final today = _today();
    final unit = await _plans.unitOn(today);
    if (unit == null || !recoveryEasable(unit)) return null;
    final day = await readinessOn(today);
    if (day == null || !day.eases) return null;
    return recalculate(
      PlanTrigger.feedback,
      goal,
      last,
      reason: planReasonReadiness,
      readiness: [day],
      markChecked: false,
    );
  }

  /// Wechsel der Plananpassung (FR-0216): Gleicher Modus ändert nichts.
  /// Sonst speichert der Dienst den Modus; bei „adaptiv“ folgt die
  /// Erholungsprüfung für heute ([recheckRecovery]), bei „fix“ kehrt eine
  /// heute gelockerte Einheit zurück (`feedback`, Grund `adaptationFixed`).
  /// `null`, wenn nichts gerechnet wurde.
  Future<PlanRecalculation?> setAdaptation(PlanAdaptationMode mode) async {
    final store = _adaptation;
    if (await store.read() == mode) return null;
    await store.set(mode, at: clock.now());
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) return null;
    final last = history.last;
    if (mode == PlanAdaptationMode.adaptive) {
      return recheckRecovery(goal, last);
    }
    final today = _today();
    final easedToday = recoveryEasedFromSummary(last.summary)
        .any((e) => planDay(e.day) == today);
    if (!easedToday) return null;
    return recalculate(
      PlanTrigger.feedback,
      goal,
      last,
      reason: planReasonAdaptationFixed,
      markChecked: false,
    );
  }

  /// Readiness von [day] aus [readinessToday]; ohne Quelle, mit einem Wert
  /// eines anderen Tags oder bei einem Fehler `null` (keine Lockerung).
  Future<PlanReadinessDay?> readinessOn(DateTime day) async {
    final load = readinessToday;
    if (load == null) return null;
    try {
      final r = await load(day);
      return r != null && planDay(r.day) == day ? r : null;
    } on Object {
      return null;
    }
  }

  /// Melden und Aufheben des Warnsignals (FR-0203) mit den Eingaben des
  /// Lese-Adapters; `null` ohne Warnspeicher.
  WarningService? get warnings {
    final w = _warning;
    if (w == null) return null;
    return WarningService(
      plans: _plans,
      settings: session.settings,
      warning: w,
      parameters: parameters,
      measuredInputs: (goal, today) async =>
          (await reader.read(goal: goal, today: today)).inputs,
      runFacts: reader.runFacts,
    );
  }

  /// Signal manuell setzen (FR-0203, Quelle `manual`); ohne Warnspeicher ein
  /// Fehler. Doppeltes Melden ändert nichts.
  Future<void> markWarning() async {
    final service = warnings;
    if (service == null) throw StateError('kein Warnspeicher');
    await service.mark(source: WarningSource.manual, today: _today());
  }

  /// Fassung unter gespeichertem Signal (nur Ruhetage).
  Future<PlanRecalculation> recalculateWarned() {
    final service = warnings;
    if (service == null) throw StateError('kein Warnspeicher');
    return service.recalculateReported(today: _today(), now: clock.now());
  }

  /// Signal aufheben; die Festlegungen des Nutzers gelten wieder.
  Future<PlanRecalculation> liftWarning() {
    final service = warnings;
    if (service == null) throw StateError('kein Warnspeicher');
    return service.lift(today: _today(), now: clock.now());
  }
}
