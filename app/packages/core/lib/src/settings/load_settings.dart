import '../../ports/storage_settings.dart';
import '../fitness/banister_trimp.dart';
import '../fitness/load_profile.dart';
import 'display_settings.dart';

/// Einstellungen des Belastungsprofils (FR-0197, FR-0002, FR-0103), alle mit
/// Präfix `load.`. Lesen ist tolerant: fehlt ein Eintrag oder ist er
/// unbekannt, gilt der Start (Edwards, keine Koeffizienten, keine Zusage).
/// Das aktive Profil wechselt nur über die Neuberechnung
/// (`RecalculationService.requestLoadProfile`, OQ-0053); [writeActiveProfile]
/// ist dafür da und wird von der Oberfläche nicht direkt aufgerufen.
abstract final class LoadSettings {
  static Future<LoadProfile> activeProfile(SettingsStore store) async =>
      LoadProfile.fromStorage(await store.get(SettingKeys.loadProfile));

  static Future<LoadCoefficients?> coefficients(SettingsStore store) async =>
      LoadCoefficients.fromStorage(
        await store.get(SettingKeys.loadCoefficients),
      );

  /// Speichert die Koeffizienten-Angabe; `null` entfernt sie (leerer Wert).
  /// Ändert nichts an gespeicherten Werten: ein Banister-Profil bietet danach
  /// `RecalculationService.loadBasisChanged` an.
  static Future<void> saveCoefficients(
    SettingsStore store,
    LoadCoefficients? value, {
    required DateTime at,
  }) => store.set(
    SettingKeys.loadCoefficients,
    value?.storageValue ?? '',
    at: at,
  );

  static Future<bool> allRecorded(SettingsStore store) async =>
      await store.get(SettingKeys.loadAllRecorded) == '1';

  static Future<void> saveAllRecorded(
    SettingsStore store,
    bool value, {
    required DateTime at,
  }) => store.set(SettingKeys.loadAllRecorded, value ? '1' : '0', at: at);

  /// Das gewählte, noch unbestätigte Profil; `null` ohne offene Wahl oder bei
  /// einem unbekannten Wert.
  static Future<LoadProfile?> pendingProfile(SettingsStore store) async {
    final raw = await store.get(SettingKeys.loadProfilePending);
    for (final p in LoadProfile.values) {
      if (p.name == raw) return p;
    }
    return null;
  }

  static Future<void> writePendingProfile(
    SettingsStore store,
    LoadProfile? value, {
    required DateTime at,
  }) => store.set(SettingKeys.loadProfilePending, value?.name ?? '', at: at);

  static Future<void> writeActiveProfile(
    SettingsStore store,
    LoadProfile value, {
    required DateTime at,
  }) => store.set(SettingKeys.loadProfile, value.name, at: at);
}
