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
      calculation: ValueCalculationService(session: session, clock: clock),
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
