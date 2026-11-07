// R008: Miniatur einmal offscreen rendern (ohne Kartenwidget): Vektorkacheln -> Canvas -> PNG.
// Danach zeigt die Liste nur noch das entschluesselte PNG.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import 'route.dart';

typedef TileBytes = Future<Uint8List?> Function(int z, int x, int y);

double _mx(double lon) => (lon + 180) / 360;
double _my(double lat) {
  final r = lat * pi / 180;
  return (1 - log(tan(r) + 1 / cos(r)) / pi) / 2;
}

/// Rendert w x h Pixel. tiles == null oder theme == null: nur die Linie (ohne Einwilligung).
Future<Uint8List> renderThumb(List<P> pts, {required int w, required int h, vtr.Theme? theme, TileBytes? tiles}) async {
  var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0;
  for (final p in pts) {
    final x = _mx(p.lon), y = _my(p.lat);
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y);
  }
  const pad = 0.12;
  final spanX = (maxX - minX) * (1 + 2 * pad), spanY = (maxY - minY) * (1 + 2 * pad);
  // Weltbreite in Pixeln, damit die Strecke passt; Zoom = log2(world/256)
  final world = min(w / spanX, h / spanY);
  final zoom = log(world / 256) / ln2;
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  final ox = cx * world - w / 2, oy = cy * world - h / 2; // Pixel-Ursprung des Bildes in Weltpixeln
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint()..color = const ui.Color(0xFFF2EFE9));
  if (theme != null && tiles != null) {
    final z = zoom.floor().clamp(0, 14);
    final n = 1 << z;
    final tilePx = world / n; // Groesse einer Kachel in Bildpixeln
    final factory = vtr.TileFactory(theme, const vtr.Logger.noop());
    for (var tx = (ox / tilePx).floor(); tx <= ((ox + w) / tilePx).floor(); tx++) {
      for (var ty = (oy / tilePx).floor(); ty <= ((oy + h) / tilePx).floor(); ty++) {
        final bytes = await tiles(z, tx, ty);
        if (bytes == null) continue;
        final tile = factory.createTileData(vtr.VectorTileReader().read(bytes)).toTile();
        canvas.save();
        canvas.translate(tx * tilePx - ox, ty * tilePx - oy);
        final s = tilePx / 256;
        canvas.clipRect(ui.Rect.fromLTWH(0, 0, tilePx, tilePx));
        canvas.scale(s, s);
        vtr.Renderer(theme: theme).render(canvas, vtr.TileSource(tileset: vtr.Tileset({'openmaptiles': tile})),
            zoomScaleFactor: s, zoom: zoom, rotation: 0);
        canvas.restore();
      }
    }
  }
  final path = ui.Path();
  for (var i = 0; i < pts.length; i++) {
    final x = _mx(pts[i].lon) * world - ox, y = _my(pts[i].lat) * world - oy;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  canvas.drawPath(path, ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = const ui.Color(0xFFE53935));
  final img = await rec.endRecording().toImage(w, h);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}
