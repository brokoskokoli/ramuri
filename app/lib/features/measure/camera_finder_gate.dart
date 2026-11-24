import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'camera_finder_screen.dart';

/// Vor einer Kamera-Messung (Ruhepuls FR-0214, Morgenmessung FR-0215; FR-0220): Braucht es die
/// Kamerasuche ([needsPpgCameraFinder]: mehr als eine nutzbare Kamera, kein gültiges Ergebnis,
/// im Entwicklermodus keine gültige Wahl von Hand), öffnet sie über [context] die Seite „Kamera
/// finden“ für die Messung. Das Kamera-Recht fragt die Seite selbst an. `true` = die Messung
/// beginnt (keine Suche nötig oder Kamera gespeichert), `false` = Zurück: nichts gespeichert,
/// keine Messung.
Future<bool> runCameraFinderBeforeMeasurement(
  BuildContext context, {
  required PpgCamera camera,
  required SettingsStore settings,
  required Clock clock,
}) async {
  final developerMode = SettingsDeveloperModeStore(settings, clock).read;
  final choice = SettingsPpgCameraChoiceStore(settings, clock);
  final needed = await needsPpgCameraFinder(
    camera: camera,
    developerMode: developerMode,
    choice: choice,
  );
  if (!needed) return true;
  bool dev;
  try {
    dev = await developerMode();
  } catch (_) {
    dev = false;
  }
  if (!context.mounted) return false;
  final ref = await Navigator.of(context).push<PpgCameraRef>(
    MaterialPageRoute(
      builder: (_) => CameraFinderScreen(
        camera: camera,
        choice: choice,
        developerMode: dev,
        purpose: CameraFinderPurpose.measurement,
      ),
    ),
  );
  return ref != null;
}
