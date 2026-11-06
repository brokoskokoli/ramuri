import '../src/fitness/fitness_result.dart' show UnavailableReason;
import '../src/fitness/heart_rate_basis.dart';
import '../src/fitness/vo2max_estimator.dart';
import 'storage.dart' show StorageException, StorageFailure;
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

/// Qualitätsstufe eines Werts. Bei `undeterminable` ist der Wert `null` und
/// [ComputedValue.unavailableReason] gesetzt.
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
  /// Namen der verletzten Regeln, dann der Einschränkungen. Eine nicht endliche
  /// Zahl (NaN, unendlich) wird nie gespeichert: Sie wird `null`, und der Grund
  /// steht in `discard` (unbekannt: `incomplete`).
  factory ValueSection.fromEstimate(SectionEstimate e) {
    final s = e.section;
    final demand = e.oxygenDemand;
    final max = e.vo2max;
    final demandBad = demand != null && !demand.isFinite;
    final maxBad = max != null && !max.isFinite;
    return ValueSection(
      start: s.from,
      end: s.to,
      weight: e.weight,
      lateFactor: s.weight,
      status: s.status,
      reasons: _reasonsOf(s),
      gpsMedianAccuracyMeters: s.gpsMedianAccuracyMeters,
      discard:
          e.discard ??
          (demandBad || maxBad ? EstimateDiscard.incomplete : null),
      oxygenDemand: demandBad ? null : demand,
      estimate: maxBad ? null : max,
    );
  }

  /// Ein bewerteter Abschnitt ohne Schätzung: abgelehnte Abschnitte (der
  /// Schätzer rechnet nur verwendbare) und verwendbare, die der Schätzer nicht
  /// mehr erreicht hat (Basis fehlt, kein gültiger Abschnitt). Gewicht (PAR-033)
  /// 0, kein Schätzwert; der Spätfaktor (PAR-024) und die Gründe (verletzte
  /// Regeln, Einschränkungen) kommen aus dem Abschnitt. Warum der Wert fehlt,
  /// steht an [ComputedValue.unavailableReason].
  factory ValueSection.withoutEstimate(EvaluatedSection s) => ValueSection(
    start: s.from,
    end: s.to,
    weight: 0,
    lateFactor: s.weight,
    status: s.status,
    reasons: _reasonsOf(s),
    gpsMedianAccuracyMeters: s.gpsMedianAccuracyMeters,
  );

  static List<String> _reasonsOf(EvaluatedSection s) => [
    for (final v in s.violations) v.rule.name,
    for (final c in s.caveats) c.name,
  ];

  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);

  /// PAR-025: Median der gemeldeten GPS-Genauigkeit (m); `null` ohne Angabe.
  final double? gpsMedianAccuracyMeters;

  /// PAR-033: Gewicht im gewichteten Median (Minuten bis 10 × GPS-Faktor ×
  /// Spätfaktor). 0 bei einem abgelehnten Abschnitt und bei einem verwendbaren
  /// Abschnitt, der nicht einging, weil der Wert nicht bestimmbar ist (Grund in
  /// [ComputedValue.unavailableReason]). Verworfene Abschnitte (unplausibel,
  /// unvollständig, Gewicht null) behalten ihr PAR-033-Gewicht: es ist nur
  /// dann ein Beitrag zum Wert, wenn [discard] `null` ist und [estimate]
  /// gesetzt.
  final double weight;

  /// PAR-024: Spätfaktor.
  final double lateFactor;

  final SectionStatus status;

  /// Namen der verletzten Regeln ([SectionRule]) und Einschränkungen
  /// ([SectionCaveat]).
  final List<String> reasons;

  /// Grund, warum die Schätzung nicht einging; `null` = ging ein, Abschnitt
  /// abgelehnt (dann steht der Grund in [reasons]) oder Wert nicht bestimmbar
  /// (Grund in [ComputedValue.unavailableReason]). Ob ein Abschnitt einging,
  /// zeigt nur [estimate] zusammen mit [weight] größer 0.
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
    this.unavailableReason,
    this.heartRateBasis,
  });

  final String key;

  /// Herzfrequenzbasis, mit der der Wert gerechnet wurde (OQ-0065): HFmax,
  /// HFRuhe und ob HFmax eine Schätzung ist, unverändert und nie neu gelesen.
  /// Eine Neuberechnung rechnet den Wert mit genau dieser Basis, nie mit einer
  /// abgelehnten neuen. `null` = kein Schnappschuss: der Wert braucht keine
  /// Basis, die Zeile stammt aus Schema 1 (Basis unbekannt), oder es ist eine
  /// aerobe Effizienz aus Läufen mit verschiedenen Basen (gemischt; nie gelesen,
  /// die Neuberechnung nimmt die Basis der Laufwerte). Ein Wert in
  /// [heartRateBasis] ist `null`, wenn die Basis ihn nicht kannte; vorhandene
  /// Werte sind größer 0 ([HeartRateBasis.usableMaxBpm]).
  final HeartRateBasis? heartRateBasis;

  /// `null` genau dann, wenn [unavailableReason] gesetzt ist (FR-0068: ein
  /// fehlender Wert nennt immer den Grund).
  final double? value;

  /// Grund, warum der Wert nicht bestimmbar ist (FR-0053, FR-0068, PAR-037);
  /// gespeichert als stabiler Code (Name des Enum).
  final UnavailableReason? unavailableReason;
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
  /// Abschnitten und Grund), alle in einer Transaktion. Ungültige Werte (siehe
  /// [requireStorableValues]: nicht endliche oder negative Zahlen, Ende vor
  /// Anfang, fehlender Wert ohne Grund) sind `rejected`, nichts wird
  /// geschrieben. Existiert der Schlüssel für den Besitzer schon, ist es
  /// `rejected` (ein Original wird nie ersetzt); doppelte Schlüssel in [values]
  /// ebenso; unbekannter Lauf `notFound`.
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values);

  /// Tauscht `current` samt Abschnitten der genannten Schlüssel in einer
  /// Transaktion; `original` samt Abschnitten bleibt (ADR-0004 Punkt 5). Fehlt
  /// für einen Schlüssel das Original, ist es `notFound` und nichts ändert
  /// sich; doppelte Schlüssel und ungültige Werte (siehe [createOriginals])
  /// `rejected`, die Prüfung auf `notFound` kommt zuerst.
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values);

  /// Tauscht `current` samt Abschnitten für mehrere Besitzer in EINER
  /// Transaktion (Neuberechnung, ADR-0004 Punkt 5): Entweder gilt der ganze
  /// neue Stand oder der alte. Fehler wie bei [swapCurrent] (`notFound`,
  /// `rejected`) für irgendeinen Besitzer machen alles rückgängig; `original`
  /// bleibt überall.
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> changes);

  /// Legt neue Werte an ([create], wie [createOriginals]) und tauscht
  /// vorhandene ([swap], wie [swapCurrentAll]), für beliebig viele Besitzer in
  /// EINER Transaktion (Berechnung nach einem Lauf: Laufwert und Tageswerte
  /// gelten ganz oder gar nicht). Jeder Fehler der Einzelregeln macht alles
  /// rückgängig. Derselbe Schlüssel bei demselben Besitzer in [create] und
  /// [swap] ist `rejected` bzw. `notFound`, weil ein Wert nicht zugleich fehlen
  /// und vorhanden sein kann.
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  });

  /// Alle Werte des Besitzers, nach Schlüssel sortiert.
  Future<List<ValuePair>> read(ValueOwner owner);
}

