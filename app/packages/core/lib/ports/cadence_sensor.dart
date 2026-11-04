/// Verfügbarkeit der Schrittfrequenz (FR-0202: darf fehlen).
enum CadenceAvailability { available, permissionDenied, noSensor }

class CadenceReading {
  const CadenceReading(this.time, this.stepsPerMinute);

  final DateTime time;
  final double stepsPerMinute;
}

/// Port: Schrittfrequenz des Telefons.
abstract interface class CadenceSensor {
  Future<CadenceAvailability> availability();

  /// Werte nur bei [CadenceAvailability.available]; sonst leerer Strom.
  Stream<CadenceReading> readings();
}
