// R008: Kachelquelle fuer OpenFreeMap mit Einwilligung (fail-closed) und verschluesseltem Speicher.
// Einziger Netzzugang der Mini-App fm. Loggt keine URLs und keine Kachelkoordinaten.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'store.dart';

class ConsentMissing implements Exception {}

class OfmSource {
  OfmSource._(this.store, this._client);

  /// Ohne Einwilligung gibt es keine Quelle (fail-closed): create wirft.
  static OfmSource create({required bool consent, required EncStore store}) {
    if (!consent) throw ConsentMissing();
    final c = HttpClient()
      ..userAgent = 'running-app-research-R008'
      ..connectionTimeout = const Duration(seconds: 10);
    return OfmSource._(store, c);
  }

  final EncStore store;
  final HttpClient _client;
  int netRequests = 0, netBytes = 0;
  static const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  Future<Uint8List> _get(String url, String cacheKey, {bool cache = true}) async {
    if (cache) {
      final cached = await store.read(cacheKey);
      if (cached != null) return cached;
    }
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' || uri.host != 'tiles.openfreemap.org') throw StateError('Host nicht erlaubt');
    final req = await _client.getUrl(uri);
    final res = await req.close();
    final bb = BytesBuilder(copy: false);
    await for (final c in res) {
      bb.add(c);
    }
    final bytes = bb.takeBytes();
    if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
    netRequests++;
    netBytes += bytes.length;
    if (cache) await store.write(cacheKey, bytes);
    return bytes;
  }

  late Map<String, dynamic> styleJson;
  late String tileTemplate;
  late vtr.Theme theme;
  vtr.SpriteIndex? spriteIndex;
  Uint8List? spritePng;

  Future<void> load() async {
    styleJson = jsonDecode(utf8.decode(await _get(styleUrl, 'style:liberty'))) as Map<String, dynamic>;
    final src = (styleJson['sources'] as Map)['openmaptiles'] as Map;
    final tj = jsonDecode(utf8.decode(await _get(src['url'] as String, 'tilejson:planet'))) as Map;
    tileTemplate = (tj['tiles'] as List).first as String;
    // Der Rasterhintergrund ne2_shaded (nur bis z6) wird nicht gebraucht: aus dem Stil nehmen.
    styleJson['layers'] = (styleJson['layers'] as List).where((l) => (l as Map)['source'] != 'ne2_shaded').toList();
    (styleJson['sources'] as Map).remove('ne2_shaded');
    theme = vtr.ThemeReader().read(styleJson);
    final sprite = styleJson['sprite'] as String;
    final idx = jsonDecode(utf8.decode(await _get('$sprite@2x.json', 'sprite:json@2x'))) as Map<String, dynamic>;
    spriteIndex = vtr.SpriteIndexReader().read(idx);
    spritePng = await _get('$sprite@2x.png', 'sprite:png@2x');
  }

  /// Kachel als PBF. Schluessel ohne Datumspfad, damit der woechentliche Neubau den Speicher nicht leert.
  /// cache=false fuer die Karte: dort speichert vector_map_tiles selbst ueber EncByteStorage (sonst doppelt).
  Future<Uint8List> tile(int z, int x, int y, {bool cache = true}) {
    final url = tileTemplate.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');
    return _get(url, 'tile:$z/$x/$y', cache: cache);
  }

  VectorTileProvider provider() => _Provider(this);
  SpriteStyle sprites() => SpriteStyle(atlasProvider: () async => spritePng!, index: spriteIndex!);
}

class _Provider extends VectorTileProvider {
  _Provider(this.s);
  final OfmSource s;
  @override
  int get maximumZoom => 14;
  @override
  int get minimumZoom => 0;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
  @override
  Future<Uint8List> provide(TileIdentity t) => s.tile(t.z, t.x, t.y, cache: false);
}

/// Hook fuer den Patch: vector_map_tiles legt Kacheln, Sprite-Atlas und gerenderte Bilder hier ab statt im Klartext.
class EncByteStorage extends ByteStorage {
  EncByteStorage(this.st);
  final EncStore st;
  @override
  Future<void> write(String path, Uint8List bytes) => st.write('vmt:$path', bytes);
  @override
  Future<Uint8List?> read(String path) => st.read('vmt:$path');
  @override
  Future<void> delete(String path) => st.delete('vmt:$path');
  @override
  Future<bool> exists(String key) => st.exists('vmt:$key');
  @override
  Future<List<ByteStorageEntry>> list() async => const []; // Groesse regelt EncStore.evict selbst
}
