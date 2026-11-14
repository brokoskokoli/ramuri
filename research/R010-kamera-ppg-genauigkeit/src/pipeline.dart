// R010: Varianten der Kamera-PPG-Auswertung auf Basis des unveränderten App-Codes.
// Die Bausteine (Spline, Biquad, Spektrum, Gipfel, Vorlage, Störabschnitte, Intervalle, Kennwerte)
// kommen aus app/packages/core/lib/src/ppg/. Nur die Vorbereitung (Raster, Tiefpass) und die
// Bezugspunkte sind hier parametrisiert. Mit den App-Werten (Raster 100 Hz, Tiefpass 4 Hz,
// Vorl.Anstieg) muss das Ergebnis bitgleich zur App sein (Kontrolle in checkAppEquality).
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../app/packages/core/lib/src/ppg/ppg_analyzer.dart';
import '../../../app/packages/core/lib/src/ppg/ppg_parameters.dart';
import '../../../app/packages/core/lib/src/ppg/ppg_signal.dart';

export '../../../app/packages/core/lib/src/ppg/ppg_analyzer.dart';
export '../../../app/packages/core/lib/src/ppg/ppg_evaluator.dart';
export '../../../app/packages/core/lib/src/ppg/ppg_parameters.dart';
export '../../../app/packages/core/lib/src/ppg/ppg_signal.dart';

class Prepared {
  Prepared(this.t0, this.x, this.fs);
  final double t0; // Zeit der ersten Probe relativ zum Fensterbeginn (s)
  final List<double> x;
  final double fs;
}

