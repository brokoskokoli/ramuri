import 'dart:math' as math;

import 'ppg_analyzer.dart';
import 'ppg_evaluator.dart';
import 'ppg_parameters.dart';
import 'ppg_signal.dart';

/// Ergebnis der Fenstersuche (WP37, PAR-160K Auslegung (K66), ALGORITHMUS.md Abschn. 2).
class PpgWindowedMeasurement {
  const PpgWindowedMeasurement({
    required this.measurement,
    this.windowStartSeconds,
    this.windowEndSeconds,
    this.goodStretchSeconds = 0.0,
  });

  /// Bewertung des gewählten Fensters nach ALGORITHMUS.md Abschn. 10 (Zeitrauschen, Intervalle
  /// und RMSSD nur dieses Fensters). Ohne Fenster: „unbrauchbar“ mit Grund.
  final PpgMeasurement measurement;

  /// Anfang und Ende des gewählten Fensters in s seit Aufnahmebeginn; null, wenn die Aufnahme für
  /// kein Fenster reicht oder nicht auswertbar ist.
  final double? windowStartSeconds;
  final double? windowEndSeconds;

  /// Längstes Stück mit mindestens 70 % gültigen Intervallen in s (höchstens [ppgSearchWindowSeconds]), nur für
  /// die Anzeige („gutes Signal 0:42 von 1:00“); das Abbruchkriterium ist das Fenster der Stufe „gut“.
  final double goodStretchSeconds;
}

/// Zustand einer laufenden Aufnahme für Anzeige und Abbruch.
class PpgRecordingCheck {
  const PpgRecordingCheck({
    required this.goodWindowReached,
    required this.goodStretchSeconds,
  });

  /// Ein Fenster von [ppgSearchWindowSeconds] mit Filterrand erreicht die Stufe „gut“ (nach
  /// derselben Rechnung wie [evaluatePpgBestWindow], bestätigt am Einzelfenster): die Aufnahme darf enden.
  final bool goodWindowReached;

  /// Wie [PpgWindowedMeasurement.goodStretchSeconds].
  final double goodStretchSeconds;
}

class _Candidate {
  _Candidate(this.start, this.measurement);
  final double start;
  final PpgMeasurement measurement;

  double get fraction => measurement.intervals > 0
      ? measurement.validIntervals / measurement.intervals
      : 0.0;
}

class _Scan {
  _Scan.failed(this.failure) : candidates = const [], goodStretch = 0.0;
  _Scan(this.candidates, this.goodStretch) : failure = null;

  /// Nach Rang sortiert: höchste Stufe, höchster Anteil gültiger Intervalle, frühester Beginn.
  final List<_Candidate> candidates;
  final double goodStretch;
  final PpgQualityReason? failure;
}

PpgWindow _windowAt(double start) => PpgWindow(
  filterStart: start - ppgSearchFilterLeadSeconds,
  start: start,
  end: start + ppgSearchWindowSeconds,
  dataEnd: start + ppgSearchWindowSeconds + ppgSearchFilterTailSeconds,
);

PpgMeasurement _unusable(PpgQualityReason reason) =>
    PpgMeasurement(quality: PpgQuality.unusable, reasons: [reason]);

int _rank(PpgQuality q) => switch (q) {
  PpgQuality.good => 0,
  PpgQuality.limited => 1,
  PpgQuality.unusable => 2,
};

int _compare(_Candidate a, _Candidate b) {
  final byQuality = _rank(a.measurement.quality)
      .compareTo(_rank(b.measurement.quality));
  if (byQuality != 0) return byQuality;
  final byFraction = b.fraction.compareTo(a.fraction);
  if (byFraction != 0) return byFraction;
  return a.start.compareTo(b.start);
}

