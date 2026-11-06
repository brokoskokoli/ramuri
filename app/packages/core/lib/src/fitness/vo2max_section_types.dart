import '../preprocessing/movement_time_processor.dart';
import 'fitness_result.dart';

/// Kennung und Version der Abschnittsauswahl für die VO₂max (ADR-0004 P.3).
const String vo2maxSectionSelectionMethod = 'vo2max-section-selection';
const int vo2maxSectionSelectionMethodVersion = 1;

/// Regeln, die ein Abschnitt verletzen kann (FR-0073). Jede Regel nennt ihre
/// Parameter-ID; ein Abschnitt trägt alle verletzten Regeln, nicht nur die
/// erste.
enum SectionRule {
  /// PAR-020: kürzer als die Mindestdauer nach der Einschwingzeit.
  tooShort('PAR-020'),

  /// PAR-022: Variationskoeffizient der 30-s-Tempowerte zu hoch.
  paceVariation('PAR-022'),

  /// PAR-022: Hälftentempi unterscheiden sich zu stark.
  paceHalves('PAR-022'),

  /// PAR-023: Hälftenmittel des Pulses unterscheiden sich zu stark.
  heartRateHalves('PAR-023'),

  /// PAR-010: zu viele oder zu lange Pulslücken.
  heartRateGaps('PAR-010'),

  /// PAR-024: Abschnitt beginnt zu spät im Lauf (Drift).
  lateRun('PAR-024'),

  /// PAR-025: Median der GPS-Genauigkeit zu groß.
  gpsMedianAccuracy('PAR-025'),

  /// PAR-025: zu wenige Punkte mit ausreichender Genauigkeit.
  gpsAccuracyShare('PAR-025'),

  /// PAR-025: GPS-Lücke nach PAR-004 im Abschnitt.
  gpsGap('PAR-025'),

  /// PAR-026: Nettosteigung außerhalb der Grenzen.
  gradient('PAR-026'),

  /// PAR-028: Belastung `r` zu niedrig.
  intensityLow('PAR-028'),

  /// PAR-029: Belastung `r` zu hoch.
  intensityHigh('PAR-029'),

  /// PAR-031: langsamer als die eingeschränkte Mindestgeschwindigkeit
  /// (Gehen oder sehr langsames Laufen, FR-0074).
  tooSlow('PAR-031'),

  /// Kein Tempo bestimmbar (zu wenige akzeptierte Positionen, PAR-006).
  speedUnavailable('PAR-006'),

  /// Kein Puls im Abschnitt, `r` nicht bestimmbar (FR-0068).
  heartRateUnavailable('PAR-010'),

  /// Basiswerte für `r` fehlen oder sind unbrauchbar (PAR-018, PAR-019); der
  /// Grund steht in [SectionViolation.basisReason].
  heartRateBasisUnavailable('PAR-018');

  const SectionRule(this.parameterId);
  final String parameterId;
}

/// Eine verletzte Regel mit gemessenem Wert und Grenze (soweit es sie gibt).
class SectionViolation {
  const SectionViolation(this.rule, {this.value, this.limit, this.basisReason});

  final SectionRule rule;

  /// Gemessener Wert in der Einheit der Regel; `null`, wenn es keinen gibt
  /// (dann erklärt die Regel selbst den Grund).
  final double? value;

  /// Grenze, gegen die verglichen wurde.
  final double? limit;

  /// Nur bei [SectionRule.heartRateBasisUnavailable].
  final UnavailableReason? basisReason;

  @override
  String toString() => 'SectionViolation(${rule.name}, $value, $limit)';
}

/// Einschränkungen eines nicht abgelehnten Abschnitts.
enum SectionCaveat {
  /// PAR-031: Tempo zwischen den beiden Mindestgeschwindigkeiten.
  limitedSpeed('PAR-031'),

  /// PAR-027: keine verwertbare Höhe; wie auf ebener Strecke gerechnet.
  noAltitude('PAR-027'),

  /// PAR-027: Höhe ohne gemeldete Vertikalgenauigkeit; wie eben gerechnet.
  noVerticalAccuracy('PAR-027');

  const SectionCaveat(this.parameterId);
  final String parameterId;
}

enum SectionStatus {
  /// Alle Regeln erfüllt, keine Einschränkung.
  eligible,

  /// Alle Regeln erfüllt, aber mit Einschränkung ([EvaluatedSection.caveats]):
  /// der Wert darf nur als „vorläufig“ gelten.
  provisional,

  /// Mindestens eine Regel verletzt ([EvaluatedSection.violations]).
  rejected,
}

