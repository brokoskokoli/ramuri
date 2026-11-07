// R008 fmvt: Miniatur = einmaliger Schnappschuss einer unsichtbaren Karte (ausserhalb des Bildschirms,
// RepaintBoundary.toImage), nach Ladeende (waitIdle), danach nur noch das verschluesselte PNG.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';

import 'ofmvt.dart';

const thumbW = 480.0, thumbH = 240.0;

Widget thumbMap(List<LatLng> r, vt.Style? style, GlobalKey key) => RepaintBoundary(
      key: key,
      child: SizedBox(
        width: thumbW,
        height: thumbH,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: r, padding: const EdgeInsets.all(16)),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
            backgroundColor: const Color(0xFFF2EFE9),
          ),
          children: [
            if (style != null) vtLayer(style),
            PolylineLayer(polylines: [Polyline(points: r, strokeWidth: 3, color: const Color(0xFFE53935))]),
          ],
        ),
      ),
    );

vt.VectorTileLayer vtLayer(vt.Style s, {bool plain = false, Duration fade = const Duration(milliseconds: 150)}) =>
    vt.VectorTileLayer(
      theme: s.theme,
      tileProviders: s.providers,
      rasterSources: s.rasterSources,
      sprites: s.sprites,
      glyphs: s.glyphs,
      diskCacheMaximumSizeInBytes: plain ? 50 * 1024 * 1024 : 0,
      tileFadeDuration: fade,
      labelFadeDuration: fade,
    );

/// Schnappschuss nach Ladeende: Netz/Speicher seit 400 ms ruhig UND zwei Bilder im Abstand von 250 ms
/// pixelgleich (Kacheln dekodiert, gerastert, eingeblendet, Beschriftung platziert). Sonst Zeitgrenze 15 s.
Future<(Uint8List, bool)> snapshot(GlobalKey key, GatedClient? c) async {
  final sw = Stopwatch()..start();
  Future<ui.Image> grab() async {
    await SchedulerBinding.instance.endOfFrame;
    return (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
  }
  Future<Uint8List> rgba(ui.Image i) async => (await i.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
  var idle = false;
  // Erst auf den Beginn des Ladens warten (hoechstens 1 s; aus dem Speicher der Bibliothek kommt evtl. nichts).
  final t0 = DateTime.now();
  while (c != null && !c.lastActivity.isAfter(t0) && sw.elapsedMilliseconds < 1000) {
    await Future.delayed(const Duration(milliseconds: 20));
  }
  ui.Image img = await grab();
  while (sw.elapsed < const Duration(seconds: 15)) {
    await waitIdle(c, () => false, timeout: const Duration(seconds: 15));
    await Future.delayed(const Duration(milliseconds: 250));
    final next = await grab();
    final same = _eq(await rgba(img), await rgba(next));
    img.dispose();
    img = next;
    if (same && (c == null || c.inFlight == 0)) {
      idle = true;
      break;
    }
  }
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return (png!.buffer.asUint8List(), idle);
}

bool _eq(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
