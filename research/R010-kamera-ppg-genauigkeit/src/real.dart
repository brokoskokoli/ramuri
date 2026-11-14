// R010: echte Aufnahmen der Vorgänger-App (~/ai/puls, K70) und Messpaare der App.
// Ausgabe nur Dateinamen und Kennzahlen, keine Zeitreihen (Sammlungsregeln).
import 'dart:io';
import 'dart:math' as math;

import 'pipeline.dart';

final _w = ppgStandardWindow;

class Rec {
  Rec(this.t, this.r, this.g, this.r16, this.g16);
  final List<double> t, r, g;
  final List<List<double>> r16, g16; // [block][frame]
  bool get blocks => r16.isNotEmpty;
  Rec sub(int step, int phase) {
    List<double> s(List<double> v) => [for (var i = phase; i < v.length; i += step) v[i]];
    return Rec(s(t), s(r), s(g), [for (final b in r16) s(b)], [for (final b in g16) s(b)]);
  }
}

Rec loadFrames(String path) {
  final lines = File(path).readAsLinesSync();
  final head = lines.first.split(',');
  final it = head.indexOf('t_s'), ir = head.indexOf('r'), ig = head.indexOf('g');
  final hasB = head.contains('r0');
  final t = <double>[], r = <double>[], g = <double>[];
  final r16 = hasB ? List.generate(16, (_) => <double>[]) : <List<double>>[];
  final g16 = hasB ? List.generate(16, (_) => <double>[]) : <List<double>>[];
  for (final l in lines.skip(1)) {
    if (l.trim().isEmpty) continue;
    final c = l.split(',');
    // puls: t_s relativ zum Messbeginn (Einschwingen negativ); App-Fenster 5–65 s → +5 s (ALGORITHMUS.md Abschn. 2)
    t.add(double.parse(c[it]) + 5);
    r.add(double.parse(c[ir]));
    g.add(double.parse(c[ig]));
    if (hasB) {
      for (var k = 0; k < 16; k++) {
        r16[k].add(double.parse(c[head.indexOf('r$k')]));
        g16[k].add(double.parse(c[head.indexOf('g$k')]));
      }
    }
  }
  return Rec(t, r, g, r16, g16);
}

PpgAnalysisSet appAnalyze(Rec x) => PpgAnalyzer.analyze(
      x.t,
      [PpgSeries('Rot', x.r), PpgSeries('Grün', x.g)],
      x.blocks
          ? [for (var k = 0; k < 16; k++) PpgSeries('r$k', x.r16[k]), for (var k = 0; k < 16; k++) PpgSeries('g$k', x.g16[k])]
          : const [],
      _w,
    );

/// Rohreihe einer Quelle wie in der App (Kombi = gewichtete Summe der Teilbereiche).
List<double> sourceSeries(Rec x, String ch, {Set<int>? cols}) {
  if (ch == 'Rot') return x.r;
  if (ch == 'Grün') return x.g;
  final bl = <PpgSeries>[
    for (var k = 0; k < 16; k++)
      if (cols == null || cols.contains(k % 4)) PpgSeries('r$k', x.r16[k]),
    for (var k = 0; k < 16; k++)
      if (cols == null || cols.contains(k % 4)) PpgSeries('g$k', x.g16[k]),
  ];
  return PpgAnalyzer.combineBlocks(x.t, bl, _w).combo!;
}

/// Gurt-RR (puls-Format rx_s, hr, rr_ms) → Schlagzeiten in der Gurt-Uhr (lückenlos aufsummiert).
List<double> beltBeats(String path) {
  final lines = File(path).readAsLinesSync().skip(1).where((l) => l.trim().isNotEmpty).toList();
  final rx0 = double.parse(lines.first.split(',')[0]);
  final out = <double>[rx0];
  for (final l in lines) {
    out.add(out.last + double.parse(l.split(',')[2]) / 1000);
  }
  return out;
}

/// Versatz Kamera → Gurt: Raster −8…+8 s, Kosten = Summe min(|IBI-Fehler|, 100 ms) über gültige Intervalle.
double findOffset(List<double> camAbs, List<double> ibi, List<bool> valid, List<double> ref) {
  var best = 0.0, bestCost = double.infinity;
  for (var o = -8.0; o <= 8.0; o += 0.01) {
    final m = matchBeats(camAbs, ref, tol: 0.12, offset: o);
    var cost = 0.0;
    for (var i = 0; i < ibi.length; i++) {
      if (!valid[i]) continue;
      final a = m.idx[i], b = m.idx[i + 1];
      if (a >= 0 && b == a + 1) {
        cost += math.min(100.0, ((ibi[i] - (ref[b] - ref[a])) * 1000).abs());
      } else {
        cost += 100;
      }
    }
    if (cost < bestCost) {
      bestCost = cost;
      best = o;
    }
  }
  // fein: Median der Restabstände
  final m = matchBeats(camAbs, ref, tol: 0.12, offset: best);
  final d = <double>[];
  for (var i = 0; i < camAbs.length; i++) {
    if (m.idx[i] >= 0) d.add(camAbs[i] - best - ref[m.idx[i]]);
  }
  d.sort();
  return best + d[d.length ~/ 2];
}