/// Wie die Steigung `G` für die Formel zustande kam (PAR-027).
enum GradientBasis {
  /// Aus den Höhen gerechnet und eingesetzt.
  measured,

  /// Höhenänderung zu klein gegen Betrag oder Vertikalgenauigkeit: `G = 0`.
  belowThreshold,

  /// Keine verwertbare Höhe im Abschnitt: `G = 0`.
  noAltitude,

  /// Höhe ohne gemeldete Vertikalgenauigkeit: `G = 0`.
  noVerticalAccuracy,
}

/// Ein bewerteter Abschnitt. Kennzahlen sind `null`, wenn sie sich nicht
/// bestimmen ließen; der Grund steht dann in [violations].
class EvaluatedSection {
  EvaluatedSection({
    required this.from,
    required this.to,
    required this.status,
    required List<SectionViolation> violations,
    required List<SectionCaveat> caveats,
    required this.weight,
    required this.speedMetersPerMinute,
    required this.meanHeartRate,
    required this.relativeLoad,
    required this.gradient,
    required this.gradientBasis,
    required this.distanceMeters,
    this.gpsMedianAccuracyMeters,
  }) : violations = List.unmodifiable(violations),
       caveats = List.unmodifiable(caveats);

  final DateTime from;
  final DateTime to;
  Duration get duration => to.difference(from);
  final SectionStatus status;

  /// Alle verletzten Regeln; leer außer bei [SectionStatus.rejected].
  final List<SectionViolation> violations;
  final List<SectionCaveat> caveats;

  bool get isUsable => status != SectionStatus.rejected;
  bool get isProvisional => status == SectionStatus.provisional;

  /// PAR-024: 1 für frühe Abschnitte, `lateWeight` ab Minute 30; 0 bei einem
  /// abgelehnten Abschnitt (geht nicht ein).
  final double weight;

  /// PAR-006/PAR-030: Strecke durch Zeit des Abschnitts in m/min.
  final double? speedMetersPerMinute;

  /// Mittel der 30-s-Pulsmediane im Abschnitt (bpm).
  final double? meanHeartRate;

  /// Belastung `r` aus [meanHeartRate]; `null` ohne Puls oder Basis.
  final double? relativeLoad;

  /// Für die Formel einzusetzende Steigung `G` (Anteil, 0,02 = 2 %), nach
  /// PAR-027 bereits auf 0 gesetzt, wo sie nicht zählt.
  final double gradient;
  final GradientBasis gradientBasis;

  /// Zurückgelegte Strecke aus den akzeptierten Positionen (m).
  final double? distanceMeters;

  /// PAR-025: Median der gemeldeten GPS-Genauigkeit im Abschnitt (m); `null`,
  /// wenn keine Genauigkeit gemeldet wurde. Geht in das Gewicht ein (PAR-033).
  final double? gpsMedianAccuracyMeters;

  bool violates(SectionRule rule) => violations.any((v) => v.rule == rule);

  @override
  String toString() =>
      'EvaluatedSection($from..$to ${status.name} '
      '${violations.map((v) => v.rule.name).toList()})';
}

/// Grund, warum Zeit nicht in einen Abschnitt eingegangen ist.
enum ExclusionKind {
  /// PAR-011: Einschwingzeit nach Start, Pause oder Tempowechsel.
  settling,

  /// Pause (manuell oder erkannt), PAR-014/PAR-015.
  pause,
}

class ExcludedSpan {
  const ExcludedSpan({required this.span, required this.kind});
  final TimeSpan span;
  final ExclusionKind kind;
}

/// Ergebnis der Abschnittsauswahl: bewertete Abschnitte und ausgeschlossene
/// Zeiträume. Kein Zeitraum verschwindet still.
class SectionSelection {
  SectionSelection({
    required this.parameterVersion,
    required List<EvaluatedSection> sections,
    required List<ExcludedSpan> excluded,
  }) : sections = List.unmodifiable(sections),
       excluded = List.unmodifiable(excluded);

  String get method => vo2maxSectionSelectionMethod;
  int get methodVersion => vo2maxSectionSelectionMethodVersion;
  final int parameterVersion;

  /// Alle Abschnitte in Zeitreihenfolge, auch die abgelehnten.
  final List<EvaluatedSection> sections;
  final List<ExcludedSpan> excluded;

  /// Abschnitte, die in die Schätzung eingehen dürfen (auch „vorläufig“).
  List<EvaluatedSection> get usable => [
    for (final s in sections)
      if (s.isUsable) s,
  ];
  List<EvaluatedSection> get rejected => [
    for (final s in sections)
      if (!s.isUsable) s,
  ];
}
