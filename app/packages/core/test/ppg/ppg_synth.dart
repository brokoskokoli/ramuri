import 'dart:math' as math;

/// Kotlin-`Random(seed)` (XorWow) nachgebaut, damit die synthetischen Vektoren der Referenz
/// (`PpgAnalyzerTest.kt`) bitgleich entstehen. Geprüft gegen die Referenzwerte in
/// `fixtures/reference_synthetic.json` (ppg_reference_test.dart).
class KotlinRandom {
  KotlinRandom(int seed) {
    _x = seed & _m;
    _y = (seed >> 31) & _m;
    _v = (~seed) & _m;
    _addend = (((seed & _m) << 10) ^ (((seed >> 31) & _m) >> 4)) & _m;
    for (var i = 0; i < 64; i++) {
      _nextInt();
    }
  }

  static const int _m = 0xFFFFFFFF;
  int _x = 0, _y = 0, _z = 0, _w = 0, _v = 0, _addend = 0;

  int _nextInt() {
    var t = _x;
    t = (t ^ (t >> 2)) & _m;
    _x = _y;
    _y = _z;
    _z = _w;
    final v0 = _v;
    _w = v0;
    t = ((t ^ ((t << 1) & _m)) ^ v0 ^ ((v0 << 4) & _m)) & _m;
    _v = t;
    _addend = (_addend + 362437) & _m;
    return (t + _addend) & _m;
  }

  int _bits(int n) => (_nextInt() >> (32 - n)) & ((1 << n) - 1);

  double nextDouble(double from, double until) {
    final hi = _bits(26);
    final lo = _bits(27);
    final r = ((hi << 27) + lo) / (1 << 53);
    return from + r * (until - from);
  }
}

class Synth {
  Synth(this.t, this.red, this.green, this.beats);
  final List<double> t;
  final List<double> red;
  final List<double> green;
  final List<double> beats;
}

/// Synthetisches Kamera-PPG wie in der Referenz: unregelmäßige Bildzeitpunkte, Pulsform mit
/// dikroter Welle, Rauschen, Grundliniendrift, optional Bewegungsartefakte.
Synth synth(
  double meanIbi,
  double rsaAmp,
  double jitterIbi,
  double noise,
  double fps,
  int seed, {
  List<double> artifacts = const [],
}) {
  final rnd = KotlinRandom(seed);
  final beats = <double>[];
  var tb = 0.2;
  while (tb < 70) {
    beats.add(tb);
    tb +=
        meanIbi +
        rsaAmp * math.sin(2 * math.pi * tb / 4.5) +
        jitterIbi * rnd.nextDouble(-1.0, 1.0);
  }
  double pulse(double t) {
    var s = 0.0;
    for (final b in beats) {
      final d = t - b;
      if (d < -0.3 || d > 1.2) continue;
      s +=
          math.exp(-((d - 0.12) * (d - 0.12)) / (2 * 0.05 * 0.05)) +
          0.35 * math.exp(-((d - 0.38) * (d - 0.38)) / (2 * 0.07 * 0.07));
    }
    return s;
  }

  final ts = <double>[];
  var t = 0.0;
  while (t < 70) {
    ts.add(t);
    t += 1 / fps + rnd.nextDouble(-0.004, 0.004);
  }
  // Bewegungsartefakt: ~0,8 s langsam dunkler, dann schnell zurück
  double art(double t) {
    var s = 0.0;
    for (final a in artifacts) {
      final d = t - a;
      if (d < -0.8 || d > 0.15) {
        s += 0.0;
      } else if (d < 0) {
        s += 8 * (d + 0.8) / 0.8;
      } else {
        s += 8 * (1 - d / 0.15);
      }
    }
    return s;
  }

  final red = [
    for (final x in ts)
      200 -
          3 * pulse(x) -
          art(x) +
          4 * math.sin(2 * math.pi * x / 25) +
          noise * rnd.nextDouble(-1.0, 1.0),
  ];
  final green = [
    for (final _ in ts) 40 + noise * 2 * rnd.nextDouble(-1.0, 1.0),
  ];
  return Synth(ts, red, green, beats);
}

/// Wahrer Puls und RMSSD aus den bekannten Schlägen im Fenster [a, b).
({double bpm, double rmssd}) truth(List<double> beats, double a, double b) {
  final ibi = [
    for (var i = 1; i < beats.length; i++)
      if (beats[i] >= a && beats[i] < b) (beats[i] - beats[i - 1]) * 1000,
  ];
  final d = [for (var i = 1; i < ibi.length; i++) ibi[i] - ibi[i - 1]];
  final mean = ibi.reduce((x, y) => x + y) / ibi.length;
  final ss = d.fold<double>(0, (s, e) => s + e * e);
  return (bpm: 60000 / mean, rmssd: math.sqrt(ss / d.length));
}
