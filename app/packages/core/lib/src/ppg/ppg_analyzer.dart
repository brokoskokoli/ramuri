import 'dart:math' as math;

import 'ppg_parameters.dart';
import 'ppg_signal.dart';

/// Zu wenige oder unpassende Bilder für das Messfenster (kein Programmfehler).
class PpgInsufficientDataException implements Exception {
  const PpgInsufficientDataException(this.message);
  final String message;

  @override
  String toString() => 'PpgInsufficientDataException: $message';
}

/// Alle Signalquellen haben im Messfenster konstante (numerisch flache) Rohwerte, z. B. ein
/// übersteuerter Kanal. Es gibt nichts auszuwerten (kein Programmfehler).
class PpgFlatSignalException implements Exception {
  const PpgFlatSignalException(this.message);
  final String message;

  @override
  String toString() => 'PpgFlatSignalException: $message';
}

/// Kennwerte über einen Zeitabschnitt. Zeiten in ms, Puls in 1/min; NaN = nicht berechenbar.
class HrvStats {
  const HrvStats({
    required this.beats,
    required this.ibis,
    required this.validIbis,
    required this.bpm,
    required this.meanIbiMs,
    required this.sdnnMs,
    required this.rmssdMs,
    required this.pnn50,
    required this.minBpm,
    required this.maxBpm,
  });

  final int beats;
  final int ibis;
  final int validIbis;
  final double bpm;
  final double meanIbiMs;
  final double sdnnMs;
  final double rmssdMs;
  final double pnn50;
  final double minBpm;
  final double maxBpm;
}

/// Ergebnis eines Verfahrens zur Bestimmung der Schlagzeitpunkte.
class PpgMethodResult {
  const PpgMethodResult({
    required this.name,
    required this.times,
    required this.ibiEnd,
    required this.ibiMs,
    required this.valid,
    required this.total,
    required this.first,
    required this.second,
  });

  final String name;

  /// Schlagzeitpunkte (s).
  final List<double> times;

  /// Ende je Intervall (s), Intervall (ms), gültig ja/nein.
  final List<double> ibiEnd;
  final List<double> ibiMs;
  final List<bool> valid;
  final HrvStats total;
  final HrvStats first;
  final HrvStats second;
}

class PpgTemplateResult {
  const PpgTemplateResult({
    required this.times,
    required this.corr,
    required this.template,
  });

  /// Schlagzeitpunkte (s), auf den Bezugspunkt der Vorlage bezogen.
  final List<double> times;

  /// Pearson-Korrelation jedes Schlags mit der Vorlage.
  final List<double> corr;
  final List<double> template;
}

/// Auswertung einer Signalquelle (Kanal).
class PpgChannelResult {
  const PpgChannelResult({
    required this.channel,
    required this.methods,
    required this.artifacts,
    required this.spectralBpm,
    required this.quality,
    required this.meanFps,
    required this.frameJitterMs,
    required this.timingNoiseMs,
  });

  final String channel;

  /// Das erste Verfahren ist das Hauptergebnis (Vorlagenabgleich über den Anstieg).
  final List<PpgMethodResult> methods;

  /// Gestörte Abschnitte [von, bis] in s.
  final List<List<double>> artifacts;
  final double spectralBpm;

  /// Anteil der Signalleistung am Puls-Grundton + 1. Oberton (0..1).
  final double quality;
  final double meanFps;
  final double frameJitterMs;

  /// Geschätztes Zeitrauschen der Schlagzeitpunkte (ms); NaN, wenn nicht schätzbar.
  final double timingNoiseMs;

  PpgMethodResult get main => methods[0];
}

/// Alle ausgewerteten Signalquellen; [best] ist die gewählte.
class PpgAnalysisSet {
  const PpgAnalysisSet({
    required this.best,
    required this.all,
    required this.blocksUsed,
    required this.blocksScored,
  });

  final PpgChannelResult best;
  final List<PpgChannelResult> all;

