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
  /// Legt die Werte neu an: `original` und `current` mit gleichem Inhalt, alle
  /// in einer Transaktion. Existiert der Schlüssel für den Besitzer schon, ist
  /// es `rejected` (ein Original wird nie ersetzt); doppelte Schlüssel in
  /// [values] ebenso; unbekannter Lauf `notFound`.
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values);

  /// Tauscht `current` der genannten Schlüssel in einer Transaktion; `original`
  /// bleibt (ADR-0004 Punkt 5). Fehlt für einen Schlüssel das Original, ist es
  /// `notFound` und nichts ändert sich; doppelte Schlüssel `rejected`.
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values);

  /// Alle Werte des Besitzers, nach Schlüssel sortiert.
  Future<List<ValuePair>> read(ValueOwner owner);
}
