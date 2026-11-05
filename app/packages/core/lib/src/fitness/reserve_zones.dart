import '../preprocessing/heart_rate_processor.dart';
import '../preprocessing/measurement.dart';
import '../preprocessing/movement_time_processor.dart';
import 'algorithm_variant.dart';
import 'fitness_parameters.dart';
import 'fitness_result.dart';
import 'heart_rate_basis.dart';
import 'heart_rate_reserve.dart';
import 'heart_rate_time.dart';

/// Einordnung eines `r`. [zone] ist 1-basiert, `null` heißt unter Zone 1
/// (FR-0063).
class ReserveZonePlacement {
  const ReserveZonePlacement({required this.zone, required this.aboveHint});
  final int? zone;

  /// `r` liegt über 100 % (FR-0062, OQ-0014): HFmax zu niedrig oder
  /// Messfehler.
  final bool aboveHint;
}

/// Zeit je Reservezone in Mikrosekunden.
class ReserveZoneTimes {
  ReserveZoneTimes({
    required List<int> zoneMicros,
    required this.belowZone1Micros,
    required this.coveredMicros,
    required this.movingMicros,
    required this.aboveHint,
  }) : zoneMicros = List.unmodifiable(zoneMicros);

  /// Index 0 ist Zone 1.
  final List<int> zoneMicros;

  /// Zeit unter Zone 1, nicht in Zone 1 (FR-0063).
  final int belowZone1Micros;

  /// Zeit mit bekanntem Puls (Bewegungszeit ohne Lücken).
  final int coveredMicros;
  final int movingMicros;

  /// Mindestens ein Puls lag über 100 % der Reserve.
  final bool aboveHint;
}

/// Reservezonen (FR-0061, FR-0062), Kategorie B: Grenzen kommen aus dem
/// Parametersatz.
class ReserveZones extends AlgorithmVariant {
  const ReserveZones({this.reserve = const HeartRateReserve()});

  static const methodId = 'reserve-zones';

  final HeartRateReserve reserve;

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
  ReserveZonePlacement place(double r, FitnessParameters p) {
    validateBounds(p);
    final hint = r > p.hintAboveShare;
    if (r < p.reserveZoneBounds.first) {
      return ReserveZonePlacement(zone: null, aboveHint: hint);
    }
    var zone = 1;
    for (var i = 1; i < p.reserveZoneCount; i++) {
      if (r >= p.reserveZoneBounds[i]) zone = i + 1;
    }
    return ReserveZonePlacement(zone: zone, aboveHint: hint);
  }

  /// Zeit je Zone über die Bewegungszeit mit gehaltenem Puls.
  FitnessResult<ReserveZoneTimes> timeInZones({
    required HeartRateBasis basis,
    required List<TimeSpan> movingIntervals,
    required List<RawHeartRate> acceptedValues,
    required List<HeartRateGap> gaps,
    required FitnessParameters p,
  }) {
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
      movingIntervals: movingIntervals,
      acceptedValues: acceptedValues,
      gaps: gaps,
    );
    final zones = List<int>.filled(p.reserveZoneCount, 0);
    var below = 0;
    var hint = false;
    for (final e in time.microsByBpm.entries) {
      final r =
          (e.key - basis.restingBpm!) / (basis.maxBpm! - basis.restingBpm!);
      final placed = place(r, p);
      hint = hint || placed.aboveHint;
      final z = placed.zone;
      if (z == null) {
        below += e.value;
      } else {
        zones[z - 1] += e.value;
      }
    }
    return FitnessAvailable(
      value: ReserveZoneTimes(
        zoneMicros: zones,
        belowZone1Micros: below,
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

const reserveZonesFamily = AlgorithmFamily<ReserveZones>('reserve-zones');
