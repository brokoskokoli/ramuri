import '../health/health_day_values.dart';
import '../health/health_processing.dart';
import '../health/health_types.dart';
import '../morning/morning_logic.dart';
import '../morning/morning_parameters.dart';
import '../../ports/storage_morning.dart';
import '../ppg/ppg_evaluator.dart' show PpgQuality;
import 'readiness_deviation.dart';

DateTime _dayKey(DayRange d) {
  final l = d.start.toLocal();
  return DateTime.utc(l.year, l.month, l.day);
}

DeviationResult _healthConnect({
  required HealthProcessing p,
  required List<DayRange> days,
  required List<Map<String, HealthDailyValue>> perDay,
  required ReadinessFactor factor,
  required DeviationRules rules,
}) {
  // PAR-189: genau eine Quell-App; die Werte der anderen gehen nicht ein.
  final origin = p.selectSource(perDay);
  final byDay = <DateTime, double>{};
  if (origin != null) {
    for (var i = 0; i < days.length; i++) {
      final v = perDay[i][origin];
      if (v != null) byDay[_dayKey(days[i])] = v.value;
    }
  }
  return deviationForSeries(
    byDay: byDay,
    today: _dayKey(days.last),
    factor: factor,
    source: ReadinessSource.healthConnect,
    rules: rules,
    origin: origin,
  );
}

/// HRV-Abweichung aus Health Connect (PAR-160, PAR-161, PAR-189). [days] sind
/// aufeinanderfolgende Ortstage (29: 28 Referenztage und heute als letzter,
/// nicht leer). Die Quell-App wählt PAR-189 über alle [days].
DeviationResult healthConnectHrvDeviation({
  required HealthProcessing processing,
  required Iterable<HealthSample> samples,
  required Iterable<SleepSession> sessions,
  required List<DayRange> days,
}) => _healthConnect(
  p: processing,
  days: days,
  perDay: hrvDayValues(processing, samples, sessions, days),
  factor: ReadinessFactor.hrv,
  rules: DeviationRules.hrv,
);

/// Ruhepuls-Abweichung aus Health Connect (PAR-162, PAR-189), [days] wie bei
/// [healthConnectHrvDeviation].
DeviationResult healthConnectRestingHrDeviation({
  required HealthProcessing processing,
  required Iterable<HealthSample> samples,
  required List<DayRange> days,
}) => _healthConnect(
  p: processing,
  days: days,
  perDay: restingHeartRateDayValues(processing, samples, days),
  factor: ReadinessFactor.restingHeartRate,
  rules: DeviationRules.restingHeartRate,
);

/// RMSSD der Messung, wenn sie für die Reihe zählt (PAR-160K): Qualität „gut“,
/// Zeitrauschen unter der Grenze, Bereich 1–200 ms. Speicherung und Bau einer
/// Messung prüfen das schon, dies sichert die Regel an der Quelle der Reihe.
double? _validRmssd(MorningMeasurement m) {
  final v = m.rmssdMs;
  final noise = m.timingNoiseMs;
  if (v == null ||
      !v.isFinite ||
      m.quality != PpgQuality.good ||
      noise == null ||
      noise > morningRmssdTimingNoiseLimitMs ||
      v < morningRmssdMinMs ||
      v > morningRmssdMaxMs) {
    return null;
  }
  return v;
}

double? _validRestingHr(MorningMeasurement m) {
  final v = m.roundedRestingHr;
  if (!v.isFinite || v < morningRestingHrMinBpm || v > morningRestingHrMaxBpm) {
    return null;
  }
  return v;
}

/// Kamera-Abweichungen (PAR-160K bis PAR-162K) für [today] (Ortstag als
/// UTC-Datum), je Faktor und Reihe (Haltung und Gerät) ein Ergebnis; nie
/// gemischt, nie mit Health Connect. Es zählt die erste Messung des Ortstags
/// im Morgenfenster ([countingMorningMeasurements]). Ruhepuls bei „gut“ oder
/// „eingeschränkt“, RMSSD nur bei „gut“ und unter der Qualitätsgrenze. Das
/// Merkmal „vor der Validierung gemessen“ ändert nichts (K62 Punkt 6). Die
/// Freigabe je Faktor (Sperre) ist nicht Teil davon.
List<DeviationResult> cameraDeviations(
  Iterable<MorningMeasurement> all, {
  required DateTime today,
}) {
  final out = <DeviationResult>[];
  morningSeries(all).forEach((key, list) {
    for (final (factor, rules, pick) in [
      (ReadinessFactor.hrv, DeviationRules.cameraHrv, _validRmssd),
      (
        ReadinessFactor.restingHeartRate,
        DeviationRules.cameraRestingHeartRate,
        _validRestingHr,
      ),
    ]) {
      final byDay = <DateTime, double>{};
      for (final m in list) {
        final v = pick(m);
        if (v != null) byDay[morningLocalDay(m)] = v;
      }
      out.add(
        deviationForSeries(
          byDay: byDay,
          today: today,
          factor: factor,
          source: ReadinessSource.camera,
          rules: rules,
          cameraSeries: key,
        ),
      );
    }
  });
  return out;
}
