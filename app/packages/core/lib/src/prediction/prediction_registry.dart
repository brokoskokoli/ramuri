import '../fitness/algorithm_variant.dart';
import 'prediction_parameters.dart';

/// Familie Leistungsprognose (NFR-0001, NFR-0005, OQ-0008: nur Riegel).
abstract class PerformancePredictionMethod extends AlgorithmVariant {
  const PerformancePredictionMethod();
}

class RiegelPrediction extends PerformancePredictionMethod {
  const RiegelPrediction();

  @override
  String get method => predictionMethod;

  @override
  int get methodVersion => predictionMethodVersion;

  /// B: Das Modell ist etabliert, die Stufen sind eigene Wahl (PAR-143 bis
  /// PAR-146).
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;
}

const performancePredictionFamily =
    AlgorithmFamily<PerformancePredictionMethod>('performance-prediction');
