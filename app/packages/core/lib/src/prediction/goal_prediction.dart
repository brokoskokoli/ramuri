import 'performance_prediction.dart';
import 'prediction_level.dart';

/// Einschätzung des Ziels nach PAR-206 (kommt aus der Planung, WP21).
enum GoalFeasibility { fits, tight, later, notEnoughData }

/// Zielprognose für das geplante Wettkampfziel (FR-0133), getrennt von der
/// allgemeinen Schätzung ([DistancePrediction]). Höchstens „vorläufig“, wenn
/// PAR-206 „knapp“ oder „eher später“ ergibt (PAR-146). „Noch nicht genug
/// Daten“ ändert die Stufe nicht: PAR-146 nennt nur „knapp“ und „eher
/// später“ (gemeldet).
class GoalPrediction {
  const GoalPrediction({
    required this.general,
    required this.feasibility,
    required this.level,
    required this.reason,
  });

  /// Die zugrunde liegende allgemeine Schätzung.
  final DistancePrediction general;
  final GoalFeasibility feasibility;
  final PredictionLevel level;
  final PredictionReason reason;
}

GoalPrediction predictGoal({
  required DistancePrediction general,
  required GoalFeasibility feasibility,
}) {
  final capped =
      (feasibility == GoalFeasibility.tight ||
          feasibility == GoalFeasibility.later) &&
      general.level.index > PredictionLevel.provisional.index;
  return GoalPrediction(
    general: general,
    feasibility: feasibility,
    level: capped ? PredictionLevel.provisional : general.level,
    reason: capped ? PredictionReason.goalFeasibility : general.reason,
  );
}
