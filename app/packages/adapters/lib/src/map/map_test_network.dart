// Nur für Tests: synthetisches Netz hinter dem Kartentor. Kein Produktivcode importiert diese Datei; sie ist über
// `package:adapters/map_testing.dart` erreichbar, nicht über `adapters.dart`.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;

import 'map_provider.dart';

/// 1x1-PNG für den Sprite (die Bibliothek dekodiert ihn).
final Uint8List png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const host = MapProvider.openFreeMapHost;

/// Kleiner, synthetischer Stil: Vektorquelle über TileJSON, eine Rasterquelle (muss entfernt werden), Sprite, Glyphen.
Map<String, Object?> styleJson() => {
  'version': 8,
  'name': 'Test',
  'sprite': 'https://$host/sprites/test/sprite',
  'glyphs': 'https://$host/fonts/{fontstack}/{range}.pbf',
  'sources': {
    'openmaptiles': {'type': 'vector', 'url': 'https://$host/planet'},
    'ne2_shaded': {
      'type': 'raster',
      'tiles': ['https://$host/natural_earth/ne2sr/{z}/{x}/{y}.png'],
    },
  },
  'layers': [
    {
      'id': 'bg',
      'type': 'background',
      'paint': {'background-color': '#eeeeee'},
    },
    {'id': 'ne2', 'type': 'raster', 'source': 'ne2_shaded'},
    {
      'id': 'water',
      'type': 'fill',
      'source': 'openmaptiles',
      'source-layer': 'water',
      'paint': {'fill-color': '#336699'},
    },
  ],
};

/// Inneres Netz: beantwortet Anfragen aus synthetischen Daten und merkt sich jede Anfrage.
class FakeInner extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  int? forceStatus;
  Completer<void>? hold;

  /// Anfragen, für die das Netz mit einem Fehler antwortet (etwa nur Kacheln: Flugmodus nach gecachtem Stil).
  bool Function(Uri)? failWhere;

  /// Fehlerstatus für bestimmte Anfragen (etwa 404 nur für Kacheln), leerer Körper.
  int? Function(Uri)? statusWhere;

  /// Eigener Körper für bestimmte Anfragen (kaputter Stil, zu große Antwort); `chunked` sendet ihn in Stücken ohne
  /// Längenangabe.
  Uint8List? Function(Uri)? bodyWhere;
  bool chunked = false;

  /// Verzögerung jeder Antwort und die Zahl gleichzeitig offener Anfragen (Spitze in [maxActive]).
  Duration? delay;
  int active = 0;
  int maxActive = 0;

  /// Nur diese Anfragen warten auf [hold] (Standard: alle).
  bool Function(Uri)? holdWhere;

  /// Datierter Pfad der Kacheln im TileJSON (der Anbieter ändert ihn wöchentlich).
  String tileDate = '20260101_000000_pt';

  /// Zahl der Anfragen, deren Verbindung der Aufrufer über `abortTrigger` abgebrochen hat.
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    requests.add(r);
    if (r is http.Abortable) r.abortTrigger?.then((_) => aborted++);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return await _answer(r);
    } finally {
      active--;
    }
  }

  Future<http.StreamedResponse> _answer(http.BaseRequest r) async {
    if (hold != null && (holdWhere?.call(r.url) ?? true)) await hold!.future;
    if (delay != null) await Future<void>.delayed(delay!);
    if (failWhere?.call(r.url) ?? false) throw StateError('Netz weg');
    final status = forceStatus ?? statusWhere?.call(r.url);
    if (status != null) {
      return http.StreamedResponse(
        Stream.value(const <int>[]),
        status,
        request: r,
      );
    }
    final p = r.url.path;
    final Uint8List body;
    final custom = bodyWhere?.call(r.url);
    if (custom != null) {
      body = custom;
      if (chunked) {
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < body.length; i += 4096)
              Uint8List.sublistView(
                body,
                i,
                i + 4096 > body.length ? body.length : i + 4096,
              ),
          ]),
          200,
          request: r,
        );
      }
    } else if (p.startsWith('/styles/')) {
      body = Uint8List.fromList(utf8.encode(jsonEncode(styleJson())));
    } else if (p == '/planet') {
      body = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'tilejson': '3.0.0',
            'tiles': ['https://$host/planet/$tileDate/{z}/{x}/{y}.pbf'],
            'minzoom': 0,
            'maxzoom': 14,
          }),
        ),
      );
    } else if (p.endsWith('.json')) {
      body = Uint8List.fromList(utf8.encode('{}'));
    } else if (p.endsWith('.png')) {
      body = png1x1;
    } else {
      body = Uint8List.fromList([1, 2, 3]);
    }
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
      request: r,
    );
  }

  int count(bool Function(Uri) f) => requests.where((r) => f(r.url)).length;
}

/// Netz, das jede Anfrage aufzeichnet und mit einem Fehler beantwortet (Netz weg, Anbieter nicht erreichbar).
class ThrowingInner extends FakeInner {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    requests.add(r);
    throw StateError('Netz weg');
  }
}

/// Leert den prozessweiten Speicher der Kachelbibliothek (je Test, R008 Hinweis 3).
void clearMapMemoryCache() => vt.VectorTileLayer.clearMemoryCache();
