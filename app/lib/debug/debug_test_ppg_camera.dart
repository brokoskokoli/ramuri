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

  /// Kein Finger: eine Szene mit Rot unter Grün (R/G < 1,5) und regelmäßigem 2-Hz-Wechsel
  /// (wie die Emulator-Szene). Ohne Fingerprüfung ergäbe das „gut, 120/min“; erwartet wird
  /// „unbrauchbar, kein Finger“.
  noFinger,

  /// Kamera belegt: Abbruch gleich zu Beginn.
  busy,

  /// Kamera wird nach 3 s getrennt: Abbruch mitten in der Messung.
  disconnected,

  /// Kein Kamera-Recht; auch [DebugTestPpgCamera.requestPermission] liefert
  /// `permissionDenied` (Nutzer verweigert erneut), das Szenario bleibt.
  permissionDenied,

  /// Kein Kamera-Recht, bis [DebugTestPpgCamera.requestPermission] aufgerufen wird
  /// (Nutzer erteilt es bei der Anfrage); danach wie [goodPulse].
  permissionGrantedOnRequest,

  /// Keine Rückkamera.
  noCamera,
}

/// Stand der Sensorzeit einer Aufnahme der Fake-Kamera: [run] zählt die gestarteten Aufnahmen
/// (je Start neu, Sensorzeit beginnt bei 0), [seconds] ist die Sensorzeit des nächsten Bildes,
/// [speed] der beim Start festgehaltene Zeitraffer.
typedef DebugPpgSensorTime = ({int run, double seconds, double speed});

