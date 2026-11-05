import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/movement_time_processor.dart';
import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'heart_rate_time.dart';

/// Einordnung eines `r`: in einer Zone oder ausdrücklich unter Zone 1
/// (FR-0063).
sealed class ReserveZonePlacement {
  const ReserveZonePlacement({
    required this.aboveHint,
    required this.reserveMethod,
    required this.reserveMethodVersion,
  });

  /// Reserve-Variante, aus der `r` kam (NFR-0005).
  final String reserveMethod;
  final int reserveMethodVersion;

  /// `r` liegt über 100 % (FR-0062, OQ-0014): HFmax zu niedrig oder
  /// Messfehler.
  final bool aboveHint;
}

/// `r` liegt in einer Zone; [zone] ist 1-basiert.
final class InReserveZone extends ReserveZonePlacement {
  const InReserveZone({
    required this.zone,
    required super.aboveHint,
    required super.reserveMethod,
    required super.reserveMethodVersion,
  });
  final int zone;
}

/// `r` liegt unter der Untergrenze von Zone 1 (FR-0063).
final class BelowReserveZone1 extends ReserveZonePlacement {
  const BelowReserveZone1({
    required super.aboveHint,
    required super.reserveMethod,
    required super.reserveMethodVersion,
  });
}

/// Zeit je Reservezone in Mikrosekunden.
class ReserveZoneTimes {
  ReserveZoneTimes({
    required List<int> zoneMicros,
    required this.belowZone1Micros,
    required this.coveredMicros,
    required this.movingMicros,
    required this.aboveHint,
    required this.reserveMethod,
    required this.reserveMethodVersion,
  }) : zoneMicros = List.unmodifiable(zoneMicros);

  /// Index 0 ist Zone 1.
  final List<int> zoneMicros;

  /// Zeit unter Zone 1, nicht in Zone 1 (FR-0063).
  final int belowZone1Micros;

  /// Zeit mit bekanntem Puls (Bewegungszeit ohne Lücken über PAR-010, Halt
  /// höchstens bis zum nächsten Wert, siehe `heartRateTimeByBpm`).
  final int coveredMicros;
  final int movingMicros;

  /// Mindestens ein Puls lag über 100 % der Reserve.
  final bool aboveHint;

  /// Reserve-Variante, aus der `r` kam (NFR-0005).
  final String reserveMethod;
  final int reserveMethodVersion;
}

/// Familie Reservezonen (FR-0061): Zone zu einem Puls und Zeit je Zone.
abstract class ReserveZoneModel extends AlgorithmVariant {
  const ReserveZoneModel();

  /// Zone eines Pulses, mit Kennung der Variante.
  FitnessResult<ReserveZonePlacement> zoneFor(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  );

  FitnessResult<ReserveZoneTimes> timeInZones({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  });
}

/// Reservezonen (FR-0061, FR-0062), Kategorie B: Grenzen kommen aus dem
/// Parametersatz, `r` aus der übergebenen [reserve].
class ReserveZones extends ReserveZoneModel {
  const ReserveZones({required this.reserve});

  static const methodId = 'reserve-zones';

  final HeartRateReserveModel reserve;

  @override
  String get method => methodId;
  @override
  int get methodVersion => 1;
  @override
  AlgorithmCategory get category => AlgorithmCategory.heuristic;

  /// [ArgumentError] bei falscher Anzahl, nicht endlichen, negativen oder
  /// nicht streng aufsteigenden Grenzen (lückenlos, OQ-0065).
  static void validateBounds(FitnessParameters p) {
    final b = p.reserveZoneBounds;
    if (b.length != p.reserveZoneCount + 1) {
      throw ArgumentError.value(b, 'reserveZoneBounds', 'falsche Anzahl');
    }
    for (var i = 0; i < b.length; i++) {
      if (!b[i].isFinite || b[i] < 0) {
        throw ArgumentError.value(b[i], 'reserveZoneBounds', 'ungültig');
      }
      if (i > 0 && b[i] <= b[i - 1]) {
        throw ArgumentError.value(b, 'reserveZoneBounds', 'nicht aufsteigend');
      }
    }
  }

