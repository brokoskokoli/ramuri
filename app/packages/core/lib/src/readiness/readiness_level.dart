import 'readiness_deviation.dart';
import 'readiness_parameters.dart';
import 'readiness_precedence.dart';
import 'readiness_result.dart';

/// Stufe der Datenlage (PAR-147 bis PAR-150). Beschreibt nur die Datenlage,
/// keine Genauigkeit (PAR-159: keine Prozente).
enum ReadinessLevel { notDeterminable, provisional, sufficient, good }

/// Gründe für eine Stufe (PAR-159). Der Schlüssel ist [name]; die Texte setzt
/// die App.
enum ReadinessLevelReasonCode {
  // nicht bestimmbar (PAR-147)
  hrvNoSeries,
  hrvNoValueToday,
  hrvTooFewInWindow,
  hrvTooFewReference,
  hrvMadTooSmall,
  hrvCameraLocked,
  sleepMissing,

  // vorläufig (PAR-148) und ausreichend (PAR-149): Bedingung der nächsthöheren
  // Stufe nicht erfüllt
  hrvReferenceBelowSufficient,
  restingHrMissing,
  hrvReferenceBelowGood,
  sleepPhasesMissing,
  loadMissing,
  sourceTooShort,

  /// Hinweis aus PAR-148/PAR-161K, ändert die Stufe nicht.
  fewMeasurements,
}

/// Ein Grund mit Parametern: [count] ist der Istwert (Messungen bzw. Tage),
/// [required] die verlangte Zahl. [toString] nennt sie nicht.
class ReadinessLevelReason {
  const ReadinessLevelReason(this.code, {this.count, this.required});

  final ReadinessLevelReasonCode code;
  final int? count;
  final int? required;

  Map<String, Object?> toJson() => {
    'code': code.name,
    'count': ?count,
    'required': ?required,
  };

  @override
  bool operator ==(Object other) =>
      other is ReadinessLevelReason &&
      other.code == code &&
      other.count == count &&
      other.required == required;

  @override
  int get hashCode => Object.hash(code, count, required);

  @override
  String toString() => 'ReadinessLevelReason($code)';
}

ReadinessLevelReasonCode _noZCode(NoDeviationReason r) => switch (r) {
  NoDeviationReason.noSeries => ReadinessLevelReasonCode.hrvNoSeries,
  NoDeviationReason.noValueToday => ReadinessLevelReasonCode.hrvNoValueToday,
  NoDeviationReason.tooFewInWindow =>
    ReadinessLevelReasonCode.hrvTooFewInWindow,
  NoDeviationReason.tooFewReference =>
    ReadinessLevelReasonCode.hrvTooFewReference,
  NoDeviationReason.madTooSmall => ReadinessLevelReasonCode.hrvMadTooSmall,
};

/// Stufe und Gründe. [factors] sind die eingegangenen Faktoren, [hrv] die
/// Bewertung der HRV nach K-1, [hrvCameraLocked] ob eine gesperrte oder nicht
/// eingeschaltete Kamera-HRV mit `z` vorlag (PAR-147). Fehlt der Schlaf, steht
/// das in [factors] (OQ-0006).
({ReadinessLevel level, List<ReadinessLevelReason> reasons}) readinessLevelOf({
  required List<ReadinessFactorValue> factors,
  required FactorEvaluation hrv,
  required bool hrvCameraLocked,
  required int hrvSourceSpanDays,
}) {
  ReadinessFactorValue? f(ReadinessFactorId id) {
    for (final x in factors) {
      if (x.id == id) return x;
    }
    return null;
  }

  final hrvF = f(ReadinessFactorId.hrv);
  final rhrF = f(ReadinessFactorId.restingHeartRate);
  final sleepF = f(ReadinessFactorId.sleep);
  final few = factors.any((x) => x.fewMeasurements);
  final hint = [
    if (few)
      const ReadinessLevelReason(ReadinessLevelReasonCode.fewMeasurements),
  ];

  // PAR-147: keine HRV mit `z` (oder gesperrte Kamera) oder kein Schlaf.
  if (hrvF == null || sleepF == null) {
    final reasons = <ReadinessLevelReason>[];
    if (hrvF == null) {
      DeviationResult? best;
      for (final o in hrv.others) {
        if (o.reason == null) continue;
        if (best == null || o.referenceCount > best.referenceCount) best = o;
      }
      if (best != null) {
        final code = _noZCode(best.reason!);
        reasons.add(
          ReadinessLevelReason(
            code,
            count: code == ReadinessLevelReasonCode.hrvTooFewReference
                ? best.referenceCount
                : null,
            required: code == ReadinessLevelReasonCode.hrvTooFewReference
                ? readinessMinReferenceValues
                : null,
          ),
        );
      }
      if (hrvCameraLocked) {
        reasons.add(
          const ReadinessLevelReason(ReadinessLevelReasonCode.hrvCameraLocked),
        );
      }
      if (reasons.isEmpty) {
        reasons.add(
          const ReadinessLevelReason(ReadinessLevelReasonCode.hrvNoSeries),
        );
      }
    }
    if (sleepF == null) {
      reasons.add(
        const ReadinessLevelReason(ReadinessLevelReasonCode.sleepMissing),
      );
    }
    return (level: ReadinessLevel.notDeterminable, reasons: reasons);
  }

  final n = hrvF.referenceCount;
  // PAR-149: ausreichend.
  final sufficient = n >= readinessSufficientHrvReference && rhrF != null;
  if (!sufficient) {
    return (
      level: ReadinessLevel.provisional,
      reasons: [
        if (n < readinessSufficientHrvReference)
          ReadinessLevelReason(
            ReadinessLevelReasonCode.hrvReferenceBelowSufficient,
            count: n,
            required: readinessSufficientHrvReference,
          ),
        if (rhrF == null)
          const ReadinessLevelReason(ReadinessLevelReasonCode.restingHrMissing),
        ...hint,
      ],
    );
  }
  // PAR-150: gut.
  final phases =
      sleepF.source == ReadinessFactorSource.healthConnect && !sleepF.estimated;
  final unmet = [
    if (n < readinessGoodHrvReference)
      ReadinessLevelReason(
        ReadinessLevelReasonCode.hrvReferenceBelowGood,
        count: n,
        required: readinessGoodHrvReference,
      ),
    if (!phases)
      const ReadinessLevelReason(ReadinessLevelReasonCode.sleepPhasesMissing),
    if (f(ReadinessFactorId.load) == null)
      const ReadinessLevelReason(ReadinessLevelReasonCode.loadMissing),
    if (hrvSourceSpanDays < readinessGoodSourceDays)
      ReadinessLevelReason(
        ReadinessLevelReasonCode.sourceTooShort,
        count: hrvSourceSpanDays,
        required: readinessGoodSourceDays,
      ),
  ];
  return (
    level: unmet.isEmpty ? ReadinessLevel.good : ReadinessLevel.sufficient,
    reasons: [...unmet, ...hint],
  );
}

/// Tage vom ersten gültigen Tageswert der Reihe bis [today] (PAR-150). [days]
/// sind die Ortstage (UTC-Datum) der gültigen Tageswerte genau dieser Reihe;
/// leer ergibt 0.
int readinessSourceSpanDays(Iterable<DateTime> days, DateTime today) {
  DateTime? first;
  for (final d in days) {
    if (first == null || d.isBefore(first)) first = d;
  }
  if (first == null) return 0;
  final t = DateTime.utc(today.year, today.month, today.day);
  final f = DateTime.utc(first.year, first.month, first.day);
  final n = t.difference(f).inDays;
  return n < 0 ? 0 : n;
}