String _rowCmp(String name, Compare c, double rmssdApp, double rmssdBelt) =>
    '| $name | ${c.pairs} | ${f1(rms(c.errMs))} | ${f1(quantile(c.errMs.map((e) => e.abs()).toList(), 0.5))} | '
    '${f1(mean(c.errMs))} | ${f1(c.rmssdCam)} | ${f1(c.rmssdRef)} | ${f1((c.rmssdCam / c.rmssdRef - 1) * 100)} | '
    '${f1(rmssdApp)} | ${f1((rmssdApp / rmssdBelt - 1) * 100)} | ${f2(c.validFrac)} |';
const _headCmp = '| Variante | Paare | Fehler/Intervall RMS (ms) | Median |Fehler| | mittlerer Fehler | RMSSD Kamera (Paare) | RMSSD Gurt (Paare) | Δ % | '
    'RMSSD Variante (alle gültigen) | Δ % zum Gurt (ganzes Fenster) | gültig |\n| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |';

void runReal(String dir, void Function(String) say) {
  say('# R010 Echte Aufnahmen der Vorgänger-App (nur Kennzahlen)\n');
  final d = Directory(dir);
  if (!d.existsSync()) {
    say('Ordner fehlt: $dir – Teil übersprungen.');
    return;
  }
  final files = d.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('_frames.csv')).toList()..sort();
  say('## R1 App-Verfahren auf allen Aufnahmen\n');
  say('| Datei | Bilder/s | Teilbereiche | Quelle | Q | Zeitrauschen (ms) | Stufe | Puls | RMSSD | gültig |');
  say('| --- | ---: | --- | --- | ---: | ---: | --- | ---: | ---: | ---: |');
  for (final f in files) {
    final x = loadFrames(f);
    try {
      final s = appAnalyze(x);
      final m = ratePpg(s.best);
      final t = s.best.main.total;
      say('| ${f.split('/').last} | ${f1(s.best.meanFps)} | ${x.blocks ? "ja" : "nein"} | ${s.best.channel} | ${f2(s.best.quality)} | '
          '${f1(s.best.timingNoiseMs)} | ${m.quality.name} | ${f1(t.bpm)} | ${f1(t.rmssdMs)} | ${t.validIbis}/${t.ibis} |');
    } catch (e) {
      say('| ${f.split('/').last} | – | – | – | – | – | Fehler: $e | | | |');
    }
  }

  // --- Aufnahme mit Gurt ---
  final belts = d.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('_gurt.csv')).toList()..sort();
  for (final bp in belts) {
    final fp = bp.replaceFirst('_gurt.csv', '_frames.csv');
    if (!File(fp).existsSync()) continue;
    final name = fp.split('/').last;
    say('\n## R2 Kamera gegen Gurt: $name\n');
    final x = loadFrames(fp);
    final ref = beltBeats(bp);
    final s = appAnalyze(x);
    final ch = s.best.channel;
    // Gurt im ganzen Fenster: alle Gurt-Intervalle, deren Schläge im Kamerafenster liegen (nach Versatz)
    final p0 = prepare(x.t, sourceSeries(x, ch), _w);
    final fid0 = fiducials(p0, _w);
    checkEq(fid0['tplRise']!.times, s.best.main.times);
    final ta0 = [for (final t in fid0['tplRise']!.times) _w.start + p0.t0 + t];
    final off0 = findOffset(ta0, fid0['tplRise']!.ibi, fid0['tplRise']!.valid, ref);
    final rrW = <double>[];
    for (var k = 1; k < ref.length; k++) {
      if (ref[k - 1] + off0 >= _w.start && ref[k] + off0 <= _w.end) rrW.add(ref[k] - ref[k - 1]);
    }
    final beltR = rmssdOf(rrW, List.filled(rrW.length, true));
    say('App wählt Quelle $ch, Zeitrauschen ${f1(s.best.timingNoiseMs)} ms (Kontrolle: Variante „tplRise“ bitgleich zur App). '
        'Gurt im Fenster: ${rrW.length} Intervalle, RMSSD ${f1(beltR)} ms (ohne Artefaktregel; Gurt-Intervalle außerhalb 0,27–2 s: '
        '${rrW.where((v) => v < 0.27 || v > 2).length}). Versatz Kamera − Gurt (App-Bezugspunkt) ${f1(off0 * 1000)} ms.\n');
    say(_headCmp);
    void row(String n, Prepared p, BeatSeries b, {List<double>? ov}) {
      final ta = [for (final t in b.times) _w.start + p.t0 + t];
      final off = findOffset(ta, b.ibi, b.valid, ref);
      final c = compareToRef(ta, b.ibi, b.valid, ref, tol: 0.12, offset: off, camIbiOverride: ov);
      final rAll = ov == null ? b.rmssdMs : rmssdOf(ov, b.valid);
      say(_rowCmp(n, c, rAll, beltR));
    }

    for (final src in [ch, 'Rot', 'Grün']) {
      if (src != ch && src == 'Kombi') continue;
      final p = src == ch ? p0 : prepare(x.t, sourceSeries(x, src), _w);
      final fid = src == ch ? fid0 : fiducials(p, _w);
      for (final e in fid.entries) {
        row('$src ${e.key}', p, e.value);
      }
      if (src == ch) {
        for (final lp in [3.0, 6.0, 8.0, 10.0, 12.0]) {
          final pl = prepare(x.t, sourceSeries(x, src), _w, lp: lp);
          final fl = fiducials(pl, _w, only: {'tplRise', 'slope', 'tangent'});
          for (final e in fl.entries) {
            row('$src ${e.key} TP ${lp.toInt()} Hz', pl, e.value);
          }
        }
        {
          final ph = prepare(x.t, sourceSeries(x, src), _w, hp: 0.3);
          for (final e in fiducials(ph, _w, only: {'tplRise', 'slope'}).entries) {
            row('$src ${e.key} HP 0,3 Hz', ph, e.value);
          }
        }
        for (final g in [60.0, 250.0, 1000.0]) {
          final pg = prepare(x.t, sourceSeries(x, src), _w, fs: g);
          final fg = fiducials(pg, _w, only: {'tplRise', 'slope'});
          for (final e in fg.entries) {
            row('$src ${e.key} Raster ${g.toInt()} Hz', pg, e.value);
          }
        }
        final tr = fid0['tplRise']!;
        row('$src tplRise Median-3', p0, tr, ov: median3(tr.ibi, tr.valid));
        row('$src tplRise Ausreißer min 5 %', p0, fiducials(p0, _w, minFrac: 0.05, only: {'tplRise'})['tplRise']!);
      }
    }
    say('\n### Ausgedünnt (App-Verfahren vollständig, eigene Quellenwahl)\n');
    say('| Fall | Quelle | Zeitrauschen (ms) | Paare | Fehler/Intervall RMS (ms) | RMSSD Kamera (Paare) | RMSSD Gurt (Paare) | Δ % | RMSSD App | Δ % zum Gurt |');
    say('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
    for (final (step, label) in [(1, '60 B/s'), (2, '30 B/s'), (4, '15 B/s')]) {
      for (var ph = 0; ph < step; ph++) {
        final xs = x.sub(step, ph);
        final ss = appAnalyze(xs);
        final mm = ss.best.main;
        final ps = prepare(xs.t, sourceSeries(xs, ss.best.channel), _w);
        final ta = [for (final t in mm.times) _w.start + ps.t0 + t];
        final vv = [for (var i = 0; i < mm.ibiMs.length; i++) mm.valid[i]];
        final ibi = [for (final v in mm.ibiMs) v / 1000];
        final off = findOffset(ta, ibi, vv, ref);
        final c = compareToRef(ta, ibi, vv, ref, tol: 0.12, offset: off);
        say('| $label Phase $ph | ${ss.best.channel} | ${f1(ss.best.timingNoiseMs)} | ${c.pairs} | ${f1(rms(c.errMs))} | ${f1(c.rmssdCam)} | '
            '${f1(c.rmssdRef)} | ${f1((c.rmssdCam / c.rmssdRef - 1) * 100)} | ${f1(mm.total.rmssdMs)} | ${f1((mm.total.rmssdMs / beltR - 1) * 100)} |');
      }
    }
  }

  // --- Referenzfreies Rauschmaß: zwei unabhängige Bildhälften ---
  say('\n## R3 Ohne Referenz: Übereinstimmung zweier Hälften des Bildes (Kombi links gegen rechts) bzw. Rot gegen Grün\n');
  say('Maß: RMS der Differenz der Schlagabstände beider Hälften / √2 (Rauschen je Intervall einer Hälfte; gemeinsame Physiologie fällt heraus, '
      'gemeinsame Störungen wie Bewegung auch). Kleiner = weniger Messrauschen.\n');
  final vNames = ['tplRise', 'slope', 'tangent', 'foot', 'd50', 'peak', 'mix'];
  say('| Datei | Paar | ${vNames.join(' | ')} | tplRise TP 8 Hz | slope TP 8 Hz |');
  say('| --- | --- |${' ---: |' * (vNames.length + 2)}');
  for (final f in files) {
    final x = loadFrames(f);
    final pairsL = x.blocks ? [('links/rechts', {0, 1}, {2, 3}), ('Rot/Grün', null, null)] : [('Rot/Grün', null, null)];
    for (final (label, ca, cb) in pairsL) {
      try {
        List<double> sa, sb;
        if (ca != null) {
          sa = sourceSeries(x, 'Kombi', cols: ca);
          sb = sourceSeries(x, 'Kombi', cols: cb);
        } else {
          sa = x.r;
          sb = x.g;
        }
        final cells = <String>[];
        for (final lp in [4.0, 8.0]) {
          final pa = prepare(x.t, sa, _w, lp: lp), pb = prepare(x.t, sb, _w, lp: lp);
          final fa = fiducials(pa, _w), fb = fiducials(pb, _w);
          for (final v in (lp == 4 ? vNames : ['tplRise', 'slope'])) {
            final a = fa[v]!, b = fb[v]!;
            final m = matchBeats(a.times, b.times, tol: 0.1);
            final dI = <double>[];
            for (var i = 0; i < a.ibi.length; i++) {
              final j = m.idx[i], j1 = m.idx[i + 1];
              if (a.valid[i] && j >= 0 && j1 == j + 1 && b.valid[j]) dI.add((a.ibi[i] - b.ibi[j]) * 1000);
            }
            cells.add(dI.length >= 10 ? '${f1(rms(dI) / math.sqrt2)} (${dI.length})' : '–');
          }
        }
        say('| ${f.split('/').last} | $label | ${cells.join(' | ')} |');
      } catch (e) {
        say('| ${f.split('/').last} | $label | Fehler: $e |');
      }
    }
  }
}

