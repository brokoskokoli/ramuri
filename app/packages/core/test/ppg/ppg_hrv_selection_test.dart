import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'ppg_synth.dart';

/// Synthetische Schlagfolge (Hauptverfahren) mit Abstand Vorlage−Anstieg je Schlag: [n] Schläge
/// um 1 s mit kleiner, fester Schwankung; Schlag [jump] liegt um [jumpMs] zu spät (Zeitfehler der
/// Vorlage), sein Abstand Vorlage−Anstieg springt um denselben Betrag.
({List<double> times, List<double> offsets}) beats({
  int n = 71,
  int? jump,
  double jumpMs = 30,
  double offsetMs = 40,
}) {
  final times = <double>[];
  final offsets = <double>[];
  var t = 0.0;
  for (var k = 0; k < n; k++) {
    final e = k == jump ? jumpMs / 1000 : 0.0;
    times.add(t + e);
    offsets.add(offsetMs + (k == jump ? jumpMs : 0.0));
    t += 1.0 + 0.012 * math.sin(k * 0.9); // RMSSD um 7 ms
  }
  return (times: times, offsets: offsets);
}

/// Kanal wie `PpgAnalyzer.analyzeChannel`, aus Schlagzeiten und Abständen gebaut (ohne Signal).
PpgChannelResult channelOf(
  List<double> times,
  List<double> offsets, {
  bool filter = true,
}) {
  final iv = PpgAnalyzer.intervals(times, null, const []);
  final dur = times.last + 1;
  final total = PpgAnalyzer.stats(
    times,
    iv.end,
    iv.ibi,
    iv.valid,
    0.0,
    dur + 1e-9,
  );
  // Ohne Filter: HRV-Auswahl = gültige Intervalle (Stand Version 2).
  final hrvValid = filter
      ? PpgAnalyzer.hrvSelection(
          iv.valid,
          PpgAnalyzer.inconsistentBeats(offsets),
        )
      : iv.valid;
  final hrv = PpgAnalyzer.stats(
    times,
    iv.end,
    iv.ibi,
    iv.valid,
    0.0,
    dur + 1e-9,
    hrvValid: hrvValid,
  );
  return PpgChannelResult(
    channel: 'Rot',
    methods: [
      PpgMethodResult(
        name: 'Vorl.Anstieg',
        times: times,
        ibiEnd: iv.end,
        ibiMs: [for (final v in iv.ibi) v * 1000],
        valid: iv.valid,
        total: total,
        first: total,
        second: total,
      ),
    ],
    artifacts: const [],
    spectralBpm: 60,
    quality: 0.8,
    meanFps: 30,
    frameJitterMs: 1,
    timingNoiseMs: 5,
    hrv: hrv,
    hrvValid: hrvValid,
    beatOffsetsMs: offsets,
  );
}

double rmssdOf(List<double> seq) {
  var sum = 0.0;
  var n = 0;
  for (var i = 0; i + 1 < seq.length; i++) {
    if (seq[i].isNaN || seq[i + 1].isNaN) continue;
    final d = seq[i + 1] - seq[i];
    sum += d * d;
    n++;
  }
  return math.sqrt(sum / n);
}

