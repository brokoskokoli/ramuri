import '../../ports/clock.dart';
import '../../ports/storage_morning.dart';
import '../../ports/storage_settings.dart';
import '../ppg/ppg_evaluator.dart';
import '../ppg/ppg_parameters.dart';
import '../ppg/validation_status.dart';
import '../profile/resting_hr_origin.dart';
import '../settings/display_settings.dart';
import 'morning_parameters.dart';

/// Morgenfenster (PAR-160K): ganze Stunden Ortszeit, `[startHour, endHour)`, am
/// selben Tag (kein Fenster über Mitternacht).
class MorningWindow {
  const MorningWindow(this.startHour, this.endHour);

  /// Vorgabe 4 bis 11 Uhr.
  static const MorningWindow standard = MorningWindow(
    morningWindowDefaultStartHour,
    morningWindowDefaultEndHour,
  );

  final int startHour;
  final int endHour;

  /// 0 <= Beginn < Ende <= 24.
  bool get isValid => startHour >= 0 && startHour < endHour && endHour <= 24;

  /// Liegt der Zeitpunkt (UTC) mit dem Versatz des Ortes im Fenster? Der
  /// Beginn zählt dazu, das Ende nicht.
  bool contains(DateTime utc, Duration utcOffset) {
    final local = utc.toUtc().add(utcOffset);
    final minutes = local.hour * 60 + local.minute;
    return minutes >= startHour * 60 && minutes < endHour * 60;
  }

  /// `H-H`, sonst `null`.
  static MorningWindow? parse(String? raw) {
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(raw ?? '');
    if (m == null) return null;
    final w = MorningWindow(int.parse(m[1]!), int.parse(m[2]!));
    return w.isValid ? w : null;
  }

  String format() => '$startHour-$endHour';

  @override
  bool operator ==(Object other) =>
      other is MorningWindow &&
      other.startHour == startHour &&
      other.endHour == endHour;

  @override
  int get hashCode => Object.hash(startHour, endHour);

  @override
  String toString() => 'MorningWindow(${format()})';
}

/// Port: Morgenfenster lesen und setzen. Fehlender oder ungültiger Eintrag:
/// [MorningWindow.standard]; ein ungültiges Fenster wird nicht gespeichert
/// (`ArgumentError`).
abstract interface class MorningWindowStore {
  Future<MorningWindow> read();

  Future<void> set(MorningWindow window);
}

/// [MorningWindowStore] auf [SettingsStore] unter [SettingKeys.morningWindow].
class SettingsMorningWindowStore implements MorningWindowStore {
  const SettingsMorningWindowStore(this._settings, this._clock);

  final SettingsStore _settings;
  final Clock _clock;

  @override
  Future<MorningWindow> read() async =>
      MorningWindow.parse(await _settings.get(SettingKeys.morningWindow)) ??
      MorningWindow.standard;

  @override
  Future<void> set(MorningWindow window) {
    if (!window.isValid) throw ArgumentError.value(window, 'window');
    return _settings.set(
      SettingKeys.morningWindow,
      window.format(),
      at: _clock.now(),
    );
  }
}

