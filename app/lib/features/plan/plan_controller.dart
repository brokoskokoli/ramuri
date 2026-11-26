import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'plan_data_reader.dart';
import 'plan_started_unit.dart';

enum PlanLoadPhase { loading, ready, failed }

/// Einstellungsschlüssel: Ortstag (`JJJJ-MM-TT`) der letzten Antwort auf die
/// Nachfrage nach PAR-200. Fehlt er, zählt die Anlage des Plans.
const String planFeedbackKey = 'plan.feedback_answered_on';

/// Einstellungsschlüssel: letzter Tag (`JJJJ-MM-TT`) der Programmwoche, deren
/// Vorschlag „Woche wiederholen“ der Nutzer abgelehnt hat (PAR-140).
const String planWalkRunRepeatDeclinedKey = 'plan.walk_run_repeat_declined';

/// Ergebnis von [PlanController.answerFeedback].
class PlanFeedbackOutcome {
  const PlanFeedbackOutcome(
    this.result, {
    this.raiseGoalSignal = false,
    this.planChanged = false,
  });

  final PlanActionResult result;

  /// „Zu leicht“ am Regler: Die App fragt, ob das Ziel steigen soll; der Plan
  /// ist unverändert.
  final bool raiseGoalSignal;

  /// Eine neue Planfassung wurde geschrieben. Bei „zu schwer“ im kleinsten
  /// Plan bleibt die Fassung gleich, die Meldung sagt dann „bleibt“.
  final bool planChanged;
}