void main() {
  group('Uneinige Schläge (PAR-230)', () {
    test('Grenze: genau 15 ms bleibt, 15,1 ms wird verworfen', () {
      final base = List<double>.filled(21, 40.0);
      expect(
        PpgAnalyzer.inconsistentBeats([...base]..[10] = 55.0)[10],
        isFalse,
      );
      expect(
        PpgAnalyzer.inconsistentBeats([...base]..[10] = 25.0)[10],
        isFalse,
      );
      final over = PpgAnalyzer.inconsistentBeats([...base]..[10] = 55.1);
      expect(over[10], isTrue);
      expect(over.where((b) => b).length, 1, reason: 'nur dieser Schlag');
      expect(PpgAnalyzer.inconsistentBeats([...base]..[10] = 24.9)[10], isTrue);
    });

    test('Median am Rand mit gekürztem Fenster (k−5 bis k+5)', () {
      // Schlag 0: Fenster 0..5 (sechs Werte), Median = Mittel der beiden mittleren.
      // Werte 0, 0, 0, 30, 30, 30 → Median 15: Schlag 0 (Abstand 0) weicht genau 15 ms ab.
      final d = [0.0, 0.0, 0.0, 30.0, 30.0, 30.0, 30.0, 30.0, 30.0, 30.0];
      final r = PpgAnalyzer.inconsistentBeats(d);
      expect(r[0], isFalse, reason: 'Fenster 0..5, Median 15, |0 − 15| = 15');
      // Mit dem ungekürzten Fenster wäre der Median 30 und Schlag 0 uneinig; mit dem oberen
      // Median (Index n ~/ 2) ebenfalls.
      final d2 = [...d]..[0] = -0.1;
      expect(PpgAnalyzer.inconsistentBeats(d2)[0], isTrue);
      // Letzter Schlag: Fenster 4..9 (sechs Werte, alle 30).
      expect(r[9], isFalse);
      // Schlag 1: Fenster 0..6 (sieben Werte), Median 30 → |0 − 30| > 15.
      expect(r[1], isTrue);
    });

    test(
      'alle Schläge zählen für den Median, auch an ungültigen Intervallen',
      () {
        // Der Median hängt nur an den Abständen; die Gültigkeit geht erst in die Auswahl ein.
        final d = List<double>.filled(11, 40.0)..[5] = 80.0;
        final inc = PpgAnalyzer.inconsistentBeats(d);
        final valid = List<bool>.filled(10, true)..[0] = false;
        final sel = PpgAnalyzer.hrvSelection(valid, inc);
        expect(sel, [
          false,
          true,
          true,
          true,
          false,
          false,
          true,
          true,
          true,
          true,
        ]);
      },
    );

    test('nicht endlicher Abstand ist uneinig und stört den Median nicht', () {
      final d = List<double>.filled(11, 40.0)..[3] = double.nan;
      final inc = PpgAnalyzer.inconsistentBeats(d);
      expect(inc[3], isTrue);
      expect(inc.where((b) => b).length, 1);
    });
  });

  group('HRV-Auswahl in der Bewertung (PAR-230)', () {
    test('ein Schlag mit 30 ms Sprung: er und seine beiden Intervalle fehlen, RMSSD sinkt; '
        'Puls, Anteil gültig und Stufe wie Version 2', () {
      final b = beats(jump: 35);
      final v3ch = channelOf(b.times, b.offsets);
      final v2ch = channelOf(b.times, b.offsets, filter: false);
      expect(
        PpgAnalyzer.inconsistentBeats(b.offsets).indexed
            .where((e) => e.$2)
            .map((e) => e.$1),
        [35],
      );
      expect(
        [
          for (var i = 0; i < v3ch.hrvValid.length; i++)
            if (!v3ch.hrvValid[i]) i,
        ],
        [34, 35],
      );
      final v3 = ratePpg(v3ch);
      final v2 = ratePpg(v2ch);
      expect(v2.quality, PpgQuality.good);
      expect(v3.quality, v2.quality);
      expect(v3.reasons, v2.reasons);
      expect(v3.bpm, v2.bpm);
      expect(v3.validIntervals, v2.validIntervals);
      expect(v3.intervals, v2.intervals);
      expect(v3.rmssdMs, lessThan(v2.rmssdMs!));
      final clean = beats();
      final cleanRmssd = ratePpg(channelOf(clean.times, clean.offsets))
          .rmssdMs!;
      expect(v3.rmssdMs, closeTo(cleanRmssd, 1.0));
      expect(v2.rmssdMs, greaterThan(v3.rmssdMs! + 3));
      // Ausgabe: Länge wie bisher, die beiden Intervalle als NaN, RMSSD daraus nachrechenbar.
      expect(v3.intervalsMs.length, v2.intervalsMs.length);
      expect(
        [
          for (var i = 0; i < v3.intervalsMs.length; i++)
            if (v3.intervalsMs[i].isNaN) i,
        ],
        [34, 35],
      );
      expect(rmssdOf(v3.intervalsMs), closeTo(v3.rmssdMs!, 1e-9));
    });

    test(
      'ohne Sprung: Auswahl = gültige Intervalle, Ergebnis wie Version 2',
      () {
        final b = beats();
        final v3 = ratePpg(channelOf(b.times, b.offsets));
        final v2 = ratePpg(channelOf(b.times, b.offsets, filter: false));
        expect(v3.rmssdMs, v2.rmssdMs);
        expect(v3.quality, PpgQuality.good);
        expect(v3.intervalsMs, v2.intervalsMs);
      },
    );

    test('weniger als 20 Differenzen bei sonst „gut“: eingeschränkt, fewConsistentBeats, '
        'Puls, kein RMSSD', () {
      // Jeder dritte Schlag springt: Zwischen zwei uneinigen Schlägen bleibt höchstens ein
      // Intervall, es gibt keine benachbarten Paare mehr.
      final b = beats();
      final off = [
        for (var k = 0; k < b.offsets.length; k++)
          b.offsets[k] + (k % 3 == 2 ? 30.0 : 0.0),
      ];
      final ch = channelOf(b.times, off);
      expect(ch.hrv.diffs, lessThan(ppgMinHrvDiffs));
      expect(ch.hrv.rmssdMs.isNaN, isTrue);
      expect(ch.hrv.sdnnMs.isNaN, isTrue);
      expect(ch.hrv.pnn50.isNaN, isTrue);
      final m = ratePpg(ch);
      expect(m.quality, PpgQuality.limited);
      expect(m.reasons, [PpgQualityReason.fewConsistentBeats]);
      expect(m.bpm, ratePpg(channelOf(b.times, b.offsets)).bpm);
      expect(m.rmssdMs, isNull);
      expect(
        m.validIntervals,
        m.intervals,
        reason: 'Anteil gültig unverändert',
      );
    });

    test('Mindestzahl: 20 Differenzen genügen, 19 nicht', () {
      final b = beats();
      final iv = PpgAnalyzer.intervals(b.times, null, const []);
      HrvStats hrvWith(int kept) => PpgAnalyzer.stats(
        b.times,
        iv.end,
        iv.ibi,
        iv.valid,
        0.0,
        1e9,
        hrvValid: [for (var i = 0; i < iv.valid.length; i++) i < kept],
      );
      expect(hrvWith(21).diffs, 20);
      expect(hrvWith(21).rmssdMs.isFinite, isTrue);
      expect(hrvWith(20).diffs, 19);
      expect(hrvWith(20).rmssdMs.isNaN, isTrue);
    });

    test('unbrauchbar bleibt unbrauchbar, ohne den neuen Grund', () {
      final b = beats();
      final off = [
        for (var k = 0; k < b.offsets.length; k++)
          b.offsets[k] + (k % 3 == 2 ? 30.0 : 0.0),
      ];
      final ch = channelOf(b.times, off);
      final weak = PpgChannelResult(
        channel: ch.channel,
        methods: ch.methods,
        artifacts: ch.artifacts,
        spectralBpm: ch.spectralBpm,
        quality: 0.1,
        meanFps: ch.meanFps,
        frameJitterMs: ch.frameJitterMs,
        timingNoiseMs: ch.timingNoiseMs,
        hrv: ch.hrv,
        hrvValid: ch.hrvValid,
      );
      final m = ratePpg(weak);
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.weakSignal]);
    });
  });

  group('evaluatePpg mit HRV-Auswahl (PAR-230)', () {
    List<PpgFrame> frames(Synth s) => [
      for (var i = 0; i < s.t.length; i++)
        PpgFrame(
          t: s.t[i],
          r: s.red[i],
          g: s.green[i],
          r16: List.filled(16, s.red[i]),
          g16: List.filled(16, s.green[i]),
        ),
    ];

    test('RMSSD aus intervalsMs nachgerechnet = rmssdMs, Version 3', () {
      for (final seed in [1, 2, 3, 21, 22]) {
        final m = evaluatePpg(frames(synth(0.85, 0.05, 0.03, 1.0, 30.0, seed)));
        if (m.rmssdMs == null) continue;
        expect(m.intervalsMs.length, m.intervals);
        expect(rmssdOf(m.intervalsMs), closeTo(m.rmssdMs!, 1e-9));
        expect(m.methodVersion, 3);
      }
    });

    test('alle Quellen tragen eine HRV-Auswahl je Intervall', () {
      final s = synth(0.85, 0.05, 0.03, 1.0, 30.0, 2);
      final t = s.t;
      final set = PpgAnalyzer.analyze(
        t,
        [PpgSeries('Rot', s.red), PpgSeries('Grün', s.green)],
        [PpgSeries('r0', s.red), PpgSeries('r1', s.red)],
        ppgStandardWindow,
      );
      expect(
        set.all.map((c) => c.channel),
        containsAll(['Rot', 'Grün', 'Kombi']),
      );
      for (final c in set.all) {
        expect(c.hrvValid.length, c.main.valid.length);
        final inc = PpgAnalyzer.inconsistentBeats(c.beatOffsetsMs);
        expect(c.hrvValid, PpgAnalyzer.hrvSelection(c.main.valid, inc));
        expect(c.hrv.validIbis, c.main.total.validIbis);
        expect(c.hrv.bpm, c.main.total.bpm);
      }
    });
  });
}
