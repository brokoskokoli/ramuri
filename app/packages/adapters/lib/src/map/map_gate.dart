import 'dart:async';
import 'dart:collection' show Queue;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
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

  /// Entfernt einen Eintrag (etwa einen unlesbaren Stil). Fehler sind kein Wurf.
  Future<void> remove(String key);
}

/// Höchstalter von Stil und TileJSON im Speicher (WP13 N1c, M2; Vorschlag des Supervisors, kein Messwert). Der
/// TileJSON trägt den datierten Kachelpfad (`/planet/<Datum>/...`); danach holt das Tor beide neu und nutzt den alten
/// Eintrag nur noch, wenn das Netz scheitert.
const Duration mapStyleMaxAge = Duration(days: 7);

/// Zeitgrenze je Anfrage ins Netz (Verbindung, Antwort und Körper zusammen) und Höchstgröße des Körpers
/// (WP13 N1c, S7). Die größte Antwort der R008-Messung hatte 431 kB; 2 MiB lassen reichlich Luft und halten einen
/// fehlerhaften oder böswilligen Anbieter aus dem Speicher. Überschreitung ist ein Fehler, nichts wird gespeichert.
const Duration mapRequestTimeout = Duration(seconds: 20);
const int mapMaxBodyBytes = 2 * 1024 * 1024;

/// So viele Kachel-Anfragen müssen ohne einen einzigen Treffer scheitern, bevor die Karte als unbrauchbar gilt und
/// die Oberfläche auf die Linie zurückfällt (FR-0204 "ohne Netz oder bei Fehlern"). Klein gehalten, denn die Karte
/// zeigt bei Zoom 16 und höher nur 1 bis 4 verschiedene Kacheln (Vektorkacheln bis Zoom 14, darüber vergrößert; im
/// Test der Live-Seite 2). Eine Kachel mit Fehler versucht die Bibliothek dreimal, eine mit 404 einmal. Zwei
/// Fehlschläge ohne jeden Treffer reichen deshalb für Netzfehler einer Kachel und für 404 zweier Kacheln; zeigt die
/// Ansicht nur eine einzige Kachel und die antwortet 404, bleibt die Karte (Hintergrund mit Linie) stehen. Ein
/// Treffer holt die Karte zurück, der Rückfall kostet nichts.
const int mapTileFailureLimit = 2;

/// Miniaturen der Läufe im Kartenspeicher (WP13 D). Schlüssel haben das Präfix [thumbnailKeyPrefix]; die Miniatur
/// eines Laufs verschwindet mit dem Lauf ([deleteRun]).
abstract interface class MapThumbnailStore implements MapTileStore {
  /// Entfernt alle Miniaturen des Laufs [runId] (jede Variante). Fehler sind kein Wurf.
  Future<void> deleteRun(int runId);
}

/// Schlüssel einer Miniatur: `thumb:<Variante>:<Lauf>`. [variant] trägt Fassung, Größe und Farben, damit sich
/// Miniaturen verschiedener Darstellung nie überschreiben und eine Änderung des Aussehens neue erzeugt.
String thumbnailKey(String variant, int runId) =>
    '$thumbnailKeyPrefix$variant:$runId';

