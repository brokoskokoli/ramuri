import '../algorithm_category.dart';
import 'ppg_analyzer.dart';
import 'ppg_parameters.dart';

/// Bildstatistik eines Kamerabilds (ADR-0011): Sensor-Zeitstempel und Mittelwerte von Rot und
/// Grün in der Bildmitte sowie in 4×4 Teilbereichen. Keine Pixel.
class PpgFrame {
  const PpgFrame({
    required this.t,
    required this.r,
    required this.g,
    required this.r16,
    required this.g16,
  });

  /// Sekunden seit Aufnahmebeginn (Sensor-Zeit), vor dem Messfenster liegt das Einschwingen.
  final double t;
  final double r;
  final double g;

  /// 16 Teilbereiche, zeilenweise (r0 bis r15, g0 bis g15 wie in der Referenz).
  final List<double> r16;
  final List<double> g16;
}

/// Stufe der Signalqualität (PAR-160K, ALGORITHMUS.md Abschn. 10).
enum PpgQuality { good, limited, unusable }

/// Grund für eine Stufe unter „gut“.
enum PpgQualityReason {
  /// Zu wenige oder unpassende Bilder für das Messfenster.
  insufficientData,

  /// Bilder mit nicht endlichen Werten oder falscher Teilbereichszahl.
  invalidInput,

  /// Signalqualität Q unter 0,25 (kein klarer Puls).
  weakSignal,

  /// Weniger als 50 % gültige Schlagintervalle (zu viele Störungen).
  tooManyDisturbances,

  /// Zwischen zwei Bildern im Messfenster liegt mehr als [ppgMaxFrameGapSeconds] (Unterbrechung).
  frameGap,

  /// Mittel Rot geteilt durch Mittel Grün im Messfenster unter [ppgMinRedGreenRatio]: kein Finger
  /// auf Kamera und Blitz (Maintainer 2026-11-11).
  noFinger,

  /// Alle Signalquellen sind im Messfenster konstant (z. B. übersteuert).
  flatSignal,

  /// Die Auswertung ist an unerwarteten Werten gescheitert (Sicherung, kein Ergebnis).
  analysisFailed,

  /// Q unter 0,3.
  lowSignalQuality,

  /// Weniger als 70 % gültige Schlagintervalle.
  someDisturbances,

  /// Zeitrauschen über 25 ms oder nicht schätzbar: Puls ok, HRV unsicher.
  timingNoise,
}

/// Ergebnis einer Messung. Bei [PpgQuality.unusable] gibt es weder Puls noch RMSSD.
class PpgMeasurement {
  const PpgMeasurement({
    required this.quality,
    required this.reasons,
    this.bpm,
    this.rmssdMs,
    this.signalQuality,
    this.timingNoiseMs,
    this.validIntervals = 0,
    this.intervals = 0,
    this.disturbances = 0,
    this.channel,
    this.meanFps,
    this.intervalsMs = const [],
  });

  final PpgQuality quality;

  /// Alle zutreffenden Gründe der Stufe; bei „gut“ leer.
  final List<PpgQualityReason> reasons;

  /// Puls (1/min) und RMSSD (ms) über das Messfenster. Puls null bei „unbrauchbar“, RMSSD null
  /// außer bei „gut“ (PAR-160K), jeweils auch wenn nicht berechenbar.
  final double? bpm;
  final double? rmssdMs;

  /// Diagnose: Q (0..1), Zeitrauschen (ms), Intervalle, Störabschnitte, Quelle, mittlere Bildrate.
  final double? signalQuality;
  final double? timingNoiseMs;
  final int validIntervals;
  final int intervals;
  final int disturbances;
  final String? channel;
  final double? meanFps;

  /// Gültige Schlagabstände (ms) des Messfensters in zeitlicher Reihenfolge, genau die Werte, aus
  /// denen RMSSD und Puls gerechnet sind (WP33, wird gespeichert). Leer bei „unbrauchbar“.
  final List<double> intervalsMs;

  /// Methode und Version für die Ablage (NFR-0001, NFR-0005).
  String get method => ppgMethod;
  int get methodVersion => ppgMethodVersion;
  AlgorithmCategory get category => ppgCategory;

  bool get hasResult => bpm != null;
}

PpgMeasurement _unusable(PpgQualityReason reason) =>
    PpgMeasurement(quality: PpgQuality.unusable, reasons: [reason]);

double? _finite(double v) => v.isFinite ? v : null;

