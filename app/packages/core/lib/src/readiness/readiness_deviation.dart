import 'dart:math' as math;

import '../morning/morning_logic.dart' show MorningSeriesKey;
import 'readiness_level.dart' show readinessSourceSpanDays;
import 'readiness_parameters.dart';

/// Gesundheitsgröße eines Faktors mit Abweichung.
enum ReadinessFactor { hrv, restingHeartRate }

/// Herkunft einer Reihe (FR-0115): nie gemischt.
enum ReadinessSource { healthConnect, camera }

/// Warum kein `z` entstanden ist (FR-0114: keine Scheinpräzision).
enum NoDeviationReason {
  /// Die Quelle hat keinen einzigen Tageswert.
  noSeries,

  /// Heute fehlt der Wert der Reihe.
  noValueToday,

  /// Weniger als [readinessMinWindowValues] Werte in den letzten 7 Tagen.
  tooFewInWindow,

  /// Weniger als [readinessMinReferenceValues] Referenzwerte in 28 Tagen.
  tooFewReference,

  /// MAD unter der Grenze (insbesondere 0).
  madTooSmall,
}

/// Regeln einer Reihe: Transformation, Vorzeichen, MAD-Grenze.
class DeviationRules {
  const DeviationRules({
    required this.logTransform,
    required this.invertSign,
    required this.madMin,
    this.valueDecimals = 0,
  });

  /// PAR-161 / PAR-161K: HRV auf `ln(RMSSD)`, Gesundheitswerte (z. B. 0 ms)
  /// sind vorher durch den Bereich 1–200 ms ausgeschlossen.
  final bool logTransform;

  /// PAR-162 / PAR-162K: Vorzeichen umgedreht, positiv heißt niedriger.
  final bool invertSign;

  /// MAD unter diesem Wert ergibt kein `z` (in der Einheit nach der
  /// Transformation).
  final double madMin;

  /// Nachkommastellen der Werte für Tatsachentexte (FR-0114, keine
  /// Scheinpräzision): ganze ms bzw. bpm, nur der Kamera-Ruhepuls eine Stelle
  /// (PAR-162K).
  final int valueDecimals;

  /// PAR-161: HRV aus Health Connect.
  static const DeviationRules hrv = DeviationRules(
    logTransform: true,
    invertSign: false,
    madMin: readinessHrvMadMinLn,
  );

  /// PAR-162: Ruhepuls aus Health Connect.
  static const DeviationRules restingHeartRate = DeviationRules(
    logTransform: false,
    invertSign: true,
    madMin: readinessRestingHrMadMinBpm,
  );

  /// PAR-161K: HRV der Kamera.
  static const DeviationRules cameraHrv = hrv;

  /// PAR-162K: Ruhepuls der Kamera.
  static const DeviationRules cameraRestingHeartRate = DeviationRules(
    logTransform: false,
    invertSign: true,
    madMin: readinessCameraRestingHrMadMinBpm,
    valueDecimals: 1,
  );
}

/// Ergebnis einer Reihe für heute. Enthält keine Messwerte; [toString] nennt
/// sie nicht (Gesundheitswerte gehören nicht in Logs).
class DeviationResult {
  const DeviationResult({
    required this.factor,
    required this.source,
    this.origin,
    this.cameraSeries,
    this.z,
    this.reason,
    this.windowCount = 0,
    this.referenceCount = 0,
    this.fewMeasurements = false,
    this.windowMean,
    this.referenceMedian,
    this.todayValue,
    this.todayIsFallback = false,
    this.sourceSpanDays = 0,
    this.valueDecimals = 0,
  }) : assert((z == null) != (reason == null));

  final ReadinessFactor factor;
  final ReadinessSource source;

  /// Quell-App bei Health Connect (PAR-189), sonst null.
  final String? origin;

  /// Haltung und Gerät bei der Kamera, sonst null.
  final MorningSeriesKey? cameraSeries;

  /// Gültiges `z`, sonst null mit [reason].
  final double? z;
  final NoDeviationReason? reason;

  /// `k`: gültige Werte der letzten 7 Tage (0, wenn nicht bestimmt).
  final int windowCount;

  /// Zahl gültiger Referenzwerte der 28 Tage vor heute (für PAR-148/149).
  final int referenceCount;

  /// PAR-161K: Kamerareihe mit weniger als 5 gültigen Werten in 7 Tagen
  /// („wenige Messungen, weniger verlässlich“). Bei Health Connect immer false.
  final bool fewMeasurements;

  /// Werte für die Tatsachentexte in der Einheit des Faktors (ms bzw. bpm),
  /// gerundet nach [DeviationRules.valueDecimals] (FR-0114). Nur bei `z`
  /// gesetzt. Bei der HRV zurückgerechnet aus `ln`: [windowMean] und
  /// [referenceMedian] stehen auf derselben Skala wie `z`.
  /// Mittel der letzten 7 Tage (`x`).
  final double? windowMean;

  /// Median der Referenz der 28 Tage vor heute.
  final double? referenceMedian;

