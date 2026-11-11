import 'package:core/core.dart';

/// Einstieg „Warnsignal“ aus der Zusammenfassung (FR-0203, K58): Die Antwort
/// „ja“ auf die Warnfrage meldet es mit der Quelle `run_feedback`; die Zeile
/// gehört nicht zum Lauf und übersteht dessen Löschen. Ohne Plan-Speicher
/// (z. B. in Tests) gibt es keinen Einstieg (`null`).
Future<void> Function()? warningEntry({
  required StorageSession session,
  required Clock clock,
  required int runId,
}) {
  if (session is! PlanStorage ||
      session is! WarningStorage ||
      session is! GoalStorage) {
    return null;
  }
  final service = WarningService(
    plans: (session as PlanStorage).plans,
    settings: session.settings,
    warning: (session as WarningStorage).warning,
  );
  return () async {
    final now = clock.now();
    await service.report(
      source: WarningSource.runFeedback,
      today: calendarDay(now),
      now: now,
      runId: runId,
    );
  };
}
