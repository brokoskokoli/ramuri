import 'package:core/core.dart';

import '../plan/plan_data_reader.dart';

/// Einstieg „Warnsignal“ aus der Zusammenfassung (FR-0203, K58): Die Antwort
/// „ja“ auf die Warnfrage meldet es mit der Quelle `run_feedback`; die Zeile
/// gehört nicht zum Lauf und übersteht dessen Löschen. Nimmt der Nutzer die
/// Antwort im selben Bildschirm zurück (`yes == false`), hebt der Einstieg ein
/// aus genau diesem Lauf gesetztes Warnsignal wieder auf; ein anderes bleibt.
/// Scheitert die Neuberechnung nach dem Melden, bleibt das Signal gespeichert
/// und der Fehler geht an den Aufrufer (wie `PlanController.reportWarning`).
/// Der Plan wird mit den heute gemessenen Eingaben gerechnet. Ohne Plan-Speicher
/// (z. B. in Tests) gibt es keinen Einstieg (`null`).
Future<void> Function(bool yes)? warningEntry({
  required StorageSession session,
  required Clock clock,
  required int runId,
}) {
  if (session is! PlanStorage ||
      session is! WarningStorage ||
      session is! GoalStorage) {
    return null;
  }
  final plans = (session as PlanStorage).plans;
  final reader = PlanDataReader(session: session, clock: clock);
  final service = WarningService(
    plans: plans,
    settings: session.settings,
    warning: (session as WarningStorage).warning,
    measuredInputs: (goal, today) async =>
        (await reader.read(goal: goal, today: today)).inputs,
  );
  return (yes) async {
    final now = clock.now();
    final today = calendarDay(now);
    if (yes) {
      // Wie auf der Plan-Seite: erst das Signal speichern, dann die
      // Ruhetag-Fassung. Scheitert die Fassung, bleibt das Signal und der
      // Fehler geht an die Zusammenfassung; das nächste Öffnen des Plans
      // holt die Fassung nach.
      await service.mark(
        source: WarningSource.runFeedback,
        today: today,
        runId: runId,
      );
      await service.recalculateReported(today: today, now: now);
      return;
    }
    final w = await service.current();
    if (w != null &&
        w.source == WarningSource.runFeedback &&
        w.runId == runId) {
      await service.lift(today: today, now: now);
    }
  };
}
