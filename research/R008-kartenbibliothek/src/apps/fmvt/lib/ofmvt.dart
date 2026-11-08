// R008: Netzzugang der Mini-App fmvt. Ein eigener http.Client ist der einzige Weg ins Netz:
// - nur mit Einwilligung (fail-closed: create wirft ohne),
// - nur GET https://tiles.openfreemap.org,
// - jede Antwort 200 landet verschluesselt im EncStore (Stil, TileJSON, Sprites, Glyphen, Kacheln).
// flutter_map_vector_tiles bekommt den Client ueber StyleReader(httpClient:) und die Kachelquellen ueber
// resolveProvider (sonst erzeugt StyleReader NetworkVectorTileProvider mit eigenem http.Client() = am Tor vorbei).
// Plattencache der Bibliothek aus: StyleReader(cache: false), VectorTileLayer(diskCacheMaximumSizeInBytes: 0).
// Loggt keine URLs und keine Kachelkoordinaten.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'store.dart';

class ConsentMissing implements Exception {}

const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

class GatedClient extends http.BaseClient {
  GatedClient._(this.store, this._inner);

  static GatedClient create({required bool consent, required EncStore store, http.Client? inner}) {
    if (!consent) throw ConsentMissing();
    return GatedClient._(store, inner ?? IOClient(HttpClient()
      ..userAgent = 'running-app-research-R008'
      ..connectionTimeout = const Duration(seconds: 10)));
  }

  final EncStore store;
  final http.Client _inner;
  int netRequests = 0, netBytes = 0, storeHits = 0, inFlight = 0;
  DateTime lastActivity = DateTime.now();

  /// Kachel-URLs ohne Datumspfad (woechentlicher Neubau soll den Speicher nicht leeren).
  static String key(Uri u) => 'http:${u.toString().replaceFirst(RegExp(r'/planet/[0-9_a-z]+/'), '/planet/_/')}';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    if (r.method != 'GET' || r.url.scheme != 'https' || r.url.host != 'tiles.openfreemap.org') {
      throw StateError('Host oder Methode nicht erlaubt');
    }
    inFlight++;
    try {
      final k = key(r.url);
      final have = await store.read(k);
      if (have != null) {
        storeHits++;
        return http.StreamedResponse(Stream.value(have), 200, contentLength: have.length, request: r);
      }
      final res = await _inner.send(r);
      final bytes = await res.stream.toBytes();
      netRequests++;
      netBytes += bytes.length;
      if (res.statusCode == 200) await store.write(k, bytes);
      return http.StreamedResponse(Stream.value(bytes), res.statusCode, contentLength: bytes.length, request: r);
    } finally {
      inFlight--;
      lastActivity = DateTime.now();
    }
  }

  @override
  void close() => _inner.close();
}

/// Laedt den Stil ueber das Tor. plain=true: Bibliothek mit Standardwerten (eigener Client, Plattencache) = Gegenprobe.
Future<vt.Style> loadStyle(GatedClient c, {bool plain = false}) async {
  if (plain) return vt.StyleReader(uri: styleUrl).read();
  final style = jsonDecode(await c.read(Uri.parse(styleUrl))) as Map<String, dynamic>;
  final templates = <String, (String, int, int)>{};
  for (final e in (style['sources'] as Map).entries) {
    final s = e.value as Map;
    if (s['tiles'] is List) {
      templates[e.key as String] = ((s['tiles'] as List).first as String, (s['minzoom'] ?? 0) as int, (s['maxzoom'] ?? 22) as int);
    } else if (s['url'] is String) {
      final tj = jsonDecode(await c.read(Uri.parse(s['url'] as String))) as Map;
      templates[e.key as String] = ((tj['tiles'] as List).first as String, (tj['minzoom'] ?? 0) as int, (tj['maxzoom'] ?? 14) as int);
    }
  }
  return vt.StyleReader(
    uri: styleUrl,
    httpClient: c,
    cache: false,
    resolveProvider: (id) async {
      final t = templates[id];
      if (t == null) return null;
      return vt.NetworkVectorTileProvider(urlTemplate: t.$1, client: c, minimumZoom: t.$2, maximumZoom: t.$3);
    },
  ).read();
}

/// Ladeende: kein Netz-/Speicherzugriff offen, seit [quiet] keiner mehr, und die Oberflaeche plant keine Bilder mehr.
Future<bool> waitIdle(GatedClient? c, bool Function() framesPending,
    {Duration quiet = const Duration(milliseconds: 400), Duration timeout = const Duration(seconds: 15)}) async {
  final sw = Stopwatch()..start();
  var calm = Stopwatch()..start();
  while (sw.elapsed < timeout) {
    await Future.delayed(const Duration(milliseconds: 50));
    final busy = (c != null && (c.inFlight > 0 || DateTime.now().difference(c.lastActivity) < quiet)) || framesPending();
    if (busy) calm = Stopwatch()..start();
    if (calm.elapsed >= quiet && sw.elapsed >= quiet) return true;
  }
  return false;
}
