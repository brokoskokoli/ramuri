import 'dart:async';

import '../ports/heart_rate_sensor.dart';

/// Herzfrequenzsensor mit beliebig vielen Fake-Geräten.
class FakeHeartRateSensor implements HeartRateSensor {
  final _found = StreamController<HeartRateDevice>.broadcast();
  final _connections = <String, StreamController<HeartRateEvent>>{};

  @override
  Stream<HeartRateDevice> scan() => _found.stream;

  /// Ein Gerät taucht in der Suche auf.
  void discover(HeartRateDevice d) => _found.add(d);

  /// Verbindungen, die gerade Abonnenten haben.
  Set<String> get connectedIds => {
    for (final e in _connections.entries)
      if (e.value.hasListener) e.key,
  };

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    late final StreamController<HeartRateEvent> c;
    c = StreamController<HeartRateEvent>(
      onListen: () => c.add(HeartRateConnected(deviceId)),
      onCancel: () => _connections.remove(deviceId),
    );
    _connections[deviceId] = c;
    return c.stream;
  }

  void _send(String id, HeartRateEvent e) {
    final c = _connections[id];
    if (c == null || !c.hasListener) {
      throw StateError('Gerät $id ist nicht verbunden');
    }
    c.add(e);
  }

  void emitReading(String id, DateTime time, int bpm) =>
      _send(id, HeartRateReading(id, time, bpm));

  void emitBattery(String id, int percent) =>
      _send(id, HeartRateBattery(id, percent));

  /// Ungewollter Abbruch: meldet [HeartRateDisconnected] und schließt.
  Future<void> drop(String id) async {
    final c = _connections[id];
    _send(id, HeartRateDisconnected(id, lost: true));
    await c!.close();
  }
}