String _dayText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDay(String? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v ?? '');
  if (m == null) return null;
  final d = DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  return _dayText(d) == v ? d : null;
}

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
      assessment = null,
      warning = null,
      warningReminderDue = false,
      feedbackDue = false,
      changeNotice = null,
      walkRunProposal = null,
      underloadPrompt = null,
      adaptation = PlanAdaptationMode.fixed;

  const PlanViewState.failed()
    : phase = PlanLoadPhase.failed,
      goal = null,
      version = null,
      hints = null,
      lastChange = null,
      weekUnits = const [],
      assessment = null,
      warning = null,
      warningReminderDue = false,
      feedbackDue = false,
      changeNotice = null,
      walkRunProposal = null,
      underloadPrompt = null,
      adaptation = PlanAdaptationMode.fixed;

  const PlanViewState.ready({
    required this.goal,
    required this.version,
    required this.hints,
    required this.lastChange,
    required this.weekUnits,
    this.assessment,
    this.warning,
    this.warningReminderDue = false,
    this.feedbackDue = false,
    this.changeNotice,
    this.walkRunProposal,
    this.underloadPrompt,
    this.adaptation = PlanAdaptationMode.fixed,
  }) : phase = PlanLoadPhase.ready;

  final PlanLoadPhase phase;

  /// Plananpassung an Erholung (FR-0216): gespeicherter Schalter, Vorgabe
  /// „fix“.
  final PlanAdaptationMode adaptation;

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

  /// Das aktive Warnsignal (FR-0203) oder `null`. Solange es besteht, zeigt
  /// der Plan nur Ruhetage; gehaltene festgelegte Ruhetage sind dann keine
  /// Festlegung des Nutzers.
  final WarningSignal? warning;

  /// Die Meldung besteht seit mindestens 7 Tagen (nur Karte, keine
  /// Benachrichtigung).
  final bool warningReminderDue;

  /// Die Nachfrage nach PAR-200 ist fällig (2 Wochen ab der letzten Antwort
  /// bzw. Anlage des Plans); ohne Warnsignal.
  final bool feedbackDue;

  /// Größere Änderung, die der Nutzer noch nicht gesehen hat (PAR-204,
  /// FR-0170): Karte „Plan angepasst“ bis [PlanController.markChangeSeen].
  final PlanChangeNotice? changeNotice;

  /// Vorschlag „Woche wiederholen“ in der Geh-Lauf-Phase (PAR-140); die App
  /// fragt, der Nutzer entscheidet. Nicht unter Warnsignal.
  final WalkRunWeekProposal? walkRunProposal;

  /// Offener Hinweis bzw. offene Frage der Unterforderung (PAR-236): nur bei
  /// „adaptiv“, ohne Warnsignal, ohne Korrektur nach unten in dieser Woche
  /// (PAR-201) und ohne Readiness nach PAR-173; sonst `null`.
  final PlanUnderloadPrompt? underloadPrompt;

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
    this.readinessToday,
    this.exclusive,
  }) : _writes = PlanWriteQueue.of(session),
       reader =
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

  /// Readiness des Tags (heute; Modell, FR-0116) für die Lockerung nach
  /// PAR-173, als Band und senkende Faktoren ([PlanReadinessDay.of]); `null`
  /// oder ein Fehler: keine Lockerung (fail-closed). Gesundheitsdatum: nie
  /// loggen.
  final Future<PlanReadinessDay?> Function(DateTime day)? readinessToday;

  /// Sperre der Neuberechnung der Werte (`RecalculationController`), hinter
  /// der die automatische Zuordnung beim Öffnen läuft (PAR-231): wie nach dem
  /// Lauf-Ende erst nach dessen Wertberechnung, nie parallel zu ihr. `null`
  /// (Tests, Aufrufer schon innerhalb der Sperre): ohne. Nie innerhalb der
  /// Sperre an einen Controller mit Sperre übergeben (nicht wiedereintretend).
  final Future<void> Function(Future<void> Function() action)? exclusive;

  /// Die Schreibreihe des Plans dieser Sitzung, gemeinsam mit jedem anderen
  /// Controller und dem Erholungs-Auslöser ([PlanWriteQueue.of]).
  final PlanWriteQueue _writes;

  SettingsPlanAdaptationStore get _adaptation =>
      SettingsPlanAdaptationStore(session.settings);

  GoalStore get _goals => (session as GoalStorage).goals;
  PlanRepository get _plans => (session as PlanStorage).plans;
  WarningStore? get _warning =>
      session is WarningStorage ? (session as WarningStorage).warning : null;

  PlanViewState _state = const PlanViewState.loading();
  PlanViewState get state => _state;

  GeneratedPlan? _fresh;
  PlanChangeSummary? _lastChange;

  bool _disposed = false;

  DateTime _today() => calendarDay(clock.now());

  /// Führt [action] in der Schreibreihe der Sitzung aus: nach allen vorher
  /// angestoßenen Aktionen jedes Plan-Controllers der Sitzung, nie parallel.
  Future<T> _serial<T>(Future<T> Function() action) => _writes.run(action);

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
  ///
  /// Danach ordnet das Öffnen Läufe der Woche bis heute ihren offenen
  /// Einheiten zu (PAR-231); mit [exclusive] hinter der Wertberechnung, dann
  /// erst nach dem ersten Laden der Seite. Erst nach der Zuordnung prüft es
  /// das Muster der Unterforderung (PAR-236), auch wenn die Zuordnung
  /// scheitert; dann zählen die schon zugeordneten Läufe.
  Future<void> open() async {
    final lock = exclusive;
    await _serial(() async {
      _fresh = null;
      try {
        // Pause hat Vorrang (PAR-202): ihre Fassung gilt für diese Woche und
        // setzt den Prüftag, die Wochenprüfung schreibt danach keine zweite.
        await _checkPauseRestart();
        await _checkDue();
      } on Object {
        // Die Prüfung holt der nächste Start nach; die Seite zeigt den
        // gespeicherten Plan.
      }
      // Erst zuordnen, dann das Muster prüfen (PAR-236): Ein Lauf, dessen
      // Zuordnung erst dieses Öffnen nachholt, zählt schon jetzt.
      if (lock == null) {
        await _autoAssignQuietly();
        await _advanceUnderloadQuietly();
      }
      await _load();
    });
    if (lock == null) return;
    // Sperre zuerst, dann die Schreibreihe (wie nach dem Lauf-Ende), nie
    // umgekehrt: sonst warteten beide aufeinander.
    var advanced = false;
    try {
      await lock(
        () => _serial(() async {
          await _autoAssignQuietly();
          await _advanceUnderloadQuietly();
          advanced = true;
        }),
      );
    } on Object {
      // Das nächste Öffnen holt die Zuordnung nach.
    }
    // Neu laden, auch ohne eigene Zuordnung: Während des Wartens auf die
    // Sperre kann eine andere Stelle (Lauf-Ende) zugeordnet haben. Ohne
    // Sperre prüft das Öffnen das Muster trotzdem mit den schon zugeordneten
    // Läufen.
    await _serial(() async {
      if (!advanced) await _advanceUnderloadQuietly();
      await _load();
    });
  }

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
    // Warnsignal-Zeile und letzte Fassung müssen zueinander passen: Scheiterte
    // das Schreiben nach dem Setzen oder Aufheben der Zeile (und auch deren
    // Rücknahme), stellt das Öffnen den Plan her, ohne die Wochenprüfung
    // abzuwarten.
    final warning = _warning;
    if (warning != null) {
      final warned = await warning.read() != null;
      final held = warningHeldFromSummary(last.summary) != null;
      if (warned != held) {
        // Banner bzw. Erinnerung zuerst zeigen, nicht erst nach der Rechnung;
        // unter gespeichertem Signal mit Fortschrittsanzeige wie nach dem
        // Melden, bis die Rechnung endet (auch wenn sie scheitert). Das
        // anschließende Laden in [open] blendet sie aus.
        _warningRecalculating = warned;
        try {
          await _load();
          await _recalculate(
            PlanTrigger.feedback,
            goal,
            last,
            reason: warned ? planReasonWarning : planReasonWarningLifted,
            // Die Heilung ist keine Wochenprüfung: der Prüftag bleibt, damit
            // eine fällige Bewertung der Vorwoche beim nächsten Öffnen läuft.
            markChecked: false,
          );
        } finally {
          _warningRecalculating = false;
        }
        return;
      }
    }
    final today = _today();
    final checked = await session.settings.get(planLastCheckDayKey);
    if (!weeklyCheckDue(checked, today)) return;
    // Solange die Pausenfrage offen ist (PAR-202), rechnet das Öffnen keine
    // Wochenprüfung: Nach der Antwort greift erst die Pausenregel, die
    // Prüfung gilt dann für die Woche (Prüftag) oder läuft beim nächsten
    // Öffnen normal. Die Wochenfassung würde sonst den Anker auf den Montag
    // setzen und die Pausenregel ins Leere laufen lassen.
    if (await HintService(session: session, clock: clock).pauseQuestion() !=
        null) {
      return;
    }
    // Auch unter einer älteren Regelversion bewertet die Prüfung die Woche
    // (PAR-201, NB6 1).
    await _recalculate(
      last.version.isCurrent ? PlanTrigger.weekly : PlanTrigger.ruleVersion,
      goal,
      last,
      adjust: true,
    );
    // Erholungsdaten nimmt die Prüfung nur über PAR-173 auf (FR-0158, Teil
    // „3 (Erholung)“): bei „adaptiv“ der Wert von heute, als eigene Fassung
    // mit Grund `readiness`, damit die Lockerung ihren Grund nennt.
    final after = await _plans.history();
    if (after.isNotEmpty) await _recheckRecovery(goal, after.last);
  }

  /// Rechnet mit Eingaben aus dem Speicher. Anlegen: neue Eingaben aus
  /// [buildPlanInputs]; sonst die der letzten Fassung mit den heute
  /// gemessenen Werten ([refreshMeasuredInputs]).
  ///
  /// [adjust]: die wöchentliche Prüfung bewertet zuerst die letzte Woche
  /// (PAR-201, [evaluateWeekAdjustment]); ergibt sie eine Anpassung, gilt ihr
  /// neuer Anker, der Grund-Code der Fassung nennt die Gründe. Einmal je
  /// Woche (die Prüfung merkt sich den Tag), und die bewertete Woche liegt
  /// danach vor dem Anker.
  ///
  /// Lehnt der Speicher die Fassung ab (`rejected`, etwa weil sich der Plan
  /// seit dem Lesen geändert hat, ADR-0010), liest die Rechnung die neueste
  /// Fassung neu und rechnet genau einmal noch. Scheitert auch das, bleibt
  /// der gespeicherte Stand und die Ablehnung geht an den Aufrufer (kein
  /// stiller Verlust: Aktionen melden `rejected`, die Prüfungen beim Öffnen
  /// setzen den Prüftag nicht und laufen beim nächsten Öffnen erneut).
  Future<bool> _recalculate(
    PlanTrigger trigger,
    TrainingGoal goal,
    PlanVersionRecord? last, {
    bool? adjust,
    String? reason,
    bool markChecked = true,
    Iterable<PlanReadinessDay> readiness = const [],
  }) async {
    Future<bool> once(PlanVersionRecord? from) => _recalculateOnce(
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

  Future<bool> _recalculateOnce(
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
    var inputs = _inputsFor(trigger, built, last);
    // Eine Zieländerung setzt den Prüftag; eine fällige Wochenbewertung der
    // Vorwoche fällt dadurch nicht weg (NB7 6), sie geht in dieselbe Fassung
    // ein (Grund bleibt `goalChange`).
    // Bei offener Pausenfrage (PAR-202) nicht: Die Bewertung setzte den
    // Anker auf den Montag und die Pausenregel liefe danach ins Leere (NB8 1).
    // Dann bleibt auch der Prüftag unberührt: Nach „Nein“ läuft die
    // Wochenprüfung beim nächsten Öffnen (NB9 1).
    final dueOnGoalChange =
        adjust == null &&
        trigger == PlanTrigger.goalChange &&
        weeklyCheckDue(await session.settings.get(planLastCheckDayKey), today);
    final skippedForPause =
        dueOnGoalChange &&
        await HintService(session: session, clock: clock).pauseQuestion() !=
            null;
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
        // Bewertung folgen (NB8 6): `goalChange,repeatWeek`.
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
    final r = await _write(
      trigger: trigger,
      today: today,
      reason: reason,
      inputs: inputs,
      readiness: readiness,
      // `manual` bewertet die Woche nicht (ADR-0010 Nachtrag WP24, K63): Der
      // Prüftag bleibt, sonst fiele die fällige Wochenbewertung weg.
      markChecked:
          markChecked && !skippedForPause && trigger != PlanTrigger.manual,
    );
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
    return r.wasWritten;
  }

  /// Schreibt die Neuberechnung ([recalculatePlan]) mit den Läufen der
  /// Woche für die Regel der Abweichung (PAR-235, [PlanDataReader.runFacts]):
  /// Jede Fassung des Controllers rechnet mit ihnen, sonst fielen Kürzung,
  /// Lockerung und Tausch beim nächsten Rechnen zurück.
  Future<PlanRecalculation> _write({
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
    // Die Wiederholung nach einer Ablehnung liest erst die neueste Fassung
    // ([_recalculate]); der Dienst wiederholt nicht noch einmal.
    retryRejected: false,
  );

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
          // Bei „fix“ zusätzlich der Abstand der nächsten harten Einheit zu
          // einem intensiven Lauf, wenn kein Tausch möglich war (PAR-235).
          if (await _adaptation.read() == PlanAdaptationMode.fixed)
            ...planRunSpacingConflicts(
              units,
              await _intensiveRunDays(today),
              today,
              parameters: parameters,
            ),
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
    final warning = await _warning?.read();
    final reminderDue =
        warning != null &&
        warningReminderDue(reportedOn: warning.reportedOn, today: today);
    var feedbackDue = false;
    if (warning == null && version != null && history.isNotEmpty) {
      feedbackDue = planFeedbackDue(
        created: calendarDay(history.first.createdAt),
        lastAnswer: _parseDay(await session.settings.get(planFeedbackKey)),
        today: today,
        pauseOpen:
            await HintService(session: session, clock: clock).pauseQuestion() !=
            null,
      );
    }
    final seen = await WarningState(session.settings).planChangeSeen();
    // Unter Warnsignal zeigt das Banner den Grund; die Karte „Plan angepasst“
    // mit dem Grund `warning` käme doppelt (K58, D2).
    var notice = planChangeNotice(history, seenPlanId: seen);
    if (warning != null && notice?.explanation.code == planReasonWarning) {
      notice = null;
    }
    WalkRunWeekProposal? proposal;
    final walkStart = version?.inputs.walkRunStart;
    if (warning == null && walkStart != null) {
      final declined = _parseDay(
        await session.settings.get(planWalkRunRepeatDeclinedKey),
      );
      proposal = walkRunWeekProposal(
        units: units,
        start: walkStart,
        from: version?.inputs.walkRunFrom,
        rpeByRunId: {
          for (final e in (await session.subjective.readAll()).entries)
            if (e.value.subjective.rpe case final int r) e.key: r,
        },
        today: today,
      );
      if (proposal != null && declined == proposal.lastDay) proposal = null;
    }
    PlanUnderloadPrompt? underload;
    if (version != null) {
      final u = await _underloadState();
      if (u.prompt != null && !await _underloadBlocked(history, warning)) {
        underload = u.prompt;
      }
    }
    return PlanViewState.ready(
      adaptation: await _adaptation.read(),
      underloadPrompt: underload,
      changeNotice: notice,
      walkRunProposal: proposal,
      warning: warning,
      warningReminderDue: reminderDue,
      feedbackDue: feedbackDue,
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

  /// Ortstag der frühesten gespeicherten Planeinheit vor [before] über alle
  /// Fassungen, `null` ohne solche Einheit: untere Blättergrenze des
  /// Kalenders (FR-0172). Liest nur die Einheiten vor [before].
  Future<DateTime?> firstUnitDayBefore(DateTime before) async {
    final units = await _plans.unitsBetween(
      DateTime.utc(2000),
      planDay(before).subtract(const Duration(days: 1)),
    );
    DateTime? first;
    for (final u in units) {
      final d = planDay(u.day);
      if (first == null || d.isBefore(first)) first = d;
    }
    return first;
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

  /// Ortstage der intensiven Läufe und Sporteinheiten (PAR-058, PAR-233),
  /// zu denen die harte Einheit der Woche von [today] Abstand halten muss
  /// (PAR-059), wie [planIntensiveRunDays]; über [runsBetween], damit die
  /// Seite nicht auf die Kennzahlen aller Läufe wartet.
  Future<Set<DateTime>> _intensiveRunDays(DateTime today) async {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return {
      for (final r in await runsBetween(
        monday.subtract(Duration(days: parameters.minGapDays - 1)),
        today,
      ))
        if (r.intensive) r.day,
    };
  }

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
      for (final o in await reader.runOverviews())
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
  ///
  /// Mit [newStart] (neuer Einstieg nach langer Pause, PAR-181) rechnet die
  /// Einschätzung mit den Eingaben des Neustarts mit dem Stand aus [draft].
  Future<GoalDraftCheck> checkGoal(
    TrainingGoal draft, {
    bool newStart = false,
  }) async {
    final today = _today();
    final existed = await _goals.goal() != null;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final built = await reader.read(goal: draft, today: today);
    var inputs = _inputsFor(_saveTrigger(existed, history), built, last);
    var goal = built.goal;
    if (newStart && last != null) {
      final q = await HintService(session: session, clock: clock).newStartDue();
      final restart = q == null
          ? null
          : planPauseRestart(
              goal: draft,
              inputs: inputs,
              today: today,
              lastTrainingDay: q.lastTrainingDay,
              baseWeekMinutes: q.baseWeekMinutes,
              parameters: parameters,
              replacesProvisional: await _pauseProvisional(q),
            ).inputs;
      if (restart != null) {
        inputs = restart;
        goal = draft;
      }
    }
    final assessment = assessGoal(
      goal: goal,
      inputs: inputs,
      today: today,
      basis: await reader.timeGoalBasis(goal: goal, today: today),
      parameters: parameters,
    );
    final setup = planCourseSetup(goal, inputs, parameters: parameters);
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
    // Zeitpunkt statt `_today()`: `validate` liest ihn im Ortstag.
    await _goals.save(goal, today: clock.now());
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
    // Auch ein Lauf vor dem Anlegen des Plans zählt für die heutige Einheit
    // (PAR-231).
    await _autoAssignQuietly();
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
  /// Trägt die Einheit beim Schreiben nicht mehr den Lauf, den sie beim Lesen
  /// in dieser Aktion trug (veraltet): nichts geschrieben, `rejected`, der
  /// Stand wird neu geladen.
  Future<PlanActionResult> assignRun(int unitId, int? runId) => _act(() async {
    final unit = await _unitById(unitId);
    if (unit == null) throw const StorageException(StorageFailure.notFound);
    if (!await _assignAndRecalculate(
      unitId,
      runId,
      expectedRunId: unit.runId,
    )) {
      throw const StorageException(StorageFailure.rejected);
    }
  });

  Future<PlanUnit?> _unitById(int unitId) async {
    for (final u in await _plans.unitsBetween(
      DateTime.utc(2000),
      planFarFuture,
    )) {
      if (u.id == unitId) return u;
    }
    return null;
  }

  /// Ordnet beendete Läufe den offenen Einheiten ihres Ortstags zu (PAR-231,
  /// [planAutoAssignments]): Einheiten vom Sonntag der Vorwoche (oder dem
  /// früheren Tag [since], etwa dem Starttag eines Laufs über Mitternacht)
  /// bis heute. Jede Zuordnung rechnet wie [assignRun] neu; gibt es nichts
  /// zuzuordnen, ändert sich nichts und es wird nicht gerechnet.
  Future<PlanActionResult> autoAssignRuns({DateTime? since}) =>
      _act(() => _autoAssign(since: since));

  /// Wie [autoAssignRuns], innerhalb einer laufenden Aktion; ein Fehler bleibt
  /// still (das nächste Öffnen holt die Zuordnung nach). Gibt die Zahl der
  /// geschriebenen Zuordnungen zurück.
  Future<int> _autoAssignQuietly() async {
    try {
      return await _autoAssign();
    } on Object {
      // Siehe oben.
      return 0;
    }
  }

  /// Gibt die Zahl der geschriebenen Zuordnungen zurück.
  Future<int> _autoAssign({DateTime? since}) async {
    final today = _today();
    // Fenster ab dem Sonntag der Vorwoche (PAR-231): ein Sonntagslauf, dessen
    // Zuordnung nach dem Lauf ausblieb (Absturz, Fehler, Lauf über
    // Mitternacht), zählt beim Öffnen am Montag oder später noch.
    final sunday = today.subtract(Duration(days: today.weekday));
    final s = since == null ? null : planDay(since);
    final from = s != null && s.isBefore(sunday) ? s : sunday;
    // Jede Zuordnung rechnet neu und kann Einheiten ab heute ersetzen (neue
    // Kennung): darum nach jeder Zuordnung neu lesen. Jede Runde füllt eine
    // offene Einheit; mehr Runden als Einheiten gibt es nicht.
    var rounds = 0;
    var assigned = 0;
    while (true) {
      final units = await _plans.unitsBetween(
        DateTime.utc(2000),
        planFarFuture,
      );
      if (rounds++ > units.length) return assigned;
      final overviews = await session.preprocessing.readOverviews();
      // Läufe ab dem Start über „Einheit starten“ ordnet der Merker zu
      // (`PlanStartedUnitStore.settle`, auch der Nachholversuch nach einer
      // gescheiterten Neuberechnung); erst danach zählen sie hier.
      final started = PlanStartedUnit.decode(
        await session.settings.get(SettingKeys.planStartedUnit),
      );
      final runs = [
        for (final r in await session.runs.list())
          if (started == null || r.startedAt.isBefore(started.since))
            ?PlanRunCandidate.of(
              r,
              movingTime: overviews[r.id]?.summary.movingTime,
            ),
      ];
      final next = planAutoAssignments(
        units: units,
        runs: runs,
        today: today,
        from: from,
      ).firstOrNull;
      if (next == null) return assigned;
      // Die Einheit war beim Lesen offen; trägt sie inzwischen einen Lauf
      // (veraltet), liest die nächste Runde neu.
      if (await _assignAndRecalculate(
        next.unitId,
        next.runId,
        expectedRunId: null,
      )) {
        assigned++;
      }
    }
  }

  /// Darf die Sporteinheit [runId] (FR-0221) die Einheit [unit] ersetzen
  /// (PAR-233, [planSportReplacementBlock])? `null`: ja; sonst der Grund.
  /// Ohne Plan oder ohne offene Einheit: [SportReplacementBlock.noEasyUnit].
  /// Liest Puls, RPE und Zeit ab 80 % HFmax der Einheit; nie loggen.
  Future<SportReplacementBlock?> sportReplacementBlock(
    PlanUnit? unit,
    int runId,
  ) => _serial(() => _sportBlock(unit, runId));

  Future<SportReplacementBlock?> _sportBlock(PlanUnit? unit, int runId) async {
    final sport = await reader.sportFigures(runId);
    if (sport == null) return SportReplacementBlock.noEasyUnit;
    if (unit == null || unit.runId != null && unit.runId != runId) {
      return SportReplacementBlock.noEasyUnit;
    }
    final units = await _plans.unitsBetween(DateTime.utc(2000), planFarFuture);
    final sportIds = <int>{
      for (final r in await session.runs.list())
        if (!r.mode.isRunning) r.id,
    };
    double? highHr;
    for (final v in await session.values.read(ValueOwner.run(runId))) {
      if (v.current.key == highHeartRateTimeValueKey) highHr = v.current.value;
    }
    final percents = await ReserveZoneSettings.load(session.settings);
    return planSportReplacementBlock(
      unit: unit,
      sport: sport,
      units: units,
      sportRunIds: sportIds,
      rpe: (await session.subjective.read(runId))?.subjective.rpe,
      highHrMinutes: highHr,
      heartRate: resolveHeartRate(
        await session.profile.read(),
        currentYear: clock.now().year,
      ).basis,
      zoneBounds: [for (final p in percents) p / 100],
      parameters: parameters,
    );
  }

  /// Schreibt die Zuordnung, wenn die Einheit noch [expectedRunId] trägt, und
  /// rechnet neu; `false` (veraltet): nichts geschrieben, nicht gerechnet.
  Future<bool> _assignAndRecalculate(
    int unitId,
    int? runId, {
    required int? expectedRunId,
  }) async {
    // Eine andere Sportart ersetzt nur eine lockere Einheit nach PAR-233.
    if (runId != null &&
        !((await session.runs.get(runId))?.mode.isRunning ?? true)) {
      if (await _sportBlock(await _unitById(unitId), runId) != null) {
        throw const StorageException(StorageFailure.rejected);
      }
    }
    final written = await _plans.assignRun(
      unitId,
      runId,
      expectedRunId: expectedRunId,
    );
    if (written == PlanAssignResult.stale) return false;
    _fresh = null;
    onChanged?.call();
    final goal = await _goals.goal();
    if (goal == null) return true;
    final history = await _plans.history();
    final last = history.isEmpty ? null : history.last;
    final goalChanged =
        last != null && planGoalChangedSince(last.summary, goal);
    await _recalculate(
      goalChanged ? PlanTrigger.goalChange : PlanTrigger.run,
      goal,
      last,
      // `run` bewertet die Woche nicht: Der Prüftag bleibt, sonst fiele die
      // Bewertung der Vorwoche weg (Lauf über Mitternacht in den Montag,
      // NB7 1). `goalChange` bewertet bei Fälligkeit selbst.
      markChecked: goalChanged,
    );
    return true;
  }

  /// Verschiebt die Einheit nach Bestätigung des Nutzers auf [day] (setzt
  /// `pinned`, OQ-0011), mit „heute“. Keine Neuberechnung.
  Future<PlanActionResult> confirmMove(int unitId, DateTime day) =>
      _act(() async {
        await _plans.confirmMove(unitId, day, today: _today());
        _fresh = null;
        onChanged?.call();
        // Ein Lauf am neuen Tag zählt für die verschobene Einheit (PAR-231).
        await _autoAssignQuietly();
      });

  /// Prüft vor der Bestätigung, ob [unit] die Art [kind] bekommen kann
  /// ([checkPlanReplace] mit Ziel und Eingaben der neuesten Fassung, Einheiten
  /// und absolvierten intensiven Läufen um die Woche, „heute“). `null` ohne
  /// Ziel oder Fassung.
  /// Anker der Wochenzählung und Länge der Geh-Lauf-Abfolge (PAR-192), wie
  /// sie der Wochenverlauf des Plans nutzt ([planCourseSetup] aus dem
  /// gespeicherten Ziel und den Eingaben der letzten Fassung). Für den
  /// Hinweis auf die Reduktion beim Verschieben ([checkPlanMove], FR-0177).
  /// `null` ohne Ziel oder Fassung.
  Future<({DateTime anchor, int walkRunWeeks})?> courseWeeks() =>
      _serial(() async {
        final goal = await _goals.goal();
        final history = await _plans.history();
        if (goal == null || history.isEmpty) return null;
        final inputs = history.last.inputs;
        return (
          anchor: inputs.anchor,
          walkRunWeeks: planCourseSetup(
            goal,
            inputs,
            parameters: parameters,
          ).walkRunWeeks,
        );
      });

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
  /// `notFound`; Tag vor heute, Einheit mit Lauf, schon festgelegter
  /// Ruhetag, abweichende Einheit, ungültiger Zieltag: `rejected`.
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

  /// Meldet Beschwerden, Krankheit oder Überlastung (FR-0203, Quelle
  /// `manual`): Warnsignal setzen, Plan zeigt nur Ruhetage. Doppeltes
  /// Melden ändert nichts. Sobald das Signal gespeichert ist, lädt die Seite
  /// (Banner) und [onSaved] meldet es; erst danach läuft die Neuberechnung,
  /// solange ist [warningRecalculating] gesetzt. Scheitert sie, bleibt das
  /// Signal gespeichert und das Ergebnis nennt den Fehler; das nächste
  /// Öffnen stellt den Plan her ([open]).
  Future<PlanActionResult> reportWarning({void Function()? onSaved}) =>
      _serial(() async {
        final w = _warning;
        final service = w == null ? null : _warningService(w);
        final saved = await _resultOf(() async {
          if (service == null) throw StateError('kein Warnspeicher');
          await service.mark(source: WarningSource.manual, today: _today());
        });
        if (saved != PlanActionResult.done) {
          await _load();
          return saved;
        }
        _warningRecalculating = true;
        await _load();
        if (!_disposed) onSaved?.call();
        final result = await _resultOf(() async {
          final r = await service!.recalculateReported(
            today: _today(),
            now: clock.now(),
          );
          _fresh = null;
          if (r.wasWritten) onChanged?.call();
        });
        _warningRecalculating = false;
        await _load();
        return result;
      });

  /// Läuft unter Warnsignal noch die Neuberechnung: nach dem Melden
  /// ([reportWarning]) oder beim Nachholen der Ruhetag-Fassung in [open]?
  bool get warningRecalculating => _warningRecalculating;
  bool _warningRecalculating = false;

  /// Hebt das Warnsignal auf; die Festlegungen des Nutzers gelten wieder.
  Future<PlanActionResult> liftWarning() => _act(() async {
    final w = _warning;
    if (w == null) throw StateError('kein Warnspeicher');
    final r = await _warningService(w).lift(today: _today(), now: clock.now());
    _fresh = null;
    if (r.wasWritten) onChanged?.call();
  });

  WarningService _warningService(WarningStore w) => WarningService(
    plans: _plans,
    settings: session.settings,
    warning: w,
    parameters: parameters,
    measuredInputs: (goal, today) async =>
        (await reader.read(goal: goal, today: today)).inputs,
    runFacts: reader.runFacts,
  );

  /// Antwort auf die Nachfrage (PAR-200). „Passt“ und „zu leicht“ am Regler
  /// ändern den Plan nicht; „zu leicht“ davor und „zu schwer“ legen einen
  /// neuen Anker an (`feedback`). Die Antwort zählt erst, wenn alles
  /// geschrieben ist (sonst bleibt die Nachfrage fällig). Ohne Antwort
  /// ändert sich nichts.
  Future<PlanFeedbackOutcome> answerFeedback(PlanFeedback answer) async {
    var raise = false;
    var written = false;
    final r = await _act(() async {
      // Eine offene Pausenfrage hat Vorrang (PAR-202): Die Karte ist dann nicht
      // mehr gültig (etwa nach Mitternacht bei offener Seite).
      if (await HintService(session: session, clock: clock).pauseQuestion() !=
          null) {
        throw const StorageException(StorageFailure.rejected);
      }
      final goal = await _goals.goal();
      if (goal == null) throw const StorageException(StorageFailure.notFound);
      final history = await _plans.history();
      if (history.isEmpty) {
        throw const StorageException(StorageFailure.notFound);
      }
      final today = _today();
      final built = await reader.read(goal: goal, today: today);
      final inputs = _inputsFor(PlanTrigger.feedback, built, history.last);
      final result = applyPlanFeedback(
        goal: goal,
        inputs: inputs,
        answer: answer,
        today: today,
      );
      raise = result.raiseGoalSignal;
      final next = result.inputs;
      if (next != null) {
        final w = await _write(
          trigger: PlanTrigger.feedback,
          markChecked: false, // bewertet die Woche (PAR-201) nicht
          today: today,
          inputs: next,
        );
        _fresh = w.generated;
        _lastChange = w.summary;
        written = w.wasWritten;
        if (w.wasWritten) onChanged?.call();
      }
      await session.settings.set(
        planFeedbackKey,
        _dayText(today),
        at: clock.now(),
      );
    });
    return PlanFeedbackOutcome(
      r,
      raiseGoalSignal: r == PlanActionResult.done && raise,
      planChanged: r == PlanActionResult.done && written,
    );
  }

  /// Antwort auf die Pausenfrage (PAR-202, „Heute“). „Ja“ startet den Plan
  /// neu ([planPauseRestart], Auslöser `pause`), sofern ein Plan besteht und
  /// der Neustart nötig ist; „Nein“ ändert nichts. Die Antwort wird erst nach
  /// dem Schreiben gespeichert: Scheitert der Neustart, bleibt die Frage
  /// offen. Ohne offene Frage ([HintService.pauseQuestion]): `rejected`.
  Future<PlanActionResult> answerPause(bool paused) => _act(() async {
    final today = _today();
    final q = await HintService(session: session, clock: clock).pauseQuestion();
    if (q == null) throw const StorageException(StorageFailure.rejected);
    if (paused) await _restartForPause(q);
    await WarningState(session.settings).setPauseAnswer(
      PauseAnswer(paused: paused, on: today),
      at: clock.now(),
    );
  });

  /// Neustart zur Pause (PAR-202, Auslöser `pause`), einmal je Pause: Der
  /// Merker [planPauseRestartKey] trägt den Tag des letzten Trainings und ob
  /// eine Fassung entstand. Ohne Plan oder Ziel geschieht nichts (kein Merker).
  ///
  /// Ab 8 Wochen ([PlanParameters.pauseNewStartDays]) gilt ohne Wahl
  /// vorläufig die Stufe 2 (sichere Vorgabe, Merker `provisional`); der
  /// Nutzer wählt den Einstieg ([restartAfterLongPause], PAR-181) und ersetzt
  /// sie damit. Mit [chosen] hat der Nutzer den Einstieg gewählt; sein Ziel mit
  /// dem neuen Stand ist schon gespeichert.
  Future<void> _restartForPause(PauseQuestion q, {bool chosen = false}) async {
    final today = _today();
    final history = await _plans.history();
    final goal = await _goals.goal();
    if (goal == null || history.isEmpty) return;
    final mark = PauseRestartMark.parse(
      await session.settings.get(planPauseRestartKey),
    );
    final marked = mark?.day == warningDay(q.lastTrainingDay);
    final wasProvisional = marked && mark!.provisional;
    if (marked && !(chosen && wasProvisional)) return;
    final longPause = q.daysSinceTraining >= parameters.pauseNewStartDays;
    final built = await reader.read(goal: goal, today: today);
    final base = refreshMeasuredInputs(history.last.inputs, built.inputs);
    final restart = planPauseRestart(
      goal: goal,
      inputs: base,
      today: today,
      lastTrainingDay: q.lastTrainingDay,
      baseWeekMinutes: q.baseWeekMinutes,
      parameters: parameters,
      anchorFromAdjustment: planAnchorFromAdjustment(history),
      inputsBeforeAdjustment: planInputsBeforeAdjustment(history),
      provisional: longPause && !chosen,
      replacesProvisional: chosen && wasProvisional && mark.restarted,
    );
    final next = restart.inputs;
    if (next == null && chosen) {
      // Kein Neustart möglich: das neue Ziel gilt trotzdem für den Plan.
      await _recalculate(
        PlanTrigger.goalChange,
        goal,
        history.last,
        adjust: false,
      );
    }
    if (next != null) {
      final r = await _write(
        // Der gewählte Einstieg ist eine Zieländerung des Nutzers (Stand neu):
        // `goalChange` hält sie fest, sonst bliebe sie ausstehend.
        trigger: chosen ? PlanTrigger.goalChange : PlanTrigger.pause,
        today: today,
        inputs: next,
      );
      _fresh = r.generated;
      _lastChange = r.summary;
      if (r.wasWritten) onChanged?.call();
    }
    await session.settings.set(
      planPauseRestartKey,
      PauseRestartMark(
        day: q.lastTrainingDay,
        restarted: next != null,
        provisional: longPause && !chosen,
      ).format(),
      at: clock.now(),
    );
  }

  /// Würde der Plan beim neuen Einstieg nach langer Pause neu beginnen
  /// (PAR-181)? `false` ohne anstehenden Einstieg, ohne Plan und wenn kein
  /// Neustart möglich ist ([planPauseRestart] liefert nichts).
  Future<bool> newStartPossible() async {
    try {
      final q = await HintService(session: session, clock: clock).newStartDue();
      final goal = await _goals.goal();
      final history = await _plans.history();
      if (q == null || goal == null || history.isEmpty) return false;
      final today = _today();
      final built = await reader.read(goal: goal, today: today);
      return planPauseRestart(
            goal: goal,
            inputs: refreshMeasuredInputs(history.last.inputs, built.inputs),
            today: today,
            lastTrainingDay: q.lastTrainingDay,
            baseWeekMinutes: q.baseWeekMinutes,
            parameters: parameters,
            anchorFromAdjustment: planAnchorFromAdjustment(history),
            inputsBeforeAdjustment: planInputsBeforeAdjustment(history),
            replacesProvisional: await _pauseProvisional(q),
          ).inputs !=
          null;
    } on Object {
      return false;
    }
  }

  /// Gilt für die Pause nach [q] schon die vorläufige Vorgabe (als Fassung)?
  Future<bool> _pauseProvisional(PauseQuestion q) async {
    final mark = PauseRestartMark.parse(
      await session.settings.get(planPauseRestartKey),
    );
    return mark != null &&
        mark.provisional &&
        mark.restarted &&
        mark.day == warningDay(q.lastTrainingDay);
  }

  /// Steht die Pause durch die Zusage „alles erfasst“ ohne Frage fest, startet
  /// der Plan beim Öffnen neu (PAR-202), einmal je Pause.
  Future<void> _checkPauseRestart() async {
    final q = await HintService(
      session: session,
      clock: clock,
    ).pauseRestartDue();
    if (q != null) await _restartForPause(q);
  }

  /// Neuer Einstieg nach langer Pause (PAR-181, PAR-192): speichert [goal]
  /// (mit dem vom Nutzer genannten Stand) und startet den Plan neu. Ohne
  /// anstehenden Einstieg ([HintService.newStartDue]): `rejected`. Scheitert
  /// nur die Neuberechnung: [PlanActionResult.savedNotPlanned].
  Future<PlanActionResult> restartAfterLongPause(TrainingGoal goal) => _act(
    () async {
      final q = await HintService(session: session, clock: clock).newStartDue();
      if (q == null) throw const StorageException(StorageFailure.rejected);
      if ((await _plans.history()).isEmpty) {
        throw const StorageException(StorageFailure.notFound);
      }
      // Zeitpunkt statt `_today()`: `validate` liest ihn im Ortstag.
      final now = clock.now();
      if (goal.validate(now, null, true) != null) {
        throw const StorageException(StorageFailure.rejected);
      }
      await _goals.save(goal, today: now);
      onChanged?.call();
      try {
        await _restartForPause(q, chosen: true);
      } on Object {
        throw const _SavedNotPlanned();
      }
      await _autoAssignQuietly();
    },
  );

  /// Alle Fassungen, älteste zuerst (Verlauf der Änderungen, FR-0170).
  Future<List<PlanVersionRecord>> changeHistory() => _plans.history();

  /// Die Karte „Plan angepasst“ gilt bis zur Plan-ID [planId] als gesehen.
  Future<PlanActionResult> markChangeSeen(int planId) => _act(() async {
    await WarningState(session.settings)
        .setPlanChangeSeen(planId, at: clock.now());
  });

  /// Nimmt „Wiederholen“ an (PAR-140): neue Fassung, die Abfolge beginnt ab
  /// heute (nach einem Lauf heute ab morgen) an der Stelle des Vorschlags
  /// wieder; vergangene Tage bleiben unverändert. Ändert
  /// nur nach dieser Entscheidung des Nutzers.
  Future<PlanActionResult> acceptWalkRunRepeat() => _act(() async {
    final proposal = _state.walkRunProposal;
    if (proposal == null) throw const StorageException(StorageFailure.notFound);
    final goal = await _goals.goal();
    final history = await _plans.history();
    if (goal == null || history.isEmpty) {
      throw const StorageException(StorageFailure.notFound);
    }
    final today = _today();
    final built = await reader.read(goal: goal, today: today);
    final base = refreshMeasuredInputs(history.last.inputs, built.inputs);
    final inputs = applyWalkRunRepeat(
      base,
      proposal.suggestion,
      from: walkRunRepeatFrom(today, proposal.lastDay),
    ).copyWith(today: today);
    final r = await _write(
      trigger: PlanTrigger.manual,
      reason: walkRunRepeatReason,
      markChecked: false, // bewertet die Woche nicht
      today: today,
      inputs: inputs,
    );
    _fresh = r.generated;
    _lastChange = r.summary;
    if (r.wasWritten) onChanged?.call();
  });

  /// Lehnt „Woche wiederholen“ für diese Programmwoche ab; nichts ändert sich.
  Future<PlanActionResult> declineWalkRunRepeat() => _act(() async {
    final proposal = _state.walkRunProposal;
    if (proposal == null) return;
    await session.settings.set(
      planWalkRunRepeatDeclinedKey,
      _dayText(proposal.lastDay),
      at: clock.now(),
    );
  });

  /// Schalter „Plananpassung an Erholung“ (FR-0216). Der Wechsel wirkt ab
  /// heute, nie rückwirkend: Vergangene Einheiten und Lockerungen bleiben.
  /// Eine neue Fassung (`feedback`) entsteht nur, wenn heute eine harte
  /// Einheit betroffen ist: bei „adaptiv“ eine heutige harte Einheit an einem
  /// Tag mit niedrigem Wert (PAR-173, Grund `readiness`), bei „fix“ eine heute
  /// gelockerte (sie kehrt zurück, Grund `adaptationFixed`).
  Future<PlanActionResult> setAdaptation(PlanAdaptationMode mode) =>
      _act(() async {
        final store = _adaptation;
        if (await store.read() == mode) return;
        await store.set(mode, at: clock.now());
        final goal = await _goals.goal();
        final history = await _plans.history();
        if (goal == null || history.isEmpty) return;
        final last = history.last;
        final today = _today();
        if (mode == PlanAdaptationMode.adaptive) {
          await _recheckRecovery(goal, last);
        } else {
          final easedToday = recoveryEasedFromSummary(last.summary)
              .any((e) => planDay(e.day) == today);
          if (!easedToday) return;
          await _recalculate(
            PlanTrigger.feedback,
            goal,
            last,
            reason: planReasonAdaptationFixed,
            markChecked: false,
          );
        }
      });

  /// Auslöser „veränderter Erholungszustand“ (FR-0157, Teil „3 (Erholung)“):
  /// nach neuen Gesundheitsdaten aus dem Import und nach einer Morgenmessung.
  /// Nur bei „adaptiv“ und nur für heute: Ist heute eine harte Einheit offen
  /// ([recoveryEasable]) und liegt der heutige Wert in einem Band nach
  /// PAR-173, entsteht eine Fassung (`feedback`, Grund `readiness`), in der
  /// genau diese Einheit locker ist. Sonst (auch bei „fix“, ohne Wert oder bei
  /// einem Fehler) geschieht nichts. `true`, wenn eine Fassung geschrieben
  /// wurde.
  Future<bool> recheckRecovery() => _serial(() async {
    var written = false;
    try {
      final goal = await _goals.goal();
      final history = await _plans.history();
      if (goal != null && history.isNotEmpty) {
        written = await _recheckRecovery(goal, history.last);
      }
    } on Object {
      written = false;
    }
    if (written) await _load();
    return written;
  });

  /// Gemeinsamer Teil von [recheckRecovery], dem Wechsel auf „adaptiv“ und
  /// der Wochenprüfung: Lockerung der heutigen harten Einheit nach PAR-173.
  /// Der Wert anderer Tage zählt nicht (nur der heutige wird gelesen).
  Future<bool> _recheckRecovery(
    TrainingGoal goal,
    PlanVersionRecord last,
  ) async {
    if (await _adaptation.read() != PlanAdaptationMode.adaptive) return false;
    final today = _today();
    final unit = await _plans.unitOn(today);
    if (unit == null || !recoveryEasable(unit)) return false;
    final day = await _readinessOn(today);
    if (day == null || !day.eases) return false;
    return _recalculate(
      PlanTrigger.feedback,
      goal,
      last,
      reason: planReasonReadiness,
      readiness: [day],
      markChecked: false,
    );
  }

  /// Gespeicherter Zustand der Unterforderung (PAR-236).
  Future<PlanUnderloadState> _underloadState() async =>
      PlanUnderloadState.parse(
        await session.settings.get(planUnderloadStageKey),
        await session.settings.get(planUnderloadSinceKey),
      );

  Future<void> _saveUnderload(PlanUnderloadState state) async {
    final now = clock.now();
    await session.settings.set(planUnderloadStageKey, state.stageText, at: now);
    final since = state.sinceText;
    if (since != null) {
      await session.settings.set(planUnderloadSinceKey, since, at: now);
    }
  }

  /// Weder Hinweis noch Frage der Unterforderung (PAR-236): bei „fix“
  /// (FR-0216), bei einem gemeldeten Warnsignal (FR-0203), wenn PAR-201 in
  /// dieser Woche nach unten korrigiert hat, oder wenn die Readiness von heute
  /// in einem Band nach PAR-173 liegt. Ein Fehler beim Lesen sperrt
  /// (fail-closed).
  Future<bool> _underloadBlocked(
    List<PlanVersionRecord> history,
    WarningSignal? warning,
  ) async {
    if (await _adaptation.read() != PlanAdaptationMode.adaptive) return true;
    if (warning != null) return true;
    final today = _today();
    if (planCorrectedDownThisWeek(history, today)) return true;
    // Anders als die Lockerung ([_readinessOn]) unterscheidet die Sperre
    // „kein Wert“ (nicht gesperrt) von „Fehler“ (gesperrt).
    final load = readinessToday;
    if (load == null) return false;
    try {
      final r = await load(today);
      return r != null && planDay(r.day) == today && r.eases;
    } on Object {
      return true;
    }
  }

  /// Wie [_advanceUnderload]; ein Fehler bleibt still: Ohne lesbaren Stand
  /// bleibt die Stufe, das nächste Öffnen prüft neu.
  Future<void> _advanceUnderloadQuietly() async {
    try {
      await _advanceUnderload();
    } on Object {
      // Siehe oben.
    }
  }

  /// Schritt der Unterforderung beim Öffnen (PAR-236): Muster aus den Läufen
  /// nach der letzten Stufe bzw. nach der letzten Änderung der HFmax
  /// ([planUnderloadCountFrom]); erstes Muster → Hinweis, erneutes → Frage
  /// ([planUnderloadAdvance]). Ändert den Plan nicht.
  Future<void> _advanceUnderload() async {
    final goal = await _goals.goal();
    if (goal == null) return;
    final history = await _plans.history();
    if (history.isEmpty) return;
    final state = await _underloadState();
    final changed = DateTime.tryParse(
      await session.settings.get(profileHrMaxChangedAtKey) ?? '',
    )?.toUtc();
    final runs = await reader.underloadRuns(
      planUnderloadCountFrom(state, changed),
    );
    final pattern = planUnderloadPattern(runs, parameters: parameters);
    if (!pattern) return;
    // Sperre erst nach dem Muster prüfen: ohne Muster liest das Öffnen keine
    // Readiness (FR-0158, Wochenprüfung nur wenn fällig).
    final blocked = await _underloadBlocked(history, await _warning?.read());
    var canRaise = false;
    if (state.stage != PlanUnderloadStage.none) {
      final today = _today();
      final built = await reader.read(goal: goal, today: today);
      canRaise =
          applyPlanUnderloadRaise(
            goal: goal,
            inputs: _inputsFor(PlanTrigger.feedback, built, history.last),
            today: today,
            parameters: parameters,
          ) !=
          null;
    }
    final next = planUnderloadAdvance(
      state: state,
      pattern: pattern,
      blocked: blocked,
      canRaise: canRaise,
      now: clock.now(),
    );
    if (next != null) await _saveUnderload(next);
  }

  /// Antwort auf den Hinweis „HFmax prüfen“ bzw. „Passt so“ (PAR-236): Der
  /// Hinweis erscheint nicht wieder; die Zählung für die Frage läuft ab dem
  /// Hinweis weiter. Ohne offenen Hinweis: `rejected`.
  Future<PlanActionResult> answerUnderloadHint() => _act(() async {
    final state = await _underloadState();
    if (state.stage != PlanUnderloadStage.hint) {
      throw const StorageException(StorageFailure.rejected);
    }
    await _saveUnderload(
      PlanUnderloadState(
        stage: PlanUnderloadStage.hintDone,
        since: state.since,
      ),
    );
  });

  /// Antwort auf „Plan etwas steigern?“ (PAR-236). „Ja, steigern“: einmalig
  /// ein zusätzlicher Schritt nach PAR-193 ([applyPlanUnderloadRaise]), neue
  /// Fassung mit Auslöser `feedback` und Grund `underload`. „Nein“: keine
  /// Änderung. Die Antwort wird erst nach dem Schreiben gespeichert;
  /// danach zählen nur Läufe nach der Antwort. Ohne offene Frage oder ohne
  /// mögliche Steigerung: `rejected`.
  Future<PlanActionResult> answerUnderloadQuestion(bool raise) =>
      _act(() async {
        final state = await _underloadState();
        if (state.stage != PlanUnderloadStage.question) {
          throw const StorageException(StorageFailure.rejected);
        }
        if (raise) {
          final goal = await _goals.goal();
          if (goal == null) {
            throw const StorageException(StorageFailure.notFound);
          }
          final history = await _plans.history();
          if (history.isEmpty) {
            throw const StorageException(StorageFailure.notFound);
          }
          if (await _underloadBlocked(history, await _warning?.read())) {
            throw const StorageException(StorageFailure.rejected);
          }
          final today = _today();
          final built = await reader.read(goal: goal, today: today);
          final next = applyPlanUnderloadRaise(
            goal: goal,
            inputs: _inputsFor(PlanTrigger.feedback, built, history.last),
            today: today,
            parameters: parameters,
          );
          if (next == null) {
            throw const StorageException(StorageFailure.rejected);
          }
          final w = await _write(
            trigger: PlanTrigger.feedback,
            reason: planReasonUnderload,
            markChecked: false, // bewertet die Woche (PAR-201) nicht
            today: today,
            inputs: next,
          );
          _fresh = w.generated;
          _lastChange = w.summary;
          if (w.wasWritten) onChanged?.call();
        }
        await _saveUnderload(
          PlanUnderloadState(
            stage: raise
                ? PlanUnderloadStage.accepted
                : PlanUnderloadStage.declined,
            since: clock.now().toUtc(),
          ),
        );
      });

  /// Readiness von [day] aus [readinessToday]; ohne Quelle oder bei einem
  /// Fehler `null` (keine Lockerung).
  Future<PlanReadinessDay?> _readinessOn(DateTime day) async {
    final load = readinessToday;
    if (load == null) return null;
    try {
      final r = await load(day);
      return r != null && planDay(r.day) == day ? r : null;
    } on Object {
      return null;
    }
  }

  Future<PlanActionResult> _act(Future<void> Function() action) =>
      _serial(() async {
        final result = await _resultOf(action);
        await _load();
        return result;
      });

  /// Führt [action] aus und übersetzt Fehler in ein [PlanActionResult].
  Future<PlanActionResult> _resultOf(Future<void> Function() action) async {
    try {
      await action();
      return PlanActionResult.done;
    } on _SavedNotPlanned {
      return PlanActionResult.savedNotPlanned;
    } on StorageException catch (e) {
      return switch (e.failure) {
        StorageFailure.rejected => PlanActionResult.rejected,
        StorageFailure.notFound => PlanActionResult.notFound,
        _ => PlanActionResult.failed,
      };
    } on Object {
      return PlanActionResult.failed;
    }
  }

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

/// Ein beendeter Lauf oder eine Sporteinheit (FR-0221) im Kalender
/// ([PlanController.runsBetween]).
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
/// ([PlanController.doneRuns], FR-0171). Die Einheit selbst (Vorgabe) bleibt
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
