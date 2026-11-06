import 'dart:math' as math;

import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'vo2max_section_types.dart';

/// Kennung und Version des VO₂max-Schätzers (ADR-0004 P.3). Kategorie B
/// (Heuristik): Die Formeln sind etabliert, Auswahl, Gewichtung und Stufen
/// sind eigene Wahl (NFR-0002).
const String vo2maxEstimatorMethod = 'vo2max-acsm-hrr';
const int vo2maxEstimatorMethodVersion = 1;

/// Gründe, aus denen ein Lauf höchstens „vorläufig“ ist (PAR-038).
enum TierCap {
  /// Nur ein Abschnitt: keine Streuung, FR-0077 nicht erfüllt.
  singleSection('PAR-038'),

  /// HFmax stammt aus der Altersformel (OQ-0012).
  estimatedMaxHeartRate('PAR-038'),

  /// Ein Abschnitt fiel in 120 bis 134 m/min (PAR-031).
  limitedSpeed('PAR-031'),

  /// Ein Abschnitt ohne verwertbare Höhe oder Vertikalgenauigkeit (PAR-027).
  noAltitude('PAR-027'),

  /// Lauf aus dem Laufbandmodus (FR-0196, Phase 2; nur als Parameter).
  treadmill('PAR-038');

  const TierCap(this.parameterId);
  final String parameterId;
}

/// Warum eine Abschnittsschätzung nicht eingeht.
enum EstimateDiscard {
  /// PAR-032: außerhalb des plausiblen Bereichs.
  implausible,

  /// Tempo oder `r` fehlt, obwohl der Abschnitt zugelassen war (sollte nicht
  /// vorkommen; Teil A lehnt solche Abschnitte ab).
  incomplete,
}

/// Schätzung eines Abschnitts (FR-0076 Schritte 4 bis 7).
class SectionEstimate {
  const SectionEstimate({
    required this.section,
    required this.oxygenDemand,
    required this.vo2max,
    required this.weight,
    required this.discard,
  });

  final EvaluatedSection section;

  /// FR-0069: Sauerstoffbedarf in ml/kg/min; `null`, wenn Tempo fehlt.
  final double? oxygenDemand;

  /// FR-0071: Hochrechnung in ml/kg/min; `null`, wenn `r` fehlt.
  final double? vo2max;

  /// PAR-033: Minuten (bis 10) × GPS-Faktor × Spätfaktor.
  final double weight;

  final EstimateDiscard? discard;
  bool get isUsed => discard == null;
}

/// Ergebnis eines Laufs: Wert oder „nicht bestimmbar“ mit Grund (FR-0053),
/// dazu die Zwischenstände für Speicherung und Anzeige.
class Vo2maxRunEstimate {
  Vo2maxRunEstimate({
    required this.result,
    required List<SectionEstimate> sections,
    required this.spreadPercent,
    required Set<TierCap> caps,
    required this.maxIsEstimated,
  }) : sections = List.unmodifiable(sections),
       caps = Set.unmodifiable(caps);

  /// Wert mit Stufe, Methode, Methodenversion und Parameterversion.
  final AdvancedFitnessValue<double> result;

  /// Alle zugelassenen Abschnitte mit Schätzung, auch die verworfenen.
  final List<SectionEstimate> sections;

  /// Eingegangene Abschnitte (PAR-032 überstanden).
  List<SectionEstimate> get used => [
    for (final s in sections)
      if (s.isUsed) s,
  ];

  /// PAR-036: Streuung `S` in Prozent; `null` bei weniger als 2 Abschnitten.
  final double? spreadPercent;

  /// PAR-038: Obergrenzen, die für diesen Lauf gelten (auch bei „nicht
  /// bestimmbar“ leer, weil dann keine Stufe vergeben wird).
  final Set<TierCap> caps;

  /// HFmax war eine Schätzung (OQ-0012).
  final bool maxIsEstimated;

