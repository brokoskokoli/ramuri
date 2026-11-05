/// Basiswerte für Herzfrequenzverfahren (FR-0060, OQ-0012). Fehlende Werte
/// bleiben `null`, nie 0.
class HeartRateBasis {
  const HeartRateBasis({
    this.maxBpm,
    this.restingBpm,
    this.maxIsEstimated = false,
  });

  /// Maximale Herzfrequenz.
  final int? maxBpm;

  /// Ruheherzfrequenz.
  final int? restingBpm;

  /// HFmax stammt aus einer Altersnäherung und ist eine Schätzung (OQ-0012).
  final bool maxIsEstimated;
}
