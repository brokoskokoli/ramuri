import 'dart:math' as math;

import '../preprocessing/measurement.dart' show RrPacket;

/// Kennung des Vergleichs Kamera gegen Gurt (FR-0217, nur Anzeige im
/// Entwicklermodus, keine Auswertung; Kategorie in
/// `docs/architecture/algorithm-categories.md`).
const String morningBeltCompareMethod = 'morning-belt-compare';

/// Version des Vergleichs; steigt mit jeder Änderung der Rechnung.
const int morningBeltCompareMethodVersion = 1;

/// PAR-229: Die Zuordnung gilt nur, wenn die kleinsten Kosten höchstens so viel
/// mal die zweitkleinsten sind (sonst mehrdeutig).
const double morningBeltCompareAmbiguityRatio = 0.9;

/// Mindestzahl Paare je Versatz (FR-0217, Zuordnungsverfahren): mindestens
/// diese Zahl …
const int morningBeltCompareMinPairs = 10;

/// … und mindestens dieser Anteil der gültigen Kamera-Abstände.
const double morningBeltCompareMinPairsFraction = 0.6;

/// Obergrenze des Betrags je Paar in den Kosten (ms).
const double morningBeltCompareCostCapMs = 100;

/// Gültige Gurt-Abstände im Fenster in ms, Grenzen eingeschlossen.
const double morningBeltCompareBeltMinMs = 270;
const double morningBeltCompareBeltMaxMs = 2000;

/// Warum es keine Zuordnung gibt.
enum MorningBeltNoMatchReason {
  /// Keine Gurt-Werte (oder keine Kamera-Abstände).
  empty,

  /// Kein Versatz hat genug Paare.
  tooFewPairs,

  /// Kleinste Kosten größer als PAR-229 × zweitkleinste.
  ambiguous,
}

/// Ergebnis von [compareMorningWithBelt].
sealed class MorningBeltCompareResult {
  const MorningBeltCompareResult();

  String get method => morningBeltCompareMethod;
  int get methodVersion => morningBeltCompareMethodVersion;
}

/// Keine Zuordnung der Kamera-Abstände zur Gurt-Folge.
class MorningBeltNoMatch extends MorningBeltCompareResult {
  const MorningBeltNoMatch(this.reason);

  final MorningBeltNoMatchReason reason;

  @override
  String toString() => 'MorningBeltNoMatch(${reason.name})';
}

/// Vergleich einer Morgenmessung mit dem Gurt (FR-0217). Werte in ms bzw.
/// 1/min; `null`, wenn der Wert sich nicht bilden lässt.
class MorningBeltComparison extends MorningBeltCompareResult {
  const MorningBeltComparison({
    required this.offset,
    required this.cost,
    required this.secondCost,
    required this.pairCount,
    required this.cameraIbiMs,
    required this.beltWindowMs,
    required this.beltRmssdMs,
    required this.beltRestingHrBpm,
    required this.pairedCameraRmssdMs,
    required this.pairedBeltRmssdMs,
    required this.pairedDiffCount,
    required this.ibiErrorMs,
    required this.cameraRmssdMs,
    required this.cameraRestingHrBpm,
  });

  /// Versatz L in Schlägen: Kamera i gehört zu Gurt i + L.
  final int offset;

  /// Kosten des gewählten Versatzes und des zweitbesten (`null`, wenn es nur
  /// einen zulässigen Versatz gibt), in ms.
  final double cost;
  final double? secondCost;

  /// Paare des gewählten Versatzes (gültiger Kamera-Wert, Gurt-Wert vorhanden).
  final int pairCount;

  /// Kamera-Abstände wie gespeichert (NaN = ungültig).
  final List<double> cameraIbiMs;

  /// Gurt im Fenster, gleiche Länge wie [cameraIbiMs]; `null` = kein Gurt-Wert
  /// an dieser Stelle oder außerhalb 0,27 bis 2,0 s.
  final List<double?> beltWindowMs;

  /// RMSSD aus direkt aufeinanderfolgenden gültigen Gurt-Werten im Fenster.
  final double? beltRmssdMs;

  /// 60000 / Mittel der gültigen Gurt-Werte im Fenster.
  final double? beltRestingHrBpm;

  /// RMSSD beider auf denselben Paaren und deren Anzahl (Differenzen).
  final double? pairedCameraRmssdMs;
  final double? pairedBeltRmssdMs;
  final int pairedDiffCount;

  /// Fehler je Schlagabstand: RMS von Kamera − Gurt über die Paare mit
  /// gültigem Gurt-Wert im Fenster.
  final double? ibiErrorMs;

  /// Gespeicherte Werte der Kamera (Stufe eingeschränkt/unbrauchbar: oft
  /// `null`).
  final double? cameraRmssdMs;
  final double? cameraRestingHrBpm;

  /// RMSSD Kamera − Gurt in ms und in % des Gurts.
  double? get rmssdDiffMs => _diff(cameraRmssdMs, beltRmssdMs);
  double? get rmssdDiffPercent => _pct(cameraRmssdMs, beltRmssdMs);

  /// Ruhepuls Kamera − Gurt in 1/min und in % des Gurts.
  double? get restingHrDiffBpm => _diff(cameraRestingHrBpm, beltRestingHrBpm);
  double? get restingHrDiffPercent =>
      _pct(cameraRestingHrBpm, beltRestingHrBpm);

  /// Gültige Kamera-Abstände.
  int get validCameraCount => cameraIbiMs.where(_valid).length;

  static double? _diff(double? a, double? b) =>
      a == null || b == null ? null : a - b;

  static double? _pct(double? a, double? b) =>
      a == null || b == null || b == 0 ? null : (a - b) / b * 100;

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'MorningBeltComparison(…)';
}

bool _valid(double v) => v.isFinite;