  QualityTier get tier => result.metadata.tier;
}

/// Familie VO₂max-Schätzer (FR-0066). Weitere Verfahren kommen als weitere
/// Varianten (NFR-0005).
abstract class Vo2maxEstimator extends AlgorithmVariant {
  const Vo2maxEstimator();

  /// Schätzt die VO₂max eines Laufs aus den bewerteten Abschnitten.
  /// [calculatedAt] kommt von außen (keine Uhr). [runStart] und [runEnd]
  /// bilden den Datenzeitraum. [treadmill] ist die Vorgabe für Laufbandläufe
  /// (FR-0196), sie begrenzt die Stufe auf „vorläufig“.
  Vo2maxRunEstimate estimate({
    required SectionSelection selection,
    required HeartRateBasis basis,
    required FitnessParameters p,
    required DateTime calculatedAt,
    required DateTime runStart,
    required DateTime runEnd,
    Set<String> dataSources = const {},
    bool treadmill = false,
  });
}

/// ACSM-Laufformel mit Hochrechnung über die Herzfrequenzreserve (FR-0069,
/// FR-0071) und gewichtetem Median (FR-0076).
class AcsmReserveVo2maxEstimator extends Vo2maxEstimator {
  const AcsmReserveVo2maxEstimator({this.reserve = const HeartRateReserve()});

  /// Verfahren für die Prüfung der Basis (PAR-018, PAR-019).
  final HeartRateReserveModel reserve;

  @override
  String get method => vo2maxEstimatorMethod;
  @override
  int get methodVersion => vo2maxEstimatorMethodVersion;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  /// FR-0069: `VO2 = 3,5 + 0,2·v + 0,9·v·G` (v in m/min, G als Dezimalzahl).
  static double oxygenDemand(
    double metersPerMinute,
    double gradient,
    Vo2maxParameters p,
  ) =>
      p.restingOxygen +
      p.runCoefficient * metersPerMinute +
      p.gradeCoefficient * metersPerMinute * gradient;

  /// FR-0071: `VO2max ≈ 3,5 + (VO2 − 3,5) / r`; `r` muss größer 0 sein.
  static double extrapolate(double demand, double load, Vo2maxParameters p) =>
      p.restingOxygen + (demand - p.restingOxygen) / load;

  /// PAR-033: Gewicht eines Abschnitts.
  static double sectionWeight(EvaluatedSection s, Vo2maxParameters p) {
    final minutes =
        math.min(
          s.duration.inMicroseconds,
          p.weightMaxDuration.inMicroseconds,
        ) /
        Duration.microsecondsPerMinute;
    final gps = s.gpsMedianAccuracyMeters;
    final factor = gps != null && gps <= p.gpsGoodMedianMeters
        ? p.gpsGoodFactor
        : p.gpsOtherFactor;
    return minutes * factor * s.weight;
  }

  /// Gewichteter Median: der Wert, bei dem das Gewicht der kleineren Werte
  /// die Hälfte nicht erreicht und das der kleineren und gleichen sie
  /// erreicht. Trifft die Summe genau die Hälfte, gilt die Mitte zwischen
  /// diesem und dem nächsten Wert. Werte mit Gewicht 0 zählen nicht.
  static double weightedMedian(List<double> values, List<double> weights) {
    if (values.length != weights.length || values.isEmpty) {
      throw ArgumentError('Werte und Gewichte müssen gleich lang sein');
    }
    final idx = [
      for (var i = 0; i < values.length; i++)
        if (weights[i] > 0) i,
    ]..sort((a, b) => values[a].compareTo(values[b]));
    if (idx.isEmpty) throw ArgumentError('kein Gewicht größer 0');
    final total = idx.fold<double>(0, (a, i) => a + weights[i]);
    var cum = 0.0;
    for (var k = 0; k < idx.length; k++) {
      cum += weights[idx[k]];
      if (cum * 2 == total && k + 1 < idx.length) {
        return (values[idx[k]] + values[idx[k + 1]]) / 2;
      }
      if (cum * 2 >= total) return values[idx[k]];
    }
    return values[idx.last];
  }

