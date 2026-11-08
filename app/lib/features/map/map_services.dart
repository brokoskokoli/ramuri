import 'package:adapters/adapters.dart';

/// Verwaltung des Kartenspeichers für die Oberfläche: Größe und Löschen (WP13). Schmale Schnittstelle, damit die App
/// weder Speicher noch Bibliothek kennt und Tests einen Fake einsetzen.
abstract interface class MapCacheAdmin {
  /// Belegte Bytes; wirft, wenn sie nicht zu ermitteln sind.
  Future<int> sizeBytes();

  /// Löscht den Kartenspeicher samt Nebendateien.
  Future<void> delete();
}

/// [MapCacheAdmin] auf dem verschlüsselten Speicher.
class StoreMapCacheAdmin implements MapCacheAdmin {
  const StoreMapCacheAdmin(this._store);
  final EncryptedMapTileStore _store;

  @override
  Future<int> sizeBytes() => _store.sizeBytes();

  @override
  Future<void> delete() => _store.delete();
}

/// Baut das Tor zum Kartenanbieter. [consent] wird bei jeder Anfrage neu gelesen (Widerruf wirkt sofort).
typedef MapGateFactory = MapGate Function(MapConsent consent);

/// Was die Karte der App braucht: Tor und Speicherverwaltung. `null` in [AppDependencies.map]: kein Kartenanbieter
/// verdrahtet (Tests), dann bietet die Oberfläche keine Karte an.
class MapServices {
  const MapServices({
    required this.gate,
    required this.cache,
    this.attribution = '',
    this.thumbnails,
  });

  final MapGateFactory gate;
  final MapCacheAdmin cache;

  /// Quellenangabe des Kartenmaterials (Einstellungen).
  final String attribution;

  /// Miniaturen der Läufe (WP13 D); `null`: keine Miniaturen mit Kartenhintergrund, der Verlauf zeigt die Linie.
  final MapThumbnailStore? thumbnails;

  /// Produktiv: OpenFreeMap über das Tor, Kacheln im verschlüsselten Speicher.
  factory MapServices.production(EncryptedMapTileStore store) => MapServices(
    gate: (consent) => MapGate(
      provider: MapProvider.openFreeMap,
      consent: consent,
      store: store,
    ),
    cache: StoreMapCacheAdmin(store),
    thumbnails: store,
    attribution: MapProvider.openFreeMap.attribution,
  );
}
