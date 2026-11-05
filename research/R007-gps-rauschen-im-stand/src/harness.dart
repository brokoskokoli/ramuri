// R007: speist Stand-Rohdaten durch den RunPreprocessor (app/packages/core).
// Forschungscode: nichts hieraus gehört in die App. Gegenmittel nur hier.
//
// Eingabe: normierte Spuren <norm>/<quelle>__<sitzung>.tsv mit den Spalten
//   t_ms lat lon acc speed sacc   (leer = fehlt)
// Ausgabe nach <out>: stops.csv, runs.csv, slow.csv, traces.csv.
import 'dart:io';
import 'dart:math' as math;

import 'package:core/core.dart';

const double mPerDeg = earthRadiusMeters * math.pi / 180;
const double baseLat = 48;
final double cosBase = math.cos(baseLat * math.pi / 180);
final DateTime t0 = DateTime.utc(2030);

class Fix {
  Fix(this.ms, this.lat, this.lon, this.acc, this.speed);
  final int ms;
  final double lat, lon;
  final double acc;
  final double? speed;
}

class Session {
  Session(this.source, this.name, this.fixes);
  final String source, name;
  final List<Fix> fixes;
  late final List<int> starts;
}

/// Gegenmittel als kausaler Filter vor dem RunPreprocessor.
abstract class Mitigation {
  String get name;
  Fix apply(Fix f);
  bool get needsSpeed => false;
}

class NoFilter extends Mitigation {
  @override
  String get name => 'keins';
  @override
  Fix apply(Fix f) => f;
}

double distM(double aLat, double aLon, double bLat, double bLon) =>
    haversineMeters(aLat, aLon, bLat, bLon);

/// Mindestdistanz: Anker bleibt, bis der Abstand D erreicht. Der Punkt behält
/// seine Zeit, sonst entstünde eine PAR-004-Lücke.
class MinDistance extends Mitigation {
  MinDistance(this.d, {this.useAcc = false, this.distanceOnly = false});
  final double d;
  final bool useAcc;

  /// Filtert nur die Strecke; die Bewegungszeit rechnet auf den Rohpunkten.
  final bool distanceOnly;
  Fix? anchor;
  @override
  String get name => 'mindist_${useAcc ? 'max${d.toInt()}acc' : '${d.toInt()}'}${distanceOnly ? '_nurstrecke' : ''}';
  @override
  Fix apply(Fix f) {
    if (f.acc > 25) return f; // wird im Prozessor verworfen, kein Anker
    final a = anchor;
    final limit = useAcc ? math.max(d, f.acc) : d;
    if (a == null || distM(a.lat, a.lon, f.lat, f.lon) >= limit) {
      anchor = f;
      return f;
    }
    return Fix(f.ms, a.lat, a.lon, f.acc, f.speed);
  }
}

/// Gleitendes Mittel über die letzten W s (nur Vergangenheit).
class MovingAverage extends Mitigation {
  MovingAverage(this.w);
  final int w;
  final List<Fix> buf = [];
  @override
  String get name => 'mittel_${w}s';
  @override
  Fix apply(Fix f) {
    if (f.acc > 25) return f;
    buf.add(f);
    while (f.ms - buf.first.ms >= w * 1000) {
      buf.removeAt(0);
    }
    var la = 0.0, lo = 0.0;
    for (final b in buf) {
      la += b.lat;
      lo += b.lon;
    }
    return Fix(f.ms, la / buf.length, lo / buf.length, f.acc, f.speed);
  }
}

/// Position hält, solange getSpeed unter v0 liegt.
class SpeedGate extends Mitigation {
  SpeedGate(this.v0);
  final double v0;
  Fix? anchor;
  @override
  String get name => 'getspeed_gate_$v0';
  @override
  bool get needsSpeed => true;
  @override
  Fix apply(Fix f) {
    if (f.acc > 25) return f;
    final a = anchor;
    if (a == null || (f.speed ?? 0) >= v0) {
      anchor = f;
      return f;
    }
    return Fix(f.ms, a.lat, a.lon, f.acc, f.speed);
  }
}

