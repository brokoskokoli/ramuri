// R010 – Einstieg. Aufruf über ../run.sh (Parameter dort).
import 'dart:io';
import 'dart:math' as math;

import 'pipeline.dart';
import 'real.dart';
import 'synth.dart';

late IOSink out;
void say(String s) {
  out.writeln(s);
  stdout.writeln(s);
}

void main(List<String> args) async {
  final a = <String, String>{};
  for (var i = 0; i + 1 < args.length; i += 2) {
    a[args[i].replaceFirst('--', '')] = args[i + 1];
  }
  final seed = int.parse(a['seed'] ?? '1');
  final reps = int.parse(a['reps'] ?? '40');
  final part = a['part'] ?? 'all';
  final dir = a['out']!;
  final puls = a['puls'] ?? '';
  final pairs = a['pairs'] ?? '';
  final sw = Stopwatch()..start();
  if (part == 'synth' || part == 'all') {
    out = File('$dir/synth.txt').openWrite();
    runSynth(seed, reps);
    await out.close();
  }
  if (part == 'real' || part == 'all') {
    out = File('$dir/real.txt').openWrite();
    runReal(puls, say);
    await out.close();
  }
  if (part == 'pairs' || part == 'all') {
    out = File('$dir/pairs.txt').openWrite();
    runPairs(pairs, say, '$dir/pairs-selftest.csv');
    await out.close();
  }
  stdout.writeln('Laufzeit ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(0)} s');
}

// ---------------------------------------------------------------------------------------------
// Synthese
// ---------------------------------------------------------------------------------------------

class Agg {
  final err = <double>[]; // Fehler je Intervall gegen R-Zacken (ms), gepoolt
  final errOn = <double>[]; // gegen Fußpunkte am Finger (nur Algorithmus)
  final ln = <double>[]; // ln(RMSSD Kamera / RMSSD Referenz), gleiche Intervallpaare
  final vf = <double>[]; // Anteil gültiger Intervalle
  int fails = 0;
  void add(Compare c, Compare? on) {
    if (c.pairs < 10 || !c.lnRatio.isFinite) {
      fails++;
      return;
    }
    err.addAll(c.errMs);
    if (on != null) errOn.addAll(on.errMs);
    ln.add(c.lnRatio);
    vf.add(c.validFrac);
  }

  String row(String name) =>
      '| $name | ${ln.length} | ${f1(rms(err))} | ${f1(quantile(err.map((e) => e.abs()).toList(), 0.5))} | '
      '${f1(rms(errOn))} | ${f3(mean(ln))} | ${f3(sd(ln))} | ${f3(quantile(ln, 0.9))} | ${f2(mean(vf))} | $fails |';
  static const head = '| Variante | n | Fehler/Intervall RMS (ms) | Median |Fehler| (ms) | RMS gegen Fußpunkt (ms) | '
      'ln-Verhältnis RMSSD Mittel | SD | 90 %-Quantil | gültig | verworfen |\n| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |';
}

final w = ppgStandardWindow;

List<double> absTimes(Prepared p, List<double> t) => [for (final x in t) w.start + p.t0 + x];

void checkEqual(List<double> a, List<double> b, String what) {
  if (a.length != b.length) throw StateError('$what: Länge ${a.length} != ${b.length}');
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) throw StateError('$what: Abweichung bei $i');
  }
}

/// RMSSD der R-Zacken, deren Fußpunkt im Messfenster liegt (wie ein Gurt im selben Fenster).
double ecgFull(SynthRec r) {
  final rr = <double>[];
  for (var k = 1; k < r.rPeaks.length; k++) {
    if (r.onsets[k - 1] >= w.start && r.onsets[k] <= w.end) rr.add(r.rPeaks[k] - r.rPeaks[k - 1]);
  }
  return rmssdOf(rr, List.filled(rr.length, true));
}

