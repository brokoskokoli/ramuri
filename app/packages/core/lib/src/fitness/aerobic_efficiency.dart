import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'vo2max_section_types.dart';

/// Kennung und Version der aeroben Effizienz (ADR-0004 P.3). Kategorie B
/// (Heuristik): Bereich, Mengen und Stufen sind eigene Wahl (OQ-0036,
/// PAR-044 bis PAR-047).
const String aerobicEfficiencyMethod = 'aerobic-efficiency-median';
const int aerobicEfficiencyMethodVersion = 1;

/// Kategorie der aeroben Effizienz (NFR-0002): B.
const AlgorithmCategory aerobicEfficiencyCategory = AlgorithmCategory.heuristic;

/// Ein Lauf als Eingabe: Ende und Abschnittsauswahl der VO₂max (Teil A).
class EfficiencyRun {
  const EfficiencyRun({required this.endedAt, required this.selection});

  /// Laufende; es entscheidet über das Fenster.
  final DateTime endedAt;

  /// Ergebnis von `Vo2maxSectionSelector.select` für diesen Lauf.
  final SectionSelection selection;
}

/// Ein Abschnitt, der in ein Fenster eingeht.
class EfficiencySection {
  const EfficiencySection({required this.section, required this.runIndex});

  final EvaluatedSection section;

  /// Position des Laufs in der Eingabeliste.
  final int runIndex;
}

/// Ein 4-Wochen-Fenster mit seinen Abschnitten und Kennzahlen.
class EfficiencyWindow {
  EfficiencyWindow({
    required this.from,
    required this.to,
    required List<EfficiencySection> sections,
    required this.runCount,
    required this.totalDuration,
    required this.medianSpeed,
    required this.meanGradient,
    required this.meetsMinimum,
    required this.tier,
  }) : sections = List.unmodifiable(sections);

  /// Grenzen des Fensters (Beginn inklusiv; Ende inklusiv beim aktuellen,
  /// exklusiv beim Vergleichsfenster).
  final DateTime from;
  final DateTime to;
  final List<EfficiencySection> sections;

  /// Läufe mit mindestens einem eingegangenen Abschnitt.
  final int runCount;
  final Duration totalDuration;

  /// FR-0085: ungewichteter Median der Abschnittsgeschwindigkeiten in
  /// m/min; `null` ohne Abschnitt.
  final double? medianSpeed;

  /// Mittlere Nettosteigung (Anteil) der eingegangenen Abschnitte, ungewichtet.
  final double? meanGradient;

  /// PAR-046 erfüllt.
  final bool meetsMinimum;

  /// PAR-047 ohne Steigungsregel; `null`, wenn die Mindestmenge fehlt.
  final QualityTier? tier;
}

/// Ergebnis: Veränderung in Prozent oder „nicht bestimmbar“ mit Grund, dazu
/// beide Fenster.
class AerobicEfficiencyResult {
  const AerobicEfficiencyResult({
    required this.change,
    required this.current,
    required this.reference,
    required this.slopeCapped,
  });

  /// FR-0087: `ΔE = (v_aktuell / v_referenz − 1) · 100` in Prozent.
  final AdvancedFitnessValue<double> change;
  final EfficiencyWindow current;
  final EfficiencyWindow reference;

  /// PAR-047: Die mittleren Steigungen weichen um mehr als einen
  /// Prozentpunkt ab; die Stufe ist dann höchstens „vorläufig“.
  final bool slopeCapped;
}

/// Familie aerobe Effizienz (FR-0084). Weitere Verfahren kommen als weitere
/// Varianten (NFR-0005).
abstract class AerobicEfficiency extends AlgorithmVariant {
  const AerobicEfficiency();

  /// Veränderung der letzten 4 Wochen gegenüber den 4 Wochen davor.
  /// [now] ist der Berechnungszeitpunkt (kommt vom Aufrufer aus der
  /// Uhr-Schnittstelle, wie bei `Vo2maxLongTerm`). Läufe nach [now] zählen
  /// nicht. Jede Auswahl muss zur Parameterversion von [p] passen.
  AerobicEfficiencyResult compute({
    required List<EfficiencyRun> runs,
    required FitnessParameters p,
    required DateTime now,
    Set<String> dataSources = const {},
  });
}

/// Median der Abschnittsgeschwindigkeiten bei 65 bis 75 % der Reserve
/// (FR-0085 bis FR-0087).
class MedianAerobicEfficiency extends AerobicEfficiency {
  const MedianAerobicEfficiency();

  @override
  String get method => aerobicEfficiencyMethod;
  @override
  int get methodVersion => aerobicEfficiencyMethodVersion;
  @override
  AlgorithmCategory get category => aerobicEfficiencyCategory;

  /// Regeln der VO₂max-Auswahl, die hier nicht gelten: PAR-026 (Steigung,
  /// ersetzt durch PAR-045), PAR-028/PAR-029 (Bereich, ersetzt durch OQ-0036)
  /// und PAR-030/PAR-031 (Mindestgeschwindigkeit, PAR-044).
  static const Set<SectionRule> replacedRules = {
    SectionRule.gradient,
    SectionRule.intensityLow,
    SectionRule.intensityHigh,
    SectionRule.tooSlow,
  };

  /// PAR-044 und PAR-045 für einen Abschnitt der VO₂max-Auswahl: alle
  /// übrigen Regeln erfüllt, Tempo und `r` bekannt, `r` im Bereich aus
  /// OQ-0036, Nettosteigung höchstens [AerobicEfficiencyParameters
  /// .gradientMaxAbs] im Betrag.
  static bool isEligible(EvaluatedSection s, AerobicEfficiencyParameters p) {
    if (s.violations.any((v) => !replacedRules.contains(v.rule))) return false;
    final r = s.relativeLoad;
    final v = s.speedMetersPerMinute;
    if (r == null || v == null) return false;
    if (r < p.loadMin || r > p.loadMax) return false;
    return s.gradient.abs() <= p.gradientMaxAbs;
  }