  /// Der Wert von heute (Tageswert, nicht das Mittel).
  final double? todayValue;

  /// PAR-160: der Wert von heute ist der Ersatzwert aus den 60 min nach der
  /// Hauptschlafphase; der Tag wird markiert.
  final bool todayIsFallback;

  /// PAR-150: Tage vom ersten gültigen Tageswert dieser Reihe bis heute
  /// ([readinessSourceSpanDays] über alle übergebenen Tage der Reihe); nur bei
  /// `z` gesetzt, sonst 0 (unbekannt, erfüllt „28 Tage“ nicht).
  final int sourceSpanDays;

  /// Nachkommastellen der Werte ([DeviationRules.valueDecimals]).
  final int valueDecimals;

  bool get hasZ => z != null;

  @override
  String toString() => 'DeviationResult($factor, $source)';
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// Median Absolute Deviation (ohne Skalierung).
double madOf(List<double> v) {
  final m = _median(v);
  return _median([for (final x in v) (x - m).abs()]);
}

/// FR-0113: `z = (x − Median(X)) / (1,4826 · MAD(X) / √k)`. Null bei leerem
/// [reference], `k < 1` oder MAD unter [madMin] (FR-0114, auch bei MAD = 0).
/// Rechnet auf den übergebenen Werten; Transformation und Vorzeichen stehen
/// in [deviationForSeries].
double? robustZ({
  required List<double> reference,
  required double x,
  required int k,
  required double madMin,
}) {
  if (reference.isEmpty || k < 1) return null;
  final mad = madOf(reference);
  if (mad < madMin || mad == 0) return null;
  return (x - _median(reference)) / (readinessMadScale * mad / math.sqrt(k));
}

/// Tageswerte einer einzigen Reihe nach Ortstag (UTC-Datum ohne Uhrzeit, wie
/// `morningLocalDay`) zu `z` für [today] nach PAR-161/162 bzw. PAR-161K/162K.
/// [byDay] darf nur Werte einer Reihe enthalten (der Aufrufer trennt, FR-0115).
DeviationResult deviationForSeries({
  required Map<DateTime, double> byDay,
  required DateTime today,
  required ReadinessFactor factor,
  required ReadinessSource source,
  required DeviationRules rules,
  String? origin,
  MorningSeriesKey? cameraSeries,
  bool todayIsFallback = false,
}) {
  DeviationResult fail(
    NoDeviationReason r, {
    int k = 0,
    int refN = 0,
    bool few = false,
  }) => DeviationResult(
    todayIsFallback: todayIsFallback,
    factor: factor,
    source: source,
    origin: origin,
    cameraSeries: cameraSeries,
    reason: r,
    windowCount: k,
    referenceCount: refN,
    fewMeasurements: few,
  );

  double t(double v) => rules.logTransform ? math.log(v) : v;
  DateTime back(int n) => today.subtract(Duration(days: n));
  final isCamera = source == ReadinessSource.camera;

  final window = <double>[
    for (var i = 0; i < readinessWindowDays; i++)
      if (byDay[back(i)] case final v?) t(v),
  ];
  final reference = <double>[
    for (var i = 1; i <= readinessReferenceDays; i++)
      if (byDay[back(i)] case final v?) t(v),
  ];
  final few = isCamera && window.length < readinessFewMeasurementsBelow;
  final k = window.length;

  if (byDay.isEmpty) return fail(NoDeviationReason.noSeries, few: few);
  if (byDay[today] == null) {
    return fail(
      NoDeviationReason.noValueToday,
      k: k,
      refN: reference.length,
      few: few,
    );
  }
  if (k < readinessMinWindowValues) {
    return fail(
      NoDeviationReason.tooFewInWindow,
      k: k,
      refN: reference.length,
      few: few,
    );
  }
  if (reference.length < readinessMinReferenceValues) {
    return fail(
      NoDeviationReason.tooFewReference,
      k: k,
      refN: reference.length,
      few: few,
    );
  }
  final x = window.reduce((a, b) => a + b) / k;
  var z = robustZ(reference: reference, x: x, k: k, madMin: rules.madMin);
  if (z == null) {
    return fail(
      NoDeviationReason.madTooSmall,
      k: k,
      refN: reference.length,
      few: few,
    );
  }
  if (rules.invertSign) z = 0 - z;
  double shown(double v) {
    final back = rules.logTransform ? math.exp(v) : v;
    final f = math.pow(10, rules.valueDecimals).toDouble();
    return (back * f).round() / f;
  }

  return DeviationResult(
    windowMean: shown(x),
    referenceMedian: shown(_median(reference)),
    todayValue: shown(t(byDay[today]!)),
    todayIsFallback: todayIsFallback,
    sourceSpanDays: readinessSourceSpanDays(byDay.keys, today),
    valueDecimals: rules.valueDecimals,
    factor: factor,
    source: source,
    origin: origin,
    cameraSeries: cameraSeries,
    z: z,
    windowCount: k,
    referenceCount: reference.length,
    fewMeasurements: few,
  );
}
