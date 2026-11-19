/// Verfügbarkeit der Schrittfrequenz (FR-0202: darf fehlen).
enum CadenceAvailability { available, permissionDenied, noSensor }

class CadenceReading {
  const CadenceReading(
    this.time,
    this.stepsPerMinute,
    this.elapsed, {
    this.steps = 1,
  });

  /// Wanduhrzeit des letzten Schritts (nur zur Anzeige und Zuordnung).
  final DateTime time;

  /// Monotone Zeit des letzten Schritts (Zeitbasis des Sensors); sie allein
  /// zählt für Abstände, die Wanduhr kann im Lauf umgestellt werden.
  final Duration elapsed;
  final double stepsPerMinute;

  /// Schritte, die der Sensor seit dem vorigen Wert dieses Stroms erkannt hat
  /// (mindestens 1; auch die Schritte, für die es noch keine Frequenz gab).
  /// Die Aufzeichnung summiert sie zum Zähler des Laufs (`raw_steps`).
  final int steps;
}

/// Port: Schrittfrequenz des Telefons.
abstract interface class CadenceSensor {
  Future<CadenceAvailability> availability();

  /// Werte nur bei [CadenceAvailability.available]; sonst leerer Strom.
  Stream<CadenceReading> readings();
}