/// Einmal über die ganze Aufnahme analysieren, dann jedes Kandidatenfenster auf den Ergebnissen
/// (Schläge, Intervalle, gefiltertes Signal) nach den Kriterien aus `ratePpg` bewerten. Das ist
/// eine Näherung der Einzelauswertung des Fensters (Ausreißerprüfung und Vorlage gelten für die
/// ganze Aufnahme); das gewählte Fenster wird danach mit `evaluatePpg` einzeln ausgewertet.
/// [live]: laufende Aufnahme: Der Filterrand nach dem Fenster muss schon aufgenommen sein, und auch
/// ohne Kandidatenfenster wird für die Anzeige des guten Stücks analysiert.
_Scan _scan(List<PpgFrame> frames, {required bool live}) {
  if (!frames.every(ppgFrameIsValid)) {
    return _Scan.failed(PpgQualityReason.invalidInput);
  }
  final first = ppgStandardWindow.filterStart;
  final fs = <PpgFrame>[];
  for (final f in frames) {
    if (f.t < first || f.t > ppgSearchMaxRecordSeconds) continue;
    if (fs.isNotEmpty && f.t <= fs.last.t) continue;
    fs.add(f);
  }
  if (fs.length <= ppgMinFrames) {
    return _Scan.failed(PpgQualityReason.insufficientData);
  }
  final lastT = fs.last.t;
  final startMin = ppgStandardWindow.start;
  final margin = live ? ppgSearchFilterTailSeconds : 0.0;
  final starts = <double>[];
  for (var k = 0; ; k++) {
    final s = startMin + k * ppgSearchStepSeconds;
    if (s + ppgSearchWindowSeconds + margin > lastT + 1e-9) break;
    if (s + ppgSearchWindowSeconds + ppgSearchFilterTailSeconds >
        ppgSearchMaxRecordSeconds + 1e-9) {
      break;
    }
    starts.add(s);
  }
  if (starts.isEmpty && !live) {
    return _Scan.failed(PpgQualityReason.insufficientData);
  }

  final PpgAnalysisSet set;
  try {
    set = _analyze(
      fs,
      PpgWindow(
        filterStart: first,
        start: startMin,
        end: lastT,
        dataEnd: lastT,
      ),
    );
  } on PpgInsufficientDataException {
    return _Scan.failed(PpgQualityReason.insufficientData);
  } on PpgFlatSignalException {
    return _Scan.failed(PpgQualityReason.flatSignal);
  } catch (_) {
    return _Scan.failed(PpgQualityReason.analysisFailed);
  }

  final candidates = [
    for (final s in starts) _Candidate(s, _rateWindow(fs, set, startMin, s)),
  ]..sort(_compare);
  return _Scan(candidates, _progress(fs, _goodStretch(set)));
}

PpgAnalysisSet _analyze(List<PpgFrame> fs, PpgWindow w) => PpgAnalyzer.analyze(
  [for (final f in fs) f.t],
  [
    PpgSeries('Rot', [for (final f in fs) f.r]),
    PpgSeries('Grün', [for (final f in fs) f.g]),
  ],
  [
    for (var k = 0; k < 16; k++)
      PpgSeries('r$k', [for (final f in fs) f.r16[k]]),
    for (var k = 0; k < 16; k++)
      PpgSeries('g$k', [for (final f in fs) f.g16[k]]),
  ],
  w,
);

/// Längen der jüngsten Abschnitte (s), die für die Anzeige zusätzlich einzeln analysiert werden.
const List<double> _recentSeconds = [ppgSearchWindowSeconds, 30.0];

/// Anzeige des guten Stücks. Die Gesamtanalyse bezieht eine starke Störung am Anfang in Vorlage
/// und Schwellen ein und kann danach auch gute Schläge als ungültig führen (30 s Rauschen, dann
/// 40 s gutes Signal: 4,7 statt rund 40 s). Darum zählt zusätzlich das gute Stück je einer
/// Analyse der jüngsten 60 und 30 s (nur wenn die Aufnahme dafür deutlich länger ist und die
/// Gesamtanalyse noch kein volles Fenster zeigt); der größte Wert gilt.
double _progress(List<PpgFrame> fs, double overall) {
  var best = overall;
  final lastT = fs.last.t;
  if (overall >= 0.9 * ppgSearchWindowSeconds) return best;
  for (final len in _recentSeconds) {
    final from = lastT - len;
    if (from < ppgStandardWindow.filterStart + 5.0) continue;
    final recent = [
      for (final f in fs)
        if (f.t >= from) f,
    ];
    if (recent.length <= ppgMinFrames) continue;
    try {
      final set = _analyze(
        recent,
        PpgWindow(
          filterStart: recent.first.t,
          start: recent.first.t + 2.0,
          end: lastT,
          dataEnd: lastT,
        ),
      );
      best = math.max(best, _goodStretch(set));
    } catch (_) {
      // Dieser Abschnitt ist nicht auswertbar: er trägt nichts bei.
    }
  }
  return best;
}