  /// Teilbereiche in der Kombination / bewertet (0, wenn keine Teilbereiche übergeben wurden).
  final int blocksUsed;
  final int blocksScored;
}

/// Benannte Signalreihe (Kanal oder Teilbereich).
class PpgSeries {
  const PpgSeries(this.name, this.values);
  final String name;
  final List<double> values;
}

/// Vorbereitetes Signal im Messfenster.
class _Prepared {
  _Prepared(this.t, this.x, this.dtMean, this.dtSd);
  final List<double> t;
  final List<double> x;
  final double dtMean;
  final double dtSd;
}

const String _mTemplate = 'Vorlage';
const String _mTemplateRise = 'Vorl.Anstieg';
const String _mPeak = 'Gipfel';
const String _mSlope = 'max.Steigung';

/// Port von `PpgAnalyzer.kt` (ALGORITHMUS.md). Reines Dart, ohne Zustand.
/// Für die Anwendung gibt es `evaluatePpg`; diese Klasse liefert die Einzelergebnisse.
abstract final class PpgAnalyzer {
  /// [signals]: Bildmitte (z. B. Rot, Grün); [blocks]: Teilbereiche, daraus entsteht „Kombi“.
  static PpgAnalysisSet analyze(
    List<double> tSec,
    List<PpgSeries> signals,
    List<PpgSeries> blocks,
    PpgWindow w,
  ) {
    // Abweichung von der Referenz (Methode camera-ppg v1, nur Fehlerfall): Quellen mit
    // konstanten Rohwerten im Messfenster werden nicht ausgewertet. Sonst würde Rundungsrauschen
    // als Signal gelten und ein gesättigter Kanal mit Zeitrauschen ≈ 0 jede echte Quelle
    // schlagen (chooseBest). Die Fixture der Referenz enthält keine solche Quelle.
    final live = [
      for (final s in signals)
        if (!isFlat(tSec, s.values, w)) s,
    ];
    if (live.isEmpty) {
      throw const PpgFlatSignalException(
        'Alle Signalquellen sind im Messfenster konstant',
      );
    }
    final liveBlocks = [
      for (final b in blocks)
        if (!isFlat(tSec, b.values, w)) b,
    ];
    final all = [
      for (final s in live) analyzeChannel(s.name, tSec, s.values, w),
    ];
    var used = 0;
    var scored = 0;
    if (liveBlocks.isNotEmpty) {
      final c = combineBlocks(tSec, liveBlocks, w);
      used = c.used;
      scored = c.scored;
      if (c.combo != null) all.add(analyzeChannel('Kombi', tSec, c.combo!, w));
    }
    return PpgAnalysisSet(
      best: chooseBest(all),
      all: all,
      blocksUsed: used,
      blocksScored: scored,
    );
  }

  /// Konstante Rohwerte im Messfenster: Spannweite höchstens [ppgFlatRelativeTolerance] des
  /// größten Betrags (ein einzelner Wert, auch ein leeres Fenster, zählt als flach).
  static bool isFlat(List<double> tSec, List<double> values, PpgWindow w) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (var i = 0; i < tSec.length; i++) {
      final t = tSec[i];
      if (t < w.start || t > w.end) continue;
      final v = values[i];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    if (!(hi > lo)) return true;
    return hi - lo <= ppgFlatRelativeTolerance * math.max(hi.abs(), lo.abs());
  }

  /// Wahl der Signalquelle (Abschn. 9): unter den Quellen mit brauchbarem Puls die mit dem
  /// kleinsten Zeitrauschen; sonst die mit höchstem Q.
  static PpgChannelResult chooseBest(List<PpgChannelResult> all) {
    PpgChannelResult? best;
    for (final r in all) {
      final ok =
          r.quality >= ppgSourceMinQuality &&
          r.timingNoiseMs.isFinite &&
          r.main.total.validIbis >=
              ppgSourceMinValidFraction * math.max(1, r.main.total.ibis);
      if (ok && (best == null || r.timingNoiseMs < best.timingNoiseMs)) {
        best = r;
      }
    }
    if (best != null) return best;
    var top = all.first;
    for (final r in all) {
      if (r.quality > top.quality) top = r;
    }
    return top;
  }

