import 'package:core/core.dart';
import 'package:test/test.dart';

import 'ppg_synth.dart';

/// Bilder von [from] bis [to] Sekunden; Bilder in [dropFrom, dropTo) entfallen (Bildlücke).
List<PpgFrame> frames(
  Synth s, {
  double from = 0,
  double to = double.infinity,
  double dropFrom = 0,
  double dropTo = 0,
}) => [
  for (var i = 0; i < s.t.length; i++)
    if (s.t[i] >= from &&
        s.t[i] < to &&
        !(s.t[i] >= dropFrom && s.t[i] < dropTo))
      PpgFrame(
        t: s.t[i],
        r: s.red[i],
        g: s.green[i],
        r16: List.filled(16, s.red[i]),
        g16: List.filled(16, s.green[i]),
      ),
];

const _long = 130.0;

/// Gutes Signal (Rauschen 0,3) und nicht auswertbares Signal (Rauschen 30) über 130 s.
Synth good([int seed = 1]) =>
    synth(0.85, 0.05, 0.03, 0.3, 30.0, seed, duration: _long);
Synth bad([int seed = 1]) =>
    synth(0.85, 0.05, 0.03, 30.0, 30.0, seed, duration: _long);

/// Schlecht bis [switchAt], danach gut; endet bei [to].
List<PpgFrame> badThenGood(double switchAt, double to) => [
  ...frames(bad(), to: switchAt),
  ...frames(good(), from: switchAt, to: to),
];