void checkEq(List<double> a, List<double> b) {
  if (a.length != b.length) throw StateError('Länge');
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) throw StateError('Abweichung zur App');
  }
}

// ---------------------------------------------------------------------------------------------
// Messpaare (Vertrag docs/contracts/morning-pairs-csv.md, Formatversion 1)
// ---------------------------------------------------------------------------------------------

class Morning {
  final ibi = <double?>[]; // ms, null = ungültig
  final belt = <double>[]; // ms
  double? rmssdApp;
  double? noise;
  String quality = '';
}

Map<String, Morning> parsePairs(String path) {
  final lines = File(path).readAsLinesSync();
  final head = lines.first.split(',');
  int c(String n) => head.indexOf(n);
  final out = <String, Morning>{};
  for (final l in lines.skip(1)) {
    if (l.trim().isEmpty) continue;
    final v = l.split(','); // Messpaare enthalten in den genutzten Spalten keine Kommas
    if (v[c('format_version')] != '1') throw StateError('unbekannte Formatversion');
    final m = out.putIfAbsent(v[c('morning_id')], Morning.new);
    final type = v[c('row_type')], key = v[c('key')], val = v[c('value')];
    if (type == 'camera_ibi') m.ibi.add(val.isEmpty ? null : double.parse(val));
    if (type == 'belt_rr') m.belt.add(double.parse(val) * 1000 / 1024);
    if (type == 'camera' && key == 'rmssd' && val.isNotEmpty) m.rmssdApp = double.parse(val);
    if (type == 'camera' && key == 'timing_noise' && val.isNotEmpty) m.noise = double.parse(val);
    if (type == 'meta' && key == 'quality') m.quality = val;
  }
  return out;
}

