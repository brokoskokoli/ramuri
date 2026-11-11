import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Marker für den Artefaktbeleg (WP07): Dieser Text darf in keinem
/// Release-APK stehen. Der Belegbericht sucht ihn im APK.
const String testSensorMarker = 'RUNAPP-DEBUG-TEST-SENSOR-7c1e9b';

/// Test-Sensor ohne Funk (WP07, nur Debug-Einstiegspunkt `main_debug.dart`).
///
/// Zwei Fake-Geräte, Pulswerte, Abbruch und Neuverbinden simulierbar. Kein
/// Code der Release-Einstiegsdatei importiert diese Datei.
class DebugTestSensor implements HeartRateSensor {
  DebugTestSensor(
    this._clock, {
    this.interval = const Duration(seconds: 1),
    this.sendRr = false,
  }) {
    // Hält den Marker im Code, sobald der Test-Sensor erzeugt wird (Positivkontrolle
    // am Artefakt) und zeigt im Debug-Log, dass nicht der echte Sensor läuft.
    debugPrint('$testSensorMarker aktiv: Pulswerte sind simuliert');
  }

  final Clock _clock;
  final Duration interval;

  /// Sendet mit jedem Pulswert ein synthetisches RR-Intervall (FR-0213);
  /// aus = Gerät ohne RR. Zur Laufzeit umschaltbar, gilt für neue Werte.
  bool sendRr;

  /// Bekannte Fake-Geräte: Kennung -> Name.
  static const devices = <String, String>{
    'fake-gurt-1': '$testSensorMarker Gurt 1',
    'fake-gurt-2': '$testSensorMarker Gurt 2',
  };

  final _sessions = <String, _FakeSession>{};

  /// Pulsverlauf je Gerät; einfacher Anstieg und Abfall um [base].
  final _base = <String, int>{'fake-gurt-1': 120, 'fake-gurt-2': 135};

  @override
  Stream<HeartRateDevice> scan() async* {
    for (final e in devices.entries) {
      yield HeartRateDevice(id: e.key, name: e.value);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  Stream<HeartRateEvent> connect(String deviceId) {
    late final _FakeSession s;
    s = _FakeSession(
      deviceId,
      _clock,
      interval,
      () => _base[deviceId] ?? 120,
      () => sendRr,
      onClose: () {
        if (identical(_sessions[deviceId], s)) _sessions.remove(deviceId);
      },
    );
    _sessions[deviceId] = s;
    return s.stream;
  }

  /// Simuliert einen Funkabbruch: `Disconnected(lost: true)`, Strom endet.
  void drop(String deviceId) => _sessions[deviceId]?.drop();

  /// Setzt den Grundpuls eines Geräts (z. B. für Zonenwechsel).
  void setBase(String deviceId, int bpm) => _base[deviceId] = bpm;

  /// Sendet ein rohes Paket, wie es das Gerät über 0x2A37 schickte.
  void sendRaw(String deviceId, List<int> bytes) =>
      _sessions[deviceId]?.raw(bytes);
}

class _FakeSession {
  _FakeSession(
    this.id,
    this._clock,
    Duration interval,
    this._base,
    this._sendRr, {
    required this.onClose,
  }) {
    _ctl = StreamController<HeartRateEvent>(
      onListen: () {
        _ctl.add(HeartRateConnected(id));
        _ctl.add(HeartRateBattery(id, 77));
        _timer = Timer.periodic(interval, (_) => _tick());
      },
      onCancel: () {
        _timer?.cancel();
        onClose();
      },
    );
  }

  final String id;
  final Clock _clock;
  final int Function() _base;
  final bool Function() _sendRr;
  final void Function() onClose;
  late final StreamController<HeartRateEvent> _ctl;
  Timer? _timer;
  int _n = 0;

  Stream<HeartRateEvent> get stream => _ctl.stream;

  void _tick() {
    final bpm = _base() + (_n++ % 7) - 3;
    // Synthetisch: ein Schlagabstand passend zum simulierten Puls, 1/1024 s.
    final rr = _sendRr() && bpm > 0 ? [(1024 * 60 / bpm).round()] : <int>[];
    _ctl.add(
      HeartRateReading(
        id,
        _clock.now(),
        bpm,
        contact: SensorContact.good,
        rrIntervals: rr,
      ),
    );
  }

  void raw(List<int> bytes) {
    final m = HeartRateParser.parseMeasurement(bytes);
    if (m == null) return;
    _ctl.add(
      HeartRateReading(
        id,
        _clock.now(),
        m.beatsPerMinute,
        contact: m.contact,
        rrIntervals: m.rrIntervals,
      ),
    );
  }

  void drop() {
    if (_ctl.isClosed) return;
    _timer?.cancel();
    _ctl.add(HeartRateDisconnected(id, lost: true));
    _ctl.close();
  }
}
