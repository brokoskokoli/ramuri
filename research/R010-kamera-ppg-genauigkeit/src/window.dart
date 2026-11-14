// R010 Teil „window“: Verzerrt die Wahl des 60-s-Fensters nach kleinstem Zeitrauschen (WP37) die
// RMSSD, und wird eine Grenze für das Zeitrauschen dadurch faktisch lockerer? (Review 1, Befund 6)
// Synthetische 120-s-Aufnahmen, App-Verfahren unverändert (PpgAnalyzer.analyze je Fenster).
import 'dart:math' as math;

import 'pipeline.dart';
import 'synth.dart';

class WinEval {
  WinEval(this.start, this.q, this.valid, this.noise, this.rmssd, this.truth, this.sigTrue);
  final double start, q, valid, noise, rmssd, truth, sigTrue;
  bool get eligible => q >= ppgLimitedQuality && valid >= ppgLimitedValidFraction && rmssd.isFinite && noise.isFinite;
  double get ln => math.log(rmssd / truth);
}

PpgWindow winAt(double s) => PpgWindow(filterStart: s - 2, start: s, end: s + 60, dataEnd: s + 61.5);

List<WinEval> evalWindows(SynthRec rec, List<double> starts) {
  final out = <WinEval>[];
  for (final s in starts) {
    final w = winAt(s);
    final set = PpgAnalyzer.analyze(rec.tSensor, [PpgSeries('Rot', rec.y)], const [], w);
    final b = set.best;
    final m = b.main;
    // Wahrheit im selben Fenster: R-R der Schläge, deren Fußpunkt im Fenster liegt
    final rr = <double>[];
    for (var k = 1; k < rec.rPeaks.length; k++) {
      if (rec.onsets[k - 1] >= w.start && rec.onsets[k] <= w.end) rr.add(rec.rPeaks[k] - rec.rPeaks[k - 1]);
    }
    final truth = rmssdOf(rr, List.filled(rr.length, true));
    // wahres Zeitrauschen je Schlag (gegen Fußpunkte), nur Schläge an gültigen Intervallen, Versatz per Median
    var sig = double.nan;
    if (m.times.length > 10) {
      final ta = [for (final t in m.times) w.start + t];
      final mm = matchBeats(ta, rec.onsets);
      final dev = <double>[];
      bool ok(int i) => (i > 0 && i - 1 < m.valid.length && m.valid[i - 1]) || (i < m.valid.length && m.valid[i]);
      for (var i = 0; i < ta.length; i++) {
        if (mm.idx[i] >= 0 && ok(i)) dev.add(ta[i] - mm.offset - rec.onsets[mm.idx[i]]);
      }
      sig = sd(dev) * 1000;
    }
    final tot = m.total;
    out.add(WinEval(s, b.quality, tot.ibis > 0 ? tot.validIbis / tot.ibis : 0.0, b.timingNoiseMs, tot.rmssdMs, truth, sig));
  }
  return out;
}

/// Regeln für die Fensterwahl. Ergebnis: gewähltes Fenster oder null (kein Fenster erfüllt Q und Anteil gültig).
WinEval? pick(List<WinEval> ws, String rule) {
  final el = ws.where((w) => w.eligible).toList();
  WinEval? minNoise() => el.isEmpty ? null : el.reduce((a, b) => b.noise < a.noise ? b : a);
  switch (rule) {
    case 'fest 5–65 s':
      return ws.first.eligible ? ws.first : null;
    case 'kleinstes Zeitrauschen':
      return minNoise();
    case 'erstes „gut“ (25 ms), sonst kleinstes':
      for (final w in ws) {
        if (w.eligible && w.noise <= ppgLimitedTimingNoiseMs) return w;
      }
      return minNoise();
    case 'erstes ≤ 8 ms, sonst kleinstes':
      for (final w in ws) {
        if (w.eligible && w.noise <= 8) return w;
      }
      return minNoise();
    case 'zufälliges Fenster':
      return null; // wird außen gesetzt
    case 'Orakel: kleinstes wahres Zeitrauschen':
      return el.isEmpty ? null : el.reduce((a, b) => b.sigTrue < a.sigTrue ? b : a);
  }
  throw ArgumentError(rule);
}

