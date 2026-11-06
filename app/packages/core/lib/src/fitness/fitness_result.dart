/// Grund, warum ein Wert nicht verfügbar ist. Ein Fehlen ist nie 0.
enum UnavailableReason {
  /// HFmax fehlt (FR-0060).
  missingMaxHeartRate,

  /// Ruhepuls fehlt (FR-0060).
  missingRestingHeartRate,

  /// HFmax ist nicht größer als der Ruhepuls (PAR-018).
  maxNotAboveResting,

  /// Herzfrequenzreserve unter der Mindestreserve (PAR-019).
  reserveTooSmall,

  /// Keine Herzfrequenz im Lauf (OQ-0051).
  noHeartRate,

  /// Puls deckt zu wenig der Bewegungszeit ab (OQ-0051).
  insufficientCoverage,

  /// Keine Bewegungszeit.
  noMovingTime,

  /// Zu wenige Daten für eine Aussage (Stufe „nicht bestimmbar“).
  insufficientData,

  /// Kein gültiger Abschnitt im Lauf (PAR-037, FR-0073).
  noValidSection,

  /// Alle Abschnittsschätzungen liegen außerhalb des plausiblen Bereichs
  /// (PAR-032).
  allEstimatesImplausible,

  /// Die Schätzungen der Abschnitte streuen zu stark (PAR-037, FR-0077).
  spreadTooHigh,

  /// Das aktuelle 4-Wochen-Fenster erreicht die Mindestmenge nicht
  /// (PAR-046).
  currentWindowTooSmall,

  /// Das Vergleichsfenster erreicht die Mindestmenge nicht (PAR-046).
  referenceWindowTooSmall,
}

/// Berechneter Wert oder „nicht verfügbar“ mit Grund; beides nennt die
/// Variante und die Parameterversion (NFR-0001, NFR-0005).
sealed class FitnessResult<T> {
  const FitnessResult({
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    this.maxIsEstimated = false,
  });

  final String method;
  final int methodVersion;
  final int parameterVersion;

  /// HFmax war eine Schätzung (OQ-0012), wird an den Nutzer weitergegeben.
  final bool maxIsEstimated;
}

/// Verfügbarer Wert.
final class FitnessAvailable<T> extends FitnessResult<T> {
  const FitnessAvailable({
    required this.value,
    required super.method,
    required super.methodVersion,
    required super.parameterVersion,
    super.maxIsEstimated,
  });

  final T value;
}

/// Nicht verfügbar, mit Grund; kein Wert, nie 0.
final class FitnessUnavailable<T> extends FitnessResult<T> {
  const FitnessUnavailable({
    required this.reason,
    required super.method,
    required super.methodVersion,
    required super.parameterVersion,
    super.maxIsEstimated,
  });

  final UnavailableReason reason;
}

/// Qualitätsstufe fortgeschrittener Werte (PAR-036 bis PAR-043). Die Vergabe
/// macht WP09, hier steht nur das Modell.
enum QualityTier { preliminary, sufficient, good, notDeterminable }

/// Die sieben Angaben zu einem fortgeschrittenen Wert (FR-0053) plus die
/// Parameterversion (ADR-0004 P.3).
class FitnessValueMetadata {
  FitnessValueMetadata({
    required this.calculatedAt,
    required this.dataFrom,
    required this.dataTo,
    required this.usableMeasurements,
    required Set<String> dataSources,
    required this.method,
    required this.methodVersion,
    required this.parameterVersion,
    required this.tier,
  }) : dataSources = Set.unmodifiable(dataSources) {
    if (method.trim().isEmpty) {
      throw ArgumentError.value(method, 'method', 'darf nicht leer sein');
    }
    if (methodVersion < 1) {
      throw ArgumentError.value(methodVersion, 'methodVersion', 'zu klein');
    }
    if (usableMeasurements < 0) {
      throw ArgumentError.value(usableMeasurements, 'usableMeasurements');
    }
    if (dataTo.isBefore(dataFrom)) {
      throw ArgumentError.value(dataTo, 'dataTo', 'liegt vor dataFrom');
    }
  }

  /// Berechnungszeitpunkt (kommt als Eingabe, keine Uhr).
  final DateTime calculatedAt;

  /// Datenzeitraum.
  final DateTime dataFrom;
  final DateTime dataTo;

  /// Anzahl verwertbarer Messungen.
  final int usableMeasurements;

  /// Datenquellen.
  final Set<String> dataSources;

  final String method;
  final int methodVersion;
  final int parameterVersion;
  final QualityTier tier;
}

/// Fortgeschrittener Wert nach FR-0053: Wert oder Grund, immer mit
/// [FitnessValueMetadata]. „Nicht bestimmbar“ hat Grund und keinen Wert, die
/// übrigen Stufen Wert und keinen Grund.
class AdvancedFitnessValue<T> {
  AdvancedFitnessValue({required this.metadata, this.value, this.reason}) {
    final undetermined = metadata.tier == QualityTier.notDeterminable;
    if (undetermined && (reason == null || value != null)) {
      throw ArgumentError(
        'nicht bestimmbar braucht einen Grund und keinen Wert',
      );
    }
    if (!undetermined && (value == null || reason != null)) {
      throw ArgumentError('Stufe ${metadata.tier.name} braucht einen Wert');
    }
  }

  final FitnessValueMetadata metadata;
  final T? value;
  final UnavailableReason? reason;
}
