import 'package:core/core.dart';

/// Markierung des Kamera-RMSSD auf der Seite Morgenwerte (K-1, PAR-171K und
/// Validierungssperre). Es gibt einen Stand für das Verfahren, keinen je
/// Haltung und kein Opt-in (K67).
enum MorningRmssdMark {
  /// Keine Markierung (Entwicklermodus: gilt als gültig, K62 Punkt 6).
  none,

  /// lnRMSSD bestanden: „experimentell, mit einem Brustgurt verglichen“.
  experimental,

  /// „eingeschränkt“ oder „nicht bestanden“: „ungenauer als erwartet“.
  inaccurate,

  /// Validierung nicht gelaufen: „noch nicht geprüft“.
  notChecked,
}

/// Was die Seite zeigt.
class MorningTrendMarks {
  const MorningTrendMarks({required this.rmssd, required this.hrInaccurate});

  final MorningRmssdMark rmssd;

  /// Ruhepuls „nicht bestanden“: „ungenauer als erwartet“.
  final bool hrInaccurate;

  /// RMSSD wird gezeigt, geht aber in nichts ein (gesperrt oder ungeprüft):
  /// gedämpft gezeichnet.
  bool get rmssdLocked =>
      rmssd == MorningRmssdMark.inaccurate ||
      rmssd == MorningRmssdMark.notChecked;
}

/// Markierungen aus dem Stand des Verfahrens, für beide Haltungen gleich. Im
/// Entwicklermodus keine Markierung.
MorningTrendMarks morningTrendMarks({
  required bool developerMode,
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) {
  if (developerMode) {
    return const MorningTrendMarks(
      rmssd: MorningRmssdMark.none,
      hrInaccurate: false,
    );
  }
  final rmssd = switch (state[ValidationQuantity.lnRmssdSupine]) {
    ValidationState.passed => MorningRmssdMark.experimental,
    ValidationState.limited ||
    ValidationState.failed => MorningRmssdMark.inaccurate,
    _ => MorningRmssdMark.notChecked,
  };
  return MorningTrendMarks(
    rmssd: rmssd,
    hrInaccurate: state[ValidationQuantity.restingHr] == ValidationState.failed,
  );
}

/// Ein Tag der Reihe; [posture] ist die Haltung der zählenden Messung (K67,
/// der Punkt wird danach markiert).
typedef MorningDayValue = ({
  int dayIndex,
  double value,
  RestingPosture posture,
});

/// Werte der letzten [days] Ortstage bis heute (Index 0 = ältester Tag,
/// `days - 1` = heute) aus den zählenden Messungen der Reihe des Geräts (beide
/// Haltungen, K67); nur Tage mit Wert, nach Tag. [pick] wählt die Größe (Ruhepuls oder
/// RMSSD, `null` = kein Wert an dem Tag).
List<MorningDayValue> morningTrendValues(
  Iterable<MorningMeasurement> all, {
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
      morningSeries(all)[MorningSeriesKey(manufacturer, model)] ??
      const <MorningMeasurement>[];
  final out = <MorningDayValue>[];
  for (final m in series) {
    final back = today.difference(morningLocalDay(m)).inDays;
    final v = pick(m);
    if (back < 0 || back >= days || v == null) continue;
    out.add((dayIndex: days - 1 - back, value: v, posture: m.posture));
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

/// Eine Zeile der Liste „Letzte Messungen“.
enum MorningRowStatus {
  /// Zählt (erste gültige Messung des Morgens).
  counts,

  /// Außerhalb des Morgenfensters.
  outside,

  /// Gültig, aber an diesem Morgen zählt eine frühere.
  later,

  /// Unbrauchbar (nur im Entwicklermodus gespeichert, K68).
  unusable,
}

typedef MorningRow = ({MorningMeasurement m, MorningRowStatus status});

/// Die letzten [limit] Messungen des Geräts, neueste zuerst, mit Status.
/// Unbrauchbare nur im Entwicklermodus. Welche zählt, entscheidet allein
/// [countingMorningMeasurements].
List<MorningRow> morningRecentRows(
  Iterable<MorningMeasurement> all, {
  required String manufacturer,
  required String model,
  required bool developerMode,
  int limit = 7,
}) {
  final counting = Set<MorningMeasurement>.identity()
    ..addAll(countingMorningMeasurements(all));
  final rows = [
    for (final m in all)
      if (m.deviceManufacturer == manufacturer &&
          m.deviceModel == model &&
          (developerMode || m.isUsable))
        (
          m: m,
          status: !m.isUsable
              ? MorningRowStatus.unusable
              : counting.contains(m)
              ? MorningRowStatus.counts
              : m.outsideWindow
              ? MorningRowStatus.outside
              : MorningRowStatus.later,
        ),
  ]..sort((a, b) => b.m.measuredAt.compareTo(a.m.measuredAt));
  return rows.take(limit).toList();
}