/// Die drei erfundenen Rückkameras der Debug-Quelle (FR-0220), in der Reihenfolge von
/// [PpgCamera.cameras]: Standardkamera, eine physische Kamera der Standardkamera (nutzbar)
/// und eine Kamera ohne Blitz (nicht nutzbar). Bildrate: Standardkamera 60, die übrigen
/// nutzbaren 30 (nur Anzeige der Liste; die Aufnahme nutzt [DebugTestPpgCamera.fps]).
const List<PpgCameraInfo> debugPpgCameras = [
  PpgCameraInfo(
    ref: PpgCameraRef('0'),
    focalLengthMm: 5.4,
    isDefault: true,
    frameRate: 60,
  ),
  PpgCameraInfo(ref: PpgCameraRef('0', '2'), focalLengthMm: 2.2, frameRate: 30),
  PpgCameraInfo(
    ref: PpgCameraRef('1'),
    focalLengthMm: 6.8,
    unusable: PpgCameraUnusable.noFlash,
  ),
];

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

    /// Wanduhr (nur Tests); Vorgabe: eine laufende Stoppuhr.
    Duration Function()? wallClock,
  }) : _wall = wallClock ?? _stopwatchClock() {
    // Zeigt im Debug-Log, dass nicht die echte Kamera läuft (und ist die Positivkontrolle am Artefakt).
    debugPrint('$testPpgCameraMarker aktiv: Kamerabilder sind simuliert');
  }

  /// Szenario der Standardkamera. Es bestimmt auch, was für das ganze Gerät gilt
  /// (keine Kamera, kein Recht).
  DebugPpgScenario scenario;

  final Map<PpgCameraRef, DebugPpgScenario> _scenarios = {};

  /// Szenario je Kamera aus [debugPpgCameras] (Standardkamera: [scenario]; die übrigen
  /// beginnen mit [DebugPpgScenario.goodPulse]).
  DebugPpgScenario scenarioOf(PpgCameraRef camera) =>
      camera == debugPpgCameras.first.ref
      ? scenario
      : _scenarios[camera] ?? DebugPpgScenario.goodPulse;

  void setScenario(PpgCameraRef camera, DebugPpgScenario s) {
    if (camera == debugPpgCameras.first.ref) {
      scenario = s;
    } else {
      _scenarios[camera] = s;
    }
  }

  /// Gestartete Kameras in Reihenfolge (die tatsächlich geöffnete, wie `PpgCameraStarted`).
  final List<PpgCameraRef> startedCameras = [];

  /// Angeforderte Diagnose-Schalter und Werte je Bild jedes gelungenen Starts
  /// (gleiche Reihenfolge wie [startedCameras]).
  final List<({Set<PpgCameraDiagnostic> diagnostics, bool ispFrames})>
  startedRequests = [];

  /// Zeitraffer; über das Debug-Panel umschaltbar (gilt ab dem nächsten Start).
  double speed;
  final int fps;
  final Duration Function() _wall;

  static Duration Function() _stopwatchClock() {
    final w = Stopwatch()..start();
    return () => w.elapsed;
  }

  /// Aufnahme läuft (Torch an).
  bool torchOn = false;

  /// Zahl der erzeugten Bilder (Tests: nach dem Abbestellen darf sie nicht mehr wachsen).
  int framesGenerated = 0;

  @override
  Future<PpgCameraAvailability> availability() async => switch (scenario) {
    DebugPpgScenario.noCamera => PpgCameraAvailability.noCamera,
    DebugPpgScenario.permissionDenied ||
    DebugPpgScenario.permissionGrantedOnRequest =>
      PpgCameraAvailability.permissionDenied,
    _ => PpgCameraAvailability.available,
  };

  @override
  Future<PpgCameraAvailability> requestPermission() async {
    if (scenario == DebugPpgScenario.permissionGrantedOnRequest) {
      scenario = DebugPpgScenario.goodPulse;
    }
    return availability();
  }

  @override
  Future<List<PpgCameraInfo>> cameras() async =>
      scenario == DebugPpgScenario.noCamera ? const [] : debugPpgCameras;

  StreamController<PpgCameraEvent>? _active;

  int _runs = 0;
  DebugPpgSensorTime? _sensorTime;

  /// Sensorzeit der laufenden oder zuletzt gelaufenen Aufnahme (`null` vor der ersten). Der
  /// Test-Gurt folgt damit dem Schlagplan ([debugPpgBeatTime]) auch im Zeitraffer.
  DebugPpgSensorTime? get sensorTime => _sensorTime;

  static PpgCameraStopReason? _stopOf(DebugPpgScenario s) => switch (s) {
    DebugPpgScenario.noCamera => PpgCameraStopReason.noCamera,
    DebugPpgScenario.permissionDenied ||
    DebugPpgScenario.permissionGrantedOnRequest =>
      PpgCameraStopReason.permissionDenied,
    DebugPpgScenario.busy => PpgCameraStopReason.busy,
    _ => null,
  };

  @override
  Stream<PpgCameraEvent> start({
    PpgCameraRef? camera,
    Set<PpgCameraDiagnostic> diagnostics = const {},
    bool ispFrames = false,
  }) {
    late final StreamController<PpgCameraEvent> c;
    var cancelled = false;
    c = StreamController<PpgCameraEvent>(
      onListen: () async {
        // Wie der Android-Teil: genau die angegebene Kamera, ohne Angabe die Standardkamera.
        final ref = camera ?? debugPpgCameras.first.ref;
        PpgCameraInfo? info;
        for (final i in debugPpgCameras) {
          if (i.ref == ref) info = i;
        }
        final sc = scenarioOf(ref);
        final stop =
            _stopOf(scenario) ??
            switch (info?.unusable) {
              _ when info == null => PpgCameraStopReason.noCamera,
              PpgCameraUnusable.noFlash => PpgCameraStopReason.noFlash,
              PpgCameraUnusable.frameRate => PpgCameraStopReason.frameRate,
              PpgCameraUnusable.other => PpgCameraStopReason.error,
              null => null,
            } ??
            _stopOf(sc);
        if (stop != null) {
          c.add(PpgCameraStopped(stop));
          await c.close();
          return;
        }
        torchOn = true;
        startedCameras.add(ref);
        final requested = Set<PpgCameraDiagnostic>.unmodifiable(diagnostics);
        startedRequests.add((diagnostics: requested, ispFrames: ispFrames));
        // Die erfundene Kamera bietet jeden Schalter an: gesetzt ist, was angefordert
        // wurde; Weißabgleich fest mit fester Matrix (Variante a, ADR-0011).
        c.add(
          PpgCameraStarted(
            fps,
            ref,
            diagnostics: requested,
            awbVariant: requested.contains(PpgCameraDiagnostic.awbFixed)
                ? PpgAwbVariant.matrix
                : null,
          ),
        );
        final weak = sc == DebugPpgScenario.weakSignal;
        final end = sc == DebugPpgScenario.disconnected
            ? 3.0
            : ppgSearchMaxRecordSeconds + 0.5;
        final gen = _Generator(fps, weak, sc == DebugPpgScenario.noFinger);
        var locked = false;
        // Zeitraffer beim Start festhalten: eine Umschaltung im Panel gilt erst ab dem nächsten
        // Start (sonst spränge `due` und der Rest der Messung käme in einem Schwall).
        final sp = speed;
        final run = ++_runs;
        _sensorTime = (run: run, seconds: 0, speed: sp);
        final delay = Duration(microseconds: (1e6 / fps / sp).round());
        // Die Sensorzeit folgt der Wanduhr (mal [speed]) wie bei einer echten Kamera:
        // Kommt die App zeitweise nicht zum Zug, kommen die versäumten Bilder
        // gebündelt nach, statt die Messung zu verlängern (sonst liefe sie bei hoher
        // Last in die Gesamtfrist des Wächters). Je Takt mindestens ein Bild.
        final startedAt = _wall();
        var t = 0.0;
        while (t < end && !cancelled) {
          final due = (_wall() - startedAt).inMicroseconds / 1e6 * sp;
          do {
            framesGenerated++;
            c.add(
              PpgCameraFrame(
                gen.frame(t),
                ispFrames ? debugIspValues(t, fps, requested) : null,
              ),
            );
            if (!locked && t >= 2.5) {
              locked = true;
              c.add(const PpgCameraExposureLocked());
              c.add(debugCameraDetails);
            }
            t = gen.nextTime();
          } while (t < end && t <= due && !cancelled);
          // Bilder bis vor t sind gesendet.
          _sensorTime = (run: run, seconds: t, speed: sp);
          await Future<void>.delayed(delay);
        }
        if (cancelled) return;
        torchOn = false;
        if (sc == DebugPpgScenario.disconnected) {
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

/// Feste, erfundene Kamera-Angaben der Test-Kamera (wie sie der Adapter nach der Sperre meldet).
const PpgCameraDetails debugCameraDetails = PpgCameraDetails(
  exposureTimeNs: 8333333,
  iso: 100,
  timestampSource: CameraTimestampSource.realtime,
  rollingShutterSkewNs: 20000000,
  torchStrength: 1,
  saturatedFraction: 0.02,
);

/// Erfundene Werte der Bildverarbeitung eines Bildes zur Zeit [t] (s) in der Reihenfolge von
/// [ppgIspValueCount] (ADR-0011, Nachtrag 2026-11-21): feste Farbverstärkungen, Modi nach den
/// gesetzten Schaltern [set] (aus = `0`, sonst der übliche Modus der Kamera-API), AWB- und
/// AE-Zustand ab der Sperre bei 2,5 s „gesperrt“, fester Fokus. Der Linsenzustand ist bei
/// jedem 50. Bild „nicht gemeldet“ (NaN), damit der Weg leerer Felder geprüft wird.
List<double> debugIspValues(double t, int fps, Set<PpgCameraDiagnostic> set) {
  final locked = t >= 2.5;
  final frame = (t * fps).round();
  return [
    2.0, 1.0, 1.0, 1.5, // Farbverstärkungen R, G gerade, G ungerade, B
    locked ? 3 : 2, // AWB-Zustand: LOCKED bzw. CONVERGED
    set.contains(PpgCameraDiagnostic.awbFixed)
        ? 0
        : 1, // AWB-Modus: OFF bzw. AUTO
    set.contains(PpgCameraDiagnostic.awbFixed)
        ? 0
        : 1, // Farbkorrektur: MATRIX bzw. FAST
    set.contains(PpgCameraDiagnostic.noiseReductionOff) ? 0 : 1,
    set.contains(PpgCameraDiagnostic.edgeOff) ? 0 : 1,
    set.contains(PpgCameraDiagnostic.tonemapLinear) ? 0 : 1,
    set.contains(PpgCameraDiagnostic.shadingOff) ? 0 : 1,
    debugCameraDetails.exposureTimeNs!.toDouble(),
    debugCameraDetails.iso!.toDouble(),
    locked ? 3 : 2, // AE-Zustand: LOCKED bzw. CONVERGED
    (1e9 / fps).roundToDouble(), // Bilddauer (ns)
    0, // AF-Modus OFF
    10.0, // Fokusdistanz (Dioptrien)
    0, // OIS aus
    frame % 50 == 49 ? double.nan : 0, // Linsenzustand STATIONARY
  ];
}

/// Mittlerer Schlagabstand der Fake-Kamera in s (ca. 70/min).
const double debugPpgBeatPeriodSeconds = 0.85;

/// Größte Abweichung der nicht periodischen Schwankung in [debugPpgBeatTime] (s).
const double debugPpgBeatJitterSeconds = 0.03;

/// Schlagplan der Fake-Kamera: Zeitpunkt von Schlag [b] in Sensorzeit (s). Alle ca. 0,85 s
/// mit langsamer Schwankung (Periode 4,5 s) und einer nicht periodischen, deterministischen
/// Schwankung von höchstens ±[debugPpgBeatJitterSeconds] aus einem Hash des Index (kein Zufall).
/// Ohne sie wiederholten sich die Abstände nach 90 Schlägen, und die Zuordnung Kamera gegen
/// Gurt (FR-0217) wäre mehrdeutig. Kamera und Test-Gurt (`DebugTestSensor`) nutzen denselben Plan.
/// Erfundene Werte, keine Messdaten.
double debugPpgBeatTime(int b) =>
    b * debugPpgBeatPeriodSeconds +
    0.04 * math.sin(2 * math.pi * b * debugPpgBeatPeriodSeconds / 4.5) +
    debugPpgBeatJitterSeconds * _hashNoise(b + 0x5EED);

/// Deterministisches weißes Rauschen in [-1, 1] aus einem Hash des Index (kein Zufall, die Tests
/// bleiben stabil; ein Sinus des Index wäre ein Ton und kein Rauschen).
double _hashNoise(int i) {
  var x = (i * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF;
  x = ((x ^ (x >> 15)) * 2246822519) & 0xFFFFFFFF;
  x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF;
  x = x ^ (x >> 16);
  return x / 0x7FFFFFFF - 1;
}

/// Synthetische Bildstatistik: Pulsform mit dikroter Welle auf Grundlinie, deterministisches Rauschen.
class _Generator {
  _Generator(this.fps, this.weak, this.noFinger);

  final int fps;
  final bool weak;

  /// Szene ohne Finger: Rot 167 und Grün 194 (R/G ca. 0,86), 2-Hz-Rechteck auf Rot.
  final bool noFinger;
  int _n = 0;

  double nextTime() => ++_n / fps;

  double _noise(int i) => _hashNoise(i);

  double _pulse(double t) {
    // Schlagzeitpunkte nach dem gemeinsamen Schlagplan (debugPpgBeatTime).
    final k = (t / debugPpgBeatPeriodSeconds).floor();
    var s = 0.0;
    for (var b = k - 1; b <= k + 1; b++) {
      final tb = debugPpgBeatTime(b);
      final d = t - tb;
      s +=
          math.exp(-((d - 0.12) * (d - 0.12)) / (2 * 0.05 * 0.05)) +
          0.35 * math.exp(-((d - 0.38) * (d - 0.38)) / (2 * 0.07 * 0.07));
    }
    return s;
  }

  PpgFrame frame(double t) {
    final i = _n;
    if (noFinger) {
      final red = 167 + (t * 2 % 1 < 0.5 ? 2.25 : -2.25);
      const green = 194.0;
      return PpgFrame(
        t: t,
        r: red,
        g: green,
        r16: List.filled(16, red),
        g16: List.filled(16, green),
      );
    }
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
