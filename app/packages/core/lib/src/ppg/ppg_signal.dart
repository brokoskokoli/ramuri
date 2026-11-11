import 'dart:math' as math;
import 'dart:typed_data';

import 'ppg_parameters.dart';

/// Signalbausteine des Kamera-PPG-Verfahrens (ALGORITHMUS.md, Abschn. 3 bis 5).
/// Eins zu eins nach `PpgAnalyzer.kt`; Fließkommareihenfolge und Randfälle
/// (Kotlin-`coerceIn` mit NaN, `Math.round`) bleiben erhalten.

/// Kotlin `coerceIn`: NaN bleibt NaN (Dart `clamp` würde anders behandeln).
double coerceIn(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// Kotlin `Math.round` für Double (Abrunden von x + 0,5).
int roundHalfUp(double x) => (x + 0.5).floor();

/// Mittelwert in Summationsreihenfolge (Kotlin `average`); leer ergibt NaN.
double average(List<double> v) {
  var s = 0.0;
  for (final x in v) {
    s += x;
  }
  return s / v.length;
}

/// Parabel durch drei Punkte, Index mit Nachkommastellen.
double refine(List<double> y, int i) {
  if (i <= 0 || i >= y.length - 1) return i.toDouble();
  final den = y[i - 1] - 2 * y[i] + y[i + 1];
  if (den == 0.0) return i.toDouble();
  return i + coerceIn(0.5 * (y[i - 1] - y[i + 1]) / den, -0.5, 0.5);
}

/// Goertzel-Spektrum 0,5 bis 4 Hz mit Hann-Fenster. Ergebnis: Grundfrequenz (Hz), Qualität Q.
({double f0, double quality}) dominantFrequency(List<double> x, double fs) {
  final n = x.length;
  final w = List<double>.generate(
    n,
    (i) => x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))),
  );
  final freqs = <double>[];
  final pow = <double>[];
  var f = ppgSpectrumStartHz;
  while (f <= ppgSpectrumEndHz) {
    final c = 2 * math.cos(2 * math.pi * f / fs);
    var s1 = 0.0;
    var s2 = 0.0;
    for (final v in w) {
      final s = v + c * s1 - s2;
      s2 = s1;
      s1 = s;
    }
    freqs.add(f);
    pow.add(s1 * s1 + s2 * s2 - c * s1 * s2);
    f += ppgSpectrumStepHz;
  }
  var bi = -1;
  for (var i = 0; i < freqs.length; i++) {
    if (freqs[i] >= ppgPulseMinHz &&
        freqs[i] <= ppgPulseMaxHz &&
        (bi < 0 || pow[i] > pow[bi])) {
      bi = i;
    }
  }
  final f0 = freqs[bi];
  var sig = 0.0;
  var tot = 0.0;
  for (var i = 0; i < freqs.length; i++) {
    tot += pow[i];
    if ((freqs[i] - f0).abs() <= ppgFundamentalHalfWidthHz ||
        (freqs[i] - 2 * f0).abs() <= ppgHarmonicHalfWidthHz) {
      sig += pow[i];
    }
  }
  double fr;
  if (bi >= 1 && bi < freqs.length - 1) {
    final d = pow[bi - 1] - 2 * pow[bi] + pow[bi + 1];
    fr = d != 0.0
        ? f0 +
              ppgSpectrumStepHz *
                  coerceIn(0.5 * (pow[bi - 1] - pow[bi + 1]) / d, -0.5, 0.5)
        : f0;
  } else {
    fr = f0;
  }
  return (f0: fr, quality: tot > 0 ? sig / tot : 0.0);
}

/// Zentrierter gleitender Mittelwert über [win] Werte, abgezogen.
List<double> subtractMovingMean(List<double> x, int win) {
  final n = x.length;
  final cs = List<double>.filled(n + 1, 0.0);
  for (var i = 0; i < n; i++) {
    cs[i + 1] = cs[i] + x[i];
  }
  final h = win ~/ 2;
  return List<double>.generate(n, (i) {
    final a = math.max(0, i - h);
    final b = math.min(n, i + h + 1);
    return x[i] - (cs[b] - cs[a]) / (b - a);
  });
}

