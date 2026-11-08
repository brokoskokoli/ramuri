import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

import 'package:http/http.dart' as http;

import 'map_gate.dart';

/// Leert den prozessweiten Arbeitsspeicher der Kachelbibliothek (dekodierte Kacheln, Beschriftungen). Beim Widerruf
/// und bei "Alles löschen" gerufen, damit nichts vom Kartenanbieter im Speicher des Prozesses bleibt (SEC-0007).
void clearMapTileMemory() => vt.VectorTileLayer.clearMemoryCache();

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

  /// `true`, solange keine Kachel ein Treffer war und mehrere scheiterten: Die Oberfläche zeigt dann die Linie statt
  /// der Karte (siehe [MapGate.tilesFailed]).
  ValueListenable<bool> get tilesFailed => gate.tilesFailed;

  /// Zählt die Kacheln neu (nach einer Pause versucht die Oberfläche die Karte wieder).
  void retryTiles() => gate.resetTileHealth();

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

  /// Gibt die Quelle frei und schließt das Tor samt Verbindungen.
  void dispose() {
    style.dispose();
    gate.close();
  }

  /// Öffnet die Quelle. Ohne Einwilligung entsteht keine Quelle (`null`) und es gibt keine Anfrage (fail-closed,
  /// SEC-0002, SEC-0008). Die Kachelquellen löst `resolveProvider` über das Tor auf; ohne ihn ginge die Bibliothek mit
  /// eigenem Client am Tor vorbei (R008 Hinweis 1).
  static Future<MapTileSource?> open(MapGate gate) async {
    if (!gate.consent()) return null;
    try {
      final c = gate;
      // Der Stil wird einmal geholt (Tor, Speicher, Netz) und dem StyleReader aus dem Arbeitsspeicher gereicht.
      final styleBytes = await c.readBytes(gate.provider.styleUri);
      final style = jsonDecode(utf8.decode(styleBytes)) as Map<String, dynamic>;
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
        httpClient: _StyleOnce(gate.provider.styleUri, styleBytes, c),
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
      gate.close();
      throw const MapSourceUnavailable();
    }
  }
}

/// Reicht die schon geholte Stil-Antwort einmal weiter, alles andere geht an das Tor. So geht der Stil nie zweimal
/// ins Netz, auch wenn der Speicher ihn nicht hält (aus, voll, Fehler).
class _StyleOnce extends http.BaseClient {
  _StyleOnce(this._uri, this._bytes, this._inner);
  final Uri _uri;
  Uint8List? _bytes;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final b = _bytes;
    if (b != null && request.method == 'GET' && request.url == _uri) {
      _bytes = null;
      return http.StreamedResponse(
        Stream.value(b),
        200,
        contentLength: b.length,
        request: request,
      );
    }
    return _inner.send(request);
  }

  @override
  void close() {}
}