/// Bewertung eines Kandidatenfensters [s, s + 60]: Bildlücke, Finger und Bildzahl wie in
/// `evaluatePpg`, sonst die Quellen des Fensters (Q aus dem Signalstück, Intervalle und
/// Zeitrauschen aus den Schlägen im Fenster), Quellenwahl und Stufe wie `ratePpg`.
PpgMeasurement _rateWindow(
  List<PpgFrame> fs,
  PpgAnalysisSet set,
  double base,
  double s,
) {
  final w = _windowAt(s);
  var firstT = double.infinity;
  var lastT = double.negativeInfinity;
  var inWindow = 0;
  var sumR = 0.0;
  var sumG = 0.0;
  double? prev;
  for (final f in fs) {
    if (f.t >= w.filterStart && f.t <= w.dataEnd) {
      if (f.t < firstT) firstT = f.t;
      if (f.t > lastT) lastT = f.t;
      if (prev != null && f.t - prev > ppgMaxFrameGapSeconds) {
        return _unusable(PpgQualityReason.frameGap);
      }
      prev = f.t;
    }
    if (f.t >= w.start && f.t <= w.end) {
      inWindow++;
      sumR += f.r;
      sumG += f.g;
    }
  }
  if (firstT > w.start || lastT < w.end || inWindow <= ppgMinFrames) {
    return _unusable(PpgQualityReason.insufficientData);
  }
  if (!(sumR > 0) || sumR < ppgMinRedGreenRatio * sumG) {
    return _unusable(PpgQualityReason.noFinger);
  }
  final results = [
    for (final c in set.all)
      _windowChannel(c, base, s, s + ppgSearchWindowSeconds),
  ];
  return ratePpg(PpgAnalyzer.chooseBest(results));
}

const int _qDecimation = 4;

double _mean(List<double> x, int from, int n) {
  var sum = 0.0;
  for (var i = from; i < from + n; i++) {
    sum += x[i];
  }
  return sum / n;
}

PpgChannelResult _windowChannel(
  PpgChannelResult c,
  double base,
  double s,
  double e,
) {
  const eps = 1e-9;
  final m = c.main;
  final beats = m.times;
  // Schläge im Fenster, Zeiten der Quelle sind relativ zu `base`.
  var k0 = -1;
  var k1 = -1;
  for (var k = 0; k < beats.length; k++) {
    final a = base + beats[k];
    if (a >= s - eps && a <= e + eps) {
      if (k0 < 0) k0 = k;
      k1 = k;
    }
  }
  final hasBeats = k0 >= 0 && k1 > k0;
  final shift = s - base;
  final times = <double>[];
  final ends = <double>[];
  final ibi = <double>[];
  final valid = <bool>[];
  if (hasBeats) {
    for (var k = k0; k <= k1; k++) {
      times.add(beats[k] - shift);
    }
    for (var i = k0; i < k1; i++) {
      ends.add(m.ibiEnd[i] - shift);
      ibi.add(m.ibiMs[i] / 1000);
      valid.add(m.valid[i]);
    }
  }
  final total = PpgAnalyzer.stats(
    times,
    ends,
    ibi,
    valid,
    0.0,
    ppgSearchWindowSeconds + eps,
  );
  // Zeitrauschen wie in `analyzeChannel`, nur über die Schläge im Fenster.
  var noise = double.nan;
  if (hasBeats) {
    var sq = 0.0;
    var n = 0;
    for (var k = k0 + 1; k <= k1; k++) {
      if (c.beatOk[k] && c.beatOk[k - 1]) {
        final d = c.beatOffsetsMs[k] - c.beatOffsetsMs[k - 1];
        sq += d * d;
        n++;
      }
    }
    if (n >= 5) noise = math.sqrt(sq / n / 2);
  }
  // Q: Signalanteil am Puls im Signalstück des Fensters (100 Hz ab `filteredStartSeconds`).
  final x0 = base + c.filteredStartSeconds;
  final i0 = math.max(0, ((s - x0) * ppgGridRate - eps).ceil());
  final i1 = math.min(
    c.filtered.length - 1,
    ((e - x0) * ppgGridRate + eps).floor(),
  );
  // Näherung für die Suche: Mittel je [_qDecimation] Werte (25 Hz statt 100 Hz), das spart drei
  // Viertel der Goertzel-Rechnung; die Einzelauswertung des gewählten Fensters rechnet voll.
  final n = (i1 - i0 + 1) ~/ _qDecimation;
  final quality = n > 2
      ? dominantFrequency([
          for (var j = 0; j < n; j++)
            _mean(c.filtered, i0 + j * _qDecimation, _qDecimation),
        ], ppgGridRate / _qDecimation).quality
      : 0.0;
  return PpgChannelResult(
    channel: c.channel,
    methods: [
      PpgMethodResult(
        name: m.name,
        times: times,
        ibiEnd: ends,
        ibiMs: [for (final v in ibi) v * 1000],
        valid: valid,
        total: total,
        first: total,
        second: total,
      ),
    ],
    artifacts: const [],
    spectralBpm: c.spectralBpm,
    quality: quality,
    meanFps: c.meanFps,
    frameJitterMs: c.frameJitterMs,
    timingNoiseMs: noise,
  );
}

