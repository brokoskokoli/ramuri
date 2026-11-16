import '../../ports/clock.dart';
import '../../ports/ppg_camera.dart' show PpgCameraDetails;
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
/// - "unbrauchbar" oder ohne Puls: verworfen;
/// - Ruhepuls außerhalb PAR-017 (30 bis 120): unbrauchbar, also verworfen;
/// - Ruhepuls gilt bei "gut" und "eingeschränkt";
/// - RMSSD nur bei "gut", mit Zeitrauschen bekannt und höchstens
///   [morningRmssdTimingNoiseLimitMs] und im Bereich 1 bis 200 ms, sonst `null`.
/// Der Entwicklermodus ändert nichts daran (die Grenze gilt je Messung); er
/// ändert nur, ob die Messung erreichbar ist ([morningMeasurementReachable]).
/// [measuredAt] ist UTC. Außerhalb des Fensters wird gespeichert, aber mit
/// `outsideWindow` markiert (zählt nicht).
///
/// [keepUnusable] (nur Entwicklermodus, K68): eine unbrauchbare Messung wird
/// nicht verworfen, sondern als Stufe `unusable` mit Grund, ohne Puls, RMSSD und
/// Zeitrauschen und mit den Kamera-Schlagabständen zurückgegeben; sie zählt
/// nirgends. Das gilt auch für einen Ruhepuls außerhalb PAR-017 (Grund
/// [MorningUnusableReason.restingHrOutOfRange]); der Puls wird nicht
/// übernommen. [windowStartS], [windowEndS] (gewähltes Fenster, K66) und
/// [restSkippedAfterS] (Ruhephase übersprungen nach s) gehen unverändert an die
/// Messung.
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
  double? windowStartS,
  double? windowEndS,
  double? restSkippedAfterS,
  bool keepUnusable = false,
}) {
  MorningMeasurement? unusable(MorningUnusableReason? reason) {
    if (!keepUnusable) return null;
    return MorningMeasurement(
      measuredAt: measuredAt.toUtc(),
      utcOffset: utcOffset,
      posture: posture,
      deviceManufacturer: deviceManufacturer,
      deviceModel: deviceModel,
      method: ppgMethod,
      methodVersion: ppgMethodVersion,
      quality: PpgQuality.unusable,
      unusableReason: reason,
      sleepBand: sleepBand,
      cameraIntervalsMs: List.of(result.intervalsMs),
      beforeValidation: measuredBeforeValidation(state: validationState),
      outsideWindow: !window.contains(measuredAt, utcOffset),
      windowStartS: windowStartS,
      windowEndS: windowEndS,
      restSkippedAfterS: restSkippedAfterS,
    );
  }

  if (result.quality == PpgQuality.unusable) {
    return unusable(
      result.reasons.isEmpty
          ? null
          : MorningUnusableReason.fromPpg(result.reasons.first),
    );
  }
  final hr = result.bpm;
  if (hr == null || !hr.isFinite) return null;
  if (hr < morningRestingHrMinBpm || hr > morningRestingHrMaxBpm) {
    return unusable(MorningUnusableReason.restingHrOutOfRange);
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
    windowStartS: windowStartS,
    windowEndS: windowEndS,
    restSkippedAfterS: restSkippedAfterS,
  );
}

/// Kamera-Rohsignal einer Messung aus den Bildern der Aufnahme (K70, nur
/// Entwicklermodus): die Bilder unverändert, dazu Anzahl und Gesamtdauer der
/// Bildlücken (Abstand über [ppgMaxFrameGapSeconds], die Grenze der
/// Auswertung). Die übrigen Kamera-Angaben (Belichtung, ISO, Zeitstempelquelle,
/// Rolling-Shutter-Versatz, Torch-Stärke, gesättigter Anteil) kommen vom Adapter
/// als [details]; fehlen sie oder liefert das Gerät einzelne nicht, sind sie `null`.
MorningRawSignal buildMorningRawSignal(
  List<PpgFrame> frames, {
  PpgCameraDetails? details,
}) {
  var gaps = 0;
  var total = 0.0;
  for (var i = 1; i < frames.length; i++) {
    final d = frames[i].t - frames[i - 1].t;
    if (d > ppgMaxFrameGapSeconds) {
      gaps++;
      total += d;
    }
  }
  return MorningRawSignal(
    frames: List.of(frames),
    frameGapCount: gaps,
    frameGapTotalS: total,
    exposureTimeNs: details?.exposureTimeNs,
    iso: details?.iso,
    timestampSource: details?.timestampSource,
    rollingShutterSkewNs: details?.rollingShutterSkewNs,
    torchStrength: details?.torchStrength,
    saturatedFraction: details?.saturatedFraction,
  );
}

