import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'ppg_synth.dart';

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

/// Hauptkanal mit festen Kennzahlen, um die Bewertung an den Grenzen zu prüfen.
PpgChannelResult channel({
  String name = 'Rot',
  double quality = 0.8,
  int valid = 70,
  int total = 70,
  double noise = 10,
  double bpm = 60,
  double rmssd = 40,
}) {
  HrvStats stats() => HrvStats(
    beats: total + 1,
    ibis: total,
    validIbis: valid,
    bpm: bpm,
    meanIbiMs: 1000,
    sdnnMs: 50,
    rmssdMs: rmssd,
    pnn50: 10,
    minBpm: 50,
    maxBpm: 70,
  );
  final m = PpgMethodResult(
    name: 'Vorl.Anstieg',
    times: const [],
    ibiEnd: const [],
    ibiMs: const [],
    valid: const [],
    total: stats(),
    first: stats(),
    second: stats(),
  );
  return PpgChannelResult(
    channel: name,
    methods: [m],
    artifacts: const [],
    spectralBpm: bpm,
    quality: quality,
    meanFps: 30,
    frameJitterMs: 1,
    timingNoiseMs: noise,
  );
}

void main() {
  group('evaluatePpg', () {
    test('gutes Signal: Puls, RMSSD, Methode und Version', () {
      final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, 1);
      final m = evaluatePpg(frames(s));
      final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
      expect(m.quality, PpgQuality.good);
      expect(m.reasons, isEmpty);
      expect(m.bpm, closeTo(t.bpm, 0.5));
      expect(m.rmssdMs, closeTo(t.rmssd, 5.0));
      expect(m.hasResult, isTrue);
      expect(m.channel, 'Rot');
      expect(m.method, 'camera-ppg');
      expect(m.methodVersion, 1);
      expect(m.category, AlgorithmCategory.heuristic);
    });

    test('verrauschtes Signal ist eingeschränkt, mit Puls und Grund', () {
      final m = evaluatePpg(frames(synth(0.85, 0.05, 0.03, 4.0, 30.0, 1)));
      expect(m.quality, PpgQuality.limited);
      expect(m.reasons, contains(PpgQualityReason.someDisturbances));
      expect(m.bpm, isNotNull);
    });

    test('kein Ergebnis bei schlechtem Signal (kein Puls, kein RMSSD)', () {
      final m = evaluatePpg(frames(synth(0.85, 0.05, 0.03, 30.0, 30.0, 1)));
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, contains(PpgQualityReason.weakSignal));
      expect(m.bpm, isNull);
      expect(m.rmssdMs, isNull);
      expect(m.hasResult, isFalse);
    });

    test('viele Bewegungsstörungen: unbrauchbar wegen Störungen', () {
      final s = synth(
        0.85,
        0.05,
        0.03,
        0.3,
        30.0,
        4,
        artifacts: [for (var e = 10.0; e <= 64; e += 2) e],
      );
      final m = evaluatePpg(frames(s));
      expect(m.disturbances, greaterThan(10));
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.tooManyDisturbances]);
      expect(m.bpm, isNull);
    });

    test('wenige Störungen werden ausgeschlossen, das Ergebnis bleibt gut', () {
      final s = synth(
        0.85,
        0.05,
        0.03,
        0.3,
        30.0,
        21,
        artifacts: [15.3, 28.7, 48.1],
      );
      final m = evaluatePpg(frames(s));
      final t = truth([for (final b in s.beats) b + 0.12], 5.0, 65.0);
      expect(m.disturbances, greaterThanOrEqualTo(3));
      expect(m.quality, PpgQuality.good);
      expect(m.bpm, closeTo(t.bpm, 1.0));
    });

    test('zu wenige Bilder oder Messfenster nicht abgedeckt', () {
      final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
      final few = evaluatePpg(
        all.sublist(0, 120).where((f) => f.t >= 3).take(40).toList(),
      );
      expect(few.quality, PpgQuality.unusable);
      expect(few.reasons, [PpgQualityReason.insufficientData]);
      final early = evaluatePpg([...all.where((f) => f.t < 4.5)]);
      expect(early.reasons, [PpgQualityReason.insufficientData]);
      expect(early.bpm, isNull);
      expect(evaluatePpg(const []).reasons, [
        PpgQualityReason.insufficientData,
      ]);
    });

    test(
      'ungültige Eingabe: nicht endliche Werte, falsche Teilbereichszahl',
      () {
        final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
        final bad = [...all];
        bad[100] = PpgFrame(
          t: all[100].t,
          r: double.nan,
          g: 40,
          r16: all[100].r16,
          g16: all[100].g16,
        );
        expect(evaluatePpg(bad).reasons, [PpgQualityReason.invalidInput]);
        final short = [...all];
        short[5] = PpgFrame(
          t: all[5].t,
          r: 1,
          g: 1,
          r16: const [1],
          g16: all[5].g16,
        );
        expect(evaluatePpg(short).reasons, [PpgQualityReason.invalidInput]);
      },
    );

    test(
      'Aufnahme bricht früh ab: unbrauchbar, nicht „gut“ aus Teilmessung',
      () {
        final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
        final cut = evaluatePpg([...all.where((f) => f.t <= 12)]);
        expect(cut.quality, PpgQuality.unusable);
        expect(cut.reasons, [PpgQualityReason.insufficientData]);
        expect(cut.bpm, isNull);
        // Ende knapp vor 65 s, Anfang knapp nach 5 s
        expect(evaluatePpg([...all.where((f) => f.t <= 64.9)]).reasons, [
          PpgQualityReason.insufficientData,
        ]);
        expect(evaluatePpg([...all.where((f) => f.t >= 5.1)]).reasons, [
          PpgQualityReason.insufficientData,
        ]);
        expect(evaluatePpg(all).quality, PpgQuality.good);
      },
    );

    test('Bilder im Messfenster: gebündelt ohne Ausnahme, Mindestzahl 51', () {
      final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
      PpgFrame at(double t) => PpgFrame(
        t: t,
        r: 100 + (t * 1000).round() % 7,
        g: 50,
        r16: all[0].r16,
        g16: all[0].g16,
      );
      // 60 Bilder innerhalb von 1 ms um 5 s, dazu je ein Bild an den Rändern des Fensters
      final few = [
        at(4.0),
        for (var i = 0; i < 60; i++) at(5.0 + i * 1e-5),
        at(65.5),
      ];
      // Messfenster formal abgedeckt, aber kein verwertbares Signal: keine Ausnahme, kein Zahl
      final m = evaluatePpg(few);
      expect(m.quality, PpgQuality.unusable);
      expect(m.bpm, isNull);
      // Grenze: genau 50 Bilder im Fenster reichen nicht, 51 schon (Kotlin: > 50)
      List<PpgFrame> grid(int n) => [
        at(4.0),
        for (var i = 0; i < n; i++) at(5.0 + 60.0 * i / (n - 1)),
        at(65.5),
      ];
      expect(evaluatePpg(grid(50)).reasons, [
        PpgQualityReason.insufficientData,
      ]);
      expect(
        evaluatePpg(grid(51)).reasons,
        isNot(contains(PpgQualityReason.insufficientData)),
      );
    });

    test('extreme Werte: keine Ausnahme, unbrauchbar ohne Zahlen', () {
      final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
      final big = [
        for (var i = 0; i < all.length; i++)
          PpgFrame(
            t: all[i].t,
            r: i.isEven ? 1e300 : -1e300,
            g: i.isEven ? 1e300 : -1e300,
            r16: List.filled(16, i.isEven ? 1e300 : -1e300),
            g16: List.filled(16, i.isEven ? 1e300 : -1e300),
          ),
      ];
      final m = evaluatePpg(big);
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.analysisFailed]);
      expect((m.bpm, m.rmssdMs), (null, null));
    });

    test(
      'konstanter Kanal (z. B. übersteuert) ist unbrauchbar, nicht „gut“',
      () {
        PpgFrame flat(double t, double v) => PpgFrame(
          t: t,
          r: v,
          g: v,
          r16: List.filled(16, v),
          g16: List.filled(16, v),
        );
        for (final v in [255.0, 128.3, 0.0]) {
          final m = evaluatePpg([
            for (var i = 0; i < 2100; i++) flat(i / 30, v),
          ]);
          expect(m.quality, PpgQuality.unusable, reason: '$v');
          expect(m.reasons, [PpgQualityReason.flatSignal]);
          expect((m.bpm, m.rmssdMs), (null, null));
        }
      },
    );

    test('konstanter Kanal gewinnt nicht gegen einen echten (Quellenwahl)', () {
      final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, 1);
      final base = frames(s);
      // Rot gesättigt (konstant), Grün trägt den Puls; Teilbereiche folgen Grün
      final fr = [
        for (final f in base)
          PpgFrame(
            t: f.t,
            r: 255,
            g: f.r,
            r16: List.filled(16, 255.0),
            g16: f.r16,
          ),
      ];
      final m = evaluatePpg(fr);
      expect(m.channel, isNot('Rot'));
      expect(m.quality, PpgQuality.good);
      expect(
        m.bpm,
        closeTo(truth([for (final b in s.beats) b + 0.12], 5.0, 65.0).bpm, 0.5),
      );
      // numerisch flach (Rundungsrauschen 1e-14 relativ) zählt ebenfalls als konstant
      final noisy = [
        for (var i = 0; i < 2100; i++)
          PpgFrame(
            t: i / 30,
            r: 200 + (i.isEven ? 0 : 3e-14),
            g: 200,
            r16: List.filled(16, 200.0),
            g16: List.filled(16, 200.0),
          ),
      ];
      expect(evaluatePpg(noisy).reasons, [PpgQualityReason.flatSignal]);
    });

    test('nicht endliche Zeit ist ungültige Eingabe', () {
      final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
      for (final bad in [double.nan, double.infinity]) {
        final x = [...all];
        x[100] = PpgFrame(
          t: bad,
          r: 1,
          g: 1,
          r16: all[100].r16,
          g16: all[100].g16,
        );
        expect(evaluatePpg(x).reasons, [PpgQualityReason.invalidInput]);
      }
    });

    test('Rauschen ohne Puls ergibt kein Ergebnis', () {
      final rnd = KotlinRandom(77);
      final fr = [
        for (var i = 0; i < 2100; i++)
          PpgFrame(
            t: i / 30,
            r: 200 + rnd.nextDouble(-1.0, 1.0),
            g: 40 + rnd.nextDouble(-1.0, 1.0),
            r16: List.filled(16, 100.0 + rnd.nextDouble(-1.0, 1.0)),
            g16: List.filled(16, 20.0 + rnd.nextDouble(-1.0, 1.0)),
          ),
      ];
      final m = evaluatePpg(fr);
      expect(m.quality, PpgQuality.unusable);
      expect(m.bpm, isNull);
    });
  });

  group('ratePpg: Qualitätsschwellen (ALGORITHMUS.md Abschn. 10)', () {
    PpgMeasurement rate(PpgChannelResult c) => ratePpg(c);

    test('Signalqualität Q: 0,25 und 0,3 sind die Grenzen', () {
      expect(rate(channel(quality: 0.2499)).quality, PpgQuality.unusable);
      expect(rate(channel(quality: 0.2499)).reasons, [
        PpgQualityReason.weakSignal,
      ]);
      expect(rate(channel(quality: 0.25)).quality, PpgQuality.limited);
      expect(rate(channel(quality: 0.25)).reasons, [
        PpgQualityReason.lowSignalQuality,
      ]);
      expect(rate(channel(quality: 0.2999)).quality, PpgQuality.limited);
      expect(rate(channel(quality: 0.3)).quality, PpgQuality.good);
    });

    test('Anteil gültiger Intervalle: 50 % und 70 % sind die Grenzen', () {
      expect(rate(channel(valid: 34)).quality, PpgQuality.unusable);
      expect(rate(channel(valid: 34)).reasons, [
        PpgQualityReason.tooManyDisturbances,
      ]);
      expect(rate(channel(valid: 35)).quality, PpgQuality.limited);
      expect(rate(channel(valid: 35)).reasons, [
        PpgQualityReason.someDisturbances,
      ]);
      expect(rate(channel(valid: 48)).quality, PpgQuality.limited);
      expect(rate(channel(valid: 49)).quality, PpgQuality.good);
      expect(rate(channel(valid: 0, total: 0)).quality, PpgQuality.unusable);
    });

    test(
      'Zeitrauschen: bis 25 ms gut, darüber oder nicht schätzbar eingeschränkt',
      () {
        expect(rate(channel(noise: 25)).quality, PpgQuality.good);
        expect(rate(channel(noise: 25.01)).quality, PpgQuality.limited);
        expect(rate(channel(noise: 25.01)).reasons, [
          PpgQualityReason.timingNoise,
        ]);
        expect(rate(channel(noise: double.nan)).quality, PpgQuality.limited);
        expect(rate(channel(noise: double.nan)).timingNoiseMs, isNull);
      },
    );

    test('unbrauchbar liefert keine Zahlen, sonst Puls und RMSSD', () {
      final bad = rate(channel(quality: 0.1));
      expect((bad.bpm, bad.rmssdMs), (null, null));
      final ok = rate(channel(bpm: 61.5, rmssd: 33));
      expect((ok.bpm, ok.rmssdMs), (61.5, 33));
      expect(rate(channel(bpm: double.nan)).bpm, isNull);
    });

    test('RMSSD nur bei „gut“ (PAR-160K), Puls auch bei „eingeschränkt“', () {
      final lim = rate(channel(quality: 0.28, bpm: 62, rmssd: 33));
      expect(lim.quality, PpgQuality.limited);
      expect((lim.bpm, lim.rmssdMs), (62, null));
      final noisy = rate(channel(noise: 30, bpm: 62, rmssd: 33));
      expect(
        (noisy.quality, noisy.bpm, noisy.rmssdMs),
        (PpgQuality.limited, 62, null),
      );
      expect(rate(channel(bpm: 62, rmssd: 33)).rmssdMs, 33);
    });

    test('Quellenwahl: nicht schätzbares Zeitrauschen verliert immer', () {
      final nan = channel(name: 'A', noise: double.nan);
      final ok = channel(name: 'B', noise: 20);
      expect(PpgAnalyzer.chooseBest([nan, ok]).channel, 'B');
      expect(PpgAnalyzer.chooseBest([ok, nan]).channel, 'B');
    });

    test('mehrere Gründe werden alle genannt', () {
      final r = rate(channel(quality: 0.28, valid: 45, noise: 30));
      expect(r.quality, PpgQuality.limited);
      expect(r.reasons, [
        PpgQualityReason.lowSignalQuality,
        PpgQualityReason.someDisturbances,
        PpgQualityReason.timingNoise,
      ]);
    });
  });

  group('intervals: Ausreißerprüfung und Störabschnitte (Abschn. 6 und 7)', () {
    List<double> regular({int skip = -1}) => [
      for (var k = 0; k < 60; k++)
        if (k != skip) 5 + 0.85 * k,
    ];

    test('regelmäßige Schläge sind alle gültig', () {
      final iv = PpgAnalyzer.intervals(regular(), null, const []);
      expect(iv.valid.every((v) => v), isTrue);
      expect(iv.valid.length, 59);
    });

    test('verpasster Schlag (doppelt langes Intervall) wird als Ausreißer verworfen', () {
      final iv = PpgAnalyzer.intervals(regular(skip: 20), null, const []);
      expect(iv.ibi[19], closeTo(1.7, 1e-9));
      expect(iv.valid[19], isFalse);
      expect(iv.valid.where((v) => !v).length, 1);
    });

    test('Intervalle außerhalb 0,27 bis 2,0 s sind ungültig', () {
      final b = [for (var k = 0; k < 30; k++) 0.85 * k];
      final shifted = [
        ...b.sublist(0, 15),
        for (final x in b.sublist(15)) x + 1.5,
      ];
      final iv = PpgAnalyzer.intervals(shifted, null, const []);
      expect(iv.ibi[14], closeTo(2.35, 1e-9));
      expect(iv.valid[14], isFalse);
    });

    test(
      'Schläge ohne ausreichende Korrelation machen ihre Intervalle ungültig',
      () {
        final ok = List<bool>.filled(60, true);
        ok[10] = false;
        final iv = PpgAnalyzer.intervals(regular(), ok, const []);
        expect(
          [
            for (var i = 0; i < 59; i++)
              if (!iv.valid[i]) i,
          ],
          [9, 10],
        );
      },
    );

    test('Intervalle, die einen Störabschnitt berühren, sind ungültig', () {
      final iv = PpgAnalyzer.intervals(regular(), null, [
        [5 + 0.85 * 30 + 0.2, 5 + 0.85 * 30 + 0.4],
      ]);
      expect(
        [
          for (var i = 0; i < 59; i++)
            if (!iv.valid[i]) i,
        ],
        [30],
      );
    });
  });

  group('Mindestzahl Bilder (Abschn. 2)', () {
    // 30 Hz, Fenster 0 bis 1,7 s: n Bilder im Auswertebereich
    const w = PpgWindow(filterStart: 0, start: 0, end: 1.7, dataEnd: 1.7);
    List<double> tt(int n) => [for (var i = 0; i < n; i++) i * 1.7 / (n - 1)];
    List<double> vv(int n) => [
      for (final t in tt(n)) math.sin(2 * math.pi * 1.2 * t),
    ];

    test('50 Bilder sind zu wenig, 51 genügen', () {
      expect(
        () => PpgAnalyzer.analyzeChannel('x', tt(50), vv(50), w),
        throwsA(isA<PpgInsufficientDataException>()),
      );
      expect(
        () => PpgAnalyzer.analyzeChannel('x', tt(51), vv(51), w),
        isNot(throwsA(isA<PpgInsufficientDataException>())),
      );
    });
  });

  group('Störabschnitte', () {
    test('Sprung im Signal wird erkannt und um 0,3 s erweitert', () {
      final x = List<double>.generate(
        3000,
        (i) => math.sin(2 * math.pi * 1.2 * i / 100),
      );
      x[1500] = 40; // Ausreißer weit über 2 × typische Gipfelhöhe
      final peaks = PpgAnalyzer.detectPeaks(x, 100, 1.2);
      final art = PpgAnalyzer.detectArtifacts(x, 100, peaks, 1.2);
      expect(art, hasLength(1));
      expect(art[0][0], closeTo(15 - 0.3 - 0.01, 0.05));
      expect(art[0][1], closeTo(15 + 0.3 + 0.01, 0.05));
    });

    test('sauberes Signal hat keine Störabschnitte', () {
      final x = List<double>.generate(
        3000,
        (i) => math.sin(2 * math.pi * 1.2 * i / 100),
      );
      final peaks = PpgAnalyzer.detectPeaks(x, 100, 1.2);
      expect(PpgAnalyzer.detectArtifacts(x, 100, peaks, 1.2), isEmpty);
    });
  });
}
