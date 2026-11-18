import '../../ports/clock.dart';
import '../../ports/ppg_camera.dart';
import '../../ports/storage_settings.dart';
import 'display_settings.dart';

/// Port: gespeicherte Kamerawahl der Kamera-Messung (FR-0220) lesen, setzen und löschen.
/// [readManual]/[setManual]: Wahl von Hand im Entwicklermodus; [readAuto]/[setAuto]:
/// Ergebnis der Kamerasuche. `null` setzen löscht den Eintrag.
abstract interface class PpgCameraChoiceStore {
  Future<PpgCameraRef?> readManual();

  Future<void> setManual(PpgCameraRef? camera);

  Future<PpgCameraRef?> readAuto();

  Future<void> setAuto(PpgCameraRef? camera);
}

/// Kamerawahl in [SettingsStore] unter [SettingKeys.ppgCameraManual] und
/// [SettingKeys.ppgCameraAuto] als `<cameraId>` bzw. `<cameraId>/<physicalCameraId>`.
/// Geräteeinstellungen: kein Archivinhalt (siehe `archiveExcludedSettingKeys`);
/// `deleteAll` leert die Einstellungen und damit auch sie. Gelöscht wird mit dem
/// leeren Wert (der Speicher kennt kein Entfernen); leer oder unlesbar gilt als
/// nicht gesetzt.
class SettingsPpgCameraChoiceStore implements PpgCameraChoiceStore {
  const SettingsPpgCameraChoiceStore(this._settings, this._clock);

  final SettingsStore _settings;
  final Clock _clock;

  Future<PpgCameraRef?> _read(String key) async =>
      PpgCameraRef.parse(await _settings.get(key));

  Future<void> _set(String key, PpgCameraRef? camera) =>
      _settings.set(key, camera?.key ?? '', at: _clock.now());

  @override
  Future<PpgCameraRef?> readManual() => _read(SettingKeys.ppgCameraManual);

  @override
  Future<void> setManual(PpgCameraRef? camera) =>
      _set(SettingKeys.ppgCameraManual, camera);

  @override
  Future<PpgCameraRef?> readAuto() => _read(SettingKeys.ppgCameraAuto);

  @override
  Future<void> setAuto(PpgCameraRef? camera) =>
      _set(SettingKeys.ppgCameraAuto, camera);
}

/// Welche Kamera eine Kamera-Messung (Ruhepuls FR-0214, Morgenmessung FR-0215) nutzt
/// (FR-0220): Entwicklermodus an und Wahl von Hand ([manual]) in [cameras] vorhanden und
/// nutzbar → diese; sonst das Ergebnis der Kamerasuche ([auto]), wenn in [cameras]
/// vorhanden und nutzbar → dieses; sonst die Standardkamera. Ohne Entwicklermodus gilt
/// [manual] nicht (bleibt aber gespeichert).
///
/// Ergebnis `null` heißt Standardkamera: [PpgCamera.start] ohne Angabe, wie vor FR-0220.
PpgCameraRef? resolvePpgCamera({
  required List<PpgCameraInfo> cameras,
  required bool developerMode,
  required PpgCameraRef? manual,
  required PpgCameraRef? auto,
}) {
  bool usable(PpgCameraRef? ref) =>
      ref != null && cameras.any((c) => c.ref == ref && c.usable);
  if (developerMode && usable(manual)) return manual;
  if (usable(auto)) return auto;
  return null;
}

/// Liest Entwicklermodus und Kamerawahl und wendet [resolvePpgCamera] an. Die Liste der
/// Kameras wird nur geholt, wenn eine gespeicherte Wahl gelten könnte; sonst (und wenn
/// das Lesen scheitert) gilt die Standardkamera (`null`).
Future<PpgCameraRef?> choosePpgCamera({
  required PpgCamera camera,
  required Future<bool> Function() developerMode,
  required PpgCameraChoiceStore choice,
}) async {
  try {
    final dev = await developerMode();
    final manual = dev ? await choice.readManual() : null;
    final auto = await choice.readAuto();
    if (manual == null && auto == null) return null;
    return resolvePpgCamera(
      cameras: await camera.cameras(),
      developerMode: dev,
      manual: manual,
      auto: auto,
    );
  } catch (_) {
    return null;
  }
}
