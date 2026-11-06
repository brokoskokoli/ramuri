import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';

/// Kennung und Version der Langzeitglättung (ADR-0004 P.3). Kategorie B
/// (Heuristik): α, Neustart und Stufen sind eigene Wahl (PAR-034, PAR-035,
/// PAR-041 bis PAR-043).
const String vo2maxLongTermMethod = 'vo2max-long-term-ema';
const int vo2maxLongTermMethodVersion = 1;

/// Familie Langzeitwert der VO₂max (FR-0078).
abstract class Vo2maxLongTerm extends AlgorithmVariant {
  const Vo2maxLongTerm();

  /// Langzeitwert aus der Folge der Laufergebnisse [runs] (beliebige
  /// Reihenfolge; sie werden nach Laufende, `metadata.dataTo`, geordnet).
  /// [now] ist der Berechnungszeitpunkt; der Aufrufer liest ihn aus der
  /// Uhr-Schnittstelle (`Clock.now()`), diese Familie importiert keine Ports
  /// (algorithm_framework_test, NFR-0005). Läufe der Stufe „nicht bestimmbar“
  /// ändern nichts (FR-0080). Ohne einen verwertbaren Lauf ist das Ergebnis
  /// „nicht bestimmbar“.
  AdvancedFitnessValue<double> compute({
    required List<AdvancedFitnessValue<double>> runs,
    required FitnessParameters p,
    required DateTime now,
  });
}

/// Exponentielle Glättung `V[t] = V[t-1] + α·(V[neu] - V[t-1])` (FR-0079).
class SmoothedVo2maxLongTerm extends Vo2maxLongTerm {
  const SmoothedVo2maxLongTerm();

  @override
  String get method => vo2maxLongTermMethod;
  @override
  int get methodVersion => vo2maxLongTermMethodVersion;
  @override
  AlgorithmCategory get category => vo2maxLongTermCategory;

  /// PAR-034: α für die Stufe [tier] beim Lauf Nummer [n] (>= 1).
  /// „Nicht bestimmbar“ ergibt 0.
  static double alpha(QualityTier tier, int n, Vo2maxParameters p) {
    if (n < 1) throw ArgumentError.value(n, 'n', 'muss mindestens 1 sein');
    double max(double a, double b) => a > b ? a : b;
    return switch (tier) {
      QualityTier.good => max(p.alphaGoodMin, 1 / n),
      QualityTier.sufficient => max(p.alphaSufficientMin, 1 / n),
      QualityTier.preliminary => max(
        p.alphaPreliminaryMin,
        1 / (p.alphaPreliminaryDivisorFactor * n),
      ),
      QualityTier.notDeterminable => 0,
    };
  }

  /// PAR-041 bis PAR-043 für die verwertbaren Läufe [usable] (Stufe und
  /// Zeit) zum Zeitpunkt [now]. PAR-041 geht vor.
  static QualityTier tierFor(
    List<({DateTime at, QualityTier tier})> usable,
    DateTime now,
    Vo2maxParameters p,
  ) {
    bool within(DateTime at, Duration w) =>
        !at.isAfter(now) && !at.isBefore(now.subtract(w));
    final recent = usable
        .where((r) => within(r.at, p.longTermRecentWindow))
        .toList();
    if (recent.length < p.longTermMinRecentRuns) return QualityTier.preliminary;
    final wide = usable
        .where((r) => within(r.at, p.longTermGoodWindow))
        .toList();
    final goodWide = wide.where((r) => r.tier == QualityTier.good).length;
    if (wide.length >= p.longTermGoodMinRuns &&
        goodWide >= p.longTermGoodMinGoodRuns) {
      return QualityTier.good;
    }
    final quality = recent
        .where(
          (r) => r.tier == QualityTier.sufficient || r.tier == QualityTier.good,
        )
        .length;
    if (quality >= p.longTermSufficientMinQualityRuns) {
      return QualityTier.sufficient;
    }
    // Lücke im Spec: 3 Läufe in 6 Wochen, aber weniger als 2 "ausreichend"
    // oder besser. PAR-042 greift nicht; "vorläufig" ist die einzige Stufe
    // darunter.
    return QualityTier.preliminary;
  }

  @override
  AdvancedFitnessValue<double> compute({
    required List<AdvancedFitnessValue<double>> runs,
    required FitnessParameters p,
    required DateTime now,
  }) {
    final v = p.vo2max;
    final usable = [
      for (final r in runs)
        if (r.metadata.tier != QualityTier.notDeterminable && r.value != null)
          r,
    ]..sort((a, b) => a.metadata.dataTo.compareTo(b.metadata.dataTo));

    double? value;
    var n = 0;
    DateTime? last;
    for (final r in usable) {
      final at = r.metadata.dataTo;
      if (last == null) {
        n = 1;
        value = r.value;
      } else {
        n = at.difference(last) > v.restartAfter ? v.restartRunNumber : n + 1;
        value = value! + alpha(r.metadata.tier, n, v) * (r.value! - value);
      }
      last = at;
    }

    if (value == null) {
      return AdvancedFitnessValue(
        metadata: FitnessValueMetadata(
          calculatedAt: now,
          dataFrom: now,
          dataTo: now,
          usableMeasurements: 0,
          dataSources: const {},
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          tier: QualityTier.notDeterminable,
        ),
        reason: UnavailableReason.insufficientData,
      );
    }

    final tier = tierFor(
      [for (final r in usable) (at: r.metadata.dataTo, tier: r.metadata.tier)],
      now,
      v,
    );
    // Datenzeitraum: verwertbare Läufe im weiteren Fenster; ist keiner
    // darin (veralteter Wert), der letzte verwertbare Lauf.
    final windowStart = now.subtract(v.longTermGoodWindow);
    final inWindow = usable.where((r) {
      final at = r.metadata.dataTo;
      return !at.isAfter(now) && !at.isBefore(windowStart);
    }).toList();
    final basis = inWindow.isEmpty ? [usable.last] : inWindow;
    var from = basis.first.metadata.dataFrom;
    var to = basis.first.metadata.dataTo;
    for (final r in basis) {
      if (r.metadata.dataFrom.isBefore(from)) from = r.metadata.dataFrom;
      if (r.metadata.dataTo.isAfter(to)) to = r.metadata.dataTo;
    }
    return AdvancedFitnessValue(
      metadata: FitnessValueMetadata(
        calculatedAt: now,
        dataFrom: from,
        dataTo: to,
        usableMeasurements: inWindow.length,
        dataSources: {for (final r in basis) ...r.metadata.dataSources},
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        tier: tier,
      ),
      value: value,
    );
  }
}

const vo2maxLongTermFamily = AlgorithmFamily<Vo2maxLongTerm>(
  'vo2max-long-term',
);

/// Kategorie des Langzeitwerts (NFR-0002): B.
const AlgorithmCategory vo2maxLongTermCategory = AlgorithmCategory.heuristic;
