// Synthetische Kamera-PPG-Aufnahme mit bekannter Schlagfolge (R010, README Methode 3).
import 'dart:math' as math;

class Rng {
  Rng(int seed) : _r = math.Random(seed);
  final math.Random _r;
  double u() => _r.nextDouble();
  double n() {
    // Box-Muller
    final a = math.max(1e-300, _r.nextDouble());
    return math.sqrt(-2 * math.log(a)) * math.cos(2 * math.pi * _r.nextDouble());
  }
}

class SynthParams {
  const SynthParams({
    this.fps = 60,
    this.rmssdMs = 40,
    this.colored = 0.08,
    this.white = 0.05,
    this.pttJitterMs = 2,
    this.frameJitterMs = 0.0,
    this.dropProb = 0.0,
    this.dur = 70,
    this.exposureFrac = 0.9,
    this.shapeVar = 0.03,
    this.disturb = false,
    this.noisyUntil = 0,
    this.noisyFactor = 1,
  });
  final double fps;
  final double rmssdMs; // Ziel-RMSSD der R-Zacken im Fenster
  final double colored; // SD des Störsignals im Pulsband, relativ zur Pulsamplitude
  final double white; // SD des Bildrauschens je Bild, relativ zur Pulsamplitude
  final double pttJitterMs; // weißes Rauschen der Pulslaufzeit von Schlag zu Schlag
  final double frameJitterMs; // Schwankung der echten Belichtungszeitpunkte
  final double dropProb; // Anteil verlorener Bilder
  final double dur;
  final double exposureFrac; // Belichtungszeit als Anteil des Bildabstands
  final double shapeVar; // relative Schwankung der Anstiegszeit je Schlag
  final bool disturb; // eine Störung (Druckänderung) im Fenster
  final double noisyUntil; // bis zu dieser Zeit (s) ist das Störsignal um noisyFactor stärker (unruhiger Anfang)
  final double noisyFactor;
}

class SynthRec {
  SynthRec(this.tSensor, this.tNominal, this.y, this.y2, this.rPeaks, this.onsets);
  final List<double> tSensor; // Sensor-Zeitstempel der gelieferten Bilder
  final List<double> tNominal; // Index / Nennrate (was eine App ohne Zeitstempel annähme)
  final List<double> y; // Bildmittel Kanal 1 (Helligkeit, mehr Blut = dunkler)
  final List<double> y2; // zweiter Kanal mit unabhängigem Rauschen (gleiche Physiologie)
  final List<double> rPeaks; // R-Zacken (Referenz, wie Brustgurt)
  final List<double> onsets; // Fußpunkte der Pulswelle am Finger
}

double _gam(double tau, double tp, double a) => tau <= 0 ? 0.0 : math.pow(tau / tp, a) * math.exp(a * (1 - tau / tp));