/// Prüft Werte vor dem Speichern; Adapter und Fake rufen dieselbe Regel (die
/// CHECK-Regeln und Trigger der Tabellen sind die zweite Sicherung). Wirft
/// `rejected` bei: nicht endlichem Wert, Wert ohne Grund oder Grund bei Wert
/// (`value == null` genau mit [ComputedValue.unavailableReason]), Abschnitt mit
/// Ende vor Anfang, negativem oder nicht endlichem Gewicht, Spätfaktor oder
/// GPS-Genauigkeit, nicht endlichem Sauerstoffbedarf oder Schätzwert und einer
/// Herzfrequenzbasis mit HFmax oder HFRuhe kleiner oder gleich 0.
void requireStorableValues(List<ComputedValue> values) {
  bool bad(double? x) => x != null && !x.isFinite;
  bool negative(double? x) => x != null && x < 0;
  for (final v in values) {
    if (bad(v.value) || (v.value == null) == (v.unavailableReason == null)) {
      throw const StorageException(StorageFailure.rejected);
    }
    final b = v.heartRateBasis;
    if (b != null &&
        ((b.maxBpm != null && b.maxBpm! <= 0) ||
            (b.restingBpm != null && b.restingBpm! <= 0))) {
      throw const StorageException(StorageFailure.rejected);
    }
    for (final s in v.sections) {
      final invalid =
          s.end.isBefore(s.start) ||
          !s.weight.isFinite ||
          s.weight < 0 ||
          !s.lateFactor.isFinite ||
          s.lateFactor < 0 ||
          bad(s.gpsMedianAccuracyMeters) ||
          negative(s.gpsMedianAccuracyMeters) ||
          bad(s.oxygenDemand) ||
          bad(s.estimate);
      if (invalid) throw const StorageException(StorageFailure.rejected);
    }
  }
}
