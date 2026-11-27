import 'package:core/core.dart';

import 'plan_controller.dart';

enum PlanLoadPhase { loading, ready, failed }

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
  /// Fassung ab ([planGoalChangedSince], [PlanSavedNotPlanned]).
  savedNotPlanned,
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
