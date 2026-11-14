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

    test(
      'gibt die gültigen Schlagabstände heraus (Anzahl, Reihenfolge, Mittel)',
      () {
        for (final seed in [1, 2, 3]) {
          final m = evaluatePpg(
            frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, seed)),
          );
          expect(m.intervalsMs, isNotEmpty);
          expect(m.intervalsMs.length, m.validIntervals);
          expect(m.intervalsMs.every((v) => v > 300 && v < 2000), isTrue);
          final mean =
              m.intervalsMs.reduce((a, b) => a + b) / m.intervalsMs.length;
          expect(60000 / mean, closeTo(m.bpm!, 1.0));
        }
      },
    );

    test('unbrauchbar: keine Schlagabstände', () {
      final m = evaluatePpg(frames(synth(0.85, 0.05, 0.03, 30.0, 30.0, 1)));
      expect(m.intervalsMs, isEmpty);
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
      // Messfenster formal abgedeckt, aber 60 s ohne Bild: keine Ausnahme, keine Zahlen
      final m = evaluatePpg(few);
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.frameGap]);
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
      // 51 Bilder reichen für die Mindestzahl; die Lücken von 1,2 s sind dann der Grund
      expect(evaluatePpg(grid(51)).reasons, [PpgQualityReason.frameGap]);
      // gebündelt, aber ohne Lücke (alle 0,5 s ein Bild): keine Ausnahme und kein Programmfehler
      // (das periodische Testsignal darf ein Ergebnis liefern, es geht nur um die Gründe)
      final bundled = [
        at(4.0),
        for (var i = 0; i < 60; i++) at(5.0 + i * 1e-5),
        for (var i = 1; i <= 120; i++) at(5.0 + i * 0.5),
        at(65.5),
      ];
      final b = evaluatePpg(bundled);
      expect(b.reasons, isNot(contains(PpgQualityReason.analysisFailed)));
      expect(b.reasons, isNot(contains(PpgQualityReason.frameGap)));
      expect(b.reasons, isNot(contains(PpgQualityReason.insufficientData)));
    });

    test('extreme Werte: keine Ausnahme, unbrauchbar ohne Zahlen', () {
      final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
      final big = [
        for (var i = 0; i < all.length; i++)
          PpgFrame(
            t: all[i].t,
            // Rot-Summe positiv (sonst käme die Fingerprüfung zuerst), Grün hebt sich auf
            r: i.isEven ? 3e300 : 1e300,
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
          g: v / 4, // mit Finger (R/G 4), sonst käme die Fingerprüfung zuerst
          r16: List.filled(16, v),
          g16: List.filled(16, v / 4),
        );
        for (final v in [255.0, 128.3, 1.0]) {
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
      // Rot konstant (400, damit die Fingerprüfung besteht), Grün trägt den Puls; Teilbereiche folgen Grün
      final fr = [
        for (final f in base)
          PpgFrame(
            t: f.t,
            r: 400,
            g: f.r,
            r16: List.filled(16, 400.0),
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
            g: 50,
            r16: List.filled(16, 200.0),
            g16: List.filled(16, 50.0),
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
      expect(m.reasons, [PpgQualityReason.tooManyDisturbances]);
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
        returnsNormally,
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

  group('Lücke zwischen Bildern im Messfenster (Abschn. 2, Maintainer 2026-11-11)', () {
    final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));

    /// Entfernt die Bilder in (from, to). Die Lücke ist dann der Abstand der Nachbarn.
    List<PpgFrame> hole(double from, double to) => [
      for (final f in all)
        if (f.t <= from || f.t >= to) f,
    ];

    test(
      'Ausgangslage ohne Lücke ist „gut“ (Kontrolle für die Tests unten)',
      () {
        expect(evaluatePpg(all).quality, PpgQuality.good);
      },
    );

    test('Lücke 20 bis 40 s und 10 bis 55 s: unbrauchbar, keine Zahlen', () {
      for (final (a, b) in [(20.0, 40.0), (10.0, 55.0), (15.0, 25.0)]) {
        final m = evaluatePpg(hole(a, b));
        expect(m.quality, PpgQuality.unusable, reason: '$a-$b');
        expect(m.reasons, [PpgQualityReason.frameGap]);
        expect((m.bpm, m.rmssdMs, m.signalQuality), (null, null, null));
      }
    });

    test(
      'Lücke im Filter-Vorlauf (3 bis 5 s) und am Ende (65 bis 66,5 s) zählt',
      () {
        // die Auswertung nutzt alle Bilder von 3 bis 66,5 s, also auch dort
        expect(evaluatePpg(hole(3.2, 4.6)).reasons, [
          PpgQualityReason.frameGap,
        ]);
        expect(evaluatePpg(hole(65.2, 66.4)).reasons, [
          PpgQualityReason.frameGap,
        ]);
      },
    );

    test('Lücke im Einschwingbereich (vor 3 s, nach 66,5 s) zählt nicht', () {
      final m = evaluatePpg([
        for (final f in all)
          if (f.t < 0.5 || f.t > 2.9) f,
      ]);
      expect(m.reasons, isNot(contains(PpgQualityReason.frameGap)));
      expect(m.quality, PpgQuality.good);
    });

    test('Grenze: genau 1,0 s ist erlaubt, darüber nicht (exakte Zeiten)', () {
      // alle 0,5 s ein Bild (exakt darstellbar), an einer Stelle fehlen Bilder
      List<PpgFrame> grid(Set<int> missing) => [
        for (var i = 6; i <= 133; i++)
          if (!missing.contains(i))
            PpgFrame(
              t: i * 0.5,
              r: 100 + (i * 37 % 11),
              g: 50 + (i * 17 % 7),
              r16: List.filled(16, 100 + (i * 37 % 11).toDouble()),
              g16: List.filled(16, 50 + (i * 17 % 7).toDouble()),
            ),
      ];
      // fehlt ein Bild: Abstand 1,0 s -> keine Lücke
      expect(
        evaluatePpg(grid({40})).reasons,
        isNot(contains(PpgQualityReason.frameGap)),
      );
      // fehlen zwei Bilder: Abstand 1,5 s -> Lücke
      expect(evaluatePpg(grid({40, 41})).reasons, [PpgQualityReason.frameGap]);
    });

    test('doppelte und rückläufige Zeitstempel erzeugen keine Lücke', () {
      // Wie die Auswertung zählt nur, was streng steigt: ein Bild bei 19,6 s nach 20,5 s darf den
      // Abstand zum nächsten Bild (21,0 s) nicht auf 1,4 s dehnen; ein doppeltes Bild bei 30 s ändert nichts.
      PpgFrame at(double t) => PpgFrame(
        t: t,
        r: 100,
        g: 50,
        r16: List.filled(16, 100.0),
        g16: List.filled(16, 50.0),
      );
      final frames = <PpgFrame>[
        for (var i = 6; i <= 133; i++) ...[
          at(i * 0.5),
          if (i == 41) at(19.6),
          if (i == 60) at(30.0),
        ],
      ];
      expect(
        evaluatePpg(frames).reasons,
        isNot(contains(PpgQualityReason.frameGap)),
      );
    });

    test('Grenze knapp unter und über 1 s (Zeiten verschoben)', () {
      // Bilder nach t=30 um so viel verschoben, dass der Abstand um 30 s herum g beträgt
      List<PpgFrame> withGap(double g) {
        final before = all.where((f) => f.t <= 30).toList();
        final after = all.where((f) => f.t > 30).toList();
        final shift = before.last.t + g - after.first.t;
        return [
          ...before,
          for (final f in after)
            PpgFrame(t: f.t + shift, r: f.r, g: f.g, r16: f.r16, g16: f.g16),
        ];
      }

      expect(
        evaluatePpg(withGap(0.99)).reasons,
        isNot(contains(PpgQualityReason.frameGap)),
      );
      expect(evaluatePpg(withGap(1.01)).reasons, [PpgQualityReason.frameGap]);
    });
  });

  group('konstante Quellen: Fenster und Blöcke (Abschn. 2)', () {
    const w = PpgWindow(filterStart: 3, start: 5, end: 65, dataEnd: 66.5);
    final tt = [for (var i = 0; i < 2000; i++) 3 + i / 30.0];

    test(
      'isFlat betrachtet nur das Messfenster, nicht Einschwingen und Ende',
      () {
        // konstant in [5, 65], aber andere Werte bei 4 s und 66 s
        final v = [for (final t in tt) (t < 5 || t > 65) ? 50.0 : 200.0];
        expect(PpgAnalyzer.isFlat(tt, v, w), isTrue);
        // verändert sich im Fenster: nicht flach
        final w2 = [for (final t in tt) (t > 30 && t < 31) ? 201.0 : 200.0];
        expect(PpgAnalyzer.isFlat(tt, w2, w), isFalse);
      },
    );

    test(
      'Rot/Grün nur im Messfenster flach: flatSignal trotz Ausschlag davor',
      () {
        final all = frames(synth(0.85, 0.05, 0.03, 0.3, 30.0, 1));
        final fr = [
          for (final f in all)
            PpgFrame(
              t: f.t,
              r: (f.t < 5 || f.t > 65) ? f.r : 120,
              g: (f.t < 5 || f.t > 65) ? f.g : 30,
              r16: List.filled(16, (f.t < 5 || f.t > 65) ? f.r : 120.0),
              g16: List.filled(16, (f.t < 5 || f.t > 65) ? f.g : 30.0),
            ),
        ];
        expect(evaluatePpg(fr).reasons, [PpgQualityReason.flatSignal]);
      },
    );

    test('flache Teilbereiche (Rundungsrauschen) gehen nicht in die Kombination ein', () {
      final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, 1);
      final t = s.t;
      final rnd = KotlinRandom(5);
      PpgSeries live(String n) => PpgSeries(n, s.red);
      // numerisch flach, aber mit Rundungsrauschen (relativ 1e-16): Streuung nach dem Filter > 0
      PpgSeries flat(String n) => PpgSeries(n, [
        for (var i = 0; i < t.length; i++)
          200 + (rnd.nextDouble(-1.0, 1.0) > 0 ? 3e-14 : 0.0),
      ]);
      final blocks = [
        for (var k = 0; k < 4; k++) live('r$k'),
        for (var k = 0; k < 12; k++) flat('x$k'),
      ];
      const w = PpgWindow(filterStart: 3, start: 5, end: 65, dataEnd: 66.5);
      final set = PpgAnalyzer.analyze(t, [PpgSeries('Rot', s.red)], blocks, w);
      // nur die 4 lebenden Teilbereiche werden bewertet
      expect(set.blocksScored, 4);
    });
  });

  group('Fingerprüfung (Rot/Grün im Messfenster)', () {
    /// Gutes Signal, Grün so skaliert, dass Mittel Rot / Mittel Grün im Messfenster [ratio] ist.
    List<PpgFrame> withRatio(double ratio) {
      final s = synth(0.85, 0.05, 0.03, 0.3, 30.0, 1);
      var sr = 0.0, sg = 0.0;
      for (var i = 0; i < s.t.length; i++) {
        if (s.t[i] >= 5 && s.t[i] <= 65) {
          sr += s.red[i];
          sg += s.green[i];
        }
      }
      final k = sr / (ratio * sg);
      return [
        for (var i = 0; i < s.t.length; i++)
          PpgFrame(
            t: s.t[i],
            r: s.red[i],
            g: s.green[i] * k,
            r16: List.filled(16, s.red[i]),
            g16: List.filled(16, s.green[i] * k),
          ),
      ];
    }

    test('Grenze 1,5: knapp darüber gilt, knapp darunter ist kein Finger', () {
      expect(ppgMinRedGreenRatio, 1.5);
      final over = evaluatePpg(withRatio(1.501));
      expect(over.reasons, isNot(contains(PpgQualityReason.noFinger)));
      expect(over.quality, PpgQuality.good);
      final under = evaluatePpg(withRatio(1.499));
      expect(under.quality, PpgQuality.unusable);
      expect(under.reasons, [PpgQualityReason.noFinger]);
    });

    test('kein Finger: keine Zahlen, auch keine Diagnose', () {
      final m = evaluatePpg(withRatio(0.86));
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.hasResult, isFalse);
      expect(m.bpm, isNull);
      expect(m.rmssdMs, isNull);
      expect(m.signalQuality, isNull);
      expect(m.channel, isNull);
    });

    /// 2-Hz-Rechteck auf Rot, 2000 Bilder: ohne Rot-Positiv-Prüfung ginge das als „gut, 120“ durch.
    List<PpgFrame> square(double rBase, double rAmp, double g) => [
      for (var i = 0; i < 2000; i++)
        () {
          final t = i / 30;
          final r = rBase + (t * 2 % 1 < 0.5 ? rAmp : -rAmp);
          return PpgFrame(
            t: t,
            r: r,
            g: g,
            r16: List.filled(16, r),
            g16: List.filled(16, g),
          );
        }(),
    ];

    test('Rot nicht positiv (R=G=0): kein Finger', () {
      final m = evaluatePpg(square(0, 0, 0));
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.hasResult, isFalse);
    });

    test('negative Summen (R=-1,4, G=-3,4, 2-Hz-Rechteck): kein Finger', () {
      final m = evaluatePpg(square(-1.4, 0.2, -3.4));
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.bpm, isNull);
    });

    test('Rot knapp unter 0 (R=-0,005 ± 0,01, G=0): kein Finger', () {
      final m = evaluatePpg(square(-0.005, 0.01, 0));
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.bpm, isNull);
    });

    test('Rot positiv, Grün 0: „sehr rot“, besteht die Fingerprüfung', () {
      final m = evaluatePpg(square(1, 0.5, 0));
      expect(m.reasons, isNot(contains(PpgQualityReason.noFinger)));
    });

    test('nur das Messfenster zählt (Einschwingen davor und danach nicht)', () {
      // Vor 5 s und nach 65 s extrem hohes Grün (R/G 0,02), im Fenster mit Finger.
      final good = withRatio(5);
      final mixed = [
        for (final f in good)
          (f.t < 5 || f.t > 65)
              ? PpgFrame(
                  t: f.t,
                  r: f.r,
                  g: f.r * 50,
                  r16: f.r16,
                  g16: List.filled(16, f.r * 50),
                )
              : f,
      ];
      expect(
        evaluatePpg(mixed).reasons,
        isNot(contains(PpgQualityReason.noFinger)),
      );
    });

    test('Emulator-Szene (2-Hz-Rechteck, R/G ca. 0,86): kein Finger', () {
      // Synthetischer Testvektor der Emulator-Szene: ohne die Prüfung „gut, 120/min“.
      final frames = [
        for (var i = 0; i < 2000; i++)
          () {
            final t = i / 30;
            final r = 167 + (t * 2 % 1 < 0.5 ? 2.25 : -2.25);
            return PpgFrame(
              t: t,
              r: r,
              g: 194,
              r16: List.filled(16, r),
              g16: List.filled(16, 194.0),
            );
          }(),
      ];
      final m = evaluatePpg(frames);
      expect(m.quality, PpgQuality.unusable);
      expect(m.reasons, [PpgQualityReason.noFinger]);
      expect(m.bpm, isNull);
      // Kontrolle: Der Analysator allein hält das Signal für einen sauberen 120er Puls.
      final set = PpgAnalyzer.analyze(
        [for (final f in frames) f.t],
        [
          PpgSeries('Rot', [for (final f in frames) f.r]),
          PpgSeries('Grün', [for (final f in frames) f.g]),
        ],
        const [],
        ppgStandardWindow,
      );
      expect(ratePpg(set.best).quality, PpgQuality.good);
    });
  });
}
