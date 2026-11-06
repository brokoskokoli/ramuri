import 'run_figures.dart';
import 'statistics_parameters.dart';

/// Warum keine Einordnung möglich ist.
enum ClassificationUnavailable {
  /// Der Lauf hat keine Durchschnittspace.
  noPaceForRun,

  /// Weniger vorherige Läufe mit Pace als `minimumComparisonRuns`.
  tooFewPreviousRuns,
}

/// Verhältnis zum Schnitt der Vorläufe.
enum PaceRelation { faster, same, slower }

/// Einordnung gegenüber vorherigen Einheiten (FR-0037, OQ-0037): Vergleich der
/// Durchschnittspace des Laufs mit dem Schnitt der letzten Läufe. Ohne
/// Einordnung sind [referenceSecondsPerKm] und [deltaSecondsPerKm] `null`.
class RunClassification {
  const RunClassification.available({
    required double this.runSecondsPerKm,
    required double this.referenceSecondsPerKm,
    required this.comparedRuns,
  }) : unavailable = null;

  const RunClassification.unavailable(
    ClassificationUnavailable this.unavailable, {
    this.comparedRuns = 0,
  }) : runSecondsPerKm = null,
       referenceSecondsPerKm = null;

  final double? runSecondsPerKm;

  /// Mittel der Durchschnittspaces der verglichenen Vorläufe (s/km).
  final double? referenceSecondsPerKm;

  /// Zahl der tatsächlich verglichenen Vorläufe (höchstens
  /// `comparisonRunCount`; weniger, wenn es weniger gibt).
  final int comparedRuns;
  final ClassificationUnavailable? unavailable;

  bool get isAvailable => unavailable == null;

  /// Lauf minus Schnitt in s/km; negativ = schneller als der Schnitt.
  double? get deltaSecondsPerKm =>
      isAvailable ? runSecondsPerKm! - referenceSecondsPerKm! : null;

  /// Nur das Vorzeichen des Unterschieds; die Spec nennt keine Toleranz für
  /// „gleich“, darum gilt nur ein Unterschied von genau 0 als gleich.
  PaceRelation? get relation {
    final d = deltaSecondsPerKm;
    if (d == null) return null;
    return d < 0
        ? PaceRelation.faster
        : d > 0
        ? PaceRelation.slower
        : PaceRelation.same;
  }
}

/// Ordnet [run] gegenüber [others] ein. Vorläufe sind Läufe mit früherem
/// Laufende (gleiche Id und spätere zählen nicht); es zählen die letzten
/// `comparisonRunCount` mit Durchschnittspace. Der Schnitt ist das einfache
/// Mittel ihrer Durchschnittspaces.
RunClassification classifyRun(
  RunFigures run,
  Iterable<RunFigures> others, {
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  final pace = run.averagePaceSecondsPerKm;
  if (pace == null) {
    return const RunClassification.unavailable(
      ClassificationUnavailable.noPaceForRun,
    );
  }
  final previous =
      others
          .where(
            (r) =>
                r.runId != run.runId &&
                r.endedAt.isBefore(run.endedAt) &&
                r.averagePaceSecondsPerKm != null,
          )
          .toList()
        ..sort((a, b) {
          final c = b.endedAt.compareTo(a.endedAt);
          return c != 0 ? c : b.runId.compareTo(a.runId);
        });
  final used = previous.take(parameters.comparisonRunCount).toList();
  if (used.length < parameters.minimumComparisonRuns) {
    return RunClassification.unavailable(
      ClassificationUnavailable.tooFewPreviousRuns,
      comparedRuns: used.length,
    );
  }
  final mean =
      used.map((r) => r.averagePaceSecondsPerKm!).reduce((a, b) => a + b) /
      used.length;
  return RunClassification.available(
    runSecondsPerKm: pace,
    referenceSecondsPerKm: mean,
    comparedRuns: used.length,
  );
}
