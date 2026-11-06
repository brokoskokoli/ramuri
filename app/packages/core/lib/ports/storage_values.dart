import '../src/fitness/vo2max_estimator.dart';
import '../src/fitness/vo2max_section_types.dart';

/// Zu wem ein berechneter Wert gehört: einem Lauf oder einem Tag (ISO-Datum
/// `JJJJ-MM-TT`, etwa ATL/CTL; die Zeitzone legt der Aufrufer fest).
class ValueOwner {
  const ValueOwner.run(int this.runId) : day = null;
  const ValueOwner.day(String this.day) : runId = null;

  final int? runId;
  final String? day;

  @override
  bool operator ==(Object other) =>
      other is ValueOwner && other.runId == runId && other.day == day;

  @override
  int get hashCode => Object.hash(runId, day);
}

/// Qualitätsstufe eines Werts. Bei `undeterminable` ist der Wert `null`.
enum ValueQuality { provisional, sufficient, good, undeterminable }

/// Ein bewerteter Abschnitt eines Werts (FR-0073): Zeitraum, GPS-Median,
/// Gewicht (PAR-033), Spätfaktor (PAR-024), Status, Gründe und Schätzwert.
/// Die Dauer folgt aus Anfang und Ende.
class ValueSection {
  ValueSection({
    required this.start,
    required this.end,
    required this.weight,
    required this.lateFactor,
    required this.status,
    List<String> reasons = const [],
    this.gpsMedianAccuracyMeters,
    this.discard,
    this.oxygenDemand,
    this.estimate,
  }) : reasons = List.unmodifiable(reasons);

  /// Übernimmt einen Abschnitt samt Schätzung des Schätzers (WP09 B1). Gründe:
  /// Namen der verletzten Regeln, dann der Einschränkungen.
  factory ValueSection.fromEstimate(SectionEstimate e) {
    final s = e.section;
    return ValueSection(
      start: s.from,
      end: s.to,
      weight: e.weight,
      lateFactor: s.weight,
      status: s.status,
      reasons: [
        for (final v in s.violations) v.rule.name,
        for (final c in s.caveats) c.name,
      ],
      gpsMedianAccuracyMeters: s.gpsMedianAccuracyMeters,
      discard: e.discard,
      oxygenDemand: e.oxygenDemand,
      estimate: e.vo2max,
    );
  }

  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);

  /// PAR-025: Median der gemeldeten GPS-Genauigkeit (m); `null` ohne Angabe.
  final double? gpsMedianAccuracyMeters;

  /// PAR-033: Gewicht im gewichteten Median (Minuten bis 10 × GPS-Faktor ×
  /// Spätfaktor); 0 bei abgelehntem Abschnitt.
  final double weight;

  /// PAR-024: Spätfaktor.
  final double lateFactor;

  final SectionStatus status;

  /// Namen der verletzten Regeln ([SectionRule]) und Einschränkungen
  /// ([SectionCaveat]).
  final List<String> reasons;

  /// Grund, warum die Schätzung nicht einging; `null` = ging ein oder
  /// Abschnitt abgelehnt (dann steht der Grund in [reasons]).
  final EstimateDiscard? discard;

  /// FR-0069: Sauerstoffbedarf (ml/kg/min); `null`, wenn nicht bestimmbar.
  final double? oxygenDemand;

  /// FR-0071: Schätzwert dieses Abschnitts (ml/kg/min); `null`, wenn `r` fehlt.
  final double? estimate;
}

/// Berechneter Wert mit den Angaben aus FR-0053.
class ComputedValue {
  const ComputedValue({
    required this.key,
    required this.value,
    required this.unit,
    required this.computedAt,
    required this.measurementCount,
    required this.sources,
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.quality,
    this.dataFrom,
    this.dataTo,
    this.sections = const [],
  });

  final String key;
  final double? value;
  final String unit;
  final DateTime computedAt;
  final DateTime? dataFrom;
  final DateTime? dataTo;
  final int measurementCount;

  /// Quellgeräte und -quellen.
  final List<String> sources;
  final String method;
  final int methodVersion;
  final int parameterVersion;
  final ValueQuality quality;

  /// Bewertete Abschnitte (FR-0073), in der Reihenfolge der Abschnitte. Sie
  /// werden mit dem Wert in derselben Transaktion gespeichert; die des
  /// `original` bleiben unverändert.
  final List<ValueSection> sections;
}

/// Ursprünglicher und aktueller Stand eines Werts (ADR-0004 Punkt 4).
class ValuePair {
  const ValuePair({required this.original, required this.current});

  final ComputedValue original;
  final ComputedValue current;
}

/// Berechnete Werte: je Wert und Besitzer genau ein `original` (unveränderlich)
/// und ein `current`.
abstract interface class ComputedValueStore {
  /// Legt die Werte neu an: `original` und `current` mit gleichem Inhalt (samt
  /// Abschnitten), alle in einer Transaktion; ein ungültiger Abschnitt
  /// (Ende vor Anfang, negative Zahl) ist `rejected` und nichts wird geschrieben. Existiert der Schlüssel für den Besitzer schon, ist
  /// es `rejected` (ein Original wird nie ersetzt); doppelte Schlüssel in
  /// [values] ebenso; unbekannter Lauf `notFound`.
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values);

  /// Tauscht `current` samt Abschnitten der genannten Schlüssel in einer
  /// Transaktion; `original` samt Abschnitten bleibt (ADR-0004 Punkt 5). Fehlt für einen Schlüssel das Original, ist es
  /// `notFound` und nichts ändert sich; doppelte Schlüssel `rejected`.
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values);

  /// Alle Werte des Besitzers, nach Schlüssel sortiert.
  Future<List<ValuePair>> read(ValueOwner owner);
}
