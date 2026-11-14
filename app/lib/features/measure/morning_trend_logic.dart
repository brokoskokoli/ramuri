import 'package:core/core.dart';

/// Ein Tag der Reihe.
typedef MorningDayValue = ({int dayIndex, double value});

/// Werte der letzten [days] Ortstage bis heute (Index 0 = ältester Tag,
/// `days - 1` = heute) aus den zählenden Messungen der Reihe von [posture] und
/// [device]; nur Tage mit Wert, nach Tag. [pick] wählt die Größe (Ruhepuls oder
/// RMSSD, `null` = kein Wert an dem Tag).
List<MorningDayValue> morningTrendValues(
  Iterable<MorningMeasurement> all, {
  required RestingPosture posture,
  required String manufacturer,
  required String model,
  required DateTime nowUtc,
  required Duration utcOffset,
  required double? Function(MorningMeasurement) pick,
  int days = 14,
}) {
  final local = nowUtc.toUtc().add(utcOffset);
  final today = DateTime.utc(local.year, local.month, local.day);
  final series =
      morningSeries(all)[MorningSeriesKey(posture, manufacturer, model)] ??
      const <MorningMeasurement>[];
  final out = <MorningDayValue>[];
  for (final m in series) {
    final back = today.difference(morningLocalDay(m)).inDays;
    final v = pick(m);
    if (back < 0 || back >= days || v == null) continue;
    out.add((dayIndex: days - 1 - back, value: v));
  }
  return out;
}

/// Mittel der Tage ab Index [fromDay] (für 7 Tage: `days - 7`); `null` ohne Wert.
double? morningTrendMean(List<MorningDayValue> values, {required int fromDay}) {
  final v = [
    for (final e in values)
      if (e.dayIndex >= fromDay) e.value,
  ];
  if (v.isEmpty) return null;
  return v.reduce((a, b) => a + b) / v.length;
}
