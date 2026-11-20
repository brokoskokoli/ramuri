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

/// Synthetische Bildstatistik (keine Messdaten) mit wählbarem Schlagabstand
/// und Störungen, für die laufende Anzeige (PAR-234): [periodAt] liefert den
/// Abstand (s) zum nächsten Schlag ab Sensorzeit t, leichte Schwankung wie
/// [FrameSource]. [spikes]: kurze Ausschläge (Sensorzeit in s), je einer
/// macht den Schlagabstand ungültig, in dessen Mitte er liegt. [noisyAt]:
/// dort nur Rauschen (gestörtes Signal).
class PulseSource {
  PulseSource({
    required double Function(double t) periodAt,
    this.spikes = const [],
    this.noisyAt,
    this.flatAt,
    this.motion,
    this.dropBeats = const {},
    this.spikeHeight = 4,
    this.noiseLevel = 30,
    this.fps = 30,
  }) {
    var t = 0.3;
    var n = 0;
    while (t < 200) {
      _beats.add(t + 0.02 * math.sin(2 * math.pi * n / 5.3));
      t += periodAt(t);
      n++;
    }
  }

  /// Gleichmäßiger Puls mit [bpm] Schlägen je Minute.
  PulseSource.bpm(double bpm, {List<double> spikes = const []})
    : this(periodAt: (_) => 60 / bpm, spikes: spikes);

  final int fps;
  final List<double> spikes;
  final bool Function(double t)? noisyAt;
  final bool Function(double t)? flatAt;
  final double Function(double t)? motion;
  final Set<int> dropBeats;
  final double spikeHeight;
  final double noiseLevel;
  final List<double> _beats = [];
  int _n = 0;

  /// Mitte zwischen Schlag [k] und dem folgenden (für [spikes]).
  double midAfterBeat(int k) => (_beats[k] + _beats[k + 1]) / 2;

  /// Index des ersten Schlags ab Sensorzeit [t].
  int beatAfter(double t) => _beats.indexWhere((b) => b >= t);

  double _noise(int i) {
    var x = (i * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF;
    x = ((x ^ (x >> 15)) * 2246822519) & 0xFFFFFFFF;
    x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF;
    x = x ^ (x >> 16);
    return x / 0x7FFFFFFF - 1;
  }

  double _pulse(double t) {
    var s = 0.0;
    for (var b = 0; b < _beats.length; b++) {
      if (dropBeats.contains(b)) continue;
      final d = t - _beats[b];
      if (d < -1 || d > 1.5) continue;
      s +=
          math.exp(-((d - 0.12) * (d - 0.12)) / (2 * 0.05 * 0.05)) +
          0.35 * math.exp(-((d - 0.38) * (d - 0.38)) / (2 * 0.07 * 0.07));
    }
    for (final ts in spikes) {
      final d = t - ts;
      s += spikeHeight * math.exp(-(d * d) / (2 * 0.02 * 0.02));
    }
    return s;
  }

  PpgFrame next() {
    final i = _n++;
    final t = i / fps;
    final noisy = noisyAt?.call(t) ?? false;
    final flat = flatAt?.call(t) ?? false;
    final r = flat
        ? 200.0
        : noisy
        ? 200 + noiseLevel * _noise(i)
        : 200 - 3 * _pulse(t) + (motion?.call(t) ?? 0) + 0.3 * _noise(i);
    final g = flat
        ? 40.0
        : noisy
        ? 40 + noiseLevel / 3 * _noise(i + 99991)
        : 40 -
              1 * _pulse(t) +
              (motion?.call(t) ?? 0) / 3 +
              0.1 * _noise(i + 99991);
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

  /// Spielt Bilder bis [until] ein und ruft [each] nach jeder vollen Sekunde
  /// Sensorzeit (nach dem Einspielen) mit dieser Sekunde auf.
  Future<void> emitEachSecond(
    FakePpgCamera cam,
    double until,
    void Function(double t) each,
  ) async {
    var s = (_n / fps).floor() + 1;
    while (s <= until) {
      await emitUntil(cam, s.toDouble());
      each(s.toDouble());
      s++;
    }
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

  /// Hält das Speichern an, bis der Completer erfüllt ist.
  Completer<void>? holdSave;

  @override
  Future<ProfileRecord> read() => inner.read();

  @override
  Future<void> save(ProfileRecord profile) async {
    await holdSave?.future;
    if (failSave) throw StateError('Speichern scheitert');
    await inner.save(profile);
  }
}
