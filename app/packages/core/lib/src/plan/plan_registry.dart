import '../fitness/algorithm_variant.dart';
import 'plan_parameters.dart';
import 'target_intensity.dart';
import 'walk_run_program.dart';

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

/// Familie Zielintensität (FR-0153, PAR-100 bis PAR-107): Rangfolge der
/// Grundlagen und Werte je Abschnitt.
abstract class TargetIntensityMethod extends AlgorithmVariant {
  const TargetIntensityMethod();
}

class RankedTargetIntensity extends TargetIntensityMethod {
  const RankedTargetIntensity();

  @override
  String get method => targetIntensityMethod;

  @override
  int get methodVersion => targetIntensityMethodVersion;

  /// B: gesetzte Regeln, Evidenz niedrig (PAR-101 bis PAR-103, PAR-109 bis
  /// PAR-114).
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
}

const targetIntensityFamily = AlgorithmFamily<TargetIntensityMethod>(
  'target-intensity',
);

/// Familie Geh-Lauf-Abfolge (PAR-065, PAR-132 bis PAR-139): der Datensatz
/// mit den Programmwochen. Eine andere Abfolge ist eine neue Version.
abstract class WalkRunProgramMethod extends AlgorithmVariant {
  const WalkRunProgramMethod();
}

class WalkRunSequence extends WalkRunProgramMethod {
  const WalkRunSequence();

  @override
  String get method => walkRunMethod;

  @override
  int get methodVersion => walkRunMethodVersion;

  /// B: Zeiten vorgegeben, Evidenz niedrig; die Ausnahmen (PAR-141) sind
  /// eigene Wahl.
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
}

const walkRunFamily = AlgorithmFamily<WalkRunProgramMethod>('walk-run-program');

/// Gesamtversion der Regeln einer Fassung (NFR-0001, ADR-0010 Punkt 2 und 7):
/// trägt den Parameterstand ([planParameterVersion], Wochenzeit und Einheiten
/// gehören zur Methode `weekly-time-course`), die Version der Geh-Lauf-Abfolge
/// und die der Zielintensität in einer Zahl, die sich bei jeder Änderung einer
/// Teilmethode ändert. Aufbau: `parameter * 10^6 + gehLauf * 10^3 +
/// zielintensität`; jede Teilversion bleibt unter 1000.
const int planRuleVersion =
    planParameterVersion * 1000000 +
    walkRunMethodVersion * 1000 +
    targetIntensityMethodVersion;