/// Natürlicher kubischer Spline; [x] streng steigend.
List<double> splineResample(List<double> x, List<double> y, List<double> xs) {
  final n = x.length;
  final h = List<double>.generate(n - 1, (i) => x[i + 1] - x[i]);
  final a = List<double>.filled(n, 0.0);
  final b = List<double>.filled(n, 0.0);
  final c = List<double>.filled(n, 0.0);
  final d = List<double>.filled(n, 0.0);
  b[0] = 1.0;
  b[n - 1] = 1.0;
  for (var i = 1; i < n - 1; i++) {
    a[i] = h[i - 1];
    b[i] = 2 * (h[i - 1] + h[i]);
    c[i] = h[i];
    d[i] = 6 * ((y[i + 1] - y[i]) / h[i] - (y[i] - y[i - 1]) / h[i - 1]);
  }
  for (var i = 1; i < n; i++) {
    final mm = a[i] / b[i - 1];
    b[i] -= mm * c[i - 1];
    d[i] -= mm * d[i - 1];
  }
  final m = List<double>.filled(n, 0.0);
  m[n - 1] = d[n - 1] / b[n - 1];
  for (var i = n - 2; i >= 0; i--) {
    m[i] = (d[i] - c[i] * m[i + 1]) / b[i];
  }
  var k = 0;
  return List<double>.generate(xs.length, (j) {
    final xv = xs[j];
    while (k < n - 2 && x[k + 1] < xv) {
      k++;
    }
    final hk = h[k];
    final aa = (x[k + 1] - xv) / hk;
    final bb = (xv - x[k]) / hk;
    return aa * y[k] +
        bb * y[k + 1] +
        ((aa * aa * aa - aa) * m[k] + (bb * bb * bb - bb) * m[k + 1]) *
            hk *
            hk /
            6;
  });
}

/// Biquad-Filter 2. Ordnung (Butterworth).
class Biquad {
  const Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  final double b0, b1, b2, a1, a2;

  factory Biquad.lowpass(double fc, double fs) {
    final w = 2 * math.pi * fc / fs;
    final al = math.sin(w) / (2 * ppgButterworthQ);
    final cs = math.cos(w);
    final a0 = 1 + al;
    return Biquad(
      (1 - cs) / 2 / a0,
      (1 - cs) / a0,
      (1 - cs) / 2 / a0,
      -2 * cs / a0,
      (1 - al) / a0,
    );
  }

  factory Biquad.highpass(double fc, double fs) {
    final w = 2 * math.pi * fc / fs;
    final al = math.sin(w) / (2 * ppgButterworthQ);
    final cs = math.cos(w);
    final a0 = 1 + al;
    return Biquad(
      (1 + cs) / 2 / a0,
      -(1 + cs) / a0,
      (1 + cs) / 2 / a0,
      -2 * cs / a0,
      (1 - al) / a0,
    );
  }

  List<double> run(List<double> x) {
    var z1 = 0.0;
    var z2 = 0.0;
    final out = Float64List(x.length);
    for (var i = 0; i < x.length; i++) {
      final v = x[i];
      final o = b0 * v + z1;
      z1 = b1 * v - a1 * o + z2;
      z2 = b2 * v - a2 * o;
      out[i] = o;
    }
    return out;
  }
}

/// Vorwärts und rückwärts filtern (phasenfrei), Ränder ungerade gespiegelt.
List<double> filtfilt(List<double> x, Biquad f) {
  final n = x.length;
  final pad = math.min(n - 1, (ppgFilterPadSeconds * ppgGridRate).toInt());
  final ext = Float64List(n + 2 * pad);
  for (var i = 0; i < pad; i++) {
    ext[i] = 2 * x[0] - x[pad - i];
  }
  for (var i = 0; i < n; i++) {
    ext[pad + i] = x[i];
  }
  for (var i = 0; i < pad; i++) {
    ext[pad + n + i] = 2 * x[n - 1] - x[n - 2 - i];
  }
  final y = f.run(f.run(ext).reversed.toList()).reversed.toList();
  return y.sublist(pad, pad + n);
}