/// Gurt-Folge in ms: alle RR-Werte der Pakete in Reihenfolge (Empfangszeit,
/// Paket, Position), Wert × 1000 / 1024. Pakete mit gleicher Empfangszeit
/// behalten ihre Reihenfolge.
List<double> morningBeltSequenceMs(List<RrPacket> packets) {
  final indexed = packets.indexed.toList()
    ..sort((a, b) {
      final t = a.$2.time.compareTo(b.$2.time);
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
  return [
    for (final (_, p) in indexed)
      for (final v in p.intervals) v * 1000 / 1024,
  ];
}

/// Vergleicht die Kamera-Abstände einer Morgenmessung mit der Gurt-RR
/// derselben Zeit (FR-0217, Verfahren [morningBeltCompareMethod]). Rein; speichert
/// nichts.
///
/// Zuordnung ohne gemeinsame Uhr über einen Versatz L in Schlägen: Für jedes L
/// von −n bis +m (n Kamera-Abstände, m Gurt-Werte) zählen die Paare (Kamera i,
/// Gurt i + L) mit gültigem Kamera-Wert; zulässig ist L mit mindestens
/// max(10; 60 % der gültigen Kamera-Abstände) Paaren, die Kosten sind das
/// Mittel von min(|Kamera − Gurt|; 100 ms). Gewählt wird L mit den kleinsten
/// Kosten (bei Gleichstand das kleinste L); keine Zuordnung, wenn kein L
/// zulässig ist oder die kleinsten Kosten größer als PAR-229 × die
/// zweitkleinsten sind.
MorningBeltCompareResult compareMorningWithBelt(
  List<double> cameraIbiMs,
  List<RrPacket> beltPackets, {
  double? cameraRmssdMs,
  double? cameraRestingHrBpm,
}) {
  final cam = List<double>.unmodifiable(cameraIbiMs);
  final belt = morningBeltSequenceMs(beltPackets);
  final n = cam.length;
  final m = belt.length;
  if (n == 0 || m == 0) {
    return const MorningBeltNoMatch(MorningBeltNoMatchReason.empty);
  }
  final validCam = cam.where(_valid).length;
  final minPairs = math.max(
    morningBeltCompareMinPairs.toDouble(),
    morningBeltCompareMinPairsFraction * validCam,
  );

  int? best;
  var bestCost = double.infinity;
  var bestPairs = 0;
  double? second;
  for (var l = -n; l <= m; l++) {
    var pairs = 0;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final j = i + l;
      if (j < 0 || j >= m || !_valid(cam[i])) continue;
      pairs++;
      sum += math.min((cam[i] - belt[j]).abs(), morningBeltCompareCostCapMs);
    }
    if (pairs == 0 || pairs < minPairs) continue;
    final cost = sum / pairs;
    if (cost < bestCost) {
      if (best != null) second = bestCost;
      best = l;
      bestCost = cost;
      bestPairs = pairs;
    } else if (second == null || cost < second) {
      second = cost;
    }
  }
  if (best == null) {
    return const MorningBeltNoMatch(MorningBeltNoMatchReason.tooFewPairs);
  }
  if (second != null && bestCost > morningBeltCompareAmbiguityRatio * second) {
    return const MorningBeltNoMatch(MorningBeltNoMatchReason.ambiguous);
  }

  final window = <double?>[
    for (var i = 0; i < n; i++)
      switch (i + best) {
        final j when j >= 0 && j < m => _beltValid(belt[j]) ? belt[j] : null,
        _ => null,
      },
  ];

  // RMSSD und Ruhepuls des Gurts im Fenster.
  final beltDiffs = <double>[
    for (var i = 0; i + 1 < n; i++)
      if (window[i] != null && window[i + 1] != null)
        window[i + 1]! - window[i]!,
  ];
  final beltValues = [for (final v in window) ?v];
  final beltMean = beltValues.isEmpty
      ? null
      : beltValues.reduce((a, b) => a + b) / beltValues.length;

  // Beide auf denselben Paaren: Kamera und Gurt je zwei aufeinanderfolgende
  // gültige Werte.
  final camPaired = <double>[];
  final beltPaired = <double>[];
  for (var i = 0; i + 1 < n; i++) {
    final b0 = window[i], b1 = window[i + 1];
    if (!_valid(cam[i]) || !_valid(cam[i + 1]) || b0 == null || b1 == null) {
      continue;
    }
    camPaired.add(cam[i + 1] - cam[i]);
    beltPaired.add(b1 - b0);
  }

  final errors = <double>[
    for (var i = 0; i < n; i++)
      if (_valid(cam[i]) && window[i] != null) cam[i] - window[i]!,
  ];

  return MorningBeltComparison(
    offset: best,
    cost: bestCost,
    secondCost: second,
    pairCount: bestPairs,
    cameraIbiMs: cam,
    beltWindowMs: List.unmodifiable(window),
    beltRmssdMs: _rms(beltDiffs),
    beltRestingHrBpm: beltMean == null ? null : 60000 / beltMean,
    pairedCameraRmssdMs: _rms(camPaired),
    pairedBeltRmssdMs: _rms(beltPaired),
    pairedDiffCount: camPaired.length,
    ibiErrorMs: _rms(errors),
    cameraRmssdMs: cameraRmssdMs,
    cameraRestingHrBpm: cameraRestingHrBpm,
  );
}

bool _beltValid(double v) =>
    v >= morningBeltCompareBeltMinMs && v <= morningBeltCompareBeltMaxMs;

/// Wurzel des Mittels der Quadrate; leer: `null`.
double? _rms(List<double> xs) {
  if (xs.isEmpty) return null;
  var s = 0.0;
  for (final x in xs) {
    s += x * x;
  }
  return math.sqrt(s / xs.length);
}
