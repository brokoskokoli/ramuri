import '../../ports/storage_settings.dart';
import '../fitness/banister_trimp.dart';
import '../fitness/load_profile.dart';
import 'display_settings.dart';

/// Ein gespeicherter persönlicher Faktor (PAR-087): Profil, Wert, Zahl der
/// Läufe im Median und Tag der Übernahme (lokaler Kalendertag).
class LoadFactorRecord {
  LoadFactorRecord({
    required this.profile,
    required this.value,
    required this.runs,
    required DateTime day,
  }) : day = DateTime.utc(day.year, day.month, day.day);

  final LoadProfile profile;
  final double value;
  final int runs;
  final DateTime day;

  String get storageValue {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${profile.name};$value;$runs;'
        '${day.year.toString().padLeft(4, '0')}-${two(day.month)}-${two(day.day)}';
  }

  /// Unlesbar, unbekanntes Profil oder Wert nicht endlich und positiv: `null`.
  static LoadFactorRecord? parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(';');
    if (parts.length != 4) return null;
    LoadProfile? profile;
    for (final p in LoadProfile.values) {
      if (p.name == parts[0]) profile = p;
    }
    final value = double.tryParse(parts[1]);
    final runs = int.tryParse(parts[2]);
    final day = DateTime.tryParse('${parts[3]}T00:00:00Z');
    if (profile == null ||
        value == null ||
        !value.isFinite ||
        value <= 0 ||
        runs == null ||
        runs < 0 ||
        day == null) {
      return null;
    }
    return LoadFactorRecord(
      profile: profile,
      value: value,
      runs: runs,
      day: day,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoadFactorRecord && other.storageValue == storageValue;

  @override
  int get hashCode => storageValue.hashCode;

  @override
  String toString() => 'LoadFactorRecord(…)';
}

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

  /// Der angewandte Faktor (für das Profil in der Angabe); `null` ohne.
  static Future<LoadFactorRecord?> factor(SettingsStore store) async =>
      LoadFactorRecord.parse(await store.get(SettingKeys.loadFactor));

  static Future<void> writeFactor(
    SettingsStore store,
    LoadFactorRecord? value, {
    required DateTime at,
  }) => store.set(SettingKeys.loadFactor, value?.storageValue ?? '', at: at);

  static Future<LoadFactorRecord?> pendingFactor(SettingsStore store) async =>
      LoadFactorRecord.parse(await store.get(SettingKeys.loadFactorPending));

  static Future<void> writePendingFactor(
    SettingsStore store,
    LoadFactorRecord? value, {
    required DateTime at,
  }) => store.set(
    SettingKeys.loadFactorPending,
    value?.storageValue ?? '',
    at: at,
  );

  static Future<LoadFactorRecord?> declinedFactor(SettingsStore store) async =>
      LoadFactorRecord.parse(await store.get(SettingKeys.loadFactorDeclined));

  static Future<void> writeDeclinedFactor(
    SettingsStore store,
    LoadFactorRecord? value, {
    required DateTime at,
  }) => store.set(
    SettingKeys.loadFactorDeclined,
    value?.storageValue ?? '',
    at: at,
  );
}
