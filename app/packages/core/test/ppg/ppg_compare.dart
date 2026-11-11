import 'package:core/core.dart';

/// Toleranzen des Abgleichs mit der Referenz (WP27: Puls 0,1/min, RMSSD 0,5 ms). Die übrigen
/// Größen sind Zusatzprüfungen mit eigenen Toleranzen; Zählwerte müssen exakt stimmen.
const double tolBpm = 0.1;
const double tolMs = 0.5;
const double tolQuality = 1e-3;

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

/// Gibt nur Abweichungen zurück, nie die Werte selbst (nur den Betrag der Abweichung).
/// Abweichung an (bei echten Messungen: nur Betrag, kein Wert).
List<String> comparePpgSet(PpgAnalysisSet got, Map<String, dynamic> ref) {
  final out = <String>[];
  void num_(String what, double g, Object? r, double tol) {
    final rv = _num(r);
    if (rv == null || !g.isFinite) {
      if (!(rv == null && !g.isFinite)) {
        out.add('$what: nur eine Seite ist nicht endlich');
      }
      return;
    }
    final d = (g - rv).abs();
    if (d > tol) {
      out.add('$what: Abweichung ${d.toStringAsExponential(2)} > $tol');
    }
  }

  void count(String what, int g, Object? r) {
    if (g != (r as int)) {
      out.add('$what: Zählwert weicht ab (Differenz ${(g - r).abs()})');
    }
  }

  if (got.best.channel != ref['best']) out.add('Quellenwahl weicht ab');
  final chans = (ref['channels'] as List).cast<Map<String, dynamic>>();
  if (chans.length != got.all.length) {
    out.add('Zahl der Kanäle weicht ab');
    return out;
  }
  for (var i = 0; i < chans.length; i++) {
    final g = got.all[i];
    final r = chans[i];
    final c = g.channel;
    if (c != r['channel']) {
      out.add('Kanal $i: Name weicht ab');
      continue;
    }
    num_('$c quality', g.quality, r['quality'], tolQuality);
    num_('$c spectralBpm', g.spectralBpm, r['spectralBpm'], tolBpm);
    num_('$c meanFps', g.meanFps, r['meanFps'], 0.01);
    num_('$c frameJitterMs', g.frameJitterMs, r['frameJitterMs'], 0.1);
    num_('$c timingNoiseMs', g.timingNoiseMs, r['timingNoiseMs'], tolMs);
    final refArt = (r['artifacts'] as List).cast<List>();
    count('$c artifacts', g.artifacts.length, refArt.length);
    if (g.artifacts.length == refArt.length) {
      for (var a = 0; a < refArt.length; a++) {
        num_('$c artifact$a von', g.artifacts[a][0], refArt[a][0], 0.011);
        num_('$c artifact$a bis', g.artifacts[a][1], refArt[a][1], 0.011);
      }
    }
    final rated = ratePpg(g);
    final verdict = r['verdict'] as String;
    final expected = switch (verdict) {
      'gut' => PpgQuality.good,
      'eingeschränkt' => PpgQuality.limited,
      _ => PpgQuality.unusable,
    };
    if (rated.quality != expected) out.add('$c Bewertung weicht ab');
    final ms = (r['methods'] as List).cast<Map<String, dynamic>>();
    if (ms.length != g.methods.length) {
      out.add('$c Zahl der Verfahren weicht ab');
      continue;
    }
    for (var m = 0; m < ms.length; m++) {
      final gm = g.methods[m];
      if (gm.name != ms[m]['name']) {
        out.add('$c Verfahren $m: Name weicht ab');
        continue;
      }
      for (final part in ['total', 'first', 'second']) {
        final gs = switch (part) {
          'total' => gm.total,
          'first' => gm.first,
          _ => gm.second,
        };
        final rs = ms[m][part] as Map<String, dynamic>;
        final p = '$c ${gm.name} $part';
        count('$p beats', gs.beats, rs['beats']);
        count('$p ibis', gs.ibis, rs['ibis']);
        count('$p validIbis', gs.validIbis, rs['validIbis']);
        num_('$p bpm', gs.bpm, rs['bpm'], tolBpm);
        num_('$p minBpm', gs.minBpm, rs['minBpm'], tolBpm);
        num_('$p maxBpm', gs.maxBpm, rs['maxBpm'], tolBpm);
        num_('$p meanIbiMs', gs.meanIbiMs, rs['meanIbiMs'], tolMs);
        num_('$p sdnnMs', gs.sdnnMs, rs['sdnnMs'], tolMs);
        num_('$p rmssdMs', gs.rmssdMs, rs['rmssdMs'], tolMs);
        num_('$p pnn50', gs.pnn50, rs['pnn50'], tolMs);
      }
    }
  }
  return out;
}

/// Größte beobachtete Abweichung von Puls und RMSSD (Hauptverfahren, Hauptergebnis).
({double bpm, double rmssd}) mainDeviation(
  PpgAnalysisSet got,
  Map<String, dynamic> ref,
) {
  final best = (ref['channels'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((c) => c['channel'] == ref['best']);
  final t =
      ((best['methods'] as List).first as Map<String, dynamic>)['total']
          as Map<String, dynamic>;
  return (
    bpm: (got.best.main.total.bpm - _num(t['bpm'])!).abs(),
    rmssd: (got.best.main.total.rmssdMs - _num(t['rmssdMs'])!).abs(),
  );
}