void runSynth(int seed, int reps) {
  final rng = Rng(seed);
  say('# R010 Synthese (seed $seed, $reps Aufnahmen je Fall)\n');
  say('Fehler je Intervall = Kamera-Schlagabstand minus R-R der Referenz. ln-Verhältnis = ln(RMSSD Kamera / RMSSD Referenz) '
      'auf denselben Intervallpaaren (trennt Zeitfehler von der Auswahl der Schläge). „verworfen“ = Aufnahmen mit < 10 Paaren.\n');

  // --- Kalibrierung und Hauptraster -------------------------------------------------------------
  final fpsL = [30.0, 60.0];
  final rmL = [20.0, 40.0, 70.0];
  final colL = [0.04, 0.10, 0.20];
  final aggs = <String, Agg>{};
  Agg ag(String k) => aggs.putIfAbsent(k, Agg.new);
  // Für Qualitätsgrenze und Rauschschätzer: je Aufnahme
  final recs = <List<double>>[]; // [fps, rmssd, col, noiseApp, lnAppFull, quality(0/1/2), sigmaTrue, est2ch, trueIbiErr, lnSame]
  var checked = 0;
  for (final fps in fpsL) {
    for (final rm in rmL) {
      for (final col in colL) {
        for (var rep = 0; rep < reps; rep++) {
          final rec = synth(SynthParams(fps: fps, rmssdMs: rm, colored: col), rng);
          final set = PpgAnalyzer.analyze(rec.tSensor, [PpgSeries('Rot', rec.y)], const [], w);
          final m = ratePpg(set.best);
          final appM = set.best.main;
          final p = prepare(rec.tSensor, rec.y, w);
          final fid = fiducials(p, w);
          if (checked < 30) {
            checkEqual(fid['tplRise']!.times, appM.times, 'Vorl.Anstieg gegen App');
            if ((fid['tplRise']!.noiseMs - set.best.timingNoiseMs).abs() > 1e-9 &&
                set.best.timingNoiseMs.isFinite) {
              throw StateError('Zeitrauschen weicht ab');
            }
            checked++;
          }
          final key = 'fps${fps.toInt()}|col$col';
          void addV(String name, BeatSeries b, Prepared pp, {List<double>? ibiOverride}) {
            final ta = absTimes(pp, b.times);
            final c = compareToRef(ta, b.ibi, b.valid, rec.rPeaks, camIbiOverride: ibiOverride);
            final o = compareToRef(ta, b.ibi, b.valid, rec.onsets, camIbiOverride: ibiOverride);
            ag('$name').add(c, o);
            ag('$name@$key').add(c, o);
            ag('$name@rm${rm.toInt()}').add(c, o);
          }

          for (final e in fid.entries) {
            addV('A ${e.key}', e.value, p);
          }
          // Tiefpass
          for (final lp in [3.0, 6.0, 8.0, 10.0, 12.0]) {
            final pl = prepare(rec.tSensor, rec.y, w, lp: lp);
            final fl = fiducials(pl, w, only: {'tplRise', 'slope', 'tangent'});
            for (final e in fl.entries) {
              addV('B ${e.key} TP ${lp.toInt()} Hz', e.value, pl);
            }
          }
          {
            final ph = prepare(rec.tSensor, rec.y, w, hp: 0.3);
            for (final e in fiducials(ph, w, only: {'tplRise', 'slope'}).entries) {
              addV('B ${e.key} HP 0,3 Hz', e.value, ph);
            }
          }
          // Raster (Interpolation vor der Gipfelerkennung)
          for (final g in [fps, 250.0, 1000.0]) {
            final pg = prepare(rec.tSensor, rec.y, w, fs: g);
            final fg = fiducials(pg, w, only: {'tplRise', 'slope'});
            for (final e in fg.entries) {
              addV('C ${e.key} Raster ${g == fps ? "= Bildrate" : "${g.toInt()} Hz"}', e.value, pg);
            }
          }
          // Nachbearbeitung der RR-Folge
          final tr = fid['tplRise']!;
          addV('D Median-3 geglättet', tr, p, ibiOverride: median3(tr.ibi, tr.valid));
          final f5 = fiducials(p, w, minFrac: 0.05, only: {'tplRise'});
          addV('D Ausreißergrenze min 5 %', f5['tplRise']!, p);

          // Je Aufnahme: App-Wert gegen Gurt im ganzen Fenster, wahres Zeitrauschen, Zweikanal-Schätzer
          final ta = absTimes(p, tr.times);
          final cOn = compareToRef(ta, tr.ibi, tr.valid, rec.onsets);
          final cR = compareToRef(ta, tr.ibi, tr.valid, rec.rPeaks);
          final mm = matchBeats(ta, rec.onsets);
          final dev = <double>[];
          for (var i = 0; i < ta.length; i++) {
            if (mm.idx[i] >= 0) dev.add(ta[i] - mm.offset - rec.onsets[mm.idx[i]]);
          }
          final sigTrue = sd(dev) * 1000;
          final p2 = prepare(rec.tSensor, rec.y2, w);
          final t2 = fiducials(p2, w, only: {'tplRise'})['tplRise']!;
          final ta2 = absTimes(p2, t2.times);
          final m2 = matchBeats(ta, ta2, tol: 0.1);
          final dI = <double>[];
          for (var i = 0; i < tr.ibi.length; i++) {
            final j = m2.idx[i], j1 = m2.idx[i + 1];
            if (tr.valid[i] && j >= 0 && j1 == j + 1 && t2.valid[j]) dI.add((tr.ibi[i] - t2.ibi[j]) * 1000);
          }
          final est2 = dI.length >= 10 ? rms(dI) / math.sqrt2 : double.nan;
          final q = m.quality == PpgQuality.good ? 2.0 : (m.quality == PpgQuality.limited ? 1.0 : 0.0);
          final ef = ecgFull(rec);
          recs.add([
            fps, rm, col, set.best.timingNoiseMs,
            appM.total.rmssdMs.isFinite ? math.log(appM.total.rmssdMs / ef) : double.nan,
            q, sigTrue, est2, rms(cOn.errMs), cR.pairs >= 10 ? cR.lnRatio : double.nan,
            set.best.quality, appM.total.ibis > 0 ? appM.total.validIbis / appM.total.ibis : 0.0,
          ]);
        }
      }
    }
  }
  say('Kontrolle: Vorl.Anstieg der Variante „A tplRise“ in $checked Aufnahmen bitgleich zur App (Schlagzeiten und Zeitrauschen).\n');

  say('## S1 Kalibrierung: Signalgüte und Zeitrauschen der App je Störstufe\n');
  say('| Bilder/s | Störung (rel. Pulsamplitude) | n | Q Median | Zeitrauschen App Median (ms) | 10–90 % | wahres Zeitrauschen je Schlag Median (ms) | Anteil „gut“ |');
  say('| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final fps in fpsL) {
    for (final col in colL) {
      final s = recs.where((r) => r[0] == fps && r[2] == col).toList();
      say('| ${fps.toInt()} | $col | ${s.length} | ${f2(quantile([for (final r in s) r[10]], 0.5))} | ${f1(quantile([for (final r in s) r[3]], 0.5))} | '
          '${f1(quantile([for (final r in s) r[3]], 0.1))}–${f1(quantile([for (final r in s) r[3]], 0.9))} | '
          '${f1(quantile([for (final r in s) r[6]], 0.5))} | ${f2(s.where((r) => r[5] == 2).length / s.length)} |');
    }
  }

  say('\n## S2 Varianten über alle Fälle (fps 30/60 × RMSSD 20/40/70 × Störung 0,04/0,10/0,20)\n');
  say(Agg.head);
  final names = aggs.keys.where((k) => !k.contains('@')).toList()..sort();
  for (final n in names) {
    say(aggs[n]!.row(n));
  }
  say('\n## S2b Ausgewählte Varianten je wahrer RMSSD (alle Bildraten und Störstufen)\n');
  for (final rm in rmL) {
    say('\n### RMSSD ${rm.toInt()} ms\n');
    say(Agg.head);
    for (final n in ['A tplRise', 'A slope', 'A mix', 'A tangent', 'A peak', 'B tplRise TP 8 Hz', 'B slope TP 8 Hz', 'D Median-3 geglättet']) {
      final g = aggs['$n@rm${rm.toInt()}'];
      if (g != null) say(g.row(n));
    }
  }
  say('\n## S3 Ausgewählte Varianten je Bildrate und Störstufe\n');
  for (final fps in fpsL) {
    for (final col in colL) {
      say('\n### ${fps.toInt()} Bilder/s, Störung $col\n');
      say(Agg.head);
      for (final n in names) {
        if (n.startsWith('A ') || n.contains('TP 8') || n.contains('TP 6') || n.contains('Raster') || n.startsWith('D ')) {
          final g = aggs['$n@fps${fps.toInt()}|col$col'];
          if (g != null) say(g.row(n));
        }
      }
    }
  }

  // --- Qualitätsgrenze --------------------------------------------------------------------------
  say('\n## S4 Zeitrauschen als Qualitätsgrenze (App, Wert gegen Gurt im ganzen Fenster, nur Stufe „gut“ ohne Grenze 25 ms)\n');
  say('Gezählt werden Aufnahmen mit Q ≥ 0,3 und ≥ 70 % gültigen Intervallen (Stufe „gut“ bis auf das Zeitrauschen). '
      'ln-Fehler = ln(RMSSD App / RMSSD Gurt, ganzes Fenster).\n');
  say('| RMSSD wahr (ms) | Grenze Zeitrauschen (ms) | bestanden | ln-Fehler Mittel | SD | 90 %-Quantil | Anteil ln-Fehler > 0,2 |');
  say('| ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final rm in rmL) {
    final base = recs.where((r) => r[1] == rm && r[10] >= ppgLimitedQuality && r[11] >= ppgLimitedValidFraction && r[4].isFinite).toList();
    // Stufe gut ohne Zeitrauschen-Grenze: q==2 oder (q==1 und nur Zeitrauschen) – angenähert über Neubewertung unten
    for (final th in [5.0, 8.0, 10.0, 12.0, 15.0, 20.0, 25.0, 1e9]) {
      final s = base.where((r) => r[3] <= th).toList();
      final l = [for (final r in s) r[4]];
      say('| ${rm.toInt()} | ${th > 1e8 ? "keine" : th.toInt()} | ${s.length}/${base.length} | ${f3(mean(l))} | ${f3(sd(l))} | '
          '${f3(quantile(l, 0.9))} | ${f2(l.isEmpty ? double.nan : l.where((x) => x > 0.2).length / l.length)} |');
    }
  }

  say('\n## S5 Schätzt das Zeitrauschen der App das wahre Zeitrauschen?\n');
  final ok = recs.where((r) => r[3].isFinite && r[6].isFinite).toList();
  double corr(List<double> x, List<double> y) {
    final mx = mean(x), my = mean(y);
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < x.length; i++) {
      sxy += (x[i] - mx) * (y[i] - my);
      sxx += (x[i] - mx) * (x[i] - mx);
      syy += (y[i] - my) * (y[i] - my);
    }
    return sxy / math.sqrt(sxx * syy);
  }

  final ratio = [for (final r in ok) r[6] / r[3]];
  say('Aufnahmen: ${ok.length}. Korrelation App-Schätzung ↔ wahres Zeitrauschen je Schlag (gegen Fußpunkt): '
      'r = ${f2(corr([for (final r in ok) r[3]], [for (final r in ok) r[6]]))}; Verhältnis wahr/geschätzt Median ${f2(quantile(ratio, 0.5))} '
      '(10–90 %: ${f2(quantile(ratio, 0.1))}–${f2(quantile(ratio, 0.9))}).');
  final ok2 = recs.where((r) => r[7].isFinite && r[8].isFinite).toList();
  final ratio2 = [for (final r in ok2) r[8] / r[7]];
  say('Zweikanal-Schätzer (zwei Kanäle mit unabhängigem Rauschen, RMS der IBI-Differenz / √2) ↔ wahrer Fehler je Intervall: '
      'r = ${f2(corr([for (final r in ok2) r[7]], [for (final r in ok2) r[8]]))}; Verhältnis wahr/geschätzt Median ${f2(quantile(ratio2, 0.5))} '
      '(10–90 %: ${f2(quantile(ratio2, 0.1))}–${f2(quantile(ratio2, 0.9))}), n = ${ok2.length}.');
  final ok3 = recs.where((r) => r[3].isFinite && r[9].isFinite).toList();
  say('Korrelation App-Zeitrauschen ↔ ln-Verhältnis RMSSD (gleiche Paare): r = ${f2(corr([for (final r in ok3) r[3]], [for (final r in ok3) r[9]]))}; '
      'Zweikanal-Schätzer ↔ ln-Verhältnis: r = ${f2(corr([for (final r in recs.where((r) => r[7].isFinite && r[9].isFinite)) r[7]], [for (final r in recs.where((r) => r[7].isFinite && r[9].isFinite)) r[9]]))}.');

  say('\n## S6 Rauschkorrektur RMSSD² − k·σ² (σ = Zeitrauschen der App bzw. Zweikanal-Schätzer)\n');
  // Nachrechnung je Aufnahme aus den gespeicherten Größen ist nicht möglich (RMSSD fehlt) → eigene Schleife klein
  final cTrue = quantile(ratio, 0.5);
  _noiseCorrection(rng, reps, cTrue);

  // --- Zeitstempel, Bildverlust ---------------------------------------------------------------
  say('\n## S7 Sensor-Zeitstempel gegen Nennrate (App-Verfahren, RMSSD 40 ms, Störung 0,10)\n');
  say(Agg.head.replaceFirst('Variante', 'Fall'));
  for (final fps in fpsL) {
    for (final jit in [0.0, 2.0]) {
      for (final drop in [0.0, 0.01, 0.03]) {
        final aS = Agg(), aN = Agg();
        for (var rep = 0; rep < reps; rep++) {
          final rec = synth(SynthParams(fps: fps, colored: 0.10, frameJitterMs: jit, dropProb: drop), rng);
          for (final nominal in [false, true]) {
            final t = nominal ? rec.tNominal : rec.tSensor;
            final p = prepare(t, rec.y, w);
            final b = fiducials(p, w, only: {'tplRise'})['tplRise']!;
            // Nennrate: Zeitachse der App ist falsch; verglichen wird gegen die echte Zeit über den Index
            final ta = absTimes(p, b.times);
            final c = compareToRef(ta, b.ibi, b.valid, rec.rPeaks, tol: 0.3);
            (nominal ? aN : aS).add(c, null);
          }
        }
        say(aS.row('${fps.toInt()} B/s, Jitter $jit ms, Verlust ${(drop * 100).toInt()} %, Sensor-Zeit'));
        say(aN.row('${fps.toInt()} B/s, Jitter $jit ms, Verlust ${(drop * 100).toInt()} %, Nennrate'));
      }
    }
  }

  say('\n## S8 Untergrenze durch Schwankung der Pulslaufzeit (App-Verfahren, 60 B/s, Störung 0,04)\n');
  say(Agg.head.replaceFirst('Variante', 'Fall'));
  for (final pj in [0.0, 2.0, 5.0]) {
    for (final rm in [20.0, 40.0]) {
      final g = Agg();
      for (var rep = 0; rep < reps; rep++) {
        final rec = synth(SynthParams(fps: 60, rmssdMs: rm, colored: 0.04, pttJitterMs: pj), rng);
        final p = prepare(rec.tSensor, rec.y, w);
        final b = fiducials(p, w, only: {'tplRise'})['tplRise']!;
        final ta = absTimes(p, b.times);
        g.add(compareToRef(ta, b.ibi, b.valid, rec.rPeaks), compareToRef(ta, b.ibi, b.valid, rec.onsets));
      }
      say(g.row('PTT-Rauschen $pj ms, RMSSD ${rm.toInt()}'));
    }
  }

  say('\n## S9 Eine Störung (Druckänderung bei 30 s), 60 B/s, Störung 0,10, RMSSD 40\n');
  say(Agg.head);
  final dAgg = <String, Agg>{};
  for (var rep = 0; rep < reps; rep++) {
    final rec = synth(const SynthParams(fps: 60, colored: 0.10, disturb: true), rng);
    final p = prepare(rec.tSensor, rec.y, w);
    final fid = fiducials(p, w, only: {'tplRise', 'slope', 'tangent', 'mix'});
    for (final e in fid.entries) {
      final ta = absTimes(p, e.value.times);
      dAgg.putIfAbsent(e.key, Agg.new).add(compareToRef(ta, e.value.ibi, e.value.valid, rec.rPeaks), null);
    }
  }
  for (final e in dAgg.entries) {
    say(e.value.row(e.key));
  }
}