/// Stunden der Schlafstufe für PAR-165 (4,5 / 5,5 / 6,5 / 7,5 / 8,5).
double sleepBandHours(SleepBand band) => morningSleepBandHours[band.index];

/// Ortstag der Messung als UTC-Datum ohne Uhrzeit.
DateTime morningLocalDay(MorningMeasurement m) {
  final local = m.measuredAt.toUtc().add(m.utcOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Schlüssel einer Reihe: das Gerät (PAR-160K, K67), nie mit Health Connect
/// gemischt. Die Haltung gehört nicht dazu: liegend und sitzend bilden eine
/// gemeinsame Reihe, die Haltung bleibt am Punkt gespeichert (Markierung).
/// Stehend gibt es nicht ([RestingPosture] kennt es nicht).
class MorningSeriesKey {
  const MorningSeriesKey(this.manufacturer, this.model);

  /// Reihe, zu der [m] gehört.
  MorningSeriesKey.of(MorningMeasurement m)
    : this(m.deviceManufacturer, m.deviceModel);

  final String manufacturer;
  final String model;

  @override
  bool operator ==(Object other) =>
      other is MorningSeriesKey &&
      other.manufacturer == manufacturer &&
      other.model == model;

  @override
  int get hashCode => Object.hash(manufacturer, model);

  @override
  String toString() => 'MorningSeriesKey';
}

/// Die Messungen, die zählen, an genau dieser Stelle gebildet (K67, K68):
/// je Ortstag und Reihe (Gerät, ohne Haltung) die erste gültige Messung im
/// Morgenfenster; liegend oder sitzend ist gleich, die frühere gewinnt.
/// Unbrauchbare Messungen (nur im Entwicklermodus gespeichert, K68) und
/// Messungen außerhalb des Fensters zählen nirgends. Nach Zeitpunkt sortiert.
/// Alle Leser der Reihe (Trend, Readiness, Plan) gehen durch diese Funktion
/// oder [morningSeries].
List<MorningMeasurement> countingMorningMeasurements(
  Iterable<MorningMeasurement> all,
) {
  final sorted = all.where((m) => m.isUsable && !m.outsideWindow).toList()
    ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
  final seen = <(DateTime, MorningSeriesKey)>{};
  return [
    for (final m in sorted)
      if (seen.add((morningLocalDay(m), MorningSeriesKey.of(m)))) m,
  ];
}

DateTime _localDayOf(DateTime nowUtc, Duration utcOffset) {
  final local = nowUtc.toUtc().add(utcOffset);
  return DateTime.utc(local.year, local.month, local.day);
}

/// Die heute (Ortstag von [nowUtc] mit [utcOffset]) zählenden Messungen aller
/// Geräte, nach Zeitpunkt.
List<MorningMeasurement> morningCountingToday(
  Iterable<MorningMeasurement> all, {
  required DateTime nowUtc,
  required Duration utcOffset,
}) {
  final today = _localDayOf(nowUtc, utcOffset);
  return [
    for (final m in countingMorningMeasurements(all))
      if (morningLocalDay(m) == today) m,
  ];
}

/// Darf heute in der Reihe [series] (Gerät) wiederholt werden? Nur, solange
/// heute in dieser Reihe noch keine gültige Messung vorliegt, gleich in
/// welcher Haltung; andere Geräte zählen nicht.
bool morningRepeatAllowed(
  Iterable<MorningMeasurement> all, {
  required DateTime nowUtc,
  required Duration utcOffset,
  required MorningSeriesKey series,
}) => !morningCountingToday(
  all,
  nowUtc: nowUtc,
  utcOffset: utcOffset,
).any((m) => MorningSeriesKey.of(m) == series);

/// Zählende Messungen nach Reihe (Gerät), je Reihe nach Zeitpunkt; die Haltung
/// steht an jeder Messung ([MorningMeasurement.posture]).
Map<MorningSeriesKey, List<MorningMeasurement>> morningSeries(
  Iterable<MorningMeasurement> all,
) {
  final out = <MorningSeriesKey, List<MorningMeasurement>>{};
  for (final m in countingMorningMeasurements(all)) {
    out.putIfAbsent(MorningSeriesKey.of(m), () => []).add(m);
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
