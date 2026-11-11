import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Marker für den Artefaktbeleg (WP27, ADR-0011 Punkt 9): Dieser Text darf in keinem
/// Release-APK stehen; `tool/gate.sh` sucht ihn dort.
const String testPpgCameraMarker = 'RUNAPP-DEBUG-TEST-PPG-4d2a8f';

/// Was die Fake-Kamera einspielt.
enum DebugPpgScenario {
  /// Regelmäßiger Puls (ca. 70/min) mit leichter Schwankung: Auswertung „gut“ oder „eingeschränkt“.
  goodPulse,

  /// Nur Rauschen, kein Puls: Auswertung „unbrauchbar“.
  weakSignal,

  /// Kamera belegt: Abbruch gleich zu Beginn.
  busy,

  /// Kamera wird nach 3 s getrennt: Abbruch mitten in der Messung.
  disconnected,

  /// Kein Kamera-Recht, bis [DebugTestPpgCamera.requestPermission] aufgerufen wird.
  permissionDenied,

  /// Keine Rückkamera.
  noCamera,
}

/// Fake-Kamera ohne Hardware (WP27, nur Debug-Einstiegspunkt `main_debug.dart`): spielt
/// synthetische Bildstatistik ein (Puls, schlechtes Signal, Fehlerfälle), wie sie der
/// Android-Teil über denselben Port liefert. Kein Code der Release-Einstiegsdatei importiert
/// diese Datei. Die Werte sind erfunden, keine Messdaten.
class DebugTestPpgCamera implements PpgCamera {
  DebugTestPpgCamera({
    this.scenario = DebugPpgScenario.goodPulse,

    /// Zeitraffer: 1 = Echtzeit, 30 = 60 s Messung in 2 s.
    this.speed = 1,
    this.fps = 30,
  }) {
    // Zeigt im Debug-Log, dass nicht die echte Kamera läuft (und ist die Positivkontrolle am Artefakt).
    debugPrint('$testPpgCameraMarker aktiv: Kamerabilder sind simuliert');
  }

  DebugPpgScenario scenario;
  final double speed;
  final int fps;

  /// Aufnahme läuft (Torch an).
  bool torchOn = false;

  /// Zahl der erzeugten Bilder (Tests: nach dem Abbestellen darf sie nicht mehr wachsen).
  int framesGenerated = 0;

  @override
  Future<PpgCameraAvailability> availability() async => switch (scenario) {
    DebugPpgScenario.noCamera => PpgCameraAvailability.noCamera,
    DebugPpgScenario.permissionDenied => PpgCameraAvailability.permissionDenied,
    _ => PpgCameraAvailability.available,
  };

  @override
  Future<PpgCameraAvailability> requestPermission() async {
    if (scenario == DebugPpgScenario.permissionDenied) {
      scenario = DebugPpgScenario.goodPulse;
    }
    return availability();
  }

  StreamController<PpgCameraEvent>? _active;

  @override
  Stream<PpgCameraEvent> start() {
    late final StreamController<PpgCameraEvent> c;
    var cancelled = false;
    c = StreamController<PpgCameraEvent>(
      onListen: () async {
        final stop = switch (scenario) {
          DebugPpgScenario.noCamera => PpgCameraStopReason.noCamera,
          DebugPpgScenario.permissionDenied =>
            PpgCameraStopReason.permissionDenied,
          DebugPpgScenario.busy => PpgCameraStopReason.busy,
          _ => null,
        };
        if (stop != null) {
          c.add(PpgCameraStopped(stop));
          await c.close();
          return;
        }
        torchOn = true;
        c.add(PpgCameraStarted(fps));
        final weak = scenario == DebugPpgScenario.weakSignal;
        final end = scenario == DebugPpgScenario.disconnected
            ? 3.0
            : ppgStandardWindow.dataEnd + 0.5;
        final gen = _Generator(fps, weak);
        var locked = false;
        final delay = Duration(microseconds: (1e6 / fps / speed).round());
        for (var t = 0.0; t < end && !cancelled; t = gen.nextTime()) {
          framesGenerated++;
          c.add(PpgCameraFrame(gen.frame(t)));
          if (!locked && t >= 2.5) {
            locked = true;
            c.add(const PpgCameraExposureLocked());
          }
          await Future<void>.delayed(delay);
        }
        if (cancelled) return;
        torchOn = false;
        if (scenario == DebugPpgScenario.disconnected) {
          c.add(const PpgCameraStopped(PpgCameraStopReason.disconnected));
        }
        await c.close();
      },
      onCancel: () {
        cancelled = true;
        torchOn = false;
        if (identical(_active, c)) _active = null;
      },
    );
    _active = c;
    return c.stream;
  }

  @override
  Future<void> stop() async {
    final c = _active;
    _active = null;
    torchOn = false;
    await c?.close();
  }
}

/// Synthetische Bildstatistik: Pulsform mit dikroter Welle auf Grundlinie, deterministisches Rauschen.
class _Generator {
  _Generator(this.fps, this.weak);

  final int fps;
  final bool weak;
  int _n = 0;

  double nextTime() => ++_n / fps;

  /// Deterministisches weißes Rauschen in [-1, 1] aus einem Hash des Index (kein Zufall, die Tests
  /// bleiben stabil; ein Sinus des Index wäre ein Ton und kein Rauschen).
  double _noise(int i) {
    var x = (i * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF;
    x = ((x ^ (x >> 15)) * 2246822519) & 0xFFFFFFFF;
    x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF;
    x = x ^ (x >> 16);
    return x / 0x7FFFFFFF - 1;
  }

  double _pulse(double t) {
    // Schlagzeitpunkte alle ca. 0,85 s mit langsamer Schwankung.
    final k = (t / 0.85).floor();
    var s = 0.0;
    for (var b = k - 1; b <= k + 1; b++) {
      final tb = b * 0.85 + 0.04 * math.sin(2 * math.pi * b * 0.85 / 4.5);
      final d = t - tb;
      s +=
          math.exp(-((d - 0.12) * (d - 0.12)) / (2 * 0.05 * 0.05)) +
          0.35 * math.exp(-((d - 0.38) * (d - 0.38)) / (2 * 0.07 * 0.07));
    }
    return s;
  }

  PpgFrame frame(double t) {
    final i = _n;
    final red = weak
        ? 200 + 30 * _noise(i)
        : 200 - 3 * _pulse(t) + 0.3 * _noise(i);
    return PpgFrame(
      t: t,
      r: red,
      g: 40 + 0.3 * _noise(i + 7),
      r16: [for (var k = 0; k < 16; k++) red + 0.1 * _noise(i * 16 + k)],
      g16: [for (var k = 0; k < 16; k++) 40 + 0.1 * _noise(i * 16 + k + 5)],
    );
  }
}
