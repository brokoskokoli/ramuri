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

  /// HFmax nur, wenn sie gesetzt und größer 0 ist; sonst gilt sie als fehlend
  /// (ein Vorgabewert 0 oder negativ ist keine Messung, FR-0056).
  int? get usableMaxBpm => _positive(maxBpm);

  /// Ruhepuls nur, wenn gesetzt und größer 0; sonst fehlend.
  int? get usableRestingBpm => _positive(restingBpm);

  static int? _positive(int? v) => v != null && v > 0 ? v : null;

  /// HFmax stammt aus einer Altersnäherung und ist eine Schätzung (OQ-0012).
  final bool maxIsEstimated;
}
