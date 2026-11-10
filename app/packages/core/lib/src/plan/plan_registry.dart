import '../fitness/algorithm_variant.dart';
import 'plan_parameters.dart';

/// Familie Planerzeugung (NFR-0001, NFR-0005). Hier der Verlauf der
/// Wochenzeit; die Einheiten folgen im selben Verfahren.
abstract class PlanMethod extends AlgorithmVariant {
  const PlanMethod();
}

class WeeklyTimeCourse extends PlanMethod {
  const WeeklyTimeCourse();

  @override
  String get method => planMethod;

  @override
  int get methodVersion => planMethodVersion;

  /// B: einfache, gesetzte Regeln ohne Beleg (PAR-192 bis PAR-206).
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
}

const planFamily = AlgorithmFamily<PlanMethod>('training-plan');
