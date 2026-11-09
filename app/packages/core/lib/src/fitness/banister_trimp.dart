import 'dart:math' as math;

import 'algorithm_variant.dart';
import 'edwards_trimp.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'heart_rate_time.dart';
import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/movement_time_processor.dart';

/// Koeffizienten-Angabe des Profils (FR-0002, FR-0197): wählt die Konstanten
/// des Banister-TRIMP. Gespeichert als Settings-Wert [storageValue]; ohne
/// Angabe fehlt der Schlüssel (`null`).
///
/// Zahlen als benannte Parameter (FR-0197, OQ-0053):
/// `TRIMP = Σ t[min] · r · k · e^(b·r)`.
/// Formel und b sind belegt (Banister/Morton/Fitz-Clarke 1992, K43). k nur
/// sekundär belegt (Banister 1991), K43.
enum LoadCoefficients {
  male(storageValue: 'male', k: 0.64, b: 1.92),
  female(storageValue: 'female', k: 0.86, b: 1.67);

  const LoadCoefficients({
    required this.storageValue,
    required this.k,
    required this.b,
  });

  final String storageValue;

  /// Faktor k; nur sekundär belegt (Banister 1991), K43.
  final double k;

  /// Exponent b (Banister/Morton/Fitz-Clarke 1992, K43).
  final double b;

  /// Gespeicherter Wert -> Angabe; unbekannt oder `null` -> `null` (fehlt).
  static LoadCoefficients? fromStorage(String? value) {
    for (final c in values) {
      if (c.storageValue == value) return c;
    }
    return null;
  }
}

/// Banister-TRIMP (FR-0197, FR-0091), Kategorie A: `Σ t[min] · r · k · e^(b·r)`
/// mit `r` nach FR-0060 (`HeartRateReserve`, ungeklemmt). Pulsabdeckung,
/// Lücken und Mindestabdeckung wie [EdwardsTrimp] (PAR-010, OQ-0051); braucht
/// HFmax und Ruhepuls. Pro Koeffizientenangabe eine eigene Variante, damit
/// Methode und Version an jedem Wert die Konstanten festlegen.
class BanisterTrimp extends LoadModel {
  const BanisterTrimp(this.coefficients);

  final LoadCoefficients coefficients;

  static const methodIdMale = 'banister-trimp-male';
  static const methodIdFemale = 'banister-trimp-female';

  /// Kennung am Wert, wenn das Profil Banister gewählt, aber nicht anwendbar
  /// ist (Koeffizienten oder Ruhepuls fehlen): es gibt dann kein Modell mit
  /// festen Konstanten, der Wert steht als „nicht verfügbar“.
  static const methodIdUnresolved = 'banister-trimp';

  static const _reserve = HeartRateReserve();

  @override
  String get method => switch (coefficients) {
    LoadCoefficients.male => methodIdMale,
    LoadCoefficients.female => methodIdFemale,
  };
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.established;

  /// Gewicht je Minute bei Reserveanteil [r]: `r · k · e^(b·r)`.
  double weightPerMinute(double r) =>
      r * coefficients.k * math.exp(coefficients.b * r);

  @override
  FitnessResult<TrimpResult> compute({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) {
    requireSameParameterVersion(heartRate: heartRate, movement: movement, p: p);
    FitnessUnavailable<TrimpResult> no(UnavailableReason reason) =>
        FitnessUnavailable(
          reason: reason,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );

    final basisReason = _reserve.check(basis, p);
    if (basisReason != null) return no(basisReason);
    final max = basis.usableMaxBpm!;
    final rest = basis.usableRestingBpm!;
    final time = heartRateTimeByBpm(
      heartRate: heartRate,
      movement: movement,
      p: p,
    );
    if (time.movingMicros == 0) return no(UnavailableReason.noMovingTime);
    if (time.coveredMicros == 0) {
      return no(
        heartRate.acceptedValues.isEmpty
            ? UnavailableReason.noHeartRate
            : UnavailableReason.insufficientCoverage,
      );
    }
    if (time.coveredMicros * FitnessParameters.percent <
        time.movingMicros * p.minCoveragePercent) {
      return no(UnavailableReason.insufficientCoverage);
    }

    var weighted = 0.0;
    var hint = false;
    for (final e in time.microsByBpm.entries) {
      final r = (e.key - rest) / (max - rest);
      weighted += e.value * weightPerMinute(r);
      hint = hint || e.key / max > p.hintAboveShare;
    }
    return FitnessAvailable(
      value: TrimpResult(
        points: weighted / Duration.microsecondsPerMinute,
        incomplete:
            time.coveredMicros * FitnessParameters.percent <
            time.movingMicros * p.fullCoveragePercent,
        coveredMicros: time.coveredMicros,
        movingMicros: time.movingMicros,
        aboveHint: hint,
      ),
      method: method,
      methodVersion: methodVersion,
      parameterVersion: p.parameterVersion,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}
