import 'dart:math' as math;

import 'package:core/core.dart' show RoutePoint;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'map_tile_source.dart';

/// Farben und Strichstärken der Routenkarte. Das Kernwidget kennt kein App-Theme; die App reicht alles hier an.
@immutable
class RouteMapStyle {
  const RouteMapStyle({
    required this.lineColor,
    required this.startColor,
    required this.endColor,
    required this.markerBorderColor,
    required this.backgroundColor,
    required this.attributionBackground,
    required this.attributionForeground,
    this.lineWidth = 4,
    this.markerRadius = 7,
    this.markerBorderWidth = 2,
    this.attributionTextStyle,
    this.positionColor,
    this.positionBorderColor = const Color(0xFFFFFFFF),
  });

  final Color lineColor;
  final Color startColor;
  final Color endColor;
  final Color markerBorderColor;

  /// Grund unter den Kacheln (vor dem Laden, bei fehlenden Kacheln).
  final Color backgroundColor;
  final Color attributionBackground;
  final Color attributionForeground;
  final double lineWidth;
  final double markerRadius;
  final double markerBorderWidth;
  final TextStyle? attributionTextStyle;

  /// Punkt der aktuellen Position (Live-Karte); ohne Angabe [endColor].
  final Color? positionColor;
  final Color positionBorderColor;
}

/// Wie die Karte auf Gesten reagiert. Ein Finger bleibt der Seite überlassen, damit eine Karte in einer
/// scrollbaren Seite das Scrollen nicht kapert (Zoomen und Verschieben mit zwei Fingern, Doppeltipp).
enum RouteMapGestures { none, twoFinger, full }