/// Strecke aus getSpeed: Punkt rückt um speed·dt auf einer Geraden vor.
class SpeedIntegrate extends Mitigation {
  double north = 0;
  int? last;
  @override
  String get name => 'getspeed_integral';
  @override
  bool get needsSpeed => true;
  @override
  Fix apply(Fix f) {
    if (f.acc > 25) return f;
    if (last != null) north += (f.speed ?? 0) * (f.ms - last!) / 1000;
    last = f.ms;
    return Fix(f.ms, baseLat + north / mPerDeg, 11, f.acc, f.speed);
  }
}

/// Nur diese Gegenmittel rechnen (--mitigations), leer = alle.
Set<String> onlyMitigations = {};

List<Mitigation> mitigations(bool withSpeed) => [
  NoFilter(),
  MinDistance(3),
  MinDistance(5),
  MinDistance(8),
  MinDistance(10),
  MinDistance(3, useAcc: true),
  MinDistance(3, distanceOnly: true),
  MinDistance(5, distanceOnly: true),
  MinDistance(8, distanceOnly: true),
  MinDistance(3, useAcc: true, distanceOnly: true),
  MovingAverage(5),
  MovingAverage(10),
  MovingAverage(20),
  if (withSpeed) ...[SpeedGate(0.3), SpeedGate(0.5), SpeedIntegrate()],
].where((m) => onlyMitigations.isEmpty || onlyMitigations.contains(m.name)).toList();

double? parse(String s) => s.isEmpty ? null : double.parse(s);

List<Session> load(String dir) {
  final out = <Session>[];
  final files = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.tsv')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final base = f.uri.pathSegments.last.replaceAll('.tsv', '');
    final parts = base.split('__');
    final fixes = <Fix>[];
    for (final l in f.readAsLinesSync().skip(1)) {
      final p = l.split('\t');
      fixes.add(Fix(int.parse(p[0]), double.parse(p[1]), double.parse(p[2]), double.parse(p[3]), parse(p[4])));
    }
    out.add(Session(parts[0], parts[1], fixes));
  }
  return out;
}

/// Gültige Fensteranfänge: Einlaufzeit übersprungen, keine Abstände über 2 s.
List<int> validStarts(List<Fix> x, int seconds, int burnIn) {
  final r = <int>[];
  if (x.isEmpty) return r;
  // Letzter Index mit einem Abstand > 2 s vor oder an i.
  final endOf = <int>[];
  var j = 0;
  for (var i = 0; i < x.length; i++) {
    if (j < i) j = i;
    while (j + 1 < x.length && x[j + 1].ms - x[j].ms <= 2000 && x[j].ms - x[i].ms < seconds * 1000) {
      j++;
    }
    endOf.add(j);
  }
  for (var i = 0; i < x.length; i++) {
    if (x[i].ms - x[0].ms < burnIn * 1000) continue;
    if (x[endOf[i]].ms - x[i].ms >= seconds * 1000) r.add(i);
  }
  return r;
}

class Step {
  Step(this.ms, this.lat, this.lon, this.acc, this.speed, this.stop);
  final int ms;
  final double lat, lon, acc;
  final double? speed;
  final int stop; // -1 Lauf, sonst Stoppnummer
}

class Built {
  Built(this.steps, this.stops);
  final List<Step> steps;
  final List<(int, int)> stops; // [Beginn, Ende] in ms
}

