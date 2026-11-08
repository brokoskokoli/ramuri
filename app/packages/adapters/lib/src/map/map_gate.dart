import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'dart:io' show HttpClient;

import 'map_provider.dart';

/// Einwilligung zum Kartenanbieter (SEC-0002, SEC-0007), bei jeder Anfrage neu gelesen: Ein Widerruf wirkt sofort.
typedef MapConsent = bool Function();

/// Schmale Schnittstelle zum Kartenspeicher (A2 liefert den verschlüsselten Speicher).
abstract interface class MapTileStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

enum MapGateReason {
  noConsent,
  method,
  scheme,
  host,
  unknownResource,
  redirect,
  status,
  network,
  invalidStyle,
}

/// Fehler des Tors. Der Text nennt nur den Grund, nie URL, Host oder Kachelkoordinaten.
class MapGateException implements Exception {
  const MapGateException(this.reason);
  final MapGateReason reason;
  @override
  String toString() => 'MapGateException(${reason.name})';
}

/// Zählung der Anfragen je Ressourcenart: [network] gingen ins Netz, [stored] kamen aus dem Speicher.
class MapRequestCounts {
  final Map<MapResource, int> network = {
    for (final r in MapResource.values) r: 0,
  };
  final Map<MapResource, int> stored = {
    for (final r in MapResource.values) r: 0,
  };
  int get networkTotal => network.values.fold(0, (a, b) => a + b);
}

/// Das Tor: der einzige Weg der Karte ins Netz (ADR-0009). Nur GET, nur https, nur Hosts des Anbieters, keine
/// Weiterleitungen, keine Cookies, keine Kennung, nur der App-Name als User-Agent. Jede Anfrage prüft die Einwilligung
/// neu; ohne sie geht nichts ins Netz und nichts aus dem Speicher (fail-closed). Loggt nichts.
class MapGate extends http.BaseClient {
  MapGate({
    required this.provider,
    required this.consent,
    this.store,
    http.Client? inner,
  }) : _inner =
           inner ??
           IOClient(
             HttpClient()..connectionTimeout = const Duration(seconds: 10),
           );

  final MapProvider provider;
  final MapConsent consent;
  final MapTileStore? store;
  final http.Client _inner;
  final MapRequestCounts counts = MapRequestCounts();

  /// Speicherschlüssel ohne Datumspfad: Kacheln werden wöchentlich neu erzeugt (`/planet/<Datum>/z/x/y`).
  static String storeKey(Uri u) =>
      'map:${u.path.replaceFirst(RegExp(r'^/planet/[0-9_a-z]+/'), '/planet/_/')}';

  MapResource _check(http.BaseRequest r) {
    if (!consent()) throw const MapGateException(MapGateReason.noConsent);
    if (r.method != 'GET') throw const MapGateException(MapGateReason.method);
    if (r.url.scheme != 'https') {
      throw const MapGateException(MapGateReason.scheme);
    }
    if (r.url.hasPort && r.url.port != 443 || r.url.userInfo.isNotEmpty) {
      throw const MapGateException(MapGateReason.host);
    }
    if (!provider.allowedHosts.contains(r.url.host.toLowerCase())) {
      throw const MapGateException(MapGateReason.host);
    }
    return provider.classify(r.url) ??
        (throw const MapGateException(MapGateReason.unknownResource));
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final kind = _check(request);
    final key = storeKey(request.url);
    Uint8List? bytes;
    final cached = await store?.read(key);
    if (!consent()) throw const MapGateException(MapGateReason.noConsent);
    if (cached != null) {
      counts.stored[kind] = counts.stored[kind]! + 1;
      bytes = cached;
    } else {
      // Frische Anfrage: nur URL und App-Name, nichts aus der ursprünglichen Anfrage (Cookies, Referer, Kennungen).
      final out = http.Request('GET', request.url)
        ..followRedirects = false
        ..maxRedirects = 0
        ..persistentConnection = true
        ..headers['user-agent'] = provider.userAgent;
      counts.network[kind] = counts.network[kind]! + 1;
      final http.StreamedResponse res;
      try {
        res = await _inner.send(out);
      } catch (_) {
        throw const MapGateException(
          MapGateReason.network,
        ); // Ursache verworfen: Texte können URL oder Host nennen
      }
      if (res.statusCode >= 300 && res.statusCode < 400) {
        unawaited(res.stream.drain<void>().catchError((_) {}));
        throw const MapGateException(MapGateReason.redirect);
      }
      final body = await res.stream.toBytes().catchError(
        (_) => throw const MapGateException(MapGateReason.network),
      );
      if (!consent()) {
        throw const MapGateException(
          MapGateReason.noConsent,
        ); // Widerruf während der Antwort: nichts speichern
      }
      if (res.statusCode != 200) {
        return http.StreamedResponse(
          Stream.value(body),
          res.statusCode,
          contentLength: body.length,
          request: request,
        );
      }
      bytes = body;
      await store?.write(key, bytes);
    }
    if (kind == MapResource.style) bytes = _withoutRasterSources(bytes);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      contentLength: bytes.length,
      request: request,
    );
  }

  /// Rasterquellen kosten Verkehr und verraten die Gegend grob (R008 Hinweis 4): aus dem Stil entfernen, samt der
  /// Ebenen, die sie nutzen. Unlesbarer Stil ist ein Fehler (fail-closed).
  static Uint8List _withoutRasterSources(Uint8List bytes) {
    try {
      final style = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final sources = style['sources'];
      if (sources is Map) {
        final drop = {
          for (final e in sources.entries)
            if (e.value is Map &&
                ((e.value as Map)['type'] == 'raster' ||
                    (e.value as Map)['type'] == 'raster-dem'))
              e.key,
        };
        sources.removeWhere((k, _) => drop.contains(k));
        final layers = style['layers'];
        if (layers is List) {
          layers.removeWhere(
            (l) =>
                l is Map &&
                (drop.contains(l['source']) ||
                    l['type'] == 'raster' ||
                    l['type'] == 'hillshade'),
          );
        }
      }
      return Uint8List.fromList(utf8.encode(jsonEncode(style)));
    } catch (_) {
      throw const MapGateException(MapGateReason.invalidStyle);
    }
  }

  @override
  void close() => _inner.close();
}
