import 'package:core/core.dart';

/// Markierung des Kamera-RMSSD auf der Seite Morgenwerte (K-1, PAR-171K und
/// Validierungssperre).
enum MorningRmssdMark {
  /// Keine Markierung (Entwicklermodus: gilt als gültig, K62 Punkt 6).
  none,

  /// lnRMSSD bestanden, Opt-in aus: „experimentell, nicht eingeschaltet“.
  notEnabled,

  /// Opt-in an, liegend: „experimentell, mit einem Brustgurt verglichen“.
  optIn,

  /// Opt-in an, sitzend: „experimentell, liegend verglichen“ (E6).
  optInSitting,

  /// „eingeschränkt“ oder „nicht bestanden“: „ungenauer als erwartet“.
  inaccurate,

  /// Validierung nicht gelaufen: „noch nicht geprüft“.
  notChecked,
}

/// Was die Seite je Reihe zeigt.
class MorningTrendMarks {
  const MorningTrendMarks({
    required this.rmssd,
    required this.hrInaccurate,
    required this.optInVisible,
  });

  final MorningRmssdMark rmssd;

  /// Ruhepuls „nicht bestanden“: „ungenauer als erwartet“.
  final bool hrInaccurate;

  /// Opt-in-Schalter nur bei „bestanden“, nie im Entwicklermodus.
  final bool optInVisible;

  /// RMSSD wird gezeigt, geht aber in nichts ein (gesperrt, nicht
  /// eingeschaltet oder ungeprüft): gedämpft gezeichnet.
  bool get rmssdLocked =>
      rmssd == MorningRmssdMark.notEnabled ||
      rmssd == MorningRmssdMark.inaccurate ||
      rmssd == MorningRmssdMark.notChecked;
}

/// Markierungen für die Haltung [posture]. Im Entwicklermodus keine Markierung
/// und kein Opt-in. Sonst gilt für RMSSD der Stand von lnRMSSD liegend; sitzend
/// gilt er mit, solange die Validierung im Sitzen nicht „eingeschränkt“ oder
/// „nicht bestanden“ ergab (dann gesperrt, E6).
MorningTrendMarks morningTrendMarks({
  required bool developerMode,
  required RestingPosture posture,
  required bool optIn,
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) {
  if (developerMode) {
    return const MorningTrendMarks(
      rmssd: MorningRmssdMark.none,
      hrInaccurate: false,
      optInVisible: false,
    );
  }
  final supine = state[ValidationQuantity.lnRmssdSupine];
  final sitting = state[ValidationQuantity.lnRmssdSitting];
  final eff =
      posture == RestingPosture.sitting &&
          (sitting == ValidationState.limited ||
              sitting == ValidationState.failed)
      ? sitting
      : supine;
  final lying = posture == RestingPosture.lying;
  final rmssd = switch (eff) {
    ValidationState.passed =>
      !optIn
          ? MorningRmssdMark.notEnabled
          : lying
          ? MorningRmssdMark.optIn
          : MorningRmssdMark.optInSitting,
    ValidationState.limited ||
    ValidationState.failed => MorningRmssdMark.inaccurate,
    _ => MorningRmssdMark.notChecked,
  };
  return MorningTrendMarks(
    rmssd: rmssd,
    hrInaccurate: state[ValidationQuantity.restingHr] == ValidationState.failed,
    optInVisible: eff == ValidationState.passed,
  );
}

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