/// Ordnet die Kamera-Intervalle der Gurt-Folge zu (ohne Zeitstempel der Kamera-Schläge): Verschiebung
/// mit dem kleinsten Median |Differenz| über gültige Intervalle.
({int lag, List<double> err, double rCam, double rBelt, int pairs}) alignPairs(List<double?> cam, List<double> belt) {
  var best = 0;
  var bestMed = double.infinity;
  for (var lag = -cam.length; lag < belt.length; lag++) {
    final d = <double>[];
    for (var i = 0; i < cam.length; i++) {
      final j = i + lag;
      if (cam[i] != null && j >= 0 && j < belt.length) d.add((cam[i]! - belt[j]).abs());
    }
    if (d.length < math.max(10, cam.where((x) => x != null).length * 0.6)) continue;
    final med = quantile(d, 0.5);
    if (med < bestMed) {
      bestMed = med;
      best = lag;
    }
  }
  final err = <double>[];
  var sc = 0.0, sb = 0.0;
  var n = 0;
  for (var i = 0; i < cam.length; i++) {
    final j = i + best;
    if (cam[i] == null || j < 0 || j >= belt.length) continue;
    err.add(cam[i]! - belt[j]);
    if (i > 0 && cam[i - 1] != null && j - 1 >= 0) {
      final dc = cam[i]! - cam[i - 1]!, db = belt[j] - belt[j - 1];
      sc += dc * dc;
      sb += db * db;
      n++;
    }
  }
  return (lag: best, err: err, rCam: n > 0 ? math.sqrt(sc / n) : double.nan, rBelt: n > 0 ? math.sqrt(sb / n) : double.nan, pairs: n);
}

