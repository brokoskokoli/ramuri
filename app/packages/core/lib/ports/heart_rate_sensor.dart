import '../src/preprocessing/measurement.dart' show SensorContact;

/// Ein gefundener Herzfrequenzsensor.
class HeartRateDevice {
  const HeartRateDevice({required this.id, this.name});

  final String id;
  final String? name;
}

/// Ereignisse einer Verbindung zu einem Sensor (ADR-0006).
sealed class HeartRateEvent {
  const HeartRateEvent(this.deviceId);

  /// Quellgerät: Jeder Wert trägt sein Gerät (FR-0019, FR-0020).
  final String deviceId;
}

class HeartRateConnected extends HeartRateEvent {
  const HeartRateConnected(super.deviceId);
}

class HeartRateReading extends HeartRateEvent {
  const HeartRateReading(
    super.deviceId,
    this.time,
    this.beatsPerMinute, {
    this.contact = SensorContact.unsupported,
    this.rrIntervals = const [],
  });

  final DateTime time;
  final int beatsPerMinute;

  /// Hautkontakt laut Statusbit von 0x2A37 (PAR-008).
  final SensorContact contact;

  /// RR-Intervalle dieses Pakets, roh in 1/1024 s, in Sendereihenfolge
  /// (FR-0213). Leer, wenn das Gerät keine sendet. Zeitbezug: [time].
  final List<int> rrIntervals;
}

/// Akkustand in Prozent (optional, FR-0016).
class HeartRateBattery extends HeartRateEvent {
  const HeartRateBattery(super.deviceId, this.percent);

  final int percent;
}

/// Verbindung beendet oder abgebrochen. Danach kommt kein Ereignis mehr.
class HeartRateDisconnected extends HeartRateEvent {
  const HeartRateDisconnected(super.deviceId, {this.lost = false});

  /// `true`, wenn die Verbindung ungewollt endete.
  final bool lost;
}

/// Port: Herzfrequenzsensor (Bluetooth LE, Heart Rate Service).
abstract interface class HeartRateSensor {
  /// Sucht Geräte mit Heart Rate Service, solange jemand zuhört.
  Stream<HeartRateDevice> scan();

  /// Verbindet und liefert Ereignisse. Das Abbrechen des Abos trennt.
  Stream<HeartRateEvent> connect(String deviceId);
}
