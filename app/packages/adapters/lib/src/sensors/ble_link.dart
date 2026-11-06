/// Dünne Schicht über dem Bluetooth-Plugin (ADR-0006 Punkt 2).
///
/// Nur diese Schicht kennt `universal_ble`. Die Adapterlogik
/// (`BleHeartRateSensor`) arbeitet gegen diese Schnittstelle und ist damit
/// ohne Plugin testbar.
library;

/// Ein beworbenes Gerät.
class BleAdvert {
  const BleAdvert({required this.id, this.name});

  final String id;
  final String? name;
}

/// Ein Dienst mit seinen Merkmalen, UUIDs in Kurzform (`180d`, `2a37`).
class BleServiceInfo {
  const BleServiceInfo(this.uuid, this.characteristics);

  final String uuid;
  final List<String> characteristics;
}

abstract interface class BleLink {
  /// Fragt die Bluetooth-Rechte ab. Wirft, wenn sie verweigert werden.
  Future<void> requestPermissions();

  /// Meldungen von Geräten mit dem Dienst [serviceUuid], bis das Abo endet.
  Stream<BleAdvert> scan(String serviceUuid);

  /// `true` bei Verbindung, `false` bei Trennen oder Verlust. Vor [connect]
  /// abonnieren. Ob die App das Trennen selbst auslöste, weiß der Aufrufer.
  Stream<bool> connectionStates(String deviceId);

  /// Baut die Verbindung auf. [autoConnect] wartet auf das Gerät, bis es
  /// wieder erreichbar ist; [closeGattOnDetach] gibt es beim Beenden der App frei.
  Future<void> connect(
    String deviceId, {
    required bool autoConnect,
    required bool closeGattOnDetach,
    required Duration timeout,
  });

  Future<void> disconnect(String deviceId);

  Future<List<BleServiceInfo>> discoverServices(String deviceId);

  /// Schaltet Benachrichtigungen ein und liefert die Werte, bis das Abo endet.
  Stream<List<int>> notifications(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );

  Future<List<int>> read(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  );
}