  /// Zone zu einem `r`: Untergrenze inklusiv, Obergrenze exklusiv; über der
  /// obersten Grenze bleibt es Zone [FitnessParameters.reserveZoneCount].
  ReserveZonePlacement _place(double r, FitnessParameters p) {
    final hint = r > p.hintAboveShare;
    final rm = reserve.method;
    final rv = reserve.methodVersion;
    if (r < p.reserveZoneBounds.first) {
      return BelowReserveZone1(
        aboveHint: hint,
        reserveMethod: rm,
        reserveMethodVersion: rv,
      );
    }
    var zone = 1;
    for (var i = 1; i < p.reserveZoneCount; i++) {
      if (r >= p.reserveZoneBounds[i]) zone = i + 1;
    }
    return InReserveZone(
      zone: zone,
      aboveHint: hint,
      reserveMethod: rm,
      reserveMethodVersion: rv,
    );
  }

  @override
  FitnessResult<ReserveZonePlacement> zoneFor(
    HeartRateBasis basis,
    int bpm,
    FitnessParameters p,
  ) {
    validateBounds(p);
    if (bpm <= 0) {
      return FitnessUnavailable(
        reason: UnavailableReason.noHeartRate,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        maxIsEstimated: basis.maxIsEstimated,
      );
    }
    final r = reserve.relativeLoad(basis, bpm, p);
    switch (r) {
      case FitnessUnavailable():
        return FitnessUnavailable(
          reason: r.reason,
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );
      case FitnessAvailable():
        return FitnessAvailable(
          value: _place(r.value, p),
          method: method,
          methodVersion: methodVersion,
          parameterVersion: p.parameterVersion,
          maxIsEstimated: basis.maxIsEstimated,
        );
    }
  }

  /// Zeit je Zone über die Bewegungszeit mit gehaltenem Puls.
  @override
  FitnessResult<ReserveZoneTimes> timeInZones({
    required HeartRateBasis basis,
    required HeartRateResult heartRate,
    required MovementResult movement,
    required FitnessParameters p,
  }) {
    requireSameParameterVersion(heartRate: heartRate, movement: movement, p: p);
    validateBounds(p);
    final reason = reserve.check(basis, p);
    if (reason != null) {
      return FitnessUnavailable(
        reason: reason,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        maxIsEstimated: basis.maxIsEstimated,
      );
    }
    final time = heartRateTimeByBpm(
      heartRate: heartRate,
      movement: movement,
      p: p,
    );
    // Fehlendes ist nie 0 (FR-0056, OQ-0012).
    // Werte da, aber nichts davon abgedeckt (kein Takt): zu wenig Abdeckung.
    final missing = time.movingMicros == 0
        ? UnavailableReason.noMovingTime
        : time.coveredMicros == 0
        ? (heartRate.acceptedValues.isEmpty
              ? UnavailableReason.noHeartRate
              : UnavailableReason.insufficientCoverage)
        : null;
    if (missing != null) {
      return FitnessUnavailable(
        reason: missing,
        method: method,
        methodVersion: methodVersion,
        parameterVersion: p.parameterVersion,
        maxIsEstimated: basis.maxIsEstimated,
      );
    }
    final zones = List<int>.filled(p.reserveZoneCount, 0);
    var below = 0;
    var hint = false;
    for (final e in time.microsByBpm.entries) {
      final r = reserve.relativeLoad(basis, e.key, p);
      // check() ist durch; eine andere Reserve kann trotzdem „nicht
      // verfügbar“ melden, dann ist die ganze Zeit nicht bewertbar.
      final ReserveZonePlacement placed;
      switch (r) {
        case FitnessUnavailable():
          return FitnessUnavailable(
            reason: r.reason,
            method: method,
            methodVersion: methodVersion,
            parameterVersion: p.parameterVersion,
            maxIsEstimated: basis.maxIsEstimated,
          );
        case FitnessAvailable():
          placed = _place(r.value, p);
      }
      hint = hint || placed.aboveHint;
      switch (placed) {
        case BelowReserveZone1():
          below += e.value;
        case InReserveZone(:final zone):
          zones[zone - 1] += e.value;
      }
    }
    return FitnessAvailable(
      value: ReserveZoneTimes(
        zoneMicros: zones,
        belowZone1Micros: below,
        coveredMicros: time.coveredMicros,
        movingMicros: time.movingMicros,
        aboveHint: hint,
        reserveMethod: reserve.method,
        reserveMethodVersion: reserve.methodVersion,
      ),
      method: method,
      methodVersion: methodVersion,
      parameterVersion: p.parameterVersion,
      maxIsEstimated: basis.maxIsEstimated,
    );
  }
}

const reserveZonesFamily = AlgorithmFamily<ReserveZoneModel>('reserve-zones');
