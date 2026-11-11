import 'prediction_level.dart';
import 'prediction_parameters.dart';
import 'prediction_run.dart';
import 'reference_performance.dart';
import 'riegel.dart';

/// Prognose für eine Zieldistanz.
class DistancePrediction {
  const DistancePrediction({
    required this.distance,
    required this.seconds,
    required this.level,
    required this.reason,
    required this.limits,
  });

  final PredictionDistance distance;

  /// Zeit in Sekunden; `null` bei „nicht bestimmbar“. Nie aus der VO₂max
  /// (FR-0134).
  final double? seconds;

  final PredictionLevel level;

  /// Begrenzender Grund (PAR-159); [PredictionReason.none] bei „gut“.
  final PredictionReason reason;

  /// Alle Gründe, die die nächsthöhere Stufe verhindern, in fester Reihenfolge.
  final List<PredictionReason> limits;
}

/// Metadaten nach FR-0053; nicht gespeichert, bei Bedarf berechnet.
class PredictionMetadata {
  const PredictionMetadata({
    required this.calculatedAt,
    required this.dataFrom,
    required this.dataTo,
    required this.measurementCount,
    required this.sources,
    required this.method,
    required this.methodVersion,
    required this.level,
  });

  final DateTime calculatedAt;

  /// Beginn des Datenzeitraums (Referenzdatum); `null` ohne Referenz.
  final DateTime? dataFrom;

  /// Ende des Datenzeitraums (heute).
  final DateTime dataTo;

  /// Referenz (1) plus Läufe der letzten Regelmäßigkeitsfenster-Wochen
  /// (Annahme: Läufe mit Datum nach der Referenz zählen nicht doppelt).
  final int measurementCount;

  final List<PredictionSource> sources;
  final String method;
  final int methodVersion;

  /// Höchste Stufe über alle Distanzen.
  final PredictionLevel level;
}

enum PredictionSource { enteredTime, confirmedRun, runHistory, vo2max }

/// Ergebnis der allgemeinen Schätzung (FR-0133) für alle vier Distanzen.
class PerformancePrediction {
  const PerformancePrediction({
    required this.reference,
    required this.distances,
    required this.metadata,
    this.referenceProblem,
  });

  /// Die verwendete Referenz (FR-0129); `null` ohne gültige Referenz.
  final ReferencePerformance? reference;

  /// Grund für „Referenz ungültig“ (K49) zur Anzeige: Problem der geltenden
  /// Referenz (künftiges Datum) oder, wenn keine gespeicherte Referenz
  /// brauchbar ist, das der jüngsten gespeicherten (zu kurz, Zeit ≤ 0, Tempo
  /// außerhalb der Spanne). `null`, wenn die Referenz gilt oder keine
  /// gespeichert ist.
  final ReferenceProblem? referenceProblem;

  final List<DistancePrediction> distances;
  final PredictionMetadata metadata;

  DistancePrediction of(PredictionDistance d) =>
      distances.firstWhere((x) => x.distance == d);
}

/// Allgemeine Leistungsschätzung (FR-0128 bis FR-0132, FR-0134). Reine
/// Funktion aus Referenzen, Läufen und [now]. Die Zielprognose (FR-0133) ist
/// davon getrennt (siehe `goal_prediction.dart`).
PerformancePrediction predictPerformance({
  required DateTime now,
  required Iterable<ReferencePerformance> references,
  required Iterable<PredictionRun> runs,
  bool hasVo2maxEstimate = false,
  PredictionParameters parameters = const PredictionParameters(),
}) {
  final p = parameters;
  // Gerechnet wird nur mit einer brauchbaren Referenz (isUsableReference).
  // Ist keine brauchbar, aber eine gespeichert, zeigt die Prognose wie K49
  // „Referenz ungültig“ mit dem Grund der jüngsten gespeicherten.
  final ref = activeReference(references, p);
  final problem = ref != null
      ? ref.validate(now, p)
      : newestReference(references)?.validate(now, p);
  final valid = problem == null ? ref : null;
  final today = calendarDay(now);
  final pastRuns = [
    for (final r in runs)
      if (!calendarDay(r.date).isAfter(today)) r,
  ];

  PredictionReason? blocker;
  if (problem != null) {
    blocker = PredictionReason.invalidReference;
  } else if (ref == null) {
    blocker = hasVo2maxEstimate
        ? PredictionReason.onlyVo2max
        : PredictionReason.noReference;
  } else if (daysBetween(ref.date, now) > p.maxReferenceAgeDays) {
    blocker = PredictionReason.referenceTooOld;
  } else if (_longestGap(ref.date, pastRuns, today) >=
      p.maxPauseDaysExclusive) {
    blocker = PredictionReason.pauseSinceReference;
  }

  final weeks = _regularWeeks(pastRuns, today, p);
  final results = <DistancePrediction>[];
  for (final d in PredictionDistance.values) {
    if (blocker != null || valid == null) {
      results.add(
        DistancePrediction(
          distance: d,
          seconds: null,
          level: PredictionLevel.notDeterminable,
          reason: blocker!,
          limits: [blocker],
        ),
      );
      continue;
    }
    results.add(_assess(valid, d, now, pastRuns, weeks, p));
  }

  final level = results
      .map((r) => r.level)
      .reduce((a, b) => a.index >= b.index ? a : b);
  final windowStart = today.subtract(Duration(days: p.regularityWeeks * 7 - 1));
  final recent = pastRuns
      .where((r) => !calendarDay(r.date).isBefore(windowStart))
      .length;
  return PerformancePrediction(
    reference: valid,
    referenceProblem: problem,
    distances: results,
    metadata: PredictionMetadata(
      calculatedAt: now,
      dataFrom: valid == null ? null : calendarDay(valid.date),
      dataTo: today,
      measurementCount: (valid == null ? 0 : 1) + (valid == null ? 0 : recent),
      sources: [
        if (valid != null)
          valid.kind == ReferenceKind.confirmedRun
              ? PredictionSource.confirmedRun
              : PredictionSource.enteredTime,
        if (valid != null && recent > 0) PredictionSource.runHistory,
        if (hasVo2maxEstimate) PredictionSource.vo2max,
      ],
      method: predictionMethod,
      methodVersion: predictionMethodVersion,
      level: level,
    ),
  );
}

