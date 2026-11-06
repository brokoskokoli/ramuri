import 'dart:async';

import 'package:core/core.dart';

import 'ble_link.dart';

/// Verbindung zum Sensor schlug fehl, bevor sie stand (Plugin-Fehler,
/// Zeitüberschreitung, Gerät ohne Pulsmerkmal). Der Text nennt kein Gerät.
class HeartRateConnectException implements Exception {
  const HeartRateConnectException(this.reason);

  final String reason;

  @override
  String toString() => 'HeartRateConnectException: $reason';
}

/// Port [HeartRateSensor] über Bluetooth LE (ADR-0006).
///
/// Heart Rate Service `0x180D` mit Benachrichtigung `0x2A37`, optional
/// Battery Service `0x180F` mit `0x2A19`. Ungültige Pakete ergeben kein
/// Ereignis. Weder Kennungen noch Werte werden protokolliert (SEC).
class BleHeartRateSensor implements HeartRateSensor {
  BleHeartRateSensor(
    this._link,
    this._clock, {
    this.connectTimeout = const Duration(seconds: 60),
  });

  static const heartRateService = '180d';
  static const heartRateMeasurement = '2a37';
  static const batteryService = '180f';
  static const batteryLevel = '2a19';

  final BleLink _link;
  final Clock _clock;

  /// Wartezeit des Verbindens. Mit `autoConnect` wartet das System so lange
  /// auf ein gerade nicht erreichbares Gerät.
  final Duration connectTimeout;

  /// Fragt die Bluetooth-Rechte ab. Aufrufen erst beim Einrichten eines
  /// Sensors, nie beim Start oder Lauf ohne Sensor (ADR-0006 Punkt 3).
  Future<void> requestPermissions() => _link.requestPermissions();

  @override
  Stream<HeartRateDevice> scan() {
    final seen = <String>{};
    StreamSubscription<BleAdvert>? sub;
    late final StreamController<HeartRateDevice> out;
    out = StreamController<HeartRateDevice>(
      onListen: () {
        sub = _link
            .scan(heartRateService)
            .listen(
              (a) {
                if (seen.add(a.id)) {
                  out.add(HeartRateDevice(id: a.id, name: a.name));
                }
              },
              onError: out.addError,
              onDone: out.close,
            );
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    final session = _Session(_link, _clock, deviceId, connectTimeout);
    return session.events;
  }
}

class _Session {
  _Session(this._link, this._clock, this._id, this._timeout) {
    _out = StreamController<HeartRateEvent>(onListen: _start, onCancel: _stop);
  }

  final BleLink _link;
  final Clock _clock;
  final String _id;
  final Duration _timeout;

  late final StreamController<HeartRateEvent> _out;
  StreamSubscription<bool>? _states;
  StreamSubscription<List<int>>? _notifications;
  bool _closed = false;
  bool _established = false;

  Stream<HeartRateEvent> get events => _out.stream;

  void _start() {
    _states = _link
        .connectionStates(_id)
        .listen(
          (connected) {
            if (!connected && _established) _lost();
          },
          onError: (Object _) {
            if (_established) _lost();
          },
        );
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await _link.connect(
        _id,
        autoConnect: true,
        closeGattOnDetach: true,
        timeout: _timeout,
      );
      if (_closed) return;
      final services = await _link.discoverServices(_id);
      if (_closed) return;
      final hr = _find(services, BleHeartRateSensor.heartRateService);
      if (hr == null ||
          !hr.characteristics.contains(
            BleHeartRateSensor.heartRateMeasurement,
          )) {
        throw const HeartRateConnectException('no heart rate measurement');
      }
      final battery = _find(services, BleHeartRateSensor.batteryService);
      final hasBattery =
          battery != null &&
          battery.characteristics.contains(BleHeartRateSensor.batteryLevel);

      _established = true;
      _emit(HeartRateConnected(_id));
      _notifications = _link
          .notifications(
            _id,
            BleHeartRateSensor.heartRateService,
            BleHeartRateSensor.heartRateMeasurement,
          )
          .listen(_onMeasurement, onError: (Object _) => _lost());
      if (hasBattery) await _readBattery();
    } catch (e) {
      if (_closed) return;
      if (_established) {
        _lost();
      } else {
        _closed = true;
        _out.addError(
          e is HeartRateConnectException
              ? e
              : const HeartRateConnectException('connect failed'),
        );
        await _release();
        await _out.close();
      }
    }
  }

  BleServiceInfo? _find(List<BleServiceInfo> all, String uuid) {
    for (final s in all) {
      if (s.uuid == uuid) return s;
    }
    return null;
  }

  void _onMeasurement(List<int> bytes) {
    final m = HeartRateParser.parseMeasurement(bytes);
    if (m == null) return;
    _emit(
      HeartRateReading(_id, _clock.now(), m.beatsPerMinute, contact: m.contact),
    );
  }

  Future<void> _readBattery() async {
    try {
      final bytes = await _link.read(
        _id,
        BleHeartRateSensor.batteryService,
        BleHeartRateSensor.batteryLevel,
      );
      final percent = HeartRateParser.parseBattery(bytes);
      if (percent != null) _emit(HeartRateBattery(_id, percent));
    } catch (_) {
      // Lesen nicht möglich: kein erfundener Wert (FR-0016).
    }
  }

  void _emit(HeartRateEvent e) {
    if (!_closed) _out.add(e);
  }

  /// Verbindung ging ungewollt verloren: ein Abschlussereignis, dann Ende.
  /// Neu verbinden ist Sache des Aufrufers (neuer [connect]-Aufruf).
  void _lost() {
    if (_closed) return;
    _emit(HeartRateDisconnected(_id, lost: true));
    _closed = true;
    unawaited(_release().whenComplete(_out.close));
  }

  Future<void> _stop() async {
    _closed = true;
    await _release();
  }

  bool _released = false;

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    await _notifications?.cancel();
    await _states?.cancel();
    _notifications = null;
    _states = null;
    try {
      await _link.disconnect(_id);
    } catch (_) {
      // Schon getrennt oder Bluetooth aus.
    }
  }
}
