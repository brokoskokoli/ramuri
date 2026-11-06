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
/// Durchschnittspace des Laufs mit der Referenz der letzten Läufe (Σ Strecke /
/// Σ Zeit der Vorläufe, Maintainer 2026-11-06). Ohne
/// Einordnung sind [referenceSecondsPerKm] und [deltaSecondsPerKm] `null`.
class RunClassification {
  const RunClassification.available({
    required double this.runSecondsPerKm,
    required double this.referenceSecondsPerKm,
    required this.comparedRuns,
    this.sameToleranceSecondsPerKm = 1,
  }) : unavailable = null;

  const RunClassification.unavailable(
    ClassificationUnavailable this.unavailable, {
    this.comparedRuns = 0,
  }) : runSecondsPerKm = null,
       referenceSecondsPerKm = null,
       sameToleranceSecondsPerKm = 1;

  final double? runSecondsPerKm;

  /// Unterschied unterhalb dieser Grenze (s/km, ausschließlich) gilt als gleich.
  final double sameToleranceSecondsPerKm;

  /// Referenz der verglichenen Vorläufe: Σ Strecke / Σ Zeit (s/km).
  final double? referenceSecondsPerKm;

  /// Zahl der tatsächlich verglichenen Vorläufe (höchstens
  /// `comparisonRunCount`; weniger, wenn es weniger gibt).
  final int comparedRuns;
  final ClassificationUnavailable? unavailable;

  bool get isAvailable => unavailable == null;

  /// Lauf minus Schnitt in s/km; negativ = schneller als der Schnitt.
  double? get deltaSecondsPerKm =>
      isAvailable ? runSecondsPerKm! - referenceSecondsPerKm! : null;

  /// Nur Unterschied, keine Klassifikation nach Toleranzstufen (Maintainer
  /// 2026-11-06): |Δ| unter [sameToleranceSecondsPerKm] gilt als gleich.
  PaceRelation? get relation {
    final d = deltaSecondsPerKm;
    if (d == null) return null;
    return d.abs() < sameToleranceSecondsPerKm
        ? PaceRelation.same
        : d < 0
        ? PaceRelation.faster
        : PaceRelation.slower;
  }
}

/// Ordnet [run] gegenüber [others] ein. Vorläufe sind Läufe mit früherem
/// Laufende (gleiche Id und spätere zählen nicht); es zählen die letzten
/// `comparisonRunCount` mit Durchschnittspace. Die Referenz ist Σ Strecke /
/// Σ Pace-Zeit dieser Läufe (nicht das Mittel der Paces).
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
  var meters = 0.0;
  var micros = 0;
  for (final r in used) {
    meters += r.distanceMeters!;
    micros += r.paceTime!.inMicroseconds;
  }
  return RunClassification.available(
    runSecondsPerKm: pace,
    referenceSecondsPerKm: micros / 1e6 / (meters / 1000),
    comparedRuns: used.length,
    sameToleranceSecondsPerKm: parameters.sameToleranceSecondsPerKm,
  );
}
