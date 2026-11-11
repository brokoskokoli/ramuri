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

  /// Nicht endliche Koordinate oder Höhe.
  invalidValue,
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
    this.speedMetersPerSecond,
    this.speedAccuracyMetersPerSecond,
    this.verticalAccuracyMeters,
    super.state,
  });

  final double latitude;
  final double longitude;

  /// Horizontalgenauigkeit. Alle Genauigkeiten und das Tempo sind `null`, wenn
  /// die Quelle sie nicht liefert (nie 0). Die Vorverarbeitung wertet
  /// Tempo und Tempo-Genauigkeit nicht aus (K12: nur festhalten).
  final double? accuracyMeters;
  final double? speedMetersPerSecond;
  final double? speedAccuracyMetersPerSecond;
  final double? verticalAccuracyMeters;
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

/// RR-Intervalle eines BLE-Pakets (FR-0213): Rohwerte in 1/1024 s, bitgenau
/// wie gesendet (0 und 65535 gültig, nichts gefiltert, nichts umgerechnet).
/// [time] ist der Empfangszeitpunkt des Pakets, [source] das Quellgerät
/// (FR-0020). Kein [RawSample]: Ein Paket hat keinen Messzustand und keinen
/// Platz in der Vorverarbeitung (Phase 2 speichert nur).
class RrPacket {
  const RrPacket({
    required this.time,
    required this.source,
    required this.intervals,
  });

  final DateTime time;
  final String source;

  /// Je Wert 0..65535 (uint16), nicht leer.
  final List<int> intervals;
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
