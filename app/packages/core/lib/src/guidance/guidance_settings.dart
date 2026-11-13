import '../../ports/clock.dart';
import '../../ports/storage_settings.dart';
import '../settings/display_settings.dart';
import 'guidance_event.dart';

/// Schalter der Ansagen in `settings` (Festlegung 10). Fehlt ein Eintrag,
/// gilt „an“ (Vorgabe); nur `0` schaltet aus.
class GuidanceSettings {
  const GuidanceSettings(this.store);

  final SettingsStore store;

  Future<GuidanceSwitches> load() async {
    Future<bool> on(String key) async => await store.get(key) != '0';
    return GuidanceSwitches(
      enabled: await on(SettingKeys.guidanceEnabled),
      kilometer: await on(SettingKeys.guidanceKilometer),
      heartRate: await on(SettingKeys.guidanceHeartRate),
      segments: await on(SettingKeys.guidanceSegments),
    );
  }

  Future<void> save(GuidanceSwitches s, {required Clock clock}) async {
    final at = clock.now().toUtc();
    Future<void> put(String key, bool v) =>
        store.set(key, v ? '1' : '0', at: at);
    await put(SettingKeys.guidanceEnabled, s.enabled);
    await put(SettingKeys.guidanceKilometer, s.kilometer);
    await put(SettingKeys.guidanceHeartRate, s.heartRate);
    await put(SettingKeys.guidanceSegments, s.segments);
  }
}
