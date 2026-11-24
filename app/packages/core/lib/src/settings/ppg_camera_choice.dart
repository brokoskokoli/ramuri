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

/// Ob vor einer Kamera-Messung (Ruhepuls FR-0214, Morgenmessung FR-0215) die Kamerasuche
/// erscheint (FR-0220): nur bei mehr als einer nutzbaren Kamera in [cameras] und ohne
/// gültiges Ergebnis der Suche ([auto] in [cameras] vorhanden und nutzbar). Im
/// Entwicklermodus mit gültiger Wahl von Hand ([manual]) entfällt sie ebenfalls.
bool ppgCameraFinderNeeded({
  required List<PpgCameraInfo> cameras,
  required bool developerMode,
  required PpgCameraRef? manual,
  required PpgCameraRef? auto,
}) {
  bool usable(PpgCameraRef? ref) =>
      ref != null && cameras.any((c) => c.ref == ref && c.usable);
  if (cameras.where((c) => c.usable).length < 2) return false;
  if (developerMode && usable(manual)) return false;
  return !usable(auto);
}

/// Liest Entwicklermodus, Kamerawahl und Kameras und wendet [ppgCameraFinderNeeded] an.
/// Scheitert das Lesen, entfällt die Suche (`false`): die Messung läuft dann wie ohne
/// Suchergebnis mit der Kamera nach [choosePpgCamera].
Future<bool> needsPpgCameraFinder({
  required PpgCamera camera,
  required Future<bool> Function() developerMode,
  required PpgCameraChoiceStore choice,
}) async {
  try {
    final dev = await developerMode();
    return ppgCameraFinderNeeded(
      cameras: await camera.cameras(),
      developerMode: dev,
      manual: dev ? await choice.readManual() : null,
      auto: await choice.readAuto(),
    );
  } catch (_) {
    return false;
  }
}

/// Schlüssel des Diagnose-Schalters [d] in [SettingsStore] (FR-0217).
String ppgDiagnosticSettingKey(PpgCameraDiagnostic d) => switch (d) {
  PpgCameraDiagnostic.noiseReductionOff => SettingKeys.ppgDiagNoiseReductionOff,
  PpgCameraDiagnostic.edgeOff => SettingKeys.ppgDiagEdgeOff,
  PpgCameraDiagnostic.awbFixed => SettingKeys.ppgDiagAwbFixed,
  PpgCameraDiagnostic.tonemapLinear => SettingKeys.ppgDiagTonemapLinear,
  PpgCameraDiagnostic.shadingOff => SettingKeys.ppgDiagShadingOff,
};

/// Port: Diagnose-Schalter der Kamera-Bildverarbeitung (FR-0217) lesen und
/// setzen. Vorgabe jeweils aus.
abstract interface class PpgCameraDiagnosticsStore {
  /// Die eingeschalteten Schalter.
  Future<Set<PpgCameraDiagnostic>> read();

  Future<void> set(PpgCameraDiagnostic diagnostic, {required bool on});
}

/// Schalter in [SettingsStore] unter [ppgDiagnosticSettingKey] als `1` (an)
/// bzw. leer (aus; der Speicher kennt kein Entfernen). Geräteeinstellungen wie
/// die Kamerawahl: kein Archivinhalt (`archiveExcludedSettingKeys`), `deleteAll`
/// setzt sie zurück. Jeder andere Wert gilt als aus.
class SettingsPpgCameraDiagnosticsStore implements PpgCameraDiagnosticsStore {
  const SettingsPpgCameraDiagnosticsStore(this._settings, this._clock);

  final SettingsStore _settings;
  final Clock _clock;

  @override
  Future<Set<PpgCameraDiagnostic>> read() async => {
    for (final d in PpgCameraDiagnostic.values)
      if (await _settings.get(ppgDiagnosticSettingKey(d)) == '1') d,
  };

  @override
  Future<void> set(PpgCameraDiagnostic diagnostic, {required bool on}) =>
      _settings.set(
        ppgDiagnosticSettingKey(diagnostic),
        on ? '1' : '',
        at: _clock.now(),
      );
}

/// Was die Morgenmessung (FR-0215) beim Start von der Kamera anfordert
/// (FR-0217): im Entwicklermodus die ISP-Werte je Bild und die eingeschalteten
/// Diagnose-Schalter, sonst nichts (Vorgabe). Scheitert das Lesen, gilt die
/// Vorgabe, damit die Messung wie ohne Diagnose läuft. Ruhepulsmessung
/// (FR-0214) und Kamerasuche rufen das nicht auf.
Future<({Set<PpgCameraDiagnostic> diagnostics, bool ispFrames})>
morningCameraDiagnostics({
  required Future<bool> Function() developerMode,
  required PpgCameraDiagnosticsStore store,
}) async {
  try {
    if (!await developerMode()) {
      return (diagnostics: const <PpgCameraDiagnostic>{}, ispFrames: false);
    }
    return (diagnostics: await store.read(), ispFrames: true);
  } catch (_) {
    return (diagnostics: const <PpgCameraDiagnostic>{}, ispFrames: false);
  }
}