  static _Prepared _prepare(
    List<double> tSec,
    List<double> values,
    PpgWindow w,
  ) {
    // 1) Abschnitt wählen, nur streng steigende Zeitstempel
    final tl = <double>[];
    final yl = <double>[];
    for (var i = 0; i < tSec.length; i++) {
      final t = tSec[i];
      if (t < w.filterStart || t > w.dataEnd) continue;
      if (tl.isNotEmpty && t <= tl.last) continue;
      tl.add(t);
      yl.add(values[i]);
    }
    if (tl.length <= ppgMinFrames) {
      throw PpgInsufficientDataException(
        'Zu wenige Kamerabilder (${tl.length})',
      );
    }
    final dts = <double>[];
    for (var i = 1; i < tl.length; i++) {
      if (tl[i] >= w.start && tl[i] <= w.end) dts.add(tl[i] - tl[i - 1]);
    }
    final dtMean = average(dts);
    var dtSum = 0.0;
    for (final d in dts) {
      dtSum += (d - dtMean) * (d - dtMean);
    }
    final dtSd = math.sqrt(dtSum / math.max(1, dts.length - 1));

    // 2) gleichmäßiges 100-Hz-Raster per kubischem Spline
    final g0 = (tl.first * ppgGridRate).ceilToDouble() / ppgGridRate;
    final n = ((tl.last - g0) * ppgGridRate).toInt() + 1;
    final grid = List<double>.generate(n, (i) => g0 + i / ppgGridRate);
    final ys = splineResample(tl, yl, grid);

    // 3) invertieren, Mittelwert ab, Bandpass 0,5 bis 4 Hz phasenfrei
    final m = average(ys);
    final inv = List<double>.generate(n, (i) => -(ys[i] - m));
    final bp = filtfilt(
      filtfilt(inv, Biquad.highpass(ppgBandLowHz, ppgGridRate)),
      Biquad.lowpass(ppgBandHighHz, ppgGridRate),
    );

    // 4) Messfenster
    final i0 = grid.indexWhere((g) => g >= w.start);
    final i1 = grid.lastIndexWhere((g) => g <= w.end);
    if (i0 < 0 || i1 < i0) {
      throw const PpgInsufficientDataException('Messfenster nicht abgedeckt');
    }
    return _Prepared(
      List<double>.generate(i1 - i0 + 1, (i) => grid[i0 + i] - w.start),
      bp.sublist(i0, i1 + 1),
      dtMean,
      dtSd,
    );
  }

