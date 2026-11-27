import 'dart:math' as math;

import 'package:adapters/adapters.dart' show RouteMapMark;
import 'package:core/core.dart';
import 'package:flutter/material.dart';

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.route,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
    this.padding = 16,
    this.strokeWidth = 3,
    this.markerRadius = 6,
    this.marks = const [],
    this.markColor,
    this.markTextColor,
    this.markBorderColor,
    this.markTextStyle,
  });

  final List<List<RoutePoint>> route;

  /// Kilometermarken mit Nummer (Detailansicht); fehlen die Farben, werden keine gemalt.
  final List<RouteMapMark> marks;
  final Color? markColor;
  final Color? markTextColor;
  final Color? markBorderColor;
  final TextStyle? markTextStyle;
  final Color lineColor;
  final Color startColor;
  final Color endColor;

  /// Rand, Strichstärke und Markenradius; die Miniatur im Verlauf nimmt kleinere Werte.
  final double padding;
  final double strokeWidth;
  final double markerRadius;

  /// Zahl der gezeichneten Linien: ein Teil mit mindestens zwei Punkten ist ein
  /// Pfad; Teile werden nie verbunden.
  int get pathCount => route.where((p) => p.length >= 2).length;

  /// Linien der Route: ein Pfad je zusammenhängendem Teil mit mindestens zwei
  /// Punkten, einzelne Punkte als Punkt, dazu Start und Ende. Teile werden
  /// nie verbunden.
  ({
    List<Path> paths,
    List<Offset> dots,
    Offset? start,
    Offset? end,
    List<({int index, Offset at})> marks,
  })
  shapes(Size size) {
    final all = [for (final p in route) ...p];
    if (all.isEmpty) {
      return (paths: [], dots: [], start: null, end: null, marks: []);
    }
    var minLat = all.first.latitude, maxLat = minLat;
    var minLon = all.first.longitude, maxLon = minLon;
    for (final p in all) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // Längentreue Annäherung: Längengrade schrumpfen mit cos(Breite).
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * k, 1e-9);
    final h = math.max(maxLat - minLat, 1e-9);
    final pad = padding;
    final scale = math.min(
      (size.width - 2 * pad) / w,
      (size.height - 2 * pad) / h,
    );
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset at(RoutePoint p) => Offset(
      ox + (p.longitude - minLon) * k * scale,
      oy + (maxLat - p.latitude) * scale,
    );
    final paths = <Path>[];
    final dots = <Offset>[];
    for (final part in route) {
      if (part.isEmpty) continue;
      if (part.length == 1) {
        dots.add(at(part.first));
        continue;
      }
      final path = Path()..moveTo(at(part.first).dx, at(part.first).dy);
      for (final p in part.skip(1)) {
        final o = at(p);
        path.lineTo(o.dx, o.dy);
      }
      paths.add(path);
    }
    return (
      paths: paths,
      dots: dots,
      start: at(all.first),
      end: at(all.last),
      marks: [for (final m in marks) (index: m.index, at: at(m.position))],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = shapes(size);
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in s.paths) {
      canvas.drawPath(path, paint);
    }
    for (final dot in s.dots) {
      canvas.drawCircle(dot, strokeWidth / 1.2, Paint()..color = lineColor);
    }
    // Start und Ende zuerst: die Kilometermarken liegen darüber.
    if (s.start != null) {
      canvas.drawCircle(s.start!, markerRadius, Paint()..color = startColor);
      canvas.drawCircle(s.end!, markerRadius, Paint()..color = endColor);
    }
    final fill = markColor, text = markTextColor, border = markBorderColor;
    if (fill != null && text != null && border != null) {
      for (final m in s.marks) {
        canvas.drawCircle(m.at, _markRadius, Paint()..color = fill);
        canvas.drawCircle(
          m.at,
          _markRadius,
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: '${m.index}',
            style: (markTextStyle ?? const TextStyle()).copyWith(
              color: text,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        tp.paint(canvas, m.at - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  static const double _markRadius = 12;

  @override
  bool shouldRepaint(RoutePainter old) =>
      old.marks != marks ||
      old.markColor != markColor ||
      old.route != route ||
      old.lineColor != lineColor ||
      old.startColor != startColor ||
      old.endColor != endColor ||
      old.padding != padding ||
      old.strokeWidth != strokeWidth ||
      old.markerRadius != markerRadius;
}