  /// PAR-047 je Fenster (ohne Steigungsregel).
  static QualityTier windowTier(
    int sections,
    int runs,
    AerobicEfficiencyParameters p,
  ) {
    if (sections >= p.goodMinSections && runs >= p.goodMinRuns) {
      return QualityTier.good;
    }
    if (sections >= p.sufficientMinSections && runs >= p.sufficientMinRuns) {
      return QualityTier.sufficient;
    }
    return QualityTier.preliminary;
  }

  /// Median ohne Gewichte; bei gerader Anzahl die Mitte der beiden mittleren.
  static double median(List<double> values) {
    if (values.isEmpty) throw ArgumentError('keine Werte');
    final v = [...values]..sort();
    final mid = v.length ~/ 2;
    return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
  }

  EfficiencyWindow _window({
    required DateTime from,
    required DateTime to,
    required bool Function(DateTime) contains,
    required List<EfficiencyRun> runs,
    required AerobicEfficiencyParameters ap,
  }) {
    final sections = <EfficiencySection>[];
    final runIdx = <int>{};
    for (var i = 0; i < runs.length; i++) {
      if (!contains(runs[i].endedAt)) continue;
      for (final s in runs[i].selection.sections) {
        if (isEligible(s, ap)) {
          sections.add(EfficiencySection(section: s, runIndex: i));
          runIdx.add(i);
        }
      }
    }
    final total = sections.fold<Duration>(
      Duration.zero,
      (a, e) => a + e.section.duration,
    );
    final meets =
        sections.length >= ap.minSections &&
        runIdx.length >= ap.minRuns &&
        total >= ap.minDuration;
    return EfficiencyWindow(
      from: from,
      to: to,
      sections: sections,
      runCount: runIdx.length,
      totalDuration: total,
      medianSpeed: sections.isEmpty
          ? null
          : median([for (final e in sections) e.section.speedMetersPerMinute!]),
      meanGradient: sections.isEmpty
          ? null
          : sections.fold<double>(0, (a, e) => a + e.section.gradient) /
                sections.length,
      meetsMinimum: meets,
      tier: meets ? windowTier(sections.length, runIdx.length, ap) : null,
    );
  }

  @override
  AerobicEfficiencyResult compute({
    required List<EfficiencyRun> runs,
    required FitnessParameters p,
    required DateTime now,
    Set<String> dataSources = const {},
  }) {
    for (final r in runs) {
      if (r.selection.parameterVersion != p.parameterVersion) {
        throw ArgumentError(
          'Parameterversionen weichen ab: Auswahl '
          '${r.selection.parameterVersion}, Fitness ${p.parameterVersion}',
        );
      }
    }
    final ap = p.aerobicEfficiency;
    final currentFrom = now.subtract(ap.windowLength);
    final referenceFrom = currentFrom.subtract(ap.windowLength);
    final current = _window(
      from: currentFrom,
      to: now,
      contains: (t) => !t.isBefore(currentFrom) && !t.isAfter(now),
      runs: runs,
      ap: ap,
    );
    final reference = _window(
      from: referenceFrom,
      to: currentFrom,
      contains: (t) => !t.isBefore(referenceFrom) && t.isBefore(currentFrom),
      runs: runs,
      ap: ap,
    );

    final all = [...reference.sections, ...current.sections];
    var dataFrom = now;
    var dataTo = now;
    if (all.isNotEmpty) {
      dataFrom = all.first.section.from;
      dataTo = all.first.section.to;
      for (final e in all) {
        if (e.section.from.isBefore(dataFrom)) dataFrom = e.section.from;
        if (e.section.to.isAfter(dataTo)) dataTo = e.section.to;
      }
    }
    AdvancedFitnessValue<double> make(
      QualityTier tier, {
      double? value,
      UnavailableReason? reason,
    }) => AdvancedFitnessValue<double>(
      value: value,
      reason: reason,
      metadata: FitnessValueMetadata(
        calculatedAt: now,
        dataFrom: dataFrom,
        dataTo: dataTo,
        usableMeasurements: all.length,
        dataSources: dataSources,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        tier: tier,
      ),
    );
    AerobicEfficiencyResult undetermined(UnavailableReason reason) =>
        AerobicEfficiencyResult(
          change: make(QualityTier.notDeterminable, reason: reason),
          current: current,
          reference: reference,
          slopeCapped: false,
        );

    if (!current.meetsMinimum) {
      return undetermined(UnavailableReason.currentWindowTooSmall);
    }
    if (!reference.meetsMinimum) {
      return undetermined(UnavailableReason.referenceWindowTooSmall);
    }

    final change =
        (current.medianSpeed! / reference.medianSpeed! - 1) *
        FitnessParameters.percent;
    var tier = current.tier!.index < reference.tier!.index
        ? current.tier!
        : reference.tier!;
    final capped =
        (current.meanGradient! - reference.meanGradient!).abs() >
        ap.maxGradientDifference;
    if (capped && tier != QualityTier.preliminary) {
      tier = QualityTier.preliminary;
    }
    return AerobicEfficiencyResult(
      change: make(tier, value: change),
      current: current,
      reference: reference,
      slopeCapped: capped,
    );
  }
}

const aerobicEfficiencyFamily = AlgorithmFamily<AerobicEfficiency>(
  'aerobic-efficiency',
);
