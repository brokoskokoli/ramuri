/// Einstellungen als Schlüssel und Text. Die Schlüssel legen die jeweiligen
/// Pakete fest (WP05 Zonen und Einheiten, WP06 Autopause).
abstract interface class SettingsStore {
  Future<String?> get(String key);

  Future<Map<String, String>> all();

  /// Legt an oder überschreibt.
  Future<void> set(String key, String value, {required DateTime at});
}
