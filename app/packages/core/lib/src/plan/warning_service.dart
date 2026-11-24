import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import '../../ports/storage_warning.dart';
import '../goals/training_goal.dart';
import 'build_plan_inputs.dart' show refreshMeasuredInputs;
import 'plan_deviation.dart' show PlanRunFacts;
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_warning.dart';
import 'recalculate_plan.dart';
import 'weekly_time.dart' show planDay;

/// Warnsignal melden und aufheben (FR-0203, K58). Jede Änderung erzeugt eine
/// neue Planfassung mit Auslöser [PlanTrigger.feedback] und dem Grund-Code
/// [planReasonWarning] bzw. [planReasonWarningLifted] ([recalculatePlan]).
/// Der Dienst liest keine Uhr und kennt keine Inhalte außer Quelle und Lauf.
class WarningService {
  WarningService({
    required this.plans,
    required this.settings,
    required this.warning,
    this.parameters = const PlanParameters(),
    this.measuredInputs,
    this.runFacts,
  });

  final PlanRepository plans;
  final SettingsStore settings;
  final WarningStore warning;
  final PlanParameters parameters;

  /// Gemessene Eingaben für heute (Ergebnis von [buildPlanInputs]); ohne
  /// Funktion rechnet der Dienst mit den gespeicherten Werten. Mit ihr
  /// entsteht die Fassung wie die einer automatischen Neuberechnung
  /// ([refreshMeasuredInputs]): Nach dem Aufheben erzeugt die nächste
  /// wöchentliche Prüfung keine zusätzliche Fassung nur wegen veralteter
  /// Messwerte.
  final Future<PlanInputs> Function(TrainingGoal goal, DateTime today)?
  measuredInputs;

  /// Die beendeten Läufe für die Regel der Abweichung (PAR-235) am Ortstag
  /// `today`; ohne Funktion gilt die geplante Dauer. Mit ihr entsteht nach
  /// dem Aufheben dieselbe Fassung wie bei der nächsten Neuberechnung.
  final Future<List<PlanRunFacts>> Function(DateTime today)? runFacts;

  /// Das aktive Warnsignal oder `null`.
  Future<WarningSignal?> current() => warning.read();

  /// Erinnerung fällig: nur Anzeige in der App, keine Benachrichtigung.
  Future<bool> reminderDue(DateTime today) async {
    final w = await warning.read();
    return w != null &&
        warningReminderDue(reportedOn: w.reportedOn, today: today);
  }

  /// Meldet das Warnsignal und schreibt die Ruhetag-Fassung: [mark], dann
  /// [recalculateReported]. Besteht schon eines, bleibt es mit Tag, Quelle
  /// und Lauf unverändert und es entsteht keine weitere Fassung (idempotent);
  /// der Plan wird trotzdem geprüft, ein früher gescheiterter Schreibversuch
  /// holt sich so nach. [today] ist der Ortstag. Scheitert das Schreiben des
  /// Plans, bleibt das Signal gespeichert und der Fehler geht an den
  /// Aufrufer; die nächste Neuberechnung (z. B. beim Öffnen der Plan-Seite)
  /// stellt die Ruhetag-Fassung her.
  Future<PlanRecalculation> report({
    required WarningSource source,
    required DateTime today,
    required DateTime now,
    int? runId,
  }) async {
    await mark(source: source, today: today, runId: runId);
    return recalculateReported(today: today, now: now);
  }

  /// Erster Schritt des Meldens: setzt das Warnsignal, falls noch keines
  /// besteht (Tag, Quelle und Lauf eines bestehenden bleiben). `true`, wenn
  /// es neu gesetzt wurde. Die Ruhetag-Fassung schreibt erst
  /// [recalculateReported]; bis dahin passt der Plan nicht zum Signal, das
  /// nächste Öffnen der Plan-Seite stellt ihn sonst her. Scheitert schon das
  /// Speichern, besteht kein neues Signal und der Fehler geht an den Aufrufer.
  Future<bool> mark({
    required WarningSource source,
    required DateTime today,
    int? runId,
  }) async {
    if (await warning.read() != null) return false;
    await warning.set(
      WarningSignal(reportedOn: planDay(today), source: source, runId: runId),
    );
    return true;
  }

  /// Zweiter Schritt des Meldens: schreibt die Ruhetag-Fassung zum gesetzten
  /// Warnsignal (auch ein schon länger bestehendes: ein früher gescheiterter
  /// Schreibversuch holt sich so nach). Scheitert das, bleibt das Signal
  /// gesetzt und der Fehler geht an den Aufrufer.
  Future<PlanRecalculation> recalculateReported({
    required DateTime today,
    required DateTime now,
  }) => _recalculate(today, now, planReasonWarning);

  /// Hebt das Warnsignal auf und schreibt die Fassung mit den Festlegungen
  /// zurück. Ohne Warnsignal wird nichts gelöscht; der Plan wird geprüft
  /// (idempotent). Scheitert das Schreiben, bleibt das Warnsignal aufgehoben
  /// und die nächste Neuberechnung stellt die Festlegungen wieder her.
  Future<PlanRecalculation> lift({
    required DateTime today,
    required DateTime now,
  }) async {
    await warning.lift();
    return _recalculate(today, now, planReasonWarningLifted);
  }

  Future<PlanRecalculation> _recalculate(
    DateTime today,
    DateTime now,
    String reason,
  ) async {
    PlanInputs? inputs;
    final measure = measuredInputs;
    final goal = measure == null ? null : await plans.currentGoal();
    if (measure != null && goal != null) {
      final history = await plans.history();
      if (history.isNotEmpty) {
        inputs = refreshMeasuredInputs(
          history.last.inputs,
          await measure(goal, today),
        );
      }
    }
    final facts = runFacts;
    return recalculatePlan(
      plans: plans,
      settings: settings,
      trigger: PlanTrigger.feedback,
      today: today,
      now: now,
      reason: reason,
      inputs: inputs,
      runs: facts == null ? const [] : await facts(today),
      parameters: parameters,
      warning: warning,
      // Melden und Aufheben sind keine Wochenprüfung: der Prüftag bleibt.
      markChecked: false,
    );
  }
}
