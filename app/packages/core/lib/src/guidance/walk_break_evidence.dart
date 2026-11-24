import '../../ports/storage.dart';
import '../../ports/storage_plan.dart';
import '../plan/plan_unit.dart';
import '../recalculation/run_load_values.dart';
import 'easy_run_exposure.dart';
import 'guidance_parameters.dart';

/// Wie weit zurück die lockeren Einheiten gesucht werden (Auslegung WP24; die
/// letzten 3 lockeren Einheiten liegen im Plan nie weiter zurück als dies).
const Duration walkBreakLookback = Duration(days: 120);

/// Die letzten lockeren Einheiten (Art `easy`, Lauf zugeordnet, keine
/// andere Sportart) bis [today],
/// neueste zuerst, höchstens [walkBreakHintRunCount]. Quelle der Pulsanteile:
/// die gespeicherten Zonenzeiten des Laufs. Ein Lauf ohne gespeicherte
/// Zonenzeiten bleibt als „kein Beleg“ (bekannte Zeit 0) in der Reihe und
/// zählt nie als „darüber“. Ohne Plan im Speicher: leer.
Future<List<EasyRunExposure>> recentEasyRunExposures(
  StorageSession session, {
  required DateTime today,
}) async {
  if (session is! PlanStorage) return const [];
  final day = DateTime.utc(today.year, today.month, today.day);
  final units = await (session as PlanStorage).plans.unitsBetween(
    day.subtract(walkBreakLookback),
    day,
  );
  final easy =
      units
          .where((u) => u.kind == PlanUnitKind.easy && u.runId != null)
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));
  // Nur Läufe: Eine Sporteinheit, die nach PAR-233 eine lockere Einheit
  // ersetzt, ist kein Beleg für Gehpausen beim Laufen (FR-0222).
  final last = <PlanUnit>[];
  for (final u in easy) {
    if (last.length >= walkBreakHintRunCount) break;
    final run = await session.runs.get(u.runId!);
    if (run != null && !run.mode.isRunning) continue;
    last.add(u);
  }
  if (last.isEmpty) return const [];
  final values = await session.values.readRunValues(runLoadValueKeys);
  return [for (final u in last) _exposure(values[u.runId])];
}

EasyRunExposure _exposure(dynamic stored) {
  const none = EasyRunExposure(aboveUpper: Duration.zero, known: Duration.zero);
  if (stored == null) return none;
  final load = StoredRunLoad.fromValues(stored);
  final zones = load.zoneTimes;
  if (zones == null) return none;
  return EasyRunExposure.fromZoneTimes(
    zones,
    belowZone1: load.belowZone1Time ?? Duration.zero,
  );
}