/// Lauf: Gerade nach Norden mit [speed], unterbrochen von Stopps, in denen die
/// Spur aus den Inkrementen der Standfenster weiterläuft. Kein Versatz an den
/// Nahtstellen, weil nur Inkremente verwendet werden.
Built build(int totalS, int stopS, List<(Session, int)?> windows, double speed) {
  final n = windows.length;
  final moveS = (totalS - n * stopS) ~/ (n + 1);
  var north = 0.0, east = 0.0;
  var ms = 0;
  final steps = <Step>[];
  void emit(double acc, double? sp, int stop) => steps.add(
    Step(ms, baseLat + north / mPerDeg, 11 + east / (mPerDeg * cosBase), acc, sp, stop),
  );
  emit(5, speed, -1);
  final stops = <(int, int)>[];
  void move(int seconds) {
    for (var s = 0; s < seconds; s++) {
      ms += 1000;
      north += speed;
      emit(5, speed, -1);
    }
  }

  for (var k = 0; k < n; k++) {
    move(moveS);
    final begin = ms;
    final w = windows[k];
    if (w == null) {
      // Ohne Rauschen: Kontrolle.
      for (var s = 0; s < stopS; s++) {
        ms += 1000;
        emit(5, 0, k);
      }
    } else {
      final x = w.$1.fixes;
      var i = w.$2;
      final first = x[i];
      final cosW = math.cos(first.lat * math.pi / 180);
      var prev = first;
      i++;
      while (x[i].ms - first.ms <= stopS * 1000) {
        final c = x[i];
        north += (c.lat - prev.lat) * mPerDeg;
        east += (c.lon - prev.lon) * mPerDeg * cosW;
        ms = begin + (c.ms - first.ms);
        emit(c.acc, c.speed, k);
        prev = c;
        i++;
        if (i >= x.length) break;
      }
      ms = begin + stopS * 1000;
    }
    stops.add((begin, ms));
  }
  move(moveS);
  return Built(steps, stops);
}

RawPosition raw(int ms, double lat, double lon, double acc) => RawPosition(
  time: t0.add(Duration(milliseconds: ms)),
  source: 'r007',
  latitude: lat,
  longitude: lon,
  accuracyMeters: acc,
);

class RunOut {
  RunOut(this.res, this.endMs);
  final RunPreprocessing res;
  final int endMs;
}

PreprocessingParameters params = const PreprocessingParameters.v3();

RunOut feed(Iterable<Fix> fixes, Mitigation m, int endMs, {int startMs = 0}) {
  final r = RunPreprocessor(start: t0.add(Duration(milliseconds: startMs)), parameters: params);
  for (final f in fixes) {
    final g = m.apply(f);
    r.addPosition(raw(g.ms, g.lat, g.lon, g.acc));
  }
  return RunOut(r.result(at: t0.add(Duration(milliseconds: endMs))), endMs);
}

int msOf(DateTime d) => d.difference(t0).inMilliseconds;

Map<String, double> discards(List<ProcessedPosition> ps) {
  final c = <String, double>{'accuracy': 0, 'hardJump': 0, 'softJump': 0};
  for (final p in ps) {
    if (p.reason != null) c[p.reason!.name] = (c[p.reason!.name] ?? 0) + 1;
  }
  return c;
}

String f3(num v) => v.toStringAsFixed(3);