void main() {
  group('evaluatePpgBestWindow (WP37, Fenstersuche)', () {
    test(
      '30 s schlecht, dann 60 s gut: gut mit RMSSD, Fenster = die guten 60 s',
      () {
        final fr = badThenGood(30, 95);
        // Zum Vergleich: Das feste Fenster 5 bis 65 s verfehlt „gut“ (halb schlechtes Signal).
        expect(evaluatePpg(fr).quality, isNot(PpgQuality.good));
        final r = evaluatePpgBestWindow(fr);
        expect(r.measurement.quality, PpgQuality.good);
        expect(r.measurement.rmssdMs, isNotNull);
        expect(r.windowStartSeconds, inInclusiveRange(29.0, 36.0));
        expect(r.windowEndSeconds, r.windowStartSeconds! + 60);
        final t = truth(
          [for (final b in good().beats) b + 0.12],
          r.windowStartSeconds!,
          r.windowEndSeconds!,
        );
        expect(r.measurement.bpm, closeTo(t.bpm, 0.7));
        expect(r.measurement.rmssdMs, closeTo(t.rmssd, 8.0));
        expect(r.goodStretchSeconds, greaterThan(50));
      },
    );

    test(
      'Abnahmefall: 30 s schlecht, genau 60 s gut (91,5 s mit Filterrand)',
      () {
        final fr = badThenGood(30, 91.5);
        expect(fr.last.t, closeTo(91.5, 0.1));
        final r = evaluatePpgBestWindow(fr);
        expect(r.measurement.quality, PpgQuality.good);
        expect(r.measurement.rmssdMs, isNotNull);
        // Toleranz 1 s: Beginne liegen im 1-s-Raster, und ein Fenster darf höchstens die erste
        // Sekunde des schlechten Stücks berühren, ohne die Stufe zu verlieren.
        expect(r.windowStartSeconds, inInclusiveRange(29.0, 31.0));
        expect(r.windowEndSeconds, closeTo(90.0, 1.0));
        expect(checkPpgRecording(fr).goodWindowReached, isTrue);
      },
    );

    test('das Ergebnis ist die Einzelauswertung des gewählten Fensters', () {
      final fr = badThenGood(30, 95);
      final r = evaluatePpgBestWindow(fr);
      final s = r.windowStartSeconds!;
      final single = evaluatePpg(
        fr,
        window: PpgWindow(
          filterStart: s - 2,
          start: s,
          end: s + 60,
          dataEnd: s + 61.5,
        ),
      );
      expect(r.measurement.rmssdMs, single.rmssdMs);
      expect(r.measurement.intervalsMs, single.intervalsMs);
      expect(r.measurement.timingNoiseMs, single.timingNoiseMs);
    });

    test('nie 60 s gut: bestes Fenster mit seiner Stufe wie bisher', () {
      // verrauscht (eingeschränkt) über die ganze Aufnahme
      final noisy = synth(0.85, 0.05, 0.03, 4.0, 30.0, 1, duration: _long);
      final fr = frames(noisy, to: 100);
      final r = evaluatePpgBestWindow(fr);
      // nie schlechter als das feste Fenster (hier sogar besser: dort unbrauchbar)
      expect(evaluatePpg(fr).quality, PpgQuality.unusable);
      expect(r.measurement.quality, PpgQuality.limited);
      expect(r.measurement.bpm, isNotNull);
      expect(r.measurement.rmssdMs, isNull);
      expect(r.windowStartSeconds, isNotNull);

      // gut nur in den ersten 45 s: kein „gutes“ Fenster
      final half = [
        ...frames(good(), to: 45),
        ...frames(bad(), from: 45, to: 100),
      ];
      final h = evaluatePpgBestWindow(half);
      expect(h.measurement.quality, isNot(PpgQuality.good));
      // nie schlechter als das feste Fenster
      expect(
        h.measurement.quality.index,
        greaterThanOrEqualTo(evaluatePpg(half).quality.index),
      );
      expect(h.windowStartSeconds, inInclusiveRange(5.0, 15.0));

      // gar nicht auswertbar: unbrauchbar ohne Zahlen, Fenster am Anfang
      final u = evaluatePpgBestWindow(frames(bad(), to: 100));
      expect(u.measurement.quality, PpgQuality.unusable);
      expect(u.measurement.bpm, isNull);
      expect(u.windowStartSeconds, isNotNull);
    });

    test(
      'Bildlücke: Fenster mit Lücke (samt Filterrand) kommen nicht in Frage',
      () {
        final fr = frames(good(), to: 92, dropFrom: 20, dropTo: 23);
        final r = evaluatePpgBestWindow(fr);
        expect(r.measurement.quality, PpgQuality.good);
        // Der Filterrand beginnt 2 s vor dem Fenster: ab Beginn 24 s liegt die Lücke davor
        // (davor fehlt das Bild am Fensterbeginn oder die Lücke liegt im Filterrand).
        expect(r.windowStartSeconds, inInclusiveRange(24.0, 31.0));
      },
    );

    test('gleiche Stufe und gleicher Anteil: das früheste Fenster gewinnt', () {
      final fr = frames(good(), to: 100);
      final r = evaluatePpgBestWindow(fr);
      expect(r.measurement.quality, PpgQuality.good);
      expect(r.measurement.validIntervals, r.measurement.intervals);
      expect(r.windowStartSeconds, 5.0);
    });

    test('Aufnahme kürzer als 65 s: unzureichende Daten, kein Fenster', () {
      final r = evaluatePpgBestWindow(frames(good(), to: 64));
      expect(r.measurement.quality, PpgQuality.unusable);
      expect(r.measurement.reasons, [PpgQualityReason.insufficientData]);
      expect(r.windowStartSeconds, isNull);
      expect(r.windowEndSeconds, isNull);
      expect(evaluatePpgBestWindow(const []).windowStartSeconds, isNull);
    });

    test('Aufnahme von 65 bis 66,5 s: das Standardfenster wie bisher', () {
      final fr = frames(good(), to: 65.3);
      final r = evaluatePpgBestWindow(fr);
      expect(r.windowStartSeconds, 5.0);
      expect(r.windowEndSeconds, 65.0);
      expect(r.measurement.quality, evaluatePpg(fr).quality);
      expect(r.measurement.rmssdMs, evaluatePpg(fr).rmssdMs);
    });

    test('genau 120 s: letztes Fenster endet bei 118 s, Bilder danach zählen nicht', () {
      // schlecht bis 55 s, danach gut: nur die letzten Fenster (Beginn 55 bis 58 s) sind gut
      final fr = badThenGood(55, 120);
      final r = evaluatePpgBestWindow(fr);
      expect(r.measurement.quality, PpgQuality.good);
      expect(r.windowStartSeconds, inInclusiveRange(55.0, 58.0));
      expect(r.windowEndSeconds, lessThanOrEqualTo(118.0));
      // Bilder nach 120 s werden nicht gelesen
      final longer = evaluatePpgBestWindow(badThenGood(55, 128));
      expect(longer.windowStartSeconds, r.windowStartSeconds);
      expect(longer.measurement.rmssdMs, r.measurement.rmssdMs);
    });

    test('ungültige Eingabe: unbrauchbar, keine Ausnahme', () {
      final broken = [
        ...frames(good(), to: 70),
        const PpgFrame(t: double.nan, r: 1, g: 1, r16: [], g16: []),
      ];
      final r = evaluatePpgBestWindow(broken);
      expect(r.measurement.reasons, [PpgQualityReason.invalidInput]);
    });
  });

  group('checkPpgRecording (Abbruch und Fortschritt)', () {
    test('gutes Signal von Anfang an: Ende bei 66,5 s, nicht früher', () {
      final g = good();
      expect(checkPpgRecording(frames(g, to: 66.4)).goodWindowReached, isFalse);
      final upTo = frames(g, to: 66.6);
      expect(upTo.last.t, greaterThanOrEqualTo(ppgStandardWindow.dataEnd));
      final at = checkPpgRecording(upTo);
      expect(at.goodWindowReached, isTrue);
      expect(at.goodStretchSeconds, greaterThan(50));
    });

    test('30 s schlecht, dann gut: erst nach 60 gutem Signal samt Rand', () {
      expect(checkPpgRecording(badThenGood(30, 67)).goodWindowReached, isFalse);
      expect(checkPpgRecording(badThenGood(30, 92)).goodWindowReached, isTrue);
    });

    test(
      'Fortschritt: gutes Stück wächst mit der Aufnahme, auch unter 65 s',
      () {
        final g = good();
        final at30 = checkPpgRecording(frames(g, to: 30));
        final at50 = checkPpgRecording(frames(g, to: 50));
        expect(at30.goodWindowReached, isFalse);
        expect(at50.goodWindowReached, isFalse);
        expect(at30.goodStretchSeconds, inInclusiveRange(15.0, 26.0));
        expect(at50.goodStretchSeconds, inInclusiveRange(35.0, 46.0));
      },
    );

    test('Fortschritt nach starker Störung am Anfang: 30 s Rauschen, 40 s gut', () {
      // Die Gesamtanalyse allein liefert hier 4,7 s, weil die Störung Vorlage und Schwellen
      // prägt. Erwartet rund 40 s: untere Grenze knapp darunter (Filterrand, Schlagabstand), obere
      // Grenze 40 / 0,7 = 57 s, denn ein Stück gilt ab 70 % gültiger Intervalle und darf daher
      // einen Teil des gestörten Stücks einschließen. Nie mehr als ein Fenster.
      final c = checkPpgRecording(badThenGood(30, 70));
      expect(c.goodWindowReached, isFalse);
      expect(c.goodStretchSeconds, inInclusiveRange(37.0, 58.0));
      expect(c.goodStretchSeconds, lessThanOrEqualTo(60.0));
      final r = evaluatePpgBestWindow(badThenGood(30, 70));
      expect(r.goodStretchSeconds, inInclusiveRange(37.0, 58.0));
    });

    test('schlechtes Signal: nicht erreicht, kein gutes Stück', () {
      final c = checkPpgRecording(frames(bad(), to: 100));
      expect(c.goodWindowReached, isFalse);
      // Gefiltertes Rauschen ist quasi periodisch: schon die Gesamtanalyse allein zeigt je nach
      // Startwert 2 bis 20 s „gutes Stück“ (A2 gemessen); entscheidend ist, dass es nie das
      // Fenster erreicht.
      expect(c.goodStretchSeconds, lessThan(25));
    });

    test('zu kurz oder leer: nicht erreicht', () {
      expect(checkPpgRecording(const []).goodWindowReached, isFalse);
      expect(
        checkPpgRecording(frames(good(), to: 40)).goodWindowReached,
        isFalse,
      );
    });
  });
}