/// Merkmal "vor der Validierung gemessen" (K62 Punkt 6): solange lnRMSSD
/// liegend nicht "bestanden" ist, der Stand, der die Morgenmessung für alle
/// freigibt. Ändert weder Anzeige noch Rechnung.
bool measuredBeforeValidation({
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) => state[ValidationQuantity.lnRmssdSupine] != ValidationState.passed;

/// Macht aus einem Messergebnis den zu speichernden Datensatz oder `null`, wenn
/// die Messung verworfen wird (PAR-160K):
/// - "unbrauchbar" oder ohne Puls: verworfen, auch im Entwicklermodus;
/// - Ruhepuls außerhalb PAR-017 (30 bis 120): verworfen;
/// - Ruhepuls gilt bei "gut" und "eingeschränkt";
/// - RMSSD nur bei "gut", mit Zeitrauschen bekannt und höchstens
///   [morningRmssdTimingNoiseLimitMs] und im Bereich 1 bis 200 ms, sonst `null`.
/// Der Entwicklermodus ändert nichts daran (die Grenze gilt je Messung); er
/// ändert nur, ob die Messung erreichbar ist ([morningMeasurementReachable]).
/// [measuredAt] ist UTC. Außerhalb des Fensters wird gespeichert, aber mit
/// `outsideWindow` markiert (zählt nicht).
MorningMeasurement? buildMorningMeasurement({
  required PpgMeasurement result,
  required DateTime measuredAt,
  required Duration utcOffset,
  required RestingPosture posture,
  required String deviceManufacturer,
  required String deviceModel,
  MorningWindow window = MorningWindow.standard,
  SleepBand? sleepBand,
  Map<ValidationQuantity, ValidationState> validationState = ppgValidationState,
}) {
  if (result.quality == PpgQuality.unusable) return null;
  final hr = result.bpm;
  if (hr == null ||
      !hr.isFinite ||
      hr < morningRestingHrMinBpm ||
      hr > morningRestingHrMaxBpm) {
    return null;
  }
  final noise = result.timingNoiseMs;
  final rmssd = result.rmssdMs;
  final rmssdValid =
      result.quality == PpgQuality.good &&
      rmssd != null &&
      rmssd.isFinite &&
      rmssd >= morningRmssdMinMs &&
      rmssd <= morningRmssdMaxMs &&
      noise != null &&
      noise <= morningRmssdTimingNoiseLimitMs;
  return MorningMeasurement(
    measuredAt: measuredAt.toUtc(),
    utcOffset: utcOffset,
    posture: posture,
    deviceManufacturer: deviceManufacturer,
    deviceModel: deviceModel,
    method: ppgMethod,
    methodVersion: ppgMethodVersion,
    quality: result.quality,
    restingHrBpm: hr,
    rmssdMs: rmssdValid ? rmssd : null,
    timingNoiseMs: noise,
    sleepBand: sleepBand,
    cameraIntervalsMs: List.of(result.intervalsMs),
    beforeValidation: measuredBeforeValidation(state: validationState),
    outsideWindow: !window.contains(measuredAt, utcOffset),
  );
}

/// Stunden der Schlafstufe für PAR-165 (4,5 / 5,5 / 6,5 / 7,5 / 8,5).
double sleepBandHours(SleepBand band) => morningSleepBandHours[band.index];

/// Ortstag der Messung als UTC-Datum ohne Uhrzeit.
DateTime morningLocalDay(MorningMeasurement m) {
  final local = m.measuredAt.toUtc().add(m.utcOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Die Messungen, die zählen: je Ortstag die erste Messung im Morgenfenster
/// (PAR-160K), unabhängig von Haltung und Gerät; Qualität ist bei gespeicherten
/// Messungen immer ausreichend. Nach Zeitpunkt sortiert.
List<MorningMeasurement> countingMorningMeasurements(
  Iterable<MorningMeasurement> all,
) {
  final sorted = all.where((m) => !m.outsideWindow).toList()
    ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  final seen = <DateTime>{};
  return [
    for (final m in sorted)
      if (seen.add(morningLocalDay(m))) m,
  ];
}

/// Darf heute (Ortstag von [nowUtc] mit [utcOffset]) wiederholt werden? Nur,
/// solange heute noch keine gültige Messung vorliegt.
bool morningRepeatAllowed(
  Iterable<MorningMeasurement> all, {
  required DateTime nowUtc,
  required Duration utcOffset,
}) {
  final local = nowUtc.toUtc().add(utcOffset);
  final today = DateTime.utc(local.year, local.month, local.day);
  return !countingMorningMeasurements(all)
      .any((m) => morningLocalDay(m) == today);
}

/// Schlüssel einer Reihe: Haltung und Gerät (PAR-160K), nie gemischt, nie
/// mit Health Connect. Stehend gibt es nicht ([RestingPosture] kennt es nicht).
class MorningSeriesKey {
  const MorningSeriesKey(this.posture, this.manufacturer, this.model);

  final RestingPosture posture;
  final String manufacturer;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is MorningSeriesKey &&
      other.posture == posture &&
      other.manufacturer == manufacturer &&
      other.model == model;

  @override
  int get hashCode => Object.hash(posture, manufacturer, model);

  @override
  String toString() => 'MorningSeriesKey($posture)';
}

/// Zählende Messungen nach Reihe (Haltung, Gerät), je Reihe nach Zeitpunkt.
Map<MorningSeriesKey, List<MorningMeasurement>> morningSeries(
  Iterable<MorningMeasurement> all,
) {
  final out = <MorningSeriesKey, List<MorningMeasurement>>{};
  for (final m in countingMorningMeasurements(all)) {
    out
        .putIfAbsent(
          MorningSeriesKey(m.posture, m.deviceManufacturer, m.deviceModel),
          () => [],
        )
        .add(m);
  }
  return out;
}

/// Sichtbarkeit gespeicherter Messungen: nur wenn die Morgenmessung erreichbar
/// ist ([morningMeasurementReachable]); sonst nichts, ohne zu löschen.
List<T> visibleMorningMeasurements<T>(
  List<T> stored, {
  required bool developerMode,
  Map<ValidationQuantity, ValidationState> state = ppgValidationState,
}) => morningMeasurementReachable(developerMode: developerMode, state: state)
    ? stored
    : const [];
