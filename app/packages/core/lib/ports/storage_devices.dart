class KnownDevice {
  const KnownDevice({
    required this.deviceId,
    required this.addedAt,
    this.displayName,
    this.isPreferred = false,
    this.lastUsedAt,
  });

  /// Plattformkennung (Adresse, ADR-0006).
  final String deviceId;
  final String? displayName;
  final bool isPreferred;
  final DateTime addedAt;

  /// Zeitpunkt der letzten erfolgreichen Verbindung (UTC); `null` = nie
  /// genutzt. Grundlage der Gurt-Autoverbindung.
  final DateTime? lastUsedAt;
}

/// Bekannte Pulssensoren (FR-0013, FR-0014).
abstract interface class KnownDeviceStore {
  /// Nach Hinzufügen sortiert.
  Future<List<KnownDevice>> list();

  /// Legt das Gerät an oder ändert nur den Anzeigenamen (`addedAt` und die
  /// Bevorzugung bleiben). Ein `null` als Name lässt den vorhandenen stehen.
  Future<void> upsert(
    String deviceId, {
    String? displayName,
    required DateTime at,
  });

  /// Macht das Gerät zum einzigen bevorzugten, `null` hebt die Festlegung auf.
  /// Unbekanntes Gerät: `notFound`, nichts ändert sich.
  Future<void> setPreferred(String? deviceId);

  /// Vermerkt, dass das Gerät zu [at] erfolgreich genutzt wurde
  /// (`lastUsedAt`); sonst bleibt alles. Unbekanntes Gerät: `notFound`.
  Future<void> markUsed(String deviceId, {required DateTime at});
}
