import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import '../../ports/storage_warning.dart';
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
  });

  final PlanRepository plans;
  final SettingsStore settings;
  final WarningStore warning;
  final PlanParameters parameters;

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
  /// Ortstag. Scheitert das Schreiben des Plans, bleibt das Warnsignal
  /// gesetzt (jede spätere Neuberechnung legt es über den Plan).
  Future<PlanRecalculation> report({
    required WarningSource source,
    required DateTime today,
    required DateTime now,
    int? runId,
  }) async {
    if (await warning.read() == null) {
      await warning.set(
        WarningSignal(reportedOn: planDay(today), source: source, runId: runId),
      );
    }
    return _recalculate(today, now, planReasonWarning);
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
  ) => recalculatePlan(
    plans: plans,
    settings: settings,
    trigger: PlanTrigger.feedback,
    today: today,
    now: now,
    reason: reason,
    parameters: parameters,
    warning: warning,
  );
}
