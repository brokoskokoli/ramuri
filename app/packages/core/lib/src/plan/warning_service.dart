import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import '../../ports/storage_warning.dart';
import '../goals/training_goal.dart';
import 'build_plan_inputs.dart' show refreshMeasuredInputs;
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

  /// Das aktive Warnsignal oder `null`.
  Future<WarningSignal?> current() => warning.read();

  /// Erinnerung fällig: nur Anzeige in der App, keine Benachrichtigung.
  Future<bool> reminderDue(DateTime today) async {
    final w = await warning.read();
    return w != null &&
        warningReminderDue(reportedOn: w.reportedOn, today: today);
  }

  /// Meldet das Warnsignal und schreibt die Ruhetag-Fassung. Besteht schon
  /// eines, bleibt es mit Tag, Quelle und Lauf unverändert und es entsteht
  /// keine weitere Fassung (idempotent); der Plan wird trotzdem geprüft, ein
  /// früher gescheiterter Schreibversuch holt sich so nach. [today] ist der
  /// Ortstag. Scheitert das Schreiben des Plans, nimmt der Dienst die eben
  /// gesetzte Zeile zurück und wirft den Fehler weiter: Warnsignal und Plan
  /// gelten beide oder keines (die App zeigt sonst ein Banner über einem Plan
  /// mit Läufen). Ein schon früher gesetztes Warnsignal bleibt.
  Future<PlanRecalculation> report({
    required WarningSource source,
    required DateTime today,
    required DateTime now,
    int? runId,
  }) async {
    final created = await warning.read() == null;
    if (created) {
      await warning.set(
        WarningSignal(reportedOn: planDay(today), source: source, runId: runId),
      );
    }
    try {
      return await _recalculate(today, now, planReasonWarning);
    } catch (_) {
      if (created) {
        try {
          await warning.lift();
        } catch (_) {
          // Der ursprüngliche Fehler zählt; die nächste Neuberechnung legt
          // die gesetzte Zeile über den Plan.
        }
      }
      rethrow;
    }
  }

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
    return recalculatePlan(
      plans: plans,
      settings: settings,
      trigger: PlanTrigger.feedback,
      today: today,
      now: now,
      reason: reason,
      inputs: inputs,
      parameters: parameters,
      warning: warning,
    );
  }
}
