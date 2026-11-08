"""Kopiert vector_map_tiles 9.0.0-beta.13 aus dem Pub-Cache nach DEST und ergaenzt einen Hook:
VectorTileLayer(cacheStorage: ByteStorage?) ersetzt den Klartext-Dateicache (IoByteStorage im Temp-Ordner).
Ohne cacheStorage bleibt das Verhalten wie im Original. Usage: patch_vmt.py <pub-cache-paket> <dest>"""
import pathlib, shutil, sys
src, dest = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
if dest.exists():
    shutil.rmtree(dest)
shutil.copytree(src, dest)
def sub(rel, old, new, count=1):
    p = dest / rel
    s = p.read_text()
    assert s.count(old) == count, (rel, old, s.count(old))
    p.write_text(s.replace(old, new))
sub('lib/vector_map_tiles.dart', "export 'src/vector_tile_provider.dart';",
    "export 'src/vector_tile_provider.dart';\nexport 'src/cache/byte_storage.dart'; // R008-Patch")
sub('lib/src/vector_tile_layer.dart', "  final Future<Directory> Function()? cacheFolder;",
    "  final Future<Directory> Function()? cacheFolder;\n\n  /// R008-Patch: eigener Speicher statt Dateicache, z. B. verschluesselt.\n  final ByteStorage? cacheStorage;")
sub('lib/src/vector_tile_layer.dart', "      this.cacheFolder}) {", "      this.cacheFolder,\n      this.cacheStorage}) {")
p = dest / 'lib/src/vector_tile_layer.dart'; s = p.read_text(); p.write_text("import 'cache/byte_storage.dart'; // R008-Patch\n" + s)
sub('lib/src/options.dart', "  final Future<Directory> Function()? cacheFolder;",
    "  final Future<Directory> Function()? cacheFolder;\n  final ByteStorage? cacheStorage; // R008-Patch")
sub('lib/src/options.dart', "        cacheFolder = layer.cacheFolder;", "        cacheFolder = layer.cacheFolder,\n        cacheStorage = layer.cacheStorage;")
p = dest / 'lib/src/options.dart'; s = p.read_text(); p.write_text("import 'cache/byte_storage.dart'; // R008-Patch\n" + s)
sub('lib/src/grid/grid_layer.dart', "cacheStorage: createByteStorage(widget.options.cacheFolder));",
    "cacheStorage: widget.options.cacheStorage ?? createByteStorage(widget.options.cacheFolder)); // R008-Patch")
print('gepatcht:', dest)