  /// P-tes Perzentil (Anteil 0..1) mit linearer Interpolation zwischen den
  /// Rängen (Rang `p·(n−1)`).
  static double percentile(List<double> values, double p) {
    final v = [...values]..sort();
    final pos = p * (v.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    return v[lo] + (v[hi] - v[lo]) * (pos - lo);
  }

  /// PAR-036: Streuung in Prozent des gewichteten Medians [center].
  /// [times] sind die Abschnittsmitten in Minuten. `null` bei weniger als 2
  /// Werten oder Median 0.
  static double? spread(
    List<double> values,
    List<double> times,
    double center,
    Vo2maxParameters p,
  ) {
    final n = values.length;
    if (n < 2 || center <= 0) return null;
    var resid = values;
    if (n >= p.trendFromSections) {
      final mx = times.reduce((a, b) => a + b) / n;
      final my = values.reduce((a, b) => a + b) / n;
      var sxy = 0.0;
      var sxx = 0.0;
      for (var i = 0; i < n; i++) {
        sxy += (times[i] - mx) * (values[i] - my);
        sxx += (times[i] - mx) * (times[i] - mx);
      }
      final slope = sxx == 0 ? 0.0 : sxy / sxx;
      resid = [
        for (var i = 0; i < n; i++) values[i] - my - slope * (times[i] - mx),
      ];
    }
    final width = n >= p.percentileFromSections
        ? percentile(resid, p.percentileHigh) -
              percentile(resid, p.percentileLow)
        : resid.reduce(math.max) - resid.reduce(math.min);
    return width / center * FitnessParameters.percent;
  }

  /// PAR-037 bis PAR-040: Stufe aus Streuung, Abschnitten und Obergrenzen.
  /// [spreadPercent] `null` heißt: keine Streuung bestimmbar (ein Abschnitt).
  static QualityTier tierFor({
    required int sections,
    required Duration total,
    required double? spreadPercent,
    required Set<TierCap> caps,
    required Vo2maxParameters p,
  }) {
    if (sections < 1) return QualityTier.notDeterminable;
    if (spreadPercent != null && spreadPercent > p.undeterminableAbovePercent) {
      return QualityTier.notDeterminable;
    }
    if (caps.isNotEmpty || spreadPercent == null) {
      return QualityTier.preliminary;
    }
    if (sections >= p.goodMinSections &&
        total >= p.goodMinDuration &&
        spreadPercent <= p.goodMaxPercent) {
      return QualityTier.good;
    }
    if (sections >= p.sufficientMinSections &&
        spreadPercent <= p.sufficientMaxPercent) {
      return QualityTier.sufficient;
    }
    return QualityTier.preliminary;
  }

  @override
  Vo2maxRunEstimate estimate({
    required SectionSelection selection,
    required HeartRateBasis basis,
    required FitnessParameters p,
    required DateTime calculatedAt,
    required DateTime runStart,
    required DateTime runEnd,
    Set<String> dataSources = const {},
    bool treadmill = false,
  }) {
    final vp = p.vo2max;
    AdvancedFitnessValue<double> make(
      QualityTier tier, {
      double? value,
      UnavailableReason? reason,
      int measurements = 0,
    }) => AdvancedFitnessValue<double>(
      value: value,
      reason: reason,
      metadata: FitnessValueMetadata(
        calculatedAt: calculatedAt,
        dataFrom: runStart,
        dataTo: runEnd,
        usableMeasurements: measurements,
        dataSources: dataSources,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        tier: tier,
      ),
    );
    Vo2maxRunEstimate undetermined(
      UnavailableReason reason, {
      List<SectionEstimate> sections = const [],
      double? spread,
    }) => Vo2maxRunEstimate(
      result: make(QualityTier.notDeterminable, reason: reason),
      sections: sections,
      spreadPercent: spread,
      caps: const {},
      maxIsEstimated: basis.maxIsEstimated,
    );

    // FR-0068, OQ-0012, PAR-018, PAR-019: fehlende Basis, kein Wert.
    final basisReason = reserve.check(basis, p);
    if (basisReason != null) return undetermined(basisReason);

    final usable = selection.usable;
    if (usable.isEmpty) {
      final onlyNoHeartRate =
          selection.sections.isNotEmpty &&
          selection.sections.every(
            (s) => s.violates(SectionRule.heartRateUnavailable),
          );
      return undetermined(
        onlyNoHeartRate
            ? UnavailableReason.noHeartRate
            : UnavailableReason.noValidSection,
      );
    }

    final estimates = <SectionEstimate>[];
    for (final s in usable) {
      final v = s.speedMetersPerMinute;
      final r = s.relativeLoad;
      final demand = v == null ? null : oxygenDemand(v, s.gradient, vp);
      final max = demand == null || r == null || r <= 0
          ? null
          : extrapolate(demand, r, vp);
      final EstimateDiscard? discard;
      if (max == null || !max.isFinite) {
        discard = EstimateDiscard.incomplete;
      } else if (max < vp.plausibleMin || max > vp.plausibleMax) {
        discard = EstimateDiscard.implausible; // PAR-032
      } else {
        discard = null;
      }
      estimates.add(
        SectionEstimate(
          section: s,
          oxygenDemand: demand,
          vo2max: max,
          weight: sectionWeight(s, vp),
          discard: discard,
        ),
      );
    }
    final used = [
      for (final e in estimates)
        if (e.isUsed) e,
    ];
    if (used.isEmpty) {
      return undetermined(
        UnavailableReason.allEstimatesImplausible,
        sections: estimates,
      );
    }

    final values = [for (final e in used) e.vo2max!];
    final median = weightedMedian(values, [for (final e in used) e.weight]);

    // PAR-036: Abschnittsmitten in Minuten ab dem ersten Abschnitt.
    final origin = used.first.section.from.microsecondsSinceEpoch;
    final times = [
      for (final e in used)
        (e.section.from.microsecondsSinceEpoch +
                    e.section.to.microsecondsSinceEpoch) /
                2 /
                Duration.microsecondsPerMinute -
            origin / Duration.microsecondsPerMinute,
    ];
    final s = spread(values, times, median, vp);

    final total = used.fold<Duration>(
      Duration.zero,
      (a, e) => a + e.section.duration,
    );
    final caps = <TierCap>{
      if (used.length <= vp.preliminaryMaxSections) TierCap.singleSection,
      if (basis.maxIsEstimated) TierCap.estimatedMaxHeartRate,
      if (used.any(
        (e) => e.section.caveats.contains(SectionCaveat.limitedSpeed),
      ))
        TierCap.limitedSpeed,
      if (used.any(
        (e) =>
            e.section.caveats.contains(SectionCaveat.noAltitude) ||
            e.section.caveats.contains(SectionCaveat.noVerticalAccuracy),
      ))
        TierCap.noAltitude,
      if (treadmill) TierCap.treadmill,
    };
    final tier = tierFor(
      sections: used.length,
      total: total,
      spreadPercent: s,
      caps: caps,
      p: vp,
    );
    if (tier == QualityTier.notDeterminable) {
      return undetermined(
        UnavailableReason.spreadTooHigh,
        sections: estimates,
        spread: s,
      );
    }
    return Vo2maxRunEstimate(
      result: make(tier, value: median, measurements: used.length),
      sections: estimates,
      spreadPercent: s,
      caps: caps,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}

const vo2maxEstimatorFamily = AlgorithmFamily<Vo2maxEstimator>(
  'vo2max-estimator',
);