void runWindow(int seed, int reps, void Function(String) say) {
  final rng = Rng(seed + 1000);
  final starts = [for (var s = 5.0; s <= 58.0; s += 1) s]; // 54 Fenster, Daten bis 119,5 s
  const rules = [
    'fest 5–65 s',
    'zufälliges Fenster',
    'kleinstes Zeitrauschen',
    'erstes „gut“ (25 ms), sonst kleinstes',
    'erstes ≤ 8 ms, sonst kleinstes',
    'Orakel: kleinstes wahres Zeitrauschen',
  ];
  const gate = 8.0;
  say('# R010 Fensterwahl (seed ${seed + 1000}, $reps Aufnahmen je Fall, 60 Bilder/s, Aufnahme 120 s, '
      '${starts.length} Fenster à 60 s, Schritt 1 s, Beginn 5–58 s)\n');
  say('ln-Fehler = ln(RMSSD App / RMSSD der R-Zacken im selben Fenster). σ App = Zeitrauschen der App im gewählten Fenster, '
      'σ wahr = SD der Abweichung der App-Schlagzeiten von den Fußpunkten. „bestanden 8 ms“ = gewähltes Fenster mit Q ≥ 0,3, '
      '≥ 70 % gültig und σ App ≤ $gate ms. „ohne Fenster“ = kein Fenster erfüllt Q und Anteil gültig.\n');
  say('| Fall | RMSSD | Regel | n | ohne Fenster | σ App Median | σ wahr Median | wahr/App Median | ln Mittel (alle gewählten) | '
      'bestanden 8 ms | ln Mittel (bestanden) | Anteil ln > 0,2 (bestanden) |');
  say('| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  final cases = <(String, SynthParams Function(double))>[
    ('ruhig, Störung 0,04', (rm) => SynthParams(fps: 60, rmssdMs: rm, colored: 0.04, dur: 120)),
    ('ruhig, Störung 0,10', (rm) => SynthParams(fps: 60, rmssdMs: rm, colored: 0.10, dur: 120)),
    ('ruhig, Störung 0,20', (rm) => SynthParams(fps: 60, rmssdMs: rm, colored: 0.20, dur: 120)),
    ('Anfang 30 s Störung ×4, dann 0,10', (rm) => SynthParams(fps: 60, rmssdMs: rm, colored: 0.10, dur: 120, noisyUntil: 30, noisyFactor: 4)),
  ];
  for (final (name, mk) in cases) {
    for (final rm in [20.0, 40.0, 70.0]) {
      final chosen = {for (final r in rules) r: <WinEval?>[]};
      for (var rep = 0; rep < reps; rep++) {
        final rec = synth(mk(rm), rng);
        final ws = evalWindows(rec, starts);
        for (final r in rules) {
          if (r == 'zufälliges Fenster') {
            final w = ws[(rng.u() * ws.length).floor()];
            chosen[r]!.add(w.eligible ? w : null);
          } else {
            chosen[r]!.add(pick(ws, r));
          }
        }
      }
      for (final r in rules) {
        final c = chosen[r]!.whereType<WinEval>().toList();
        final none = chosen[r]!.length - c.length;
        final pass = c.where((w) => w.noise <= gate).toList();
        final lp = [for (final w in pass) w.ln];
        say('| $name | ${rm.toInt()} | $r | ${chosen[r]!.length} | $none | ${f1(quantile([for (final w in c) w.noise], 0.5))} | '
            '${f1(quantile([for (final w in c) w.sigTrue], 0.5))} | ${f2(quantile([for (final w in c) w.sigTrue / w.noise], 0.5))} | '
            '${f3(mean([for (final w in c) w.ln]))} | ${pass.length}/${chosen[r]!.length} | ${f3(mean(lp))} | '
            '${f2(lp.isEmpty ? double.nan : lp.where((x) => x > 0.2).length / lp.length)} |');
      }
    }
  }
}
