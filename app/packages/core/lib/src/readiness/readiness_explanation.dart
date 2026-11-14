import '../morning/morning_marks.dart' show MorningRmssdMark;
import 'readiness_parameters.dart';
import 'readiness_result.dart';

/// Richtung eines genannten Faktors gegenüber seinem Bezug (PAR-172).
enum ReadinessDirection { lower, higher }

/// Warum Schlaf unter seinem Bezug liegt (PAR-172: „wegen kurzer
/// Schlafdauer“). Folgt aus den Teilskalen: unter 7 h ist die Dauer der Grund,
/// sonst bleibt nur die Effizienz.
enum ReadinessSleepCause { shortDuration, lowEfficiency }

/// Art der Erklärung. Der Schlüssel ist [name]; die Texte setzt die App.
enum ReadinessExplanationCode {
  /// Zahl, mindestens ein Faktor weicht von seinem Bezug ab.
  drivers,

  /// Zahl, nur Schlaf liegt unter seinem Bezug (PAR-172: Grund nennen).
  onlySleepBelow,

  /// Zahl, kein Faktor weicht vom Bezug ab.
  noDeviation,

  /// Keine Zahl: nur fehlende Faktoren, Gründe stehen in Stufe und Tatsachen.
  noNumber,
}

/// Ein genannter Faktor.
class ReadinessDriver {
  const ReadinessDriver({
    required this.id,
    required this.source,
    required this.direction,
    required this.impact,
    this.mark = MorningRmssdMark.none,
    this.estimated = false,
    this.fewMeasurements = false,
    this.sleepCause,
  });

  final ReadinessFactorId id;

  /// Quelle des Faktors (PAR-172: je Faktor).
  final ReadinessFactorSource source;
  final ReadinessDirection direction;

  /// `Gewicht · (S − Bezug)`, vorzeichenbehaftet. Nur zum Ordnen; die Anzeige
  /// nennt keine Prozente oder Punkte.
  final double impact;
  final MorningRmssdMark mark;
  final bool estimated;
  final bool fewMeasurements;

  /// Nur bei Schlaf unter dem Bezug.
  final ReadinessSleepCause? sleepCause;

  @override
  String toString() => 'ReadinessDriver($id, $direction)';
}

/// Faktor mit seinem Gewicht aus FR-0110 (PAR-170).
class ReadinessWeightEntry {
  const ReadinessWeightEntry(this.id, this.weight);
  final ReadinessFactorId id;
  final double weight;

  @override
  String toString() => 'ReadinessWeightEntry($id)';
}

/// Strukturierte Erklärung (PAR-172, PAR-170): Schlüssel und Parameter, keine
/// fertigen Sätze.
class ReadinessExplanation {
  const ReadinessExplanation({
    required this.code,
    required this.drivers,
    required this.used,
    required this.missing,
    required this.cappedWithoutLoad,
  });

  final ReadinessExplanationCode code;

  /// Bis zu zwei Faktoren, größter Betrag zuerst.
  final List<ReadinessDriver> drivers;

  /// Eingegangene Faktoren mit Gewicht (PAR-170: verwendete Gewichte).
  final List<ReadinessWeightEntry> used;

  /// Fehlende Faktoren mit ihrem Gewicht (PAR-170: fehlende Faktoren).
  final List<ReadinessWeightEntry> missing;

  /// Der Wert ist auf 74 begrenzt, weil die Belastung fehlt (PAR-170).
  final bool cappedWithoutLoad;

  @override
  String toString() => 'ReadinessExplanation($code)';
}

/// Gewicht eines Faktors (FR-0110, PAR-170).
double readinessWeightOf(ReadinessFactorId id) => switch (id) {
  ReadinessFactorId.hrv => readinessWeightHrv,
  ReadinessFactorId.restingHeartRate => readinessWeightRestingHr,
  ReadinessFactorId.sleep => readinessWeightSleep,
  ReadinessFactorId.load => readinessWeightLoad,
  ReadinessFactorId.wellbeing => readinessWeightWellbeing,
};

/// Bezug der Abweichung (PAR-172): 60, bei Schlaf 70.
double readinessReferenceOf(ReadinessFactorId id) =>
    id == ReadinessFactorId.sleep
    ? readinessExplanationSleepReference
    : readinessExplanationReference;

/// Baut die Erklärung aus den eingegangenen Faktoren. [sleepHours] ist die
/// Schlafdauer der Hauptschlafphase (für den Grund bei kurzem Schlaf),
/// [hasNumber] ob eine Zahl entstand, [capped] ob PAR-170 gekappt hat.
ReadinessExplanation explainReadinessFactors({
  required List<ReadinessFactorValue> factors,
  required List<ReadinessFactorId> missing,
  required double? sleepHours,
  required bool hasNumber,
  required bool capped,
}) {
  final used = [for (final f in factors) ReadinessWeightEntry(f.id, f.weight)];
  final miss = [
    for (final id in missing) ReadinessWeightEntry(id, readinessWeightOf(id)),
  ];
  if (!hasNumber) {
    return ReadinessExplanation(
      code: ReadinessExplanationCode.noNumber,
      drivers: const [],
      used: used,
      missing: miss,
      cappedWithoutLoad: false,
    );
  }
  final all = <ReadinessDriver>[];
  for (final f in factors) {
    final impact = f.weight * (f.score - readinessReferenceOf(f.id));
    if (impact == 0) continue;
    // PAR-172, PAR-168: TSB nur als Grund für einen niedrigeren Wert. Die
    // Kappung der Teilskala auf 60 macht das schon unmöglich; die Prüfung
    // hält es auch bei einer späteren Änderung ein.
    if (f.id == ReadinessFactorId.load && impact > 0) continue;
    all.add(
      ReadinessDriver(
        id: f.id,
        source: f.source,
        direction: impact < 0
            ? ReadinessDirection.lower
            : ReadinessDirection.higher,
        impact: impact,
        mark: f.mark,
        estimated: f.estimated,
        fewMeasurements: f.fewMeasurements,
        sleepCause:
            f.id == ReadinessFactorId.sleep && impact < 0 && sleepHours != null
            ? (sleepHours < readinessSleepAnchorHours
                  ? ReadinessSleepCause.shortDuration
                  : ReadinessSleepCause.lowEfficiency)
            : null,
      ),
    );
  }
  // Größter Betrag zuerst; bei Gleichstand die Reihenfolge der Faktoren.
  all.sort((a, b) {
    final c = b.impact.abs().compareTo(a.impact.abs());
    return c != 0 ? c : a.id.index.compareTo(b.id.index);
  });
  var drivers = all.take(readinessExplanationMaxDrivers).toList();

  final below = [
    for (final d in all)
      if (d.direction == ReadinessDirection.lower) d,
  ];
  final onlySleepBelow =
      below.length == 1 && below.single.id == ReadinessFactorId.sleep;
  if (onlySleepBelow && !drivers.contains(below.single)) {
    drivers = [drivers.first, below.single];
  }
  return ReadinessExplanation(
    code: onlySleepBelow
        ? ReadinessExplanationCode.onlySleepBelow
        : (drivers.isEmpty
              ? ReadinessExplanationCode.noDeviation
              : ReadinessExplanationCode.drivers),
    drivers: List.unmodifiable(drivers),
    used: List.unmodifiable(used),
    missing: List.unmodifiable(miss),
    cappedWithoutLoad: capped,
  );
}