DistancePrediction _assess(
  ReferencePerformance ref,
  PredictionDistance d,
  DateTime now,
  List<PredictionRun> runs,
  int weeks,
  PredictionParameters p,
) {
  final seconds = riegelWithParameters(
    p,
    referenceSeconds: ref.seconds,
    referenceMeters: ref.distanceMeters,
    targetMeters: d.meters,
  );
  final age = daysBetween(ref.date, now);
  final ratio = distanceRatio(d.meters, ref.distanceMeters);

  final sufficientLimits = <PredictionReason>[
    if (age > p.sufficientMaxAgeDays) PredictionReason.referenceAge,
    if (ratio > p.sufficientMaxRatio) PredictionReason.distanceRatio,
    if (ref.kind == ReferenceKind.confirmedRun)
      PredictionReason.referenceIsConfirmedRun,
    if (d == PredictionDistance.marathon) PredictionReason.marathon,
    if (weeks < p.sufficientRegularWeeks) PredictionReason.regularity,
  ];
  if (sufficientLimits.isNotEmpty) {
    return DistancePrediction(
      distance: d,
      seconds: seconds,
      level: PredictionLevel.provisional,
      reason: sufficientLimits.first,
      limits: sufficientLimits,
    );
  }
  final longest = _longestRunSeconds(runs, now, p);
  final goodLimits = <PredictionReason>[
    if (ref.kind != ReferenceKind.race) PredictionReason.referenceIsTest,
    if (age > p.goodMaxAgeDays) PredictionReason.referenceAge,
    if (ratio > p.goodMaxRatio) PredictionReason.distanceRatio,
    if (weeks < p.goodRegularWeeks) PredictionReason.regularity,
    if (longest < p.goodLongestRunShare * seconds) PredictionReason.longestRun,
  ];
  if (goodLimits.isNotEmpty) {
    return DistancePrediction(
      distance: d,
      seconds: seconds,
      level: PredictionLevel.sufficient,
      reason: goodLimits.first,
      limits: goodLimits,
    );
  }
  return DistancePrediction(
    distance: d,
    seconds: seconds,
    level: PredictionLevel.good,
    reason: PredictionReason.none,
    limits: const [],
  );
}

/// Längster Abstand in Tagen zwischen Referenzdatum, Lauftagen danach und
/// heute (PAR-143, PAR-202).
int _longestGap(DateTime refDate, List<PredictionRun> runs, DateTime today) {
  final start = calendarDay(refDate);
  final days = <DateTime>{
    start,
    today,
    for (final r in runs)
      if (!calendarDay(r.date).isBefore(start)) calendarDay(r.date),
  }.toList()..sort();
  var longest = 0;
  for (var i = 1; i < days.length; i++) {
    final gap = days[i].difference(days[i - 1]).inDays;
    if (gap > longest) longest = gap;
  }
  return longest;
}

/// Zahl der rollenden 7-Tage-Wochen (rückwärts ab heute, [regularityWeeks]
/// Stück) mit mindestens [regularityRunsPerWeek] Läufen.
int _regularWeeks(
  List<PredictionRun> runs,
  DateTime today,
  PredictionParameters p,
) {
  final counts = List<int>.filled(p.regularityWeeks, 0);
  for (final r in runs) {
    final offset = today.difference(calendarDay(r.date)).inDays;
    if (offset < 0 || offset >= p.regularityWeeks * 7) continue;
    counts[offset ~/ 7]++;
  }
  return counts.where((c) => c >= p.regularityRunsPerWeek).length;
}

/// Längste Bewegungszeit der letzten [goodLongestRunDays] Tage (heute
/// eingeschlossen); 0 ohne Läufe.
double _longestRunSeconds(
  List<PredictionRun> runs,
  DateTime now,
  PredictionParameters p,
) {
  var longest = 0.0;
  for (final r in runs) {
    final age = daysBetween(r.date, now);
    if (age >= 0 && age < p.goodLongestRunDays && r.movingSeconds > longest) {
      longest = r.movingSeconds;
    }
  }
  return longest;
}