void main(List<String> a) {
  String opt(String k, String d) {
    final i = a.indexOf('--$k');
    return i >= 0 ? a[i + 1] : d;
  }

  final norm = opt('norm', '');
  final out = opt('out', '');
  final seed = int.parse(opt('seed', '42'));
  final runs = int.parse(opt('runs', '200'));
  final speed = double.parse(opt('run-speed', '3'));
  final totalS = int.parse(opt('total-s', '1800'));
  final stopS = int.parse(opt('stop-s', '60'));
  final nStops = int.parse(opt('stops', '3'));
  final burnIn = int.parse(opt('burn-in-s', '120'));
  final below = double.parse(opt('standstill-below', '0.5'));
  final from = double.parse(opt('movement-from', '0.8'));
  // Weitere Parameter nur zum Vergleich (varianten.py), 1e9 schaltet PAR-002 oder -003 ab.
  final hardJump = double.parse(opt('hard-jump', '12.5'));
  final softJump = double.parse(opt('soft-jump', '8'));
  final gapS = int.parse(opt('gap-s', '10'));
  final standstillS = int.parse(opt('standstill-s', '10'));
  final simOnly = a.contains('--sim-only'); // ohne Spurmodus und langsame Bewegung
  if (opt('mitigations', '').isNotEmpty) onlyMitigations = opt('mitigations', '').split(';').toSet();
  if (below != 0.5 || from != 0.8 || hardJump != 12.5 || softJump != 8 || gapS != 10 || standstillS != 10) {
    // Nur zum Vergleich; Version 999 ist keine echte Parameterversion.
    params = PreprocessingParameters(
      parameterVersion: 999,
      standstillBelow: below,
      movementFrom: from,
      hardJumpMaxSpeed: hardJump,
      softJumpSpeed: softJump,
      gapMaxDuration: Duration(seconds: gapS),
      standstillMinDuration: Duration(seconds: standstillS),
    );
  }
  final rnd = math.Random(seed);
  final all = load(norm);
  Directory(out).createSync(recursive: true);

  final stopsCsv = File('$out/stops.csv').openWrite()
    ..writeln('source,mitigation,run,stop,session,win,paused,pause_delay_s,resumes,sham_m,sham_in_pause_m,disc_acc,disc_hard,disc_soft');
  final runsCsv = File('$out/runs.csv').openWrite()
    ..writeln('source,mitigation,run,unpaused,sham_stop_m,dist_m,dist_err_m,dist_err_base_m,post_stop_m,rest_m,moving_s,moving_excess_s,gaps');
  final slowCsv = File('$out/slow.csv').openWrite()
    ..writeln('source,mitigation,v,rep,dist_ratio,moving_share,false_pauses');
  final traceCsv = File('$out/traces.csv').openWrite()
    ..writeln('source,session,mitigation,dur_s,n,dist_m,integral_m,moving_s,pauses,disc_acc,disc_hard,disc_soft,gaps');

  // Kontrolle: rauschfreier Lauf, Handrechnung siehe README.
  final ctrlB = build(totalS, stopS, List.filled(nStops, null), speed);
  final ctrlFix = [for (final s in ctrlB.steps) Fix(s.ms, s.lat, s.lon, s.acc, s.speed)];
  final ctrl = feed(ctrlFix, NoFilter(), ctrlB.steps.last.ms);
  final ctrlDist = ctrl.res.position.distanceMeters!;
  final ctrlMoving = ctrl.res.movement.movingTime.inMilliseconds / 1000;
  File('$out/control.txt').writeAsStringSync(
    'dist_m=${f3(ctrlDist)} moving_s=${f3(ctrlMoving)} intervals=${ctrl.res.movement.movingIntervals.length} '
    'total_s=${ctrl.res.movement.totalTime.inSeconds}\n',
  );
  stdout.writeln('Kontrolle: dist=$ctrlDist moving=$ctrlMoving');
  // Jedes Gegenmittel bekommt seine eigene rauschfreie Kontrolle: Es kann die Strecke auch ohne jedes
  // Rauschen ändern (Mittel endet (w-1)/2·v hinter dem letzten Punkt, Mindestdistanz je nach Phase).
  final ctrlOwn = <String, double>{};
  final ctrlMit = File('$out/control_mitigations.csv').openWrite()..writeln('mitigation,dist_m,rand_m,moving_s,moving_excess_s');
  for (final m in mitigations(true)) {
    final o = feed(ctrlFix, m, ctrlB.steps.last.ms);
    final mv = m is MinDistance && m.distanceOnly ? ctrl.res.movement : o.res.movement;
    final d = o.res.position.distanceMeters!;
    ctrlOwn[m.name] = d;
    final mvS = mv.movingTime.inMilliseconds / 1000;
    ctrlMit.writeln('${m.name},${f3(d)},${f3(d - ctrlDist)},${f3(mvS)},${f3(mvS - ctrlMoving)}');
  }
  ctrlMit.close();

  final bySource = <String, List<Session>>{};
  for (final s in all) {
    bySource.putIfAbsent(s.source, () => []).add(s);
  }

  for (final source in bySource.keys) {
    final isWalk = source.startsWith('walk') || source.startsWith('stopreal') || source == 'ncount';
    final sessions = bySource[source]!;
    // Spurmodus: jede Sitzung als Ganzes, ohne Lauf drumherum.
    final hasSpeedAll = sessions.every((s) => s.fixes.every((f) => f.speed != null));
    for (final s in simOnly ? const <Session>[] : sessions) {
      if (s.fixes.length < 20) continue;
      final startMs = s.fixes.first.ms;
      final shifted = s.fixes.map((f) => Fix(f.ms - startMs, f.lat, f.lon, f.acc, f.speed)).toList();
      var integral = 0.0;
      for (var i = 1; i < shifted.length; i++) {
        final dt = (shifted[i].ms - shifted[i - 1].ms) / 1000;
        if (dt <= 10) integral += (shifted[i].speed ?? 0) * dt;
      }
      for (final m in mitigations(hasSpeedAll)) {
        final o = feed(shifted, m, shifted.last.ms);
        final mt = m is MinDistance && m.distanceOnly ? feed(shifted, NoFilter(), shifted.last.ms).res.movement : o.res.movement;
        final d = discards(o.res.position.positions);
        traceCsv.writeln(
          '$source,${s.name},${m.name},${shifted.last.ms / 1000},${shifted.length},${f3(o.res.position.distanceMeters ?? 0)},'
          '${f3(integral)},${f3(mt.movingTime.inMilliseconds / 1000)},'
          '${mt.resumedAt.length + (mt.autoPauseState == AutoPauseState.standstillPause ? 1 : 0)},'
          '${d['accuracy']!.toInt()},${d['hardJump']!.toInt()},${d['softJump']!.toInt()},${o.res.position.gaps.length}',
        );
      }
    }
    if (isWalk) continue; // Gehspuren nur im Spurmodus.

    // Laufsimulation: gezogene Standfenster.
    final pool = <(Session, int)>[];
    for (final s in sessions) {
      for (final i in validStarts(s.fixes, stopS, burnIn)) {
        pool.add((s, i));
      }
    }
    stdout.writeln('$source: Sitzungen ${sessions.length}, Fensteranfänge ${pool.length}');
    if (pool.isEmpty) continue;

    final hasSpeed = pool.every((w) => w.$1.fixes[w.$2].speed != null);
    for (var run = 0; run < runs; run++) {
      final win = [for (var k = 0; k < nStops; k++) pool[rnd.nextInt(pool.length)]];
      final b = build(totalS, stopS, win, speed);
      final fixes = [for (final s in b.steps) Fix(s.ms, s.lat, s.lon, s.acc, s.speed)];
      final end = b.steps.last.ms;
      for (final m in mitigations(hasSpeed)) {
        final o = feed(fixes, m, end);
        // Variante nur Strecke: Bewegungszeit aus dem ungefilterten Lauf.
        final mv = m is MinDistance && m.distanceOnly ? feed(fixes, NoFilter(), end).res.movement : o.res.movement;
        final ivs = mv.movingIntervals;
        var unpaused = 0;
        var shamTotal = 0.0;
        for (var k = 0; k < nStops; k++) {
          final (b0, b1) = b.stops[k];
          // Pause ausgelöst, wenn kein Bewegungsintervall den Stopp ganz überdeckt.
          final covered = ivs.any((i) => msOf(i.start) <= b0 && msOf(i.end) >= b1);
          // Erste Pause innerhalb des Stopps.
          double delay = -1;
          for (final i in ivs) {
            final e = msOf(i.end);
            if (e >= b0 && e <= b1) {
              delay = (e - b0) / 1000;
              break;
            }
          }
          var resumes = 0;
          for (final t in mv.resumedAt) {
            final x = msOf(t);
            if (x > b0 && x <= b1) resumes++;
          }
          if (covered) unpaused++;
          var sham = 0.0, inPause = 0.0;
          var dA = 0, dH = 0, dS = 0;
          for (final p in o.res.position.positions) {
            final x = msOf(p.input.time);
            if (x <= b0 || x > b1) continue;
            sham += p.countedDistanceMeters;
            final moving = ivs.any((i) => msOf(i.start) < x && msOf(i.end) >= x);
            if (!moving) inPause += p.countedDistanceMeters;
            if (p.reason == DiscardReason.accuracy) dA++;
            if (p.reason == DiscardReason.hardJump) dH++;
            if (p.reason == DiscardReason.softJump) dS++;
          }
          shamTotal += sham;
          stopsCsv.writeln(
            '$source,${m.name},$run,$k,${win[k].$1.name},${win[k].$2},${covered ? 0 : 1},${f3(delay)},$resumes,${f3(sham)},${f3(inPause)},$dA,$dH,$dS',
          );
        }
        final dist = o.res.position.distanceMeters!;
        final moving = mv.movingTime.inMilliseconds / 1000;
        // Zerlegung: was der Laufteil gegenüber speed je Sekunde mehr zählt, in den 25 s nach Stopps und sonst.
        var postStop = 0.0, rest = 0.0;
        for (final p in o.res.position.positions) {
          final x = msOf(p.input.time);
          if (x == 0 || b.stops.any((st) => x > st.$1 && x <= st.$2)) continue;
          final extra = p.countedDistanceMeters - speed;
          if (b.stops.any((st) => x > st.$2 && x <= st.$2 + 25000)) {
            postStop += extra;
          } else {
            rest += extra;
          }
        }
        runsCsv.writeln(
          '$source,${m.name},$run,$unpaused,${f3(shamTotal)},${f3(dist)},${f3(dist - ctrlOwn[m.name]!)},${f3(dist - ctrlDist)},${f3(postStop)},${f3(rest)},${f3(moving)},${f3(moving - ctrlMoving)},${o.res.position.gaps.length}',
        );
      }
    }

    if (simOnly) continue;
    // Langsame echte Bewegung mit echtem Rauschen: falsche Pausen je Gegenmittel.
    // getSpeed fehlt hier bewusst: dessen Verhalten im Gehen zeigen nur die Gehspuren.
    final poolLong = <(Session, int)>[];
    for (final s in sessions) {
      for (final i in validStarts(s.fixes, 300, burnIn)) {
        poolLong.add((s, i));
      }
    }
    if (poolLong.isEmpty) continue;
    for (final v in [0.6, 0.8, 1.0, 1.5, 3.0]) {
      for (var rep = 0; rep < 30; rep++) {
        final w = poolLong[rnd.nextInt(poolLong.length)];
        final x = w.$1.fixes;
        final first = x[w.$2];
        final cosW = math.cos(first.lat * math.pi / 180);
        final fx = <Fix>[];
        for (var i = w.$2; i < x.length && x[i].ms - first.ms <= 300000; i++) {
          final c = x[i];
          final ms = c.ms - first.ms;
          final north = (c.lat - first.lat) * mPerDeg + v * ms / 1000;
          final east = (c.lon - first.lon) * mPerDeg * cosW;
          fx.add(Fix(ms, baseLat + north / mPerDeg, 11 + east / (mPerDeg * cosBase), c.acc, null));
        }
        for (final m in mitigations(false)) {
          final o = feed(fx, m, fx.last.ms);
          final mv = m is MinDistance && m.distanceOnly ? feed(fx, NoFilter(), fx.last.ms).res.movement : o.res.movement;
          final total = mv.totalTime.inMilliseconds / 1000;
          final pauses = mv.resumedAt.length + (mv.autoPauseState == AutoPauseState.standstillPause ? 1 : 0);
          slowCsv.writeln(
            '$source,${m.name},$v,$rep,${f3((o.res.position.distanceMeters ?? 0) / (v * total))},${f3(mv.movingTime.inMilliseconds / 1000 / total)},$pauses',
          );
        }
      }
    }
    stdout.writeln('$source fertig');
  }
  stopsCsv.close();
  runsCsv.close();
  slowCsv.close();
  traceCsv.close();
}
