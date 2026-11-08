import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Nur für Tests: Kamera der Karte unterhalb von [context] (etwa das Element der Live-Karte). Breite, Länge, Zoomstufe.
({double lat, double lon, double zoom}) mapCameraOf(BuildContext context) {
  BuildContext? inner;
  void visit(Element e) {
    if (inner != null) return;
    if (e.widget is PolylineLayer) {
      inner = e;
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  final c = MapCamera.of(inner!);
  return (lat: c.center.latitude, lon: c.center.longitude, zoom: c.zoom);
}

/// Nur für Tests: Zahl der gezeichneten Linienzüge der Karte unterhalb von [context].
int mapPolylineCount(BuildContext context) {
  var n = 0;
  void visit(Element e) {
    final w = e.widget;
    if (w is PolylineLayer) {
      n += w.polylines.length;
      return;
    }
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return n;
}
