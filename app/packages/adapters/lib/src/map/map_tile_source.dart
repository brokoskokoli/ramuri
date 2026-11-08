import 'dart:convert';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import 'map_gate.dart';

/// Die Kachelquelle konnte nicht entstehen (Netz, Anbieter, Stil). Ohne Text: Ursachen können URLs nennen.
class MapSourceUnavailable implements Exception {
  const MapSourceUnavailable();
  @override
  String toString() => 'MapSourceUnavailable';
}

/// Kachelquelle für die Kartenansicht: der Stil mit allen Anfragen über das [MapGate]. Nur der Kartenadapter kennt
/// die Bibliothek (ADR-0009).
class MapTileSource {
  MapTileSource._(this.gate, this.style);

  final MapGate gate;
  final vt.Style style;

  String get attribution => gate.provider.attribution;

  /// Ebene der Bibliothek ohne Plattencache (`diskCacheMaximumSizeInBytes: 0`, R008 Hinweis 2) und ohne Rasterquellen.
  vt.VectorTileLayer layer({
    Duration fade = const Duration(milliseconds: 150),
  }) => vt.VectorTileLayer(
    theme: style.theme,
    tileProviders: style.providers,
    rasterSources: const {},
    sprites: style.sprites,
    glyphs: style.glyphs,
    diskCacheMaximumSizeInBytes: 0,
    tileFadeDuration: fade,
    labelFadeDuration: fade,
  );

  void dispose() => style.dispose();

  /// Öffnet die Quelle. Ohne Einwilligung entsteht keine Quelle (`null`) und es gibt keine Anfrage (fail-closed,
  /// SEC-0002, SEC-0008). Die Kachelquellen löst `resolveProvider` über das Tor auf; ohne ihn ginge die Bibliothek mit
  /// eigenem Client am Tor vorbei (R008 Hinweis 1).
  static Future<MapTileSource?> open(MapGate gate) async {
    if (!gate.consent()) return null;
    try {
      final c = gate;
      final style = jsonDecode(
        await c.read(gate.provider.styleUri),
      ) as Map<String, dynamic>;
      final templates = <String, (String, int, int)>{};
      for (final e in (style['sources'] as Map).entries) {
        final s = e.value as Map;
        if (s['type'] != 'vector') continue;
        if (s['tiles'] is List) {
          templates[e.key as String] = (
            (s['tiles'] as List).first as String,
            (s['minzoom'] ?? 0) as int,
            (s['maxzoom'] ?? 14) as int,
          );
        } else if (s['url'] is String) {
          final tj =
              jsonDecode(await c.read(Uri.parse(s['url'] as String))) as Map;
          templates[e.key as String] = (
            (tj['tiles'] as List).first as String,
            (tj['minzoom'] ?? 0) as int,
            (tj['maxzoom'] ?? 14) as int,
          );
        }
      }
      final read = await vt.StyleReader(
        uri: gate.provider.styleUri.toString(),
        httpClient: c,
        cache: false,
        resolveProvider: (id) async {
          final t = templates[id];
          if (t == null) return null;
          return vt.NetworkVectorTileProvider(
            urlTemplate: t.$1,
            client: c,
            minimumZoom: t.$2,
            maximumZoom: t.$3,
          );
        },
      ).read();
      return MapTileSource._(gate, read);
    } catch (_) {
      throw const MapSourceUnavailable();
    }
  }
}
