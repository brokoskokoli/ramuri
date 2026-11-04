/// Die vier Zustände eines Messwerts (FR-0057).
enum MeasurementState { present, estimated, unavailable, discarded }

/// Grund, aus dem ein Filter einen Wert verworfen hat.
enum DiscardReason {
  accuracy,
  hardJump,
  softJump,
  nonMonotonicTime,
  implausibleHeartRate,
  noContact,
  heartRateOutlier,
  verticalAccuracy,
}

/// Hautkontakt des Pulssensors.
enum SensorContact { good, poor, unsupported }

/// Gemeinsame Felder roher Eingaben. Fehlende Angaben sind `null`, nie 0.
abstract class RawSample {
  const RawSample({
    required this.time,
    required this.source,
    this.state = MeasurementState.present,
  });

  final DateTime time;

  /// Quellgerät (FR-0020).
  final String source;

  /// Ein Sensor kann `estimated` liefern.
  final MeasurementState state;
}

class RawPosition extends RawSample {
  const RawPosition({
    required super.time,
    required super.source,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    super.state,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
}

class RawHeartRate extends RawSample {
  const RawHeartRate({
    required super.time,
    required super.source,
    required this.bpm,
    this.contact = SensorContact.unsupported,
    super.state,
  });

  final int bpm;
  final SensorContact contact;
}

class RawAltitude extends RawSample {
  const RawAltitude({
    required super.time,
    required super.source,
    required this.meters,
    this.verticalAccuracyMeters,
    super.state,
  });

  final double meters;
  final double? verticalAccuracyMeters;
}

class RawSteps extends RawSample {
  const RawSteps({
    required super.time,
    required super.source,
    required this.count,
    super.state,
  });

  final int count;
}