void runPairs(String dir, void Function(String) say, String selftestPath) {
  say('# R010 Messpaare (Kamera-Schlagabstände gegen Gurt-RR, nur Kennzahlen)\n');
  // Selbsttest mit synthetischer Datei: bekannte Verschiebung, bekannter Fehler
  final rnd = math.Random(7);
  final belt = [for (var i = 0; i < 80; i++) 1000 + 40 * math.sin(i / 2) + 10 * (rnd.nextDouble() - 0.5)];
  final sb = StringBuffer('format_version,morning_id,row_type,key,seq,sub,time,value,unit\r\n');
  sb.write('1,1,camera,rmssd,,,,50.0,ms\r\n');
  for (var i = 0; i < 55; i++) {
    final v = i == 20 ? '' : (belt[i + 12] + (i.isEven ? 5 : -5)).toStringAsFixed(3);
    sb.write('1,1,camera_ibi,ibi,${i + 1},,,$v,ms\r\n');
  }
  for (var i = 0; i < belt.length; i++) {
    sb.write('1,1,belt_rr,rr,${i + 1},1,2026-01-01T00:00:00Z,${(belt[i] * 1024 / 1000).round()},1/1024 s\r\n');
  }
  File(selftestPath).writeAsStringSync(sb.toString());
  final st = parsePairs(selftestPath)['1']!;
  final al = alignPairs(st.ibi, st.belt);
  say('Selbsttest (synthetische Datei): Verschiebung ${al.lag} (erwartet 12), Fehler RMS ${f1(rms(al.err))} ms (erwartet ≈ 5 plus Rundung 1/1024 s).\n');

  final d = Directory(dir);
  final files = d.existsSync()
      ? (d.listSync().whereType<File>().map((f) => f.path).where((p) => p.endsWith('.csv')).toList()..sort())
      : <String>[];
  if (files.isEmpty) {
    say('Keine Messpaar-Dateien in der Sammlung (`$dir`) – nichts ausgewertet.');
    return;
  }
  say('| Datei | Morgen | Stufe | Zeitrauschen App | Paare | Fehler/Intervall RMS | Median |Fehler| | RMSSD Kamera (Paare) | RMSSD Gurt (Paare) | Δ % | Δ % mit Median-3 |');
  say('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |');
  for (final f in files) {
    final ms = parsePairs(f);
    for (final e in ms.entries) {
      final m = e.value;
      if (m.belt.isEmpty || m.ibi.where((x) => x != null).length < 10) continue;
      final a = alignPairs(m.ibi, m.belt);
      // Median-3 auf der Kamera-Folge (nur gültige Nachbarn)
      final valid = [for (final v in m.ibi) v != null];
      final med = median3([for (final v in m.ibi) (v ?? 0) / 1000], valid);
      final a3 = alignPairs([for (var i = 0; i < med.length; i++) valid[i] ? med[i] * 1000 : null], m.belt);
      say('| ${f.split('/').last} | ${e.key} | ${m.quality} | ${m.noise == null ? "–" : f1(m.noise!)} | ${a.pairs} | ${f1(rms(a.err))} | '
          '${f1(quantile(a.err.map((x) => x.abs()).toList(), 0.5))} | ${f1(a.rCam)} | ${f1(a.rBelt)} | ${f1((a.rCam / a.rBelt - 1) * 100)} | '
          '${f1((a3.rCam / a3.rBelt - 1) * 100)} |');
    }
  }
}
