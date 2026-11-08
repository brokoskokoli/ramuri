import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:http/http.dart' as http;

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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    requests.add(r);
    if (hold != null) await hold!.future;
    final status = forceStatus;
    if (status != null) {
      return http.StreamedResponse(
        Stream.value(const <int>[]),
        status,
        request: r,
      );
    }
    final p = r.url.path;
    final Uint8List body;
    if (p.startsWith('/styles/')) {
      body = Uint8List.fromList(utf8.encode(jsonEncode(styleJson())));
    } else if (p == '/planet') {
      body = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'tilejson': '3.0.0',
            'tiles': [
              'https://$host/planet/20260101_000000_pt/{z}/{x}/{y}.pbf',
            ],
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

class MemoryStore implements MapTileStore {
  final Map<String, Uint8List> data = {};
  int writes = 0;
  int reads = 0;
  Completer<void>? holdRead;
  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    if (holdRead != null) await holdRead!.future;
    return data[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    data[key] = bytes;
  }
}
