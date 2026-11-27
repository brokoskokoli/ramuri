import 'package:core/core.dart';

import 'readiness_service.dart';

/// Lädt die Readiness von heute ([ReadinessService]) mit dem letzten Tag des
/// Belastungsverlaufs (WP19) als Faktor Belastung, rein lesend. Gemeinsamer
/// Weg für „Heute“ und den Plan, damit beide denselben Wert sehen. Fehler
/// ergeben `null`, nie eine Teilrechnung.
Future<ReadinessSnapshot?> loadReadinessToday({
  required StorageSession session,
  required Clock clock,
  required RecalculationService recalculation,
}) async {
  Future<LoadDay?> loadToday() async {
    final report = await TrainingLoadService(
      session: session,
      clock: clock,
      calculation: recalculation.calculation,
      recalculation: recalculation,
    ).loadReadOnly();
    final days = report.series.days;
    return days.isEmpty ? null : days.last;
  }

  try {
    return await ReadinessService(
      session: session,
      clock: clock,
      loadToday: loadToday,
    ).load();
  } on Object {
    return null;
  }
}

/// Readiness-Quelle für den Plan (FR-0216, PAR-173): lädt mit [load] und
/// versieht den Wert mit dem Tag, für den er berechnet wurde
/// ([ReadinessSnapshot.today]), nie mit dem angefragten Tag. So gilt ein
/// Wert des Vortags (Mitternacht zwischen Anfrage und Rechnung) nicht als
/// heutiger; der Plan vergleicht den Tag selbst. Ohne Snapshot oder ohne
/// Tag `null` (keine Lockerung).
Future<PlanReadinessDay?> Function(DateTime day) planReadinessSource(
  Future<ReadinessSnapshot?> Function() load,
) => (day) async {
  final snapshot = await load();
  final computed = snapshot?.today;
  if (snapshot == null || computed == null) return null;
  return PlanReadinessDay.of(planDay(computed), snapshot.result);
};
