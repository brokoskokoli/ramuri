import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import 'debug_test_ppg_camera.dart';

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

  /// RR-Art „passend zur Fake-Kamera“ (nur mit [sendRr]): Ist eine Kamera gesetzt, sendet der
  /// Gurt statt eines Werts aus dem Puls die Schlagabstände ihres Schlagplans
  /// ([debugPpgBeatTime], gerundet auf 1/1024 s) lückenlos und in Reihenfolge, gekoppelt an
  /// deren Sensorzeit und Zeitraffer; mit jeder neuen Aufnahme beginnt der Plan wieder bei
  /// Schlag 0. `null` (Standard) = ein Wert je Takt aus dem Puls. Zur Laufzeit umschaltbar.
  DebugTestPpgCamera? rrFollowsPpgCamera;

  /// Höchstzahl RR-Werte je Paket (BLE 0x2A37).
  static const maxRrPerPacket = 9;

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
      () => rrFollowsPpgCamera,
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
    this._sendRr,
    this._follow, {
    required this.onClose,
  }) : _interval = interval {
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
  final DebugTestPpgCamera? Function() _follow;
  final Duration _interval;
  final void Function() onClose;
  late final StreamController<HeartRateEvent> _ctl;
  Timer? _timer;
  int _n = 0;

  /// RR-Art „passend zur Fake-Kamera“: Aufnahme, der der Gurt folgt, und der nächste Schlag.
  int? _camRun;
  int _beat = 0;

  Stream<HeartRateEvent> get stream => _ctl.stream;

  void _tick() {
    final cam = _follow();
    if (_sendRr() && cam != null) return _tickFollowing(cam);
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

  /// Sendet alle Schlagabstände des Plans bis zur Sensorzeit der Kamera plus einem Takt im
  /// Zeitraffer (der Gurt eilt etwas voraus, so fehlt am Ende der Aufnahme kein Abstand),
  /// höchstens [DebugTestSensor.maxRrPerPacket] je Paket. Ohne neue Schläge ein Paket ohne RR.
  void _tickFollowing(DebugTestPpgCamera cam) {
    final st = cam.sensorTime;
    final rr = <int>[];
    if (st != null) {
      if (st.run != _camRun) {
        _camRun = st.run;
        _beat = 0;
      }
      final horizon = st.seconds + _interval.inMicroseconds / 1e6 * st.speed;
      while (debugPpgBeatTime(_beat + 1) <= horizon) {
        final d = debugPpgBeatTime(_beat + 1) - debugPpgBeatTime(_beat);
        rr.add((d * 1024).round());
        _beat++;
      }
    }
    if (rr.isEmpty) {
      _ctl.add(
        HeartRateReading(
          id,
          _clock.now(),
          (60 / debugPpgBeatPeriodSeconds).round(),
          contact: SensorContact.good,
        ),
      );
      return;
    }
    const max = DebugTestSensor.maxRrPerPacket;
    for (var i = 0; i < rr.length; i += max) {
      final part = rr.sublist(i, i + max < rr.length ? i + max : rr.length);
      final sum = part.reduce((a, b) => a + b);
      _ctl.add(
        HeartRateReading(
          id,
          _clock.now(),
          (1024 * 60 * part.length / sum).round(),
          contact: SensorContact.good,
          rrIntervals: part,
        ),
      );
    }
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