void _noiseCorrection(Rng rng, int reps, double c) {
  say('Faktor c = ${f2(c)} (Median wahr/geschätzt aus S5, an denselben Synthesedaten bestimmt, also optimistisch). '
      'Werte: Mittel ± SD des ln-Fehlers (gleiche Paare), in Klammern Aufnahmen, bei denen die Korrektur ≤ 0 ergäbe.\n');
  say('| RMSSD wahr | Störung | n | ln-Fehler ohne Korrektur | k=6, σ App | k=6, σ = c × App | k=6, σ 2 Kanäle |');
  say('| ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final rm in [20.0, 40.0, 70.0]) {
    for (final col in [0.04, 0.10, 0.20]) {
      final l0 = <double>[], l1 = <double>[], l2 = <double>[], l3 = <double>[];
      for (var rep = 0; rep < reps; rep++) {
        final rec = synth(SynthParams(fps: 60, rmssdMs: rm, colored: col), rng);
        final p = prepare(rec.tSensor, rec.y, w);
        final b = fiducials(p, w, only: {'tplRise'})['tplRise']!;
        final p2 = prepare(rec.tSensor, rec.y2, w);
        final b2 = fiducials(p2, w, only: {'tplRise'})['tplRise']!;
        final ta = absTimes(p, b.times), ta2 = absTimes(p2, b2.times);
        final c = compareToRef(ta, b.ibi, b.valid, rec.rPeaks);
        if (c.pairs < 10) continue;
        final m2 = matchBeats(ta, ta2, tol: 0.1);
        final dI = <double>[];
        for (var i = 0; i < b.ibi.length; i++) {
          final j = m2.idx[i], j1 = m2.idx[i + 1];
          if (b.valid[i] && j >= 0 && j1 == j + 1 && b2.valid[j]) dI.add((b.ibi[i] - b2.ibi[j]) * 1000);
        }
        final sIbi = dI.length >= 10 ? rms(dI) / math.sqrt2 : double.nan;
        double corr(double k, double s) {
          final v = c.rmssdCam * c.rmssdCam - k * s * s;
          return v > 0 ? math.log(math.sqrt(v) / c.rmssdRef) : double.nan;
        }

        l0.add(c.lnRatio);
        l1.add(corr(6, b.noiseMs));
        l2.add(corr(6, c * b.noiseMs));
        l3.add(corr(6, sIbi / math.sqrt2));
      }
      String s(List<double> l) => '${f3(mean(l))} ± ${f3(sd(l))} (${l.where((x) => !x.isFinite).length} nicht def.)';
      say('| ${rm.toInt()} | $col | ${l0.length} | ${s(l0)} | ${s(l1)} | ${s(l2)} | ${s(l3)} |');
    }
  }
}
