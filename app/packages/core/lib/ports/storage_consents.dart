enum ConsentState { granted, revoked }

/// Einwilligungen je Quelle. Fehlt ein Eintrag, gilt nichts als erteilt.
abstract interface class ConsentStore {
  /// `null`, wenn nie gesetzt.
  Future<ConsentState?> get(String sourceKey);

  Future<Map<String, ConsentState>> all();

  Future<void> set(
    String sourceKey,
    ConsentState state, {
    required DateTime at,
  });
}