SynthRec synth(SynthParams p, Rng rng) {
  // 1) RR-Folge: Atemmodulation + AR(1), auf Ziel-RMSSD skaliert
  final hr = 50 + 20 * rng.u();
  final rr0 = 60 / hr;
  final fResp = 0.2 + 0.1 * rng.u();
  final ph = 2 * math.pi * rng.u();
  final nB = ((p.dur + 4) / rr0 * 1.3).ceil();
  final dev = <double>[];
  var ar = 0.0;
  for (var k = 0; k < nB; k++) {
    ar = 0.5 * ar + math.sqrt(1 - 0.25) * rng.n();
    dev.add(math.sin(2 * math.pi * fResp * k * rr0 + ph) + 0.7 * ar);
  }
  var s = 0.0;
  for (var k = 1; k < nB; k++) {
    s += math.pow(dev[k] - dev[k - 1], 2);
  }
  final scale = p.rmssdMs / 1000 / math.sqrt(s / (nB - 1));
  final r = <double>[];
  var t = -2.0;
  for (var k = 0; k < nB && t < p.dur + 2; k++) {
    final rr = (rr0 + scale * dev[k]).clamp(0.4, 1.6);
    t += rr;
    r.add(t);
  }
  // 2) Pulslaufzeit und Form je Schlag
  final ph2 = 2 * math.pi * rng.u();
  final on = <double>[];
  final amp = <double>[];
  final tp = <double>[];
  final dic = <double>[];
  for (final rk in r) {
    on.add(rk + 0.25 + 0.004 * math.sin(2 * math.pi * fResp * rk + ph2) + p.pttJitterMs / 1000 * rng.n());
    amp.add(1 + 0.12 * math.sin(2 * math.pi * fResp * rk + ph) + 0.05 * rng.n());
    tp.add(0.13 * (1 + p.shapeVar * rng.n()));
    dic.add(0.35 * (1 + 0.15 * rng.n()));
  }
  // 3) Störsignal im Pulsband: Summe zufälliger Schwingungen 0,5–6 Hz, SD = colored
  const nSin = 40;
  final sf = List<double>.generate(nSin, (_) => 0.5 + 5.5 * rng.u());
  final sp = List<double>.generate(nSin, (_) => 2 * math.pi * rng.u());
  final sf2 = List<double>.generate(nSin, (_) => 0.5 + 5.5 * rng.u());
  final sp2 = List<double>.generate(nSin, (_) => 2 * math.pi * rng.u());
  final sa = p.colored * math.sqrt(2 / nSin);
  final bph = 2 * math.pi * rng.u();
  double distAt(double tt) {
    if (!p.disturb) return 0.0;
    // Druckänderung bei 30 s: Stufe von 3 Pulsamplituden über 0,4 s, langsam zurück
    if (tt < 30) return 0.0;
    final a = tt < 30.4 ? (tt - 30) / 0.4 : math.exp(-(tt - 30.4) / 2);
    return 3 * a;
  }

  double pulse(double tt) {
    var v = 0.0;
    for (var k = 0; k < on.length; k++) {
      final tau = tt - on[k];
      if (tau < 0) break;
      if (tau > 1.5) continue;
      v += amp[k] * (_gam(tau, tp[k], 3) + dic[k] * _gam(tau - 0.18, 0.12, 4));
    }
    return v;
  }

  double bright(double tt, List<double> f, List<double> phs) {
    var c = 0.0;
    for (var i = 0; i < nSin; i++) {
      c += math.sin(2 * math.pi * f[i] * tt + phs[i]);
    }
    // Pulsamplitude 1 = 0,8 % des Gleichanteils 180; Grundlinie atmet mit
    final base = 0.5 * math.sin(2 * math.pi * fResp * tt + bph) + 0.4 * math.sin(2 * math.pi * 0.03 * tt);
    final k = tt < p.noisyUntil ? p.noisyFactor : 1.0;
    return 180 * (1 - 0.008 * (pulse(tt) + base + k * sa * c + distAt(tt)));
  }

  // 4) Bilder: Belichtung als Mittel über das Belichtungsfenster, Zeitstempel = Belichtungsbeginn
  final ts = <double>[], tn = <double>[], y = <double>[], y2 = <double>[];
  final dt = 1 / p.fps;
  final exp = p.exposureFrac * dt;
  final nF = (p.dur * p.fps).floor();
  for (var i = 0; i < nF; i++) {
    final ti = i * dt + p.frameJitterMs / 1000 * rng.n();
    final w1 = 180 * 0.008 * p.white * rng.n();
    final w2 = 180 * 0.008 * p.white * rng.n();
    if (rng.u() < p.dropProb) continue;
    var a = 0.0, b = 0.0;
    const sub = 4;
    for (var j = 0; j < sub; j++) {
      final tt = ti + exp * (j + 0.5) / sub;
      a += bright(tt, sf, sp);
      b += bright(tt, sf2, sp2);
    }
    ts.add(ti);
    tn.add(ts.length - 1 == 0 ? 0.0 : (ts.length - 1) * dt);
    y.add(a / sub + w1);
    y2.add(b / sub + w2);
  }
  return SynthRec(ts, tn, y, y2, r, on);
}
