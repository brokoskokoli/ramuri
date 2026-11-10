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
  });

  final PpgQuality quality;

  /// Alle zutreffenden Gründe der Stufe; bei „gut“ leer.
  final List<PpgQualityReason> reasons;

  /// Puls (1/min) und RMSSD (ms) über das Messfenster; null bei „unbrauchbar“ oder wenn nicht
  /// berechenbar. Welche Werte gelten (RMSSD nur bei „gut“), regelt PAR-160K beim Verwender.
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
  return PpgMeasurement(
    quality: quality,
    reasons: unusable ? unusableReasons : limitedReasons,
    bpm: unusable ? null : _finite(m.bpm),
    rmssdMs: unusable ? null : _finite(m.rmssdMs),
    signalQuality: r.quality,
    timingNoiseMs: _finite(r.timingNoiseMs),
    validIntervals: m.validIbis,
    intervals: m.ibis,
    disturbances: r.artifacts.length,
    channel: r.channel,
    meanFps: _finite(r.meanFps),
  );
}