/// Längstes Stück zwischen zwei Schlägen in s, in dem mindestens [ppgLimitedValidFraction] der
/// Intervalle gültig sind (die Grenze für „gut“), höchstens ein Fenster; je Quelle, die beste zählt.
double _goodStretch(PpgAnalysisSet set) {
  var best = 0.0;
  for (final c in set.all) {
    final m = c.main;
    final n = m.valid.length;
    final prefix = List<int>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + (m.valid[i] ? 1 : 0);
    }
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b <= n; b++) {
        final len = m.times[b] - m.times[a];
        if (len > ppgSearchWindowSeconds) break;
        if (len > best &&
            prefix[b] - prefix[a] >= ppgLimitedValidFraction * (b - a)) {
          best = len;
        }
      }
    }
  }
  return best;
}

/// Einzelauswertung der Kandidaten in Rangfolge (höchstens drei): Sie hält an, sobald die Stufe
/// des Fensters nicht schlechter ist als die der Näherung; sonst gilt die beste Einzelauswertung.
({_Candidate candidate, PpgMeasurement measurement})? _verify(
  List<PpgFrame> frames,
  List<_Candidate> ranked, {
  required bool goodOnly,
}) {
  ({_Candidate candidate, PpgMeasurement measurement})? best;
  var tries = 0;
  for (final c in ranked) {
    if (goodOnly && c.measurement.quality != PpgQuality.good) break;
    if (tries++ == 3) break;
    final m = evaluatePpg(frames, window: _windowAt(c.start));
    final cand = _Candidate(c.start, m);
    if (best == null ||
        _compare(cand, _Candidate(best.candidate.start, best.measurement)) <
            0) {
      best = (candidate: c, measurement: m);
    }
    if (_rank(m.quality) <= _rank(c.measurement.quality)) break;
  }
  return best;
}

/// Beste Auswertung einer Aufnahme von bis zu [ppgSearchMaxRecordSeconds]: das Fenster von
/// [ppgSearchWindowSeconds] (Beginn ab `ppgStandardWindow.start`, Schritt [ppgSearchStepSeconds])
/// mit der höchsten Stufe, dann dem höchsten Anteil gültiger Intervalle, dann dem frühesten
/// Beginn. Das Zeitrauschen ist kein Kriterium (R010 offen). Bewertet wird das Fenster nach
/// `ratePpg`; die Aufnahme muss mindestens bis zum Fensterende reichen, sonst „unzureichende Daten“.
PpgWindowedMeasurement evaluatePpgBestWindow(List<PpgFrame> frames) {
  final scan = _scan(frames, live: false);
  if (scan.failure != null) {
    return PpgWindowedMeasurement(measurement: _unusable(scan.failure!));
  }
  final v = _verify(frames, scan.candidates, goodOnly: false)!;
  return PpgWindowedMeasurement(
    measurement: v.measurement,
    windowStartSeconds: v.candidate.start,
    windowEndSeconds: v.candidate.start + ppgSearchWindowSeconds,
    goodStretchSeconds: scan.goodStretch,
  );
}

/// Prüfung einer laufenden Aufnahme: Ist ein Fenster der Stufe „gut“ erreicht (dann darf sie
/// enden, frühestens bei Fensterende plus Filterrand, also 66,5 s) und wie lang ist das längste
/// gute Stück? Rechnet die ganze bisherige Aufnahme neu; nicht öfter als nötig aufrufen.
PpgRecordingCheck checkPpgRecording(List<PpgFrame> frames) {
  final scan = _scan(frames, live: true);
  if (scan.failure != null) {
    return const PpgRecordingCheck(
      goodWindowReached: false,
      goodStretchSeconds: 0.0,
    );
  }
  final v = _verify(frames, scan.candidates, goodOnly: true);
  return PpgRecordingCheck(
    goodWindowReached: v != null && v.measurement.quality == PpgQuality.good,
    goodStretchSeconds: scan.goodStretch,
  );
}
