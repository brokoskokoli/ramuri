/// Kategorie eines Verfahrens nach NFR-0002.
enum AlgorithmCategory {
  /// A: etabliertes Verfahren.
  established,

  /// B: Heuristik.
  heuristic,

  /// C: kalibriertes Verfahren.
  calibrated,
}

/// Kennung eines Verfahrens (NFR-0001, ADR-0004 P.3). Je Algorithmenfamilie
/// erbt ein Interface davon und gibt die Berechnung als reine Funktion aus
/// Eingabe und Parametersatz vor.
abstract class AlgorithmVariant {
  const AlgorithmVariant();

  /// Kennung des Verfahrens, nicht leer.
  String get method;

  /// Version des Verfahrens, mindestens 1.
  int get methodVersion;

  AlgorithmCategory get category;
}

/// Algorithmenfamilie, z. B. Belastung oder Zonen. Der Typparameter bindet
/// die Varianten an das Interface der Familie.
class AlgorithmFamily<V extends AlgorithmVariant> {
  const AlgorithmFamily(this.id);

  /// Eindeutige Kennung der Familie.
  final String id;

  @override
  String toString() => 'AlgorithmFamily($id)';
}
