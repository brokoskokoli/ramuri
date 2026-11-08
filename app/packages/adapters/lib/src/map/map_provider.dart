/// Art der Ressource, die der Kartenanbieter liefert (Zählung im Tor, R008 Hinweis 8).
enum MapResource { style, tilejson, sprite, glyph, tile }

/// Der Kartenanbieter an einer Stelle (R008 Hinweis 6): Host-Liste, Stil-URL, User-Agent und die
/// Zuordnung eines Pfads zur Ressourcenart. Ein Ausweichanbieter ersetzt nur diese Konfiguration.
class MapProvider {
  const MapProvider({
    required this.allowedHosts,
    required this.styleUri,
    required this.classify,
    this.userAgent = 'ramuri',
    this.attribution = 'OpenFreeMap © OpenMapTiles Data from OpenStreetMap',
  });

  /// Nur diese Hosts (ohne Port, Kleinschreibung) dürfen angefragt werden.
  final Set<String> allowedHosts;
  final Uri styleUri;

  /// Ordnet einen Pfad einer Ressourcenart zu; `null` heißt unbekannt und wird abgelehnt.
  final MapResource? Function(Uri uri) classify;

  /// Nur der App-Name, keine Kennung (ADR-0009 Punkt 2).
  final String userAgent;
  final String attribution;

  static const String openFreeMapHost = 'tiles.openfreemap.org';

  static final MapProvider openFreeMap = MapProvider(
    allowedHosts: const {openFreeMapHost},
    styleUri: Uri.https(openFreeMapHost, '/styles/liberty'),
    classify: _classifyOpenFreeMap,
  );

  static MapResource? _classifyOpenFreeMap(Uri u) {
    final p = u.path;
    if (p.startsWith('/styles/')) return MapResource.style;
    if (p.startsWith('/sprites/')) return MapResource.sprite;
    if (p.startsWith('/fonts/')) return MapResource.glyph;
    if (p.startsWith('/planet/') &&
        (p.endsWith('.pbf') || p.endsWith('.mvt'))) {
      return MapResource.tile;
    }
    if (p == '/planet') return MapResource.tilejson;
    return null;
  }
}