/// Wertet Bildstatistiken aus und bewertet die Qualität (ALGORITHMUS.md Abschn. 10).
/// Bei „unbrauchbar“ gibt es kein Ergebnis. Reines Dart, ohne Zustand und ohne Ausgabe.
PpgMeasurement evaluatePpg(
  List<PpgFrame> frames, {
  PpgWindow window = ppgStandardWindow,
}) {
  for (final f in frames) {
    if (!f.t.isFinite ||
        !f.r.isFinite ||
        !f.g.isFinite ||
        f.r16.length != 16 ||
        f.g16.length != 16 ||
        f.r16.any((v) => !v.isFinite) ||
        f.g16.any((v) => !v.isFinite)) {
      return _unusable(PpgQualityReason.invalidInput);
    }
  }
  // Referenz (MainActivity) wertet nur vollständige Aufnahmen aus; ohne Bilder am Anfang und
  // am Ende des Messfensters würde sonst eine Teilmessung als „gut“ gelten (Abschn. 2).
  var first = double.infinity;
  var last = double.negativeInfinity;
  var inWindow = 0;
  for (final f in frames) {
    if (f.t >= window.filterStart && f.t <= window.dataEnd) {
      if (f.t < first) first = f.t;
      if (f.t > last) last = f.t;
    }
    if (f.t >= window.start && f.t <= window.end) inWindow++;
  }
  if (first > window.start || last < window.end || inWindow <= ppgMinFrames) {
    return _unusable(PpgQualityReason.insufficientData);
  }
  // Lücke im Fenster: Die Spline-Interpolation würde sie sonst stumm überbrücken und eine
  // unterbrochene Messung als „gut“ oder „eingeschränkt“ bewerten (Maintainer 2026-11-11).
  // Wie die Auswertung: nur streng steigende Zeitstempel im Bereich.
  var prev = double.negativeInfinity;
  for (final f in frames) {
    if (f.t < window.filterStart || f.t > window.dataEnd || f.t <= prev) {
      continue;
    }
    if (prev.isFinite && f.t - prev > ppgMaxFrameGapSeconds) {
      return _unusable(PpgQualityReason.frameGap);
    }
    prev = f.t;
  }
  // Fingerprüfung auf den Bildern des Messfensters (wie die Zählung oben). Ohne Finger kann ein
  // regelmäßig bewegtes Bild (z. B. Emulator, 2 Hz) als „gut, 120/min“ durchgehen (Abschn. 11).
  var sumR = 0.0;
  var sumG = 0.0;
  for (final f in frames) {
    if (f.t >= window.start && f.t <= window.end) {
      sumR += f.r;
      sumG += f.g;
    }
  }
  // Rot muss im Fenster positiv sein: R und G sind ungeklemmt (BT.601) und können bei dunklem Bild
  // negativ oder 0 werden; dann wäre `sumR < 1,5 * sumG` kein Quotient mehr (fail open).
  if (!(sumR > 0) || sumR < ppgMinRedGreenRatio * sumG) {
    return _unusable(PpgQualityReason.noFinger);
  }
  final t = [for (final f in frames) f.t];
  final signals = [
    PpgSeries('Rot', [for (final f in frames) f.r]),
    PpgSeries('Grün', [for (final f in frames) f.g]),
  ];
  final blocks = [
    for (var k = 0; k < 16; k++)
      PpgSeries('r$k', [for (final f in frames) f.r16[k]]),
    for (var k = 0; k < 16; k++)
      PpgSeries('g$k', [for (final f in frames) f.g16[k]]),
  ];
  final PpgAnalysisSet set;
  try {
    set = PpgAnalyzer.analyze(t, signals, blocks, window);
  } on PpgInsufficientDataException {
    return _unusable(PpgQualityReason.insufficientData);
  } on PpgFlatSignalException {
    return _unusable(PpgQualityReason.flatSignal);
  } catch (_) {
    // Fail closed: Bei extremen Werten kann die Rechenkette scheitern (z. B. NaN beim
    // Runden). Nach außen gibt es nie eine Ausnahme, nur „unbrauchbar“ ohne Zahlen.
    return _unusable(PpgQualityReason.analysisFailed);
  }
  return ratePpg(set.best);
}

/// Stufe und Gründe nach ALGORITHMUS.md Abschn. 10; Zahlen nur, wenn nicht „unbrauchbar“.
PpgMeasurement ratePpg(PpgChannelResult r) {
  final m = r.main.total;
  final frac = m.ibis > 0 ? m.validIbis / m.ibis : 0.0;
  final unusableReasons = [
    if (r.quality < ppgUnusableQuality) PpgQualityReason.weakSignal,
    if (frac < ppgUnusableValidFraction) PpgQualityReason.tooManyDisturbances,
  ];
  final limitedReasons = [
    if (r.quality < ppgLimitedQuality) PpgQualityReason.lowSignalQuality,
    if (frac < ppgLimitedValidFraction) PpgQualityReason.someDisturbances,
    if (!(r.timingNoiseMs <= ppgLimitedTimingNoiseMs))
      PpgQualityReason.timingNoise,
  ];
  final unusable = unusableReasons.isNotEmpty;
  final quality = unusable
      ? PpgQuality.unusable
      : (limitedReasons.isNotEmpty ? PpgQuality.limited : PpgQuality.good);
  final main = r.main;
  return PpgMeasurement(
    quality: quality,
    reasons: unusable ? unusableReasons : limitedReasons,
    bpm: unusable ? null : _finite(m.bpm),
    // PAR-160K: RMSSD nur bei „gut“ (fail closed, der Verwender muss nichts filtern).
    rmssdMs: quality == PpgQuality.good ? _finite(m.rmssdMs) : null,
    signalQuality: r.quality,
    timingNoiseMs: _finite(r.timingNoiseMs),
    validIntervals: m.validIbis,
    intervals: m.ibis,
    disturbances: r.artifacts.length,
    channel: r.channel,
    meanFps: _finite(r.meanFps),
    // Wie `PpgAnalyzer.stats` für das Gesamtfenster (Ausgabe, keine neue Rechnung); Schlagzeiten sind
    // relativ zum Fensterbeginn, die obere Grenze `dur + 1e-9` schließt dort alle ein (Test: Länge = validIntervals).
    intervalsMs: unusable
        ? const []
        : List.unmodifiable([
            for (var i = 0; i < main.ibiEnd.length; i++)
              if (main.ibiEnd[i] >= 0.0 && main.valid[i]) main.ibiMs[i],
          ]),
  );
}