/// filtfilt wie in ppg_signal.dart, Rand in Proben als Parameter (App: 3 s × 100 Hz = 300).
List<double> filtfiltPad(List<double> x, Biquad f, int padWanted) {
  final n = x.length;
  final pad = math.min(n - 1, padWanted);
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

/// Wie PpgAnalyzer._prepare, aber Raster [fs] und Bandgrenzen wählbar.
Prepared prepare(List<double> tSec, List<double> values, PpgWindow w,
    {double fs = 100, double lp = 4.0, double hp = 0.5}) {
  final tl = <double>[];
  final yl = <double>[];
  for (var i = 0; i < tSec.length; i++) {
    final t = tSec[i];
    if (t < w.filterStart || t > w.dataEnd) continue;
    if (tl.isNotEmpty && t <= tl.last) continue;
    tl.add(t);
    yl.add(values[i]);
  }
  final g0 = (tl.first * fs).ceilToDouble() / fs;
  final n = ((tl.last - g0) * fs).toInt() + 1;
  final grid = List<double>.generate(n, (i) => g0 + i / fs);
  final ys = splineResample(tl, yl, grid);
  final m = average(ys);
  final inv = List<double>.generate(n, (i) => -(ys[i] - m));
  final pad = (ppgFilterPadSeconds * fs).toInt();
  final bp = filtfiltPad(
      filtfiltPad(inv, Biquad.highpass(hp, fs), pad), Biquad.lowpass(lp, fs), pad);
  final i0 = grid.indexWhere((g) => g >= w.start);
  final i1 = grid.lastIndexWhere((g) => g <= w.end);
  return Prepared(grid[i0] - w.start, bp.sublist(i0, i1 + 1), fs);
}

List<double> slope(List<double> x) => List<double>.generate(
    x.length, (i) => (i == 0 || i == x.length - 1) ? 0.0 : (x[i + 1] - x[i - 1]) / 2);

/// Ergebnis einer Variante: Schlagzeiten (s relativ zum Fensterbeginn, wie die App), Intervalle.
class BeatSeries {
  BeatSeries(this.times, this.ibi, this.valid, this.rmssdMs, this.bpm, this.noiseMs);
  final List<double> times;
  final List<double> ibi; // s
  final List<bool> valid;
  final double rmssdMs;
  final double bpm;
  final double noiseMs; // Zeitrauschen nach App-Formel (Vorl.Anstieg gegen max.Steigung)
}

/// Intervalle wie PpgAnalyzer.intervals, aber mit wählbarer Untergrenze der Ausreißerschwelle.
({List<double> end, List<double> ibi, List<bool> valid}) intervalsP(List<double> beats,
    List<bool>? beatOk, List<List<double>> artifacts, double minFrac) {
  if (minFrac == ppgOutlierMinFraction) return PpgAnalyzer.intervals(beats, beatOk, artifacts);
  final k = math.max(0, beats.length - 1);
  final ibi = List<double>.generate(k, (i) => beats[i + 1] - beats[i]);
  final end = List<double>.generate(k, (i) => beats[i + 1]);
  if (k == 0) return (end: end, ibi: ibi, valid: <bool>[]);
  final med = List<double>.generate(k, (i) {
    final win = <double>[
      for (var j = math.max(0, i - ppgOutlierMedianRadius);
          j <= math.min(k - 1, i + ppgOutlierMedianRadius);
          j++)
        ibi[j]
    ]..sort();
    return win[win.length ~/ 2];
  });
  final mrr = List<double>.generate(k, (i) => ibi[i] - med[i]);
  final sorted = List<double>.of(mrr)..sort();
  final qd = (sorted[(3 * (k - 1)) ~/ 4] - sorted[(k - 1) ~/ 4]) / 2;
  final medAll = (List<double>.of(ibi)..sort())[k ~/ 2];
  final th = coerceIn(ppgOutlierQuartileFactor * qd, minFrac * medAll, ppgOutlierMaxFraction * medAll);
  final outlier = List<bool>.generate(k, (i) => mrr[i].abs() > th);
  final valid = List<bool>.generate(k, (i) {
    if (!(ibi[i] >= ppgIntervalMinSeconds && ibi[i] <= ppgIntervalMaxSeconds)) return false;
    if (outlier[i]) return false;
    for (final j in [i - 1, i + 1]) {
      if (j >= 0 && j < k && outlier[j] && mrr[j] * mrr[i] < 0 && mrr[i].abs() > th / 2) return false;
    }
    if (beatOk != null && !(beatOk[i] && beatOk[i + 1])) return false;
    for (final a in artifacts) {
      if (beats[i] <= a[1] && beats[i + 1] >= a[0]) return false;
    }
    return true;
  });
  return (end: end, ibi: ibi, valid: valid);
}

/// Alle Bezugspunkte auf einem vorbereiteten Signal. Schlüssel = Name der Variante.
Map<String, BeatSeries> fiducials(Prepared p, PpgWindow w, {double minFrac = 0.08, Set<String>? only}) {
  final x = p.x;
  final fs = p.fs;
  final f0 = dominantFrequency(x, fs).f0;
  final peaks = PpgAnalyzer.detectPeaks(x, fs, f0);
  final dx = slope(x);
  final searchBack = (ppgSlopeSearchPeriods / f0 * fs).toInt();
  final slopeT = <double>[];
  final slopeI = <int>[];
  final footT = <double>[];
  final footI = <int>[];
  for (var k = 0; k < peaks.length; k++) {
    final pk = peaks[k];
    final lo = math.max(k > 0 ? peaks[k - 1] + 1 : 1, pk - searchBack);
    var best = pk;
    for (var i = lo; i <= pk; i++) {
      if (dx[i] > dx[best]) best = i;
    }
    slopeI.add(best);
    slopeT.add(refine(dx, best) / fs);
    var mi = best;
    for (var i = lo; i <= best; i++) {
      if (x[i] < x[mi]) mi = i;
    }
    footI.add(mi);
    footT.add(refine(x, mi) / fs);
  }
  final art = PpgAnalyzer.detectArtifacts(x, fs, peaks, f0);
  final dur = w.end - w.start;
  final slopeIdx = [for (final s in slopeT) roundHalfUp(s * fs)];
  final tmUp = PpgAnalyzer.templateMatch(x, fs, slopeIdx, f0, ppgRiseBeatPreFraction, ppgRiseBeatPostFraction,
      refOnSlope: true);
  final upOk = [for (final c in tmUp.corr) c >= ppgMinCorrelation];

  // Zeitrauschen nach App-Formel (ALGORITHMUS.md Abschn. 8), auf Vorl.Anstieg bezogen.
  final ivUp = intervalsP(tmUp.times, upOk, art, minFrac);
  final mv = ivUp.valid;
  final okBeat = [
    for (var k = 0; k < peaks.length; k++) (k > 0 && k - 1 < mv.length && mv[k - 1]) || (k < mv.length && mv[k])
  ];
  final dd = <double>[];
  for (var k = 1; k < peaks.length; k++) {
    if (okBeat[k] && okBeat[k - 1]) {
      dd.add(((tmUp.times[k] - slopeT[k]) - (tmUp.times[k - 1] - slopeT[k - 1])) * 1000);
    }
  }
  var noise = double.nan;
  if (dd.length >= 5) {
    var sq = 0.0;
    for (final d in dd) {
      sq += d * d;
    }
    noise = math.sqrt(sq / dd.length / 2);
  }

  BeatSeries mk(List<double> times, List<bool>? ok) {
    final iv = intervalsP(times, ok, art, minFrac);
    final st = PpgAnalyzer.stats(times, iv.end, iv.ibi, iv.valid, 0.0, dur + 1e-9);
    return BeatSeries(times, iv.ibi, iv.valid, st.rmssdMs, st.bpm, noise);
  }

  bool want(String n) => only == null || only.contains(n);
  final out = <String, BeatSeries>{};
  if (want('tplRise')) out['tplRise'] = mk(tmUp.times, upOk);
  if (want('slope')) out['slope'] = mk(slopeT, null);
  if (want('peak')) out['peak'] = mk([for (final pk in peaks) refine(x, pk) / fs], null);
  if (want('tpl')) {
    final tm = PpgAnalyzer.templateMatch(x, fs, peaks, f0, ppgWholeBeatPreFraction, ppgWholeBeatPostFraction);
    out['tpl'] = mk(tm.times, [for (final c in tm.corr) c >= ppgMinCorrelation]);
  }
  if (want('foot')) out['foot'] = mk(footT, null);
  if (want('tangent')) {
    // Tangentenschnitt: Tangente im steilsten Anstieg schneidet die Waagrechte durch das Minimum davor.
    final tt = <double>[];
    for (var k = 0; k < peaks.length; k++) {
      final i = slopeI[k];
      final ts = slopeT[k] * fs; // Index mit Nachkomma
      final fr = ts - i;
      final xs = fr >= 0 ? x[i] + fr * (x[i + 1] - x[i]) : x[i] + fr * (x[i] - x[i - 1]);
      final m = dx[i];
      final xmin = x[footI[k]];
      tt.add(m > 0 ? (ts - (xs - xmin) / m) / fs : slopeT[k]);
    }
    out['tangent'] = mk(tt, null);
  }
  if (want('d50')) {
    final tt = <double>[];
    for (var k = 0; k < peaks.length; k++) {
      final lvl = (x[footI[k]] + x[peaks[k]]) / 2;
      var t = slopeT[k];
      for (var i = footI[k]; i < peaks[k]; i++) {
        if (x[i] < lvl && x[i + 1] >= lvl) {
          t = (i + (lvl - x[i]) / (x[i + 1] - x[i])) / fs;
          break;
        }
      }
      tt.add(t);
    }
    out['d50'] = mk(tt, null);
  }
  if (want('mix')) {
    out['mix'] = mk([for (var k = 0; k < peaks.length; k++) (tmUp.times[k] + slopeT[k]) / 2], upOk);
  }
  return out;
}

/// RMSSD (ms) aus Intervallen (s) mit Gültigkeit, nur benachbarte gültige Paare.
double rmssdOf(List<double> ibi, List<bool> valid) {
  var s = 0.0;
  var n = 0;
  for (var i = 1; i < ibi.length; i++) {
    if (valid[i] && valid[i - 1]) {
      final d = (ibi[i] - ibi[i - 1]) * 1000;
      s += d * d;
      n++;
    }
  }
  return n > 0 ? math.sqrt(s / n) : double.nan;
}

/// Gleitender Median über 3 gültige Intervalle (Glättung der RR-Folge), ungültige bleiben ungültig.
List<double> median3(List<double> ibi, List<bool> valid) => List<double>.generate(ibi.length, (i) {
      if (!valid[i]) return ibi[i];
      final v = <double>[ibi[i]];
      if (i > 0 && valid[i - 1]) v.add(ibi[i - 1]);
      if (i + 1 < ibi.length && valid[i + 1]) v.add(ibi[i + 1]);
      if (v.length < 3) return ibi[i];
      v.sort();
      return v[1];
    });

/// Zuordnung Kamera-Schläge (absolute Zeit) zu Referenzschlägen (absolute Zeit): erst Versatz
/// (Median der nächsten Abstände, zweimal), dann je Kamera-Schlag der nächste Referenzschlag
/// innerhalb [tol]. Ergebnis: Index des Referenzschlags je Kamera-Schlag oder -1; Versatz.
({List<int> idx, double offset}) matchBeats(List<double> cam, List<double> ref, {double tol = 0.15, double? offset}) {
  int nearest(double t) {
    var lo = 0, hi = ref.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (ref[mid] < t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (t - ref[lo]).abs() <= (t - ref[hi]).abs() ? lo : hi;
  }

  var off = offset ?? 0.0;
  if (offset == null) {
    // grober Versatz: Median der Abstände zum nächsten Schlag, zweimal verfeinert
    for (var it = 0; it < 3; it++) {
      final d = [for (final c in cam) c - off - ref[nearest(c - off)]]..sort();
      off += d[d.length ~/ 2];
    }
  }
  final idx = <int>[];
  for (final c in cam) {
    final j = nearest(c - off);
    idx.add((c - off - ref[j]).abs() <= tol ? j : -1);
  }
  return (idx: idx, offset: off);
}

/// Vergleich einer Kamera-Folge mit Referenz-R-Zacken: Fehler je Intervall und RMSSD auf
/// denselben Intervallpaaren.
class Compare {
  Compare(this.errMs, this.rmssdCam, this.rmssdRef, this.pairs, this.validFrac);
  final List<double> errMs;
  final double rmssdCam;
  final double rmssdRef;
  final int pairs;
  final double validFrac;
  double get lnRatio => math.log(rmssdCam / rmssdRef);
}

Compare compareToRef(List<double> camAbs, List<double> ibi, List<bool> valid, List<double> refAbs,
    {double tol = 0.15, double? offset, List<double>? camIbiOverride}) {
  final m = matchBeats(camAbs, refAbs, tol: tol, offset: offset);
  final camIbi = camIbiOverride ?? ibi;
  final ok = List<bool>.generate(ibi.length, (i) {
    if (!valid[i]) return false;
    final a = m.idx[i], b = m.idx[i + 1];
    return a >= 0 && b == a + 1;
  });
  final err = <double>[];
  final refIbi = List<double>.filled(ibi.length, double.nan);
  for (var i = 0; i < ibi.length; i++) {
    if (!ok[i]) continue;
    refIbi[i] = refAbs[m.idx[i + 1]] - refAbs[m.idx[i]];
    err.add((camIbi[i] - refIbi[i]) * 1000);
  }
  var sc = 0.0, sr = 0.0;
  var n = 0;
  for (var i = 1; i < ibi.length; i++) {
    if (ok[i] && ok[i - 1]) {
      final dc = (camIbi[i] - camIbi[i - 1]) * 1000;
      final dr = (refIbi[i] - refIbi[i - 1]) * 1000;
      sc += dc * dc;
      sr += dr * dr;
      n++;
    }
  }
  final nv = valid.where((v) => v).length;
  return Compare(err, n > 0 ? math.sqrt(sc / n) : double.nan, n > 0 ? math.sqrt(sr / n) : double.nan, n,
      ibi.isEmpty ? 0 : nv / ibi.length);
}

double rms(Iterable<double> v) {
  var s = 0.0;
  var n = 0;
  for (final x in v) {
    s += x * x;
    n++;
  }
  return n > 0 ? math.sqrt(s / n) : double.nan;
}

double quantile(List<double> v, double q) {
  final s = v.where((x) => x.isFinite).toList()..sort();
  if (s.isEmpty) return double.nan;
  final pos = q * (s.length - 1);
  final lo = pos.floor(), hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

double mean(Iterable<double> v) {
  final l = v.where((x) => x.isFinite).toList();
  return l.isEmpty ? double.nan : l.reduce((a, b) => a + b) / l.length;
}

double sd(Iterable<double> v) {
  final l = v.where((x) => x.isFinite).toList();
  if (l.length < 2) return double.nan;
  final m = l.reduce((a, b) => a + b) / l.length;
  return math.sqrt(l.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / (l.length - 1));
}

String f1(double v) => v.isFinite ? v.toStringAsFixed(1) : '–';
String f2(double v) => v.isFinite ? v.toStringAsFixed(2) : '–';
String f3(double v) => v.isFinite ? v.toStringAsFixed(3) : '–';
