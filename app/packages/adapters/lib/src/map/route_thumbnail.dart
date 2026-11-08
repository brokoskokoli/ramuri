import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core/core.dart' show RoutePoint;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'map_gate.dart';
import 'map_tile_source.dart';
import 'route_map.dart';

/// Größe einer Miniatur in Pixeln (R008 Hinweis 5: 480 x 240).
const double thumbnailWidth = 480;
const double thumbnailHeight = 240;

/// Ladeende (R008 Hinweis 5): Netz und Speicher seit [thumbnailQuiet] ruhig und zwei Bilder im Abstand von
/// [thumbnailSettle] pixelgleich; sonst nach [thumbnailTimeLimit] aufgeben.
const Duration thumbnailQuiet = Duration(milliseconds: 400);
const Duration thumbnailSettle = Duration(milliseconds: 250);
const Duration thumbnailTimeLimit = Duration(seconds: 15);

/// Die Karte, die als Miniatur aufgenommen wird: feste Größe, nicht bedienbar, mit Quellenangabe. Sie muss wirklich
/// gemalt werden (außerhalb des Bildschirms, nicht in einem `Offstage`), sonst gibt es kein Bild. [boundary] ist der
/// Schlüssel der `RepaintBoundary`, den [captureThumbnail] liest.
class ThumbnailMap extends StatelessWidget {
  const ThumbnailMap({
    super.key,
    required this.boundary,
    required this.source,
    required this.route,
    required this.style,
  });

  final GlobalKey boundary;
  final MapTileSource source;
  final List<List<RoutePoint>> route;
  final RouteMapStyle style;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundary,
      child: SizedBox(
        width: thumbnailWidth,
        height: thumbnailHeight,
        child: RouteMap(
          source: source,
          route: route,
          style: style,
          gestures: RouteMapGestures.none,
          fitPadding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
          maxFitZoom: 16,
        ),
      ),
    );
  }
}

/// Nimmt die Karte in [boundary] als PNG auf, sobald sie fertig geladen ist. `null`, wenn sie nicht fertig wird
/// (Zeitgrenze), beim Laden eine Anfrage scheiterte ([MapGate.failures]), der Aufruf abgebrochen wurde
/// ([cancelled]) oder die Karte weg ist: dann wird nichts gespeichert.
///
/// [frame] wartet auf das nächste Bild (Tests treiben die Bilder selbst). [failuresBefore] ist der Stand von
/// [MapGate.failures] vor dem Aufbau der Karte: das Laden beginnt schon mit ihrem ersten Bild, also vor diesem Aufruf.
Future<Uint8List?> captureThumbnail(
  GlobalKey boundary,
  MapGate gate, {
  Duration quiet = thumbnailQuiet,
  Duration settle = thumbnailSettle,
  Duration limit = thumbnailTimeLimit,
  bool Function()? cancelled,
  Future<void> Function()? frame,
  int? failuresBefore,
}) async {
  final nextFrame = frame ?? () => SchedulerBinding.instance.endOfFrame;
  final failuresAtStart = failuresBefore ?? gate.failures;
  final watch = Stopwatch()..start();

  Future<ui.Image?> grab() async {
    await nextFrame();
    final object = boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary || !object.attached) return null;
    return object.toImage(pixelRatio: 1);
  }

  Future<Uint8List?> rgba(ui.Image i) async =>
      (await i.toByteData(format: ui.ImageByteFormat.rawRgba))?.buffer
          .asUint8List();

  bool aborted() => cancelled?.call() ?? false;

  while (watch.elapsed < limit) {
    if (aborted()) return null;
    // Erst ruhig werden lassen: so lange kein Zugriff läuft und die letzte Bewegung `quiet` zurückliegt.
    if (gate.quietFor < quiet || watch.elapsed < quiet) {
      // Bilder erzwingen: das Laden der Kacheln beginnt erst mit dem ersten gemalten Bild.
      await nextFrame();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      continue;
    }
    final a = await grab();
    if (a == null) return null;
    await Future<void>.delayed(settle);
    final b = await grab();
    if (b == null) {
      a.dispose();
      return null;
    }
    final same = _equal(await rgba(a), await rgba(b));
    a.dispose();
    if (aborted()) {
      b.dispose();
      return null;
    }
    // Während der beiden Bilder kam nichts Neues, und es ging nichts schief: das Bild ist fertig.
    if (same && gate.quietFor >= quiet) {
      if (gate.failures != failuresAtStart) {
        b.dispose();
        return null;
      }
      final png = await b.toByteData(format: ui.ImageByteFormat.png);
      b.dispose();
      return png?.buffer.asUint8List();
    }
    b.dispose();
  }
  return null;
}

bool _equal(Uint8List? a, Uint8List? b) {
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