  /// Wertet einen Kanal aus. Wirft [PpgInsufficientDataException], wenn zu wenige Bilder
  /// im Fenster liegen.
  static PpgChannelResult analyzeChannel(
    String name,
    List<double> tSec,
    List<double> values,
    PpgWindow w,
  ) {
    final p = _prepare(tSec, values, w);
    final x = p.x;
    final dom = dominantFrequency(x, ppgGridRate);
    final f0 = dom.f0;

    // Gipfel + steilster Anstieg
    final peaks = detectPeaks(x, ppgGridRate, f0);
    final peakT = [for (final pk in peaks) refine(x, pk) / ppgGridRate];
    final dx = _slope(x);
    final searchBack = (ppgSlopeSearchPeriods / f0 * ppgGridRate).toInt();
    final slopeT = <double>[];
    for (var k = 0; k < peaks.length; k++) {
      final pk = peaks[k];
      final lo = math.max(k > 0 ? peaks[k - 1] + 1 : 1, pk - searchBack);
      var best = pk;
      for (var i = lo; i <= pk; i++) {
        if (dx[i] > dx[best]) best = i;
      }
      slopeT.add(refine(dx, best) / ppgGridRate);
    }

    // Vorlagenabgleich: ganzer Schlag und nur Anstieg (Anker = steilster Anstieg)
    final tm = templateMatch(
      x,
      ppgGridRate,
      peaks,
      f0,
      ppgWholeBeatPreFraction,
      ppgWholeBeatPostFraction,
    );
    final slopeIdx = [for (final s in slopeT) roundHalfUp(s * ppgGridRate)];
    final tmUp = templateMatch(
      x,
      ppgGridRate,
      slopeIdx,
      f0,
      ppgRiseBeatPreFraction,
      ppgRiseBeatPostFraction,
      refOnSlope: true,
    );

    final art = detectArtifacts(x, ppgGridRate, peaks, f0);

    final dur = w.end - w.start;
    PpgMethodResult method(String n, List<double> times, List<bool>? beatOk) {
      final iv = intervals(times, beatOk, art);
      return PpgMethodResult(
        name: n,
        times: times,
        ibiEnd: iv.end,
        ibiMs: [for (final v in iv.ibi) v * 1000],
        valid: iv.valid,
        total: stats(times, iv.end, iv.ibi, iv.valid, 0.0, dur + 1e-9),
        first: stats(times, iv.end, iv.ibi, iv.valid, 0.0, dur / 2),
        second: stats(times, iv.end, iv.ibi, iv.valid, dur / 2, dur + 1e-9),
      );
    }

    final methods = [
      method(_mTemplateRise, tmUp.times, [
        for (final c in tmUp.corr) c >= ppgMinCorrelation,
      ]),
      method(_mTemplate, tm.times, [
        for (final c in tm.corr) c >= ppgMinCorrelation,
      ]),
      method(_mPeak, peakT, null),
      method(_mSlope, slopeT, null),
    ];

    // Zeitrauschen aus der Schwankung des Abstands Vorlagenbezug – steilster Anstieg
    final mv = methods[0].valid;
    final okBeat = [
      for (var k = 0; k < peaks.length; k++)
        (k > 0 && k - 1 < mv.length && mv[k - 1]) || (k < mv.length && mv[k]),
    ];
    final dd = <double>[];
    for (var k = 1; k < peaks.length; k++) {
      if (okBeat[k] && okBeat[k - 1]) {
        final d1 = tmUp.times[k] - slopeT[k];
        final d0 = tmUp.times[k - 1] - slopeT[k - 1];
        dd.add((d1 - d0) * 1000);
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

    return PpgChannelResult(
      channel: name,
      methods: methods,
      artifacts: art,
      spectralBpm: f0 * 60,
      quality: dom.quality,
      meanFps: 1 / p.dtMean,
      frameJitterMs: p.dtSd * 1000,
      timingNoiseMs: noise,
    );
  }

  /// Kombination der Teilbereiche: jeder Bereich wird gefiltert und bewertet (Q). Bereiche
  /// mit Q ≥ 0,7·Qmax gehen mit Gewicht Q²/σ ein (Abschn. 9).
  static ({List<double>? combo, int used, int scored}) combineBlocks(
    List<double> tSec,
    List<PpgSeries> blocks,
    PpgWindow w,
  ) {
    final scored = <({double q, double sd, List<double> v})>[];
    for (final b in blocks) {
      _Prepared p;
      try {
        p = _prepare(tSec, b.values, w);
      } on PpgInsufficientDataException {
        continue;
      }
      var sq = 0.0;
      for (final v in p.x) {
        sq += v * v;
      }
      final sd = math.sqrt(sq / p.x.length);
      if (sd <= 0) continue;
      scored.add((
        q: dominantFrequency(p.x, ppgGridRate).quality,
        sd: sd,
        v: b.values,
      ));
    }
    if (scored.isEmpty) return (combo: null, used: 0, scored: 0);
    final qMax = scored.map((s) => s.q).reduce(math.max);
    final used = scored
        .where((s) => s.q >= ppgBlockQualityFraction * qMax)
        .toList();
    final combo = List<double>.filled(tSec.length, 0.0);
    for (final s in used) {
      final wgt = s.q * s.q / s.sd;
      for (var i = 0; i < combo.length; i++) {
        combo[i] += wgt * s.v[i];
      }
    }
    return (combo: combo, used: used.length, scored: scored.length);
  }

  static List<double> _slope(List<double> x) => List<double>.generate(
    x.length,
    (i) => (i == 0 || i == x.length - 1) ? 0.0 : (x[i + 1] - x[i - 1]) / 2,
  );

  /// Gestörte Abschnitte im gefilterten Signal (Abschn. 6).
  static List<List<double>> detectArtifacts(
    List<double> x,
    double fs,
    List<int> peaks,
    double f0,
  ) {
    if (peaks.length < 3) return const [];
    final dx = _slope(x);
    final back = (ppgSlopeSearchPeriods / f0 * fs).toInt();
    final slopes = <double>[];
    for (final p in peaks) {
      var m = 0.0;
      for (var i = math.max(1, p - back); i <= p; i++) {
        m = math.max(m, dx[i]);
      }
      slopes.add(m);
    }
    slopes.sort();
    final amps = [for (final p in peaks) x[p]]..sort();
    final mSlope = slopes[slopes.length ~/ 2];
    final mAmp = amps[amps.length ~/ 2];
    final bad = List<bool>.generate(
      x.length,
      (i) =>
          dx[i].abs() > ppgArtifactSlopeFactor * mSlope ||
          x[i].abs() > ppgArtifactAmplitudeFactor * mAmp,
    );
    final regions = <List<double>>[];
    final gap = (ppgArtifactMarginSeconds * fs).toInt();
    var i = 0;
    while (i < x.length) {
      if (!bad[i]) {
        i++;
        continue;
      }
      var j = i;
      var k = i;
      while (k < x.length && k - j <= gap) {
        if (bad[k]) j = k;
        k++;
      }
      regions.add([
        coerceIn(i / fs - ppgArtifactMarginSeconds, 0.0, double.infinity),
        coerceIn(
          j / fs + ppgArtifactMarginSeconds,
          double.negativeInfinity,
          (x.length - 1) / fs,
        ),
      ]);
      i = j + 1;
    }
    return regions;
  }

  /// Vorlagenabgleich (Abschn. 5.3).
  static PpgTemplateResult templateMatch(
    List<double> x,
    double fs,
    List<int> peaks,
    double f0,
    double preFrac,
    double postFrac, {
    bool refOnSlope = false,
  }) {
    final period = 1 / f0;
    final pre = (preFrac * period * fs).toInt();
    final post = math.max(2, (postFrac * period * fs).toInt());
    final len = pre + post + 1;
    final maxLag = (ppgTemplateMaxLagSeconds * fs).toInt();
    final nB = peaks.length;
    final pos = List<int>.of(peaks);
    final frac = List<double>.filled(nB, 0.0);
    final corr = List<double>.filled(nB, 1.0);
    var tpl = List<double>.filled(len, 0.0);

    List<double>? seg(int start) => (start < 0 || start + len > x.length)
        ? null
        : x.sublist(start, start + len);

    for (var iter = 0; iter < ppgTemplatePasses; iter++) {
      final segs = <List<double>>[];
      for (var k = 0; k < nB; k++) {
        if (iter == 0 || corr[k] >= ppgTemplateCorrelation) {
          final s = seg(pos[k] - pre);
          if (s != null) segs.add(s);
        }
      }
      if (segs.length < 3) continue;
      tpl = List<double>.generate(len, (j) {
        final col = [for (final s in segs) s[j]]..sort();
        return col[col.length ~/ 2];
      });
      final tm = average(tpl);
      for (var j = 0; j < tpl.length; j++) {
        tpl[j] -= tm;
      }
      var tSq = 0.0;
      for (final v in tpl) {
        tSq += v * v;
      }
      final tNorm = math.sqrt(tSq);
      for (var k = 0; k < nB; k++) {
        final c = List<double>.filled(2 * maxLag + 1, double.negativeInfinity);
        for (var d = -maxLag; d <= maxLag; d++) {
          final s = seg(peaks[k] + d - pre);
          if (s == null) continue;
          final sm = average(s);
          var num = 0.0;
          var ss = 0.0;
          for (var j = 0; j < s.length; j++) {
            final v = s[j] - sm;
            num += v * tpl[j];
            ss += v * v;
          }
          c[d + maxLag] = (ss > 0 && tNorm > 0)
              ? num / (math.sqrt(ss) * tNorm)
              : 0.0;
        }
        var bi = maxLag;
        for (var i = 0; i < c.length; i++) {
          if (c[i] > c[bi]) bi = i;
        }
        if (c[bi] == double.negativeInfinity) {
          corr[k] = 0.0;
          continue;
        }
        pos[k] = peaks[k] + bi - maxLag;
        corr[k] = c[bi];
        frac[k] =
            (bi >= 1 &&
                bi < c.length - 1 &&
                c[bi - 1].isFinite &&
                c[bi + 1].isFinite)
            ? refine(c, bi) - bi
            : 0.0;
      }
    }
    // Bezugspunkt in der Vorlage: Gipfel oder steilster Anstieg
    final ref = refOnSlope
        ? List<double>.generate(
            len,
            (j) => (j == 0 || j == len - 1)
                ? double.negativeInfinity
                : (tpl[j + 1] - tpl[j - 1]) / 2,
          )
        : tpl;
    var tp = 1;
    for (var j = 1; j < len - 1; j++) {
      if (ref[j] > ref[tp]) tp = j;
    }
    final tplPeak = refine(ref, tp);
    final times = [
      for (var k = 0; k < nB; k++) (pos[k] + frac[k] - pre + tplPeak) / fs,
    ];
    return PpgTemplateResult(times: times, corr: corr, template: tpl);
  }

  /// Schlagintervalle und Ausreißerprüfung (Abschn. 7).
  static ({List<double> end, List<double> ibi, List<bool> valid}) intervals(
    List<double> beats,
    List<bool>? beatOk,
    List<List<double>> artifacts,
  ) {
    final k = math.max(0, beats.length - 1);
    final ibi = List<double>.generate(k, (i) => beats[i + 1] - beats[i]);
    final end = List<double>.generate(k, (i) => beats[i + 1]);
    if (k == 0) return (end: end, ibi: ibi, valid: <bool>[]);
    final med = List<double>.generate(k, (i) {
      final win = <double>[
        for (
          var j = math.max(0, i - ppgOutlierMedianRadius);
          j <= math.min(k - 1, i + ppgOutlierMedianRadius);
          j++
        )
          ibi[j],
      ]..sort();
      return win[win.length ~/ 2];
    });
    final mrr = List<double>.generate(k, (i) => ibi[i] - med[i]);
    final sorted = List<double>.of(mrr)..sort();
    final qd = (sorted[(3 * (k - 1)) ~/ 4] - sorted[(k - 1) ~/ 4]) / 2;
    final medAll = (List<double>.of(ibi)..sort())[k ~/ 2];
    final th = coerceIn(
      ppgOutlierQuartileFactor * qd,
      ppgOutlierMinFraction * medAll,
      ppgOutlierMaxFraction * medAll,
    );
    final outlier = List<bool>.generate(k, (i) => mrr[i].abs() > th);
    final misplaced = List<bool>.generate(k, (i) {
      if (outlier[i]) return false;
      for (final j in [i - 1, i + 1]) {
        if (j >= 0 &&
            j < k &&
            outlier[j] &&
            mrr[j] * mrr[i] < 0 &&
            mrr[i].abs() > th / 2) {
          return true;
        }
      }
      return false;
    });
    final valid = List<bool>.generate(k, (i) {
      if (!(ibi[i] >= ppgIntervalMinSeconds &&
          ibi[i] <= ppgIntervalMaxSeconds)) {
        return false;
      }
      if (outlier[i] || misplaced[i]) return false;
      if (beatOk != null && !(beatOk[i] && beatOk[i + 1])) return false;
      for (final a in artifacts) {
        if (beats[i] <= a[1] && beats[i + 1] >= a[0]) return false;
      }
      return true;
    });
    return (end: end, ibi: ibi, valid: valid);
  }

  /// Kennwerte im Abschnitt [a, b) (Abschn. 8).
  static HrvStats stats(
    List<double> beats,
    List<double> ibiT,
    List<double> ibi,
    List<bool> valid,
    double a,
    double b,
  ) {
    final idx = [
      for (var i = 0; i < ibiT.length; i++)
        if (ibiT[i] >= a && ibiT[i] < b) i,
    ];
    final v = [
      for (final i in idx)
        if (valid[i]) ibi[i] * 1000,
    ];
    final diffs = <double>[];
    for (var j = 0; j < idx.length - 1; j++) {
      final i = idx[j];
      final i2 = idx[j + 1];
      if (i2 == i + 1 && valid[i] && valid[i2]) {
        diffs.add((ibi[i2] - ibi[i]) * 1000);
      }
    }
    final mean = v.isEmpty ? double.nan : average(v);
    var sdnn = double.nan;
    if (v.length >= 2) {
      var s = 0.0;
      for (final e in v) {
        s += (e - mean) * (e - mean);
      }
      sdnn = math.sqrt(s / (v.length - 1));
    }
    var rmssd = double.nan;
    var pnn50 = double.nan;
    if (diffs.isNotEmpty) {
      var s = 0.0;
      var over = 0;
      for (final d in diffs) {
        s += d * d;
        if (d.abs() > ppgPnnThresholdMs) over++;
      }
      rmssd = math.sqrt(s / diffs.length);
      pnn50 = 100.0 * over / diffs.length;
    }
    return HrvStats(
      beats: beats.where((e) => e >= a && e < b).length,
      ibis: idx.length,
      validIbis: v.length,
      bpm: 60000 / mean,
      meanIbiMs: mean,
      sdnnMs: sdnn,
      rmssdMs: rmssd,
      pnn50: pnn50,
      minBpm: v.isEmpty ? double.nan : 60000 / v.reduce(math.max),
      maxBpm: v.isEmpty ? double.nan : 60000 / v.reduce(math.min),
    );
  }

  /// Gipfel: lokale Maxima > 0, nach Höhe gierig mit Mindestabstand, dann Mindesthöhe.
  static List<int> detectPeaks(List<double> x, double fs, double f0) {
    final minDist =
        (math.max(ppgPeakMinDistanceSeconds, ppgPeakMinDistancePeriods / f0) *
                fs)
            .toInt();
    final cand = [
      for (var i = 1; i < x.length - 1; i++)
        if (x[i] > x[i - 1] && x[i] >= x[i + 1] && x[i] > 0) i,
    ];
    // Absteigend nach Höhe, bei Gleichheit nach Index (stabil wie Kotlin sortedByDescending).
    final byHeight = List<int>.of(cand);
    _stableSort(byHeight, (a, b) => x[b].compareTo(x[a]));
    final acc = <int>[]; // sortiert
    for (final i in byHeight) {
      // lo = größtes akzeptiertes <= i, hi = kleinstes akzeptiertes >= i
      int? lo;
      int? hi;
      for (final a in acc) {
        if (a <= i) lo = a;
        if (a >= i && hi == null) hi = a;
      }
      if ((lo == null || i - lo >= minDist) &&
          (hi == null || hi - i >= minDist)) {
        acc.add(i);
        acc.sort();
      }
    }
    if (acc.isEmpty) return const [];
    final amps = [for (final i in acc) x[i]]..sort();
    final med = amps[amps.length ~/ 2];
    return [
      for (final i in acc)
        if (x[i] >= ppgPeakMinHeightFraction * med) i,
    ];
  }

  static void _stableSort<T>(List<T> l, int Function(T, T) cmp) {
    final idx = List<int>.generate(l.length, (i) => i);
    final copy = List<T>.of(l);
    idx.sort((a, b) {
      final c = cmp(copy[a], copy[b]);
      return c != 0 ? c : a.compareTo(b);
    });
    for (var i = 0; i < l.length; i++) {
      l[i] = copy[idx[i]];
    }
  }
}