/// Routenkarte: Kachelhintergrund aus [source], darüber die Route (ein Linienzug je zusammenhängendem Teil, nie
/// über Lücken oder Pausen verbunden), Start und Ende markiert, die Quellenangabe fest im Bild.
///
/// Startkamera (R008 Hinweis 5): Mitte und Zoom stammen aus den Routengrenzen und stehen schon beim ersten Bild,
/// und ohne bekannte Größe gibt es keine Kachelebene. So fragt die Karte nie Kacheln am Standardzentrum der
/// Bibliothek an. Die Linie liegt in eigenen Ebenen: ein Fehler beim Laden der Kacheln lässt sie nicht verschwinden.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.source,
    required this.route,
    required this.style,
    this.gestures = RouteMapGestures.twoFinger,
    this.mapController,
    this.fitPadding = defaultFitPadding,
    this.maxFitZoom = 17,
  });

  /// Rand um die Route; unten mehr Platz, damit die Quellenangabe keine Marke verdeckt.
  static const EdgeInsets defaultFitPadding = EdgeInsets.fromLTRB(
    32,
    32,
    32,
    52,
  );

  final MapTileSource source;
  final List<List<RoutePoint>> route;
  final RouteMapStyle style;
  final RouteMapGestures gestures;

  /// Optional von außen (etwa die Live-Seite, die der Position folgt).
  final MapController? mapController;
  final EdgeInsets fitPadding;
  final double maxFitZoom;

  /// Startkamera für eine Größe: Mitte und Zoom, in die Route samt Rand passt. `null` ohne Punkte.
  static ({LatLng center, double zoom})? startCamera(
    List<List<RoutePoint>> route,
    Size size, {
    EdgeInsets padding = defaultFitPadding,
    double maxZoom = 17,
  }) {
    final points = [
      for (final part in route)
        for (final p in part) LatLng(p.latitude, p.longitude),
    ];
    if (points.isEmpty || size.isEmpty) return null;
    final bounds = LatLngBounds.fromPoints(points);
    final base = MapCamera.initialCamera(
      MapOptions(initialCenter: bounds.center, initialZoom: 1),
    ).withNonRotatedSize(size);
    final fitted = CameraFit.bounds(
      bounds: bounds,
      padding: padding,
      maxZoom: maxZoom,
    ).fit(base);
    return (center: fitted.center, zoom: fitted.zoom);
  }

  int get _flags => switch (gestures) {
    RouteMapGestures.none => InteractiveFlag.none,
    RouteMapGestures.twoFinger =>
      InteractiveFlag.pinchZoom |
          InteractiveFlag.pinchMove |
          InteractiveFlag.doubleTapZoom,
    RouteMapGestures.full =>
      InteractiveFlag.drag |
          InteractiveFlag.flingAnimation |
          InteractiveFlag.pinchZoom |
          InteractiveFlag.pinchMove |
          InteractiveFlag.doubleTapZoom |
          InteractiveFlag.doubleTapDragZoom,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ohne bekannte Größe keine Kachelebene (sonst Kacheln am Standardzentrum).
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            constraints.biggest.isEmpty) {
          return const SizedBox.shrink();
        }
        final cam = startCamera(
          route,
          constraints.biggest,
          padding: fitPadding,
          maxZoom: maxFitZoom,
        );
        if (cam == null) return const SizedBox.shrink();
        return Stack(
          fit: StackFit.expand,
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: cam.center,
                initialZoom: cam.zoom,
                maxZoom: 18,
                backgroundColor: style.backgroundColor,
                interactionOptions: InteractionOptions(flags: _flags),
              ),
              children: [source.layer(), ..._routeLayers()],
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: _Attribution(
                  key: const Key('map_attribution'),
                  text: source.attribution,
                  style: style,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _routeLayers() {
    LatLng ll(RoutePoint p) => LatLng(p.latitude, p.longitude);
    final lines = <Polyline>[
      for (final part in route)
        if (part.length >= 2)
          Polyline(
            points: [for (final p in part) ll(p)],
            strokeWidth: style.lineWidth,
            color: style.lineColor,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
    ];
    final singles = <CircleMarker>[
      for (final part in route)
        if (part.length == 1)
          CircleMarker(
            point: ll(part.first),
            radius: math.max(style.lineWidth / 2, 2),
            color: style.lineColor,
          ),
    ];
    final all = [for (final p in route) ...p];
    CircleMarker dot(RoutePoint p, Color c) => CircleMarker(
      point: ll(p),
      radius: style.markerRadius,
      color: c,
      borderColor: style.markerBorderColor,
      borderStrokeWidth: style.markerBorderWidth,
    );
    return [
      PolylineLayer(polylines: lines),
      CircleLayer(circles: singles),
      if (all.isNotEmpty)
        CircleLayer(
          circles: [
            dot(all.last, style.endColor),
            dot(all.first, style.startColor),
          ],
        ),
    ];
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({super.key, required this.text, required this.style});

  final String text;
  final RouteMapStyle style;

  @override
  Widget build(BuildContext context) {
    // Kein Tippen, kein Ausblenden: die Angabe gehört fest zur Karte.
    return IgnorePointer(
      child: Semantics(
        container: true,
        label: text,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: style.attributionBackground,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                text,
                style: (style.attributionTextStyle ?? const TextStyle())
                    .copyWith(color: style.attributionForeground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live-Karte: folgt der Position, zeigt die bisherige Strecke (ein Linienzug je zusammenhängendem Teil) und die
/// Position als Punkt mit Hof. Die Kamera steht erst mit einer Position (R008 Hinweis 5, ADR-0009 Punkt 2): ohne sie
/// gibt es keine Kachelebene, also keine Kachelanfrage und keine Kamera am Standardzentrum der Bibliothek.
///
/// [following] gehört dem Aufrufer. Verschiebt oder zoomt der Nutzer die Karte (Geste), ruft sie [onUserMove] und
/// folgt nicht mehr, bis [following] wieder `true` ist; dann springt die Kamera auf die Position. Bis dahin ändern
/// neue Positionen die Kamera nicht. Ein Finger verschiebt (die Seite wischt nicht über die Karte).
class LiveRouteMap extends StatefulWidget {
  const LiveRouteMap({
    super.key,
    required this.source,
    required this.route,
    required this.position,
    required this.following,
    required this.onUserMove,
    required this.style,
    this.zoom = 16,
  });

  final MapTileSource source;
  final List<List<RoutePoint>> route;

  /// Aktuelle Position; `null`, solange keine akzeptiert ist (dann keine Kachelebene).
  final RoutePoint? position;
  final bool following;
  final VoidCallback onUserMove;
  final RouteMapStyle style;

  /// Zoomstufe, mit der die Karte beginnt und beim Zentrieren bleibt, solange der Nutzer nicht zoomt.
  final double zoom;

  @override
  State<LiveRouteMap> createState() => _LiveRouteMapState();
}

class _LiveRouteMapState extends State<LiveRouteMap> {
  final MapController _controller = MapController();
  bool _ready = false;

  static const _gestureSources = {
    MapEventSource.dragStart,
    MapEventSource.onDrag,
    MapEventSource.flingAnimationController,
    MapEventSource.multiFingerGestureStart,
    MapEventSource.onMultiFinger,
    MapEventSource.doubleTapZoomAnimationController,
  };

  LatLng? get _at {
    final p = widget.position;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  @override
  void didUpdateWidget(LiveRouteMap old) {
    super.didUpdateWidget(old);
    final at = _at;
    if (at == null || !_ready || !widget.following) return;
    if (widget.position != old.position || !old.following) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.following) return;
        final next = _at;
        if (next == null) return;
        _controller.move(next, _controller.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEvent(MapEvent e) {
    if (widget.following && _gestureSources.contains(e.source)) {
      widget.onUserMove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final at = _at;
    if (at == null) return ColoredBox(color: style.backgroundColor);
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: at,
            initialZoom: widget.zoom,
            maxZoom: 18,
            backgroundColor: style.backgroundColor,
            onMapReady: () => _ready = true,
            onMapEvent: _onEvent,
            interactionOptions: const InteractionOptions(
              flags:
                  InteractiveFlag.drag |
                  InteractiveFlag.flingAnimation |
                  InteractiveFlag.pinchZoom |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [widget.source.layer(), ..._layers(at)],
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width,
            ),
            child: _Attribution(
              key: const Key('map_attribution'),
              text: widget.source.attribution,
              style: style,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _layers(LatLng at) {
    final style = widget.style;
    LatLng ll(RoutePoint p) => LatLng(p.latitude, p.longitude);
    final lines = <Polyline>[
      for (final part in widget.route)
        if (part.length >= 2)
          Polyline(
            points: [for (final p in part) ll(p)],
            strokeWidth: style.lineWidth,
            color: style.lineColor,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
    ];
    final first = widget.route
        .where((p) => p.isNotEmpty)
        .map((p) => p.first)
        .firstOrNull;
    final pos = style.positionColor ?? style.endColor;
    return [
      PolylineLayer(polylines: lines),
      CircleLayer(
        circles: [
          if (first != null)
            CircleMarker(
              point: ll(first),
              radius: style.markerRadius,
              color: style.startColor,
              borderColor: style.markerBorderColor,
              borderStrokeWidth: style.markerBorderWidth,
            ),
          CircleMarker(
            point: at,
            radius: 16,
            color: pos.withValues(alpha: 0.3),
          ),
          CircleMarker(
            point: at,
            radius: 9,
            color: pos,
            borderColor: style.positionBorderColor,
            borderStrokeWidth: 3,
          ),
        ],
      ),
    ];
  }
}