/// Präfix der Miniatur-Schlüssel (Art `thumbnail` im Speicher).
const String thumbnailKeyPrefix = 'thumb:';

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
  timeout,
  tooLarge,
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
    DateTime Function()? now,
    this.requestTimeout = mapRequestTimeout,
    this.maxBodyBytes = mapMaxBodyBytes,
  }) : _now = now ?? DateTime.now,
       _inner =
           inner ??
           IOClient(
             HttpClient()..connectionTimeout = const Duration(seconds: 10),
           );

  final MapProvider provider;
  final MapConsent consent;
  final MapTileStore? store;
  final http.Client _inner;
  final DateTime Function() _now;
  final Duration requestTimeout;
  final int maxBodyBytes;
  final MapRequestCounts counts = MapRequestCounts();

  /// Anfragen, die gerade laufen (Netz oder Speicher), und der Zeitpunkt der letzten Bewegung (Beginn oder Ende einer
  /// Anfrage). Die Miniatur wartet damit auf das Ende des Ladens (WP13 D).
  int inFlight = 0;

  /// Höchstzahl gleichzeitiger Anfragen (`null`: unbegrenzt). Die Miniaturen im Verlauf nehmen 4, damit die
  /// Anfragen die Grenzen des Anbieters einhalten (R008 Hinweis 6).
  int? maxParallel;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  Future<void> _acquire() async {
    final m = maxParallel;
    if (m == null || _running < m) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future; // der Platz wird weitergereicht
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  /// Gesundheit der Kacheln (M1): `true`, wenn noch keine Kachel ein Treffer war (200 aus Netz oder Speicher) und
  /// mindestens [mapTileFailureLimit] Kachel-Anfragen scheiterten (Fehler, Fehlerstatus, 404, Zeit, Größe).
  /// Ein Treffer setzt es zurück. Stil, Sprites und Glyphen zählen nicht.
  final ValueNotifier<bool> _tilesFailed = ValueNotifier<bool>(false);
  ValueListenable<bool> get tilesFailed => _tilesFailed;
  int _tileHits = 0;
  int _tileMisses = 0;

  void _tile(bool hit) {
    if (hit) {
      _tileHits++;
      _tileMisses = 0;
      _tilesFailed.value = false;
    } else if (_tileHits == 0) {
      if (++_tileMisses >= mapTileFailureLimit) _tilesFailed.value = true;
    }
  }

  /// Beginnt die Zählung der Kacheln neu (die Oberfläche versucht es nach einer Pause wieder).
  void resetTileHealth() {
    _tileHits = 0;
    _tileMisses = 0;
    _tilesFailed.value = false;
  }

  /// Anfragen, die gescheitert sind (Netz, Weiterleitung, Fehlerstatus außer 404). Die Miniatur speichert nichts,
  /// wenn beim Laden eine scheiterte: ein Bild mit Lücken wäre halbfertig.
  int failures = 0;
  final Stopwatch _sinceActivity = Stopwatch()..start();
  Duration get quietFor =>
      inFlight > 0 ? Duration.zero : _sinceActivity.elapsed;

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
    inFlight++;
    _sinceActivity.reset();
    await _acquire();
    MapResource? kind;
    try {
      kind = _check(request);
      final res = await _send(request, kind);
      if (res.statusCode != 200 && res.statusCode != 404) failures++;
      if (kind == MapResource.tile) {
        _tile(res.statusCode == 200);
      }
      return res;
    } catch (e) {
      failures++;
      if (kind == MapResource.tile &&
          !(e is MapGateException && e.reason == MapGateReason.noConsent)) {
        _tile(false);
      }
      rethrow;
    } finally {
      _release();
      inFlight--;
      _sinceActivity.reset();
    }
  }

  http.StreamedResponse _ok(http.BaseRequest request, Uint8List bytes) =>
      http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
        request: request,
      );

  Future<http.StreamedResponse> _send(
    http.BaseRequest request,
    MapResource kind,
  ) async {
    final key = storeKey(request.url);
    final cached = await store?.read(key);
    if (!consent()) throw const MapGateException(MapGateReason.noConsent);
    final volatile = kind == MapResource.style || kind == MapResource.tilejson;
    Uint8List bytes;
    if (volatile) {
      bytes = await _volatile(request, kind, key, cached);
    } else if (cached != null) {
      counts.stored[kind] = counts.stored[kind]! + 1;
      bytes = cached;
    } else {
      final f = await _fetch(request, kind);
      if (f.status != 200) {
        return http.StreamedResponse(
          Stream.value(f.body),
          f.status,
          contentLength: f.body.length,
          request: request,
        );
      }
      bytes = f.body;
      await store?.write(key, bytes);
    }
    if (kind == MapResource.style) bytes = _withoutRasterSources(bytes);
    return _ok(request, bytes);
  }

  /// Stil und TileJSON (M2): jung im Speicher gilt, älter oder unlesbar wird neu geholt. Der neue Inhalt wird erst
  /// **nach** der Prüfung gespeichert (mit dem Zeitpunkt vor dem Inhalt, innerhalb der verschlüsselten Datei). Scheitert
  /// der Abruf (Netz, Fehlerstatus, kaputter Inhalt), gilt der alte, lesbare Eintrag weiter; ohne ihn der Fehler.
  Future<Uint8List> _volatile(
    http.BaseRequest request,
    MapResource kind,
    String key,
    Uint8List? cached,
  ) async {
    Uint8List? old;
    if (cached != null) {
      final at = _storedAt(cached);
      final payload = at == null ? null : _payloadOf(cached);
      if (at == null || payload == null || !_valid(kind, payload)) {
        await store?.remove(key); // unlesbar: nicht behalten
      } else {
        old = payload;
        final age = _now().difference(at);
        if (!age.isNegative && age < mapStyleMaxAge) {
          counts.stored[kind] = counts.stored[kind]! + 1;
          return payload;
        }
      }
    }
    try {
      final f = await _fetch(request, kind);
      if (f.status != 200) throw const MapGateException(MapGateReason.status);
      if (!_valid(kind, f.body)) {
        throw MapGateException(
          kind == MapResource.style
              ? MapGateReason.invalidStyle
              : MapGateReason.status,
        );
      }
      await store?.write(key, _stamp(f.body));
      return f.body;
    } on MapGateException catch (e) {
      if (old != null && e.reason != MapGateReason.noConsent) {
        counts.stored[kind] = counts.stored[kind]! + 1;
        return old;
      }
      rethrow;
    }
  }

  /// Der gespeicherte Eintrag von Stil und TileJSON: 8 Byte Zeitpunkt (Millisekunden seit 1970, UTC, big endian),
  /// danach der Inhalt.
  Uint8List _stamp(Uint8List body) {
    final out = Uint8List(8 + body.length);
    ByteData.sublistView(out)
        .setInt64(0, _now().toUtc().millisecondsSinceEpoch);
    out.setRange(8, out.length, body);
    return out;
  }

  static DateTime? _storedAt(Uint8List b) {
    if (b.length <= 8) return null;
    final ms = ByteData.sublistView(b).getInt64(0);
    if (ms <= 0 || ms > 253402300799000) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static Uint8List? _payloadOf(Uint8List b) =>
      b.length <= 8 ? null : Uint8List.sublistView(b, 8);

  /// Prüft Stil und TileJSON, bevor sie gespeichert oder weiterverwendet werden.
  static bool _valid(MapResource kind, Uint8List body) {
    try {
      final j = jsonDecode(utf8.decode(body));
      if (j is! Map) return false;
      if (kind == MapResource.style) {
        return j['sources'] is Map && j['layers'] is List;
      }
      final tiles = j['tiles'];
      return tiles is List && tiles.isNotEmpty && tiles.first is String;
    } catch (_) {
      return false;
    }
  }

  /// Ein Abruf ins Netz: nur URL und App-Name, nichts aus der ursprünglichen Anfrage (Cookies, Referer, Kennungen).
  /// Zeitgrenze und Höchstgröße des Körpers (S7); jede Überschreitung bricht die Verbindung ab. Wirft
  /// [MapGateException] ohne Ursache (Texte können URL oder Host nennen). Nach der Antwort wird die Einwilligung noch
  /// einmal geprüft: Widerruf während der Antwort heißt nichts speichern.
  Future<({int status, Uint8List body})> _fetch(
    http.BaseRequest request,
    MapResource kind,
  ) async {
    final abort = Completer<void>();
    final out =
        http.AbortableRequest('GET', request.url, abortTrigger: abort.future)
          ..followRedirects = false
          ..maxRedirects = 0
          ..persistentConnection = true
          ..headers['user-agent'] = provider.userAgent;
    counts.network[kind] = counts.network[kind]! + 1;
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    final ({int status, Uint8List body}) r;
    try {
      r = await _download(out, stop).timeout(requestTimeout);
    } on MapGateException {
      stop();
      rethrow;
    } on TimeoutException {
      stop();
      throw const MapGateException(MapGateReason.timeout);
    } catch (_) {
      stop();
      throw const MapGateException(MapGateReason.network);
    }
    if (!consent()) throw const MapGateException(MapGateReason.noConsent);
    return r;
  }

  Future<({int status, Uint8List body})> _download(
    http.BaseRequest out,
    void Function() stop,
  ) async {
    final res = await _inner.send(out);
    if (res.statusCode >= 300 && res.statusCode < 400) {
      stop();
      throw const MapGateException(MapGateReason.redirect);
    }
    final len = res.contentLength;
    if (len != null && len > maxBodyBytes) {
      throw const MapGateException(MapGateReason.tooLarge);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      builder.add(chunk);
      if (builder.length > maxBodyBytes) {
        throw const MapGateException(MapGateReason.tooLarge);
      }
    }
    return (status: res.statusCode, body: builder.takeBytes());
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
