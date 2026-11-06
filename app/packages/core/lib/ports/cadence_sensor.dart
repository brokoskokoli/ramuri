/// Verfügbarkeit der Schrittfrequenz (FR-0202: darf fehlen).
enum CadenceAvailability { available, permissionDenied, noSensor }

class CadenceReading {
  const CadenceReading(this.time, this.stepsPerMinute, this.elapsed);

  /// Wanduhrzeit des letzten Schritts (nur zur Anzeige und Zuordnung).
  final DateTime time;

  /// Monotone Zeit des letzten Schritts (Zeitbasis des Sensors); sie allein
  /// zählt für Abstände, die Wanduhr kann im Lauf umgestellt werden.
  final Duration elapsed;
  final double stepsPerMinute;
}

/// Port: Schrittfrequenz des Telefons.
abstract interface class CadenceSensor {
  Future<CadenceAvailability> availability();

  /// Werte nur bei [CadenceAvailability.available]; sonst leerer Strom.
  Stream<CadenceReading> readings();
}
