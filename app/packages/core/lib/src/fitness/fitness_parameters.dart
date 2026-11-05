import '../preprocessing/preprocessing_parameters.dart';

/// Schwellen der Fitness- und Belastungsverfahren (docs/model-parameters.md,
/// Version 3, PAR-018, PAR-019, FR-0062, FR-0092, OQ-0014, OQ-0051).
///
/// Keine dieser Zahlen steht außerhalb dieser Klasse. Verfahren bekommen den
/// Satz als Argument; seine Version ist [currentParameterVersion].
class FitnessParameters {
  const FitnessParameters({
    required this.parameterVersion,
    this.minHeartRateReserveBpm = 50,
    this.reserveZoneCount = 5,
    this.reserveZoneBounds = const [0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
    this.trimpZoneLowerBounds = const [0.5, 0.6, 0.7, 0.8, 0.9],
    this.trimpWeights = const [1, 2, 3, 4, 5],
    this.hintAboveShare = 1.0,
    this.minCoveragePercent = 80,
    this.fullCoveragePercent = 100,
  });

  /// Die Startwerte aus Version 3 von docs/model-parameters.md.
  const FitnessParameters.v3()
    : this(parameterVersion: currentParameterVersion);

  /// Version des Parametersatzes (ADR-0004 P.3).
  final int parameterVersion;

  /// PAR-019: kleinste Herzfrequenzreserve (bpm); genau dieser Wert zählt
  /// noch als verfügbar.
  final int minHeartRateReserveBpm;

  /// FR-0061: Anzahl der Reservezonen; Grenzen haben einen Eintrag mehr.
  final int reserveZoneCount;

  /// FR-0062: Standardgrenzen der Reservezonen als Anteil der Reserve,
  /// aufsteigend; die erste ist die Untergrenze von Zone 1.
  final List<double> reserveZoneBounds;

  /// FR-0092: Untergrenzen der TRIMP-Zonen als Anteil von HFmax (inklusiv,
  /// OQ-0014). Darunter gilt Gewicht 0.
  final List<double> trimpZoneLowerBounds;

  /// FR-0092: Gewicht je TRIMP-Zone, gleiche Reihenfolge wie die Grenzen.
  final List<int> trimpWeights;

  /// OQ-0014: Anteil, ab dem darüber ein Hinweis erscheint (exklusiv: genau
  /// dieser Wert liegt noch ohne Hinweis in der obersten Zone).
  final double hintAboveShare;

  /// OQ-0051: Mindestabdeckung der Bewegungszeit mit Puls in ganzen Prozent;
  /// genau dieser Wert ist noch unvollständig bewertet, darunter nicht.
  final int minCoveragePercent;

  /// OQ-0051: Abdeckung in Prozent, ab der ein Ergebnis vollständig ist.
  final int fullCoveragePercent;
}
