import '../../ports/clock.dart';
import '../../ports/storage_settings.dart';
import 'display_settings.dart';

/// Port: Entwicklermodus lesen und setzen (FR-0217). WP34 und die Morgenmessung
/// lesen ihn hier; die Oberfläche setzt ihn.
abstract interface class DeveloperModeStore {
  Future<bool> read();

  Future<void> set(bool on);
}

/// Entwicklermodus in [SettingsStore] unter [SettingKeys.developerMode].
/// Kein Archivinhalt (siehe `archiveExcludedSettingKeys`); `deleteAll` leert die
/// Einstellungen und damit auch ihn. Fehlt der Eintrag, ist er aus.
class SettingsDeveloperModeStore implements DeveloperModeStore {
  const SettingsDeveloperModeStore(this._settings, this._clock);

  final SettingsStore _settings;
  final Clock _clock;

  @override
  Future<bool> read() async =>
      await _settings.get(SettingKeys.developerMode) == '1';

  @override
  Future<void> set(bool on) => _settings.set(
    SettingKeys.developerMode,
    on ? '1' : '0',
    at: _clock.now(),
  );
}
