import 'package:core/core.dart';

import '../plan/plan_data_reader.dart';

/// Einstieg „Warnsignal“ aus der Zusammenfassung (FR-0203, K58): Die Antwort
/// „ja“ auf die Warnfrage meldet es mit der Quelle `run_feedback`; die Zeile
/// gehört nicht zum Lauf und übersteht dessen Löschen. Nimmt der Nutzer die
/// Antwort im selben Bildschirm zurück (`yes == false`), hebt der Einstieg ein
/// aus genau diesem Lauf gesetztes Warnsignal wieder auf; ein anderes bleibt.
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
      await service.report(
        source: WarningSource.runFeedback,
        today: today,
        now: now,
        runId: runId,
      );
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
