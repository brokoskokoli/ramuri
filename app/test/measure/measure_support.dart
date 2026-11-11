import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:running_app/features/measure/resting_measure_controller.dart';
import 'package:core/core.dart';

/// Synthetische Bildstatistik (keine Messdaten): Pulsform mit dikroter Welle,
/// Schlagabstand 0,85 s (ca. 70,6/min) mit leichter Schwankung; `weak`: nur Rauschen.
class FrameSource {
  FrameSource({this.fps = 30, this.weak = false});

  final int fps;
  final bool weak;
  int _n = 0;

  double _noise(int i) {
    var x = (i * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF;
    x = ((x ^ (x >> 15)) * 2246822519) & 0xFFFFFFFF;
    x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF;
    x = x ^ (x >> 16);
    return x / 0x7FFFFFFF - 1;
  }

  double _pulse(double t) {
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

  /// Überspringt [n] Bilder (Lücke in der Sensorzeit).
  void emitSkip(int n) => _n += n;

  PpgFrame next() {
    final i = _n++;
    final t = i / fps;
    final r = weak
        ? 200 + 30 * _noise(i)
        : 200 - 3 * _pulse(t) + 0.3 * _noise(i);
    final g = weak
        ? 40 + 10 * _noise(i + 99991)
        : 40 - 1 * _pulse(t) + 0.1 * _noise(i + 99991);
    return PpgFrame(
      t: t,
      r: r,
      g: g,
      r16: List<double>.filled(16, r),
      g16: List<double>.filled(16, g),
    );
  }

  /// Spielt Bilder bis Sensorzeit [until] (Sekunden) ein.
  Future<void> emitUntil(FakePpgCamera cam, double until) async {
    var k = 0;
    while (_n / fps <= until) {
      cam.emitFrame(next());
      if (++k % 60 == 0) await pump();
    }
    await pump();
  }
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

/// Wertet nur das volle Fenster echt aus; Zwischenauswertungen bleiben billig.
Future<PpgMeasurement> evalFinalOnly(
  List<PpgFrame> frames,
  PpgWindow window,
) async => identical(window, ppgStandardWindow)
    ? evaluatePpg(frames, window: window)
    : const PpgMeasurement(quality: PpgQuality.unusable, reasons: []);

/// Kamera, deren Rechteanfrage man offen halten kann.
class HoldingCamera extends FakePpgCamera {
  Completer<PpgCameraAvailability>? hold;

  @override
  Future<PpgCameraAvailability> requestPermission() {
    final h = hold;
    if (h == null) return super.requestPermission();
    permissionRequests++;
    return h.future;
  }
}

class RecordingSignal implements RestingMeasureSignal {
  int calls = 0;
  @override
  Future<void> restEnded() async => calls++;
}

/// Profildienst, der die Aufrufe von save zählt (Stellvertreter für die
/// Neuberechnung der Zonen, die in der App über diese Klasse läuft).
class SpyProfileService extends ProfileService {
  SpyProfileService(super.store, super.clock, {super.settings});
  int saves = 0;
  @override
  Future<ProfileSaveResult> save(ProfileRecord profile) {
    saves++;
    return super.save(profile);
  }
}

final Uint8List testKey = Uint8List.fromList(List.filled(32, 7));

/// Einstellungen, deren Schreiben scheitert, wenn [failSet] für den Schlüssel
/// `true` liefert.
class FailingSettingsStore implements SettingsStore {
  FailingSettingsStore(this.inner);
  final SettingsStore inner;
  bool Function(String key)? failSet;

  @override
  Future<String?> get(String key) => inner.get(key);

  @override
  Future<Map<String, String>> all() => inner.all();

  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    if (failSet?.call(key) ?? false) throw StateError('Schreiben scheitert');
    await inner.set(key, value, at: at);
  }
}

/// Profilspeicher, dessen Speichern auf Wunsch scheitert.
class FailingProfileStore implements ProfileStore {
  FailingProfileStore(this.inner);
  final ProfileStore inner;
  bool failSave = false;

  @override
  Future<ProfileRecord> read() => inner.read();

  @override
  Future<void> save(ProfileRecord profile) async {
    if (failSave) throw StateError('Speichern scheitert');
    await inner.save(profile);
  }
}
