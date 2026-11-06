import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';

/// Route und Diagramme eines Laufs (FR-0041, FR-0042), mit Flutter-Mitteln
/// gezeichnet: kein Kartenpaket, kein Netz (SEC-0008, OQ-0065). Unterbrechungen
/// (Positionslücke, Pulslücke, manuelle Pause) bleiben offen; Teile werden nie
/// zu einer Linie verbunden.
class RunDetailCharts extends StatelessWidget {
  const RunDetailCharts({
    super.key,
    required this.data,
    required this.formatter,
  });

  final RunDetailData data;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = theme.textTheme.titleSmall;
    final pace = ChartLayer(
      name: l10n.detPaceName,
      parts: data.pace,
      color: scheme.primary,
      format: formatter.pace,
      inverted: true,
      robust: true,
    );
    final hr = ChartLayer(
      name: l10n.detHeartRateName,
      parts: data.heartRate,
      color: scheme.error,
      format: (v) => l10n.runBpm(v!.round()),
    );
    final altitude = ChartLayer(
      name: l10n.detAltitudeName,
      parts: data.altitude,
      color: scheme.tertiary,
      format: formatter.elevation,
    );
    Widget section(String heading, Widget child) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: title),
          child,
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(
          l10n.sumRoute,
          data.route.isEmpty
              ? Text(l10n.detRouteNone, key: const Key('detail_route_none'))
              : RunRouteView(route: data.route),
        ),
        section(
          l10n.detPaceChart,
          _chart(
            context,
            const Key('detail_pace'),
            [pace],
            l10n.detPaceNone,
            const Key('detail_pace_none'),
          ),
        ),
        section(
          l10n.detHeartRateChart,
          _chart(
            context,
            const Key('detail_hr'),
            [hr],
            l10n.sumNoHeartRate,
            const Key('detail_hr_none'),
          ),
        ),
        section(
          l10n.detCompareChart,
          _chart(
            context,
            const Key('detail_compare'),
            [pace, hr],
            l10n.detCompareNone,
            const Key('detail_compare_none'),
          ),
        ),
        section(
          l10n.sumElevation,
          _chart(
            context,
            const Key('detail_altitude'),
            [altitude],
            l10n.detAltitudeNone,
            const Key('detail_altitude_none'),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.detGapNote, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _chart(
    BuildContext context,
    Key key,
    List<ChartLayer> layers,
    String none,
    Key noneKey,
  ) {
    if (layers.any((l) => l.parts.every((p) => p.isEmpty))) {
      return Text(none, key: noneKey);
    }
    return RunSeriesChart(
      key: key,
      layers: layers,
      totalSeconds: data.totalSeconds,
      pauses: data.pauses,
    );
  }
}

/// Eine Linie (Reihe aus Teilen) eines Diagramms.
class ChartLayer {
  const ChartLayer({
    required this.name,
    required this.parts,
    required this.color,
    required this.format,
    this.inverted = false,
    this.robust = false,
  });

  final String name;
  final List<List<DetailPoint>> parts;
  final Color color;
  final String Function(double? value) format;

  /// Schnelle (kleine) Werte oben, etwa bei der Pace.
  final bool inverted;

  /// Achse nach dem 2.- bis 98.-Perzentil, Ausreißer werden am Rand
  /// abgeschnitten (langsames Gehen soll die Pace-Achse nicht stauchen).
  final bool robust;

  Iterable<double> get values sync* {
    for (final p in parts) {
      for (final v in p) {
        yield v.value;
      }
    }
  }

  /// Echter Kleinst- und Größtwert der Reihe (nicht der Achse).
  double get minValue => values.reduce(math.min);
  double get maxValue => values.reduce(math.max);

  /// Ob die Achse Werte abschneidet (nur bei [robust]): Diese Werte werden am
  /// Rand gezeichnet, nicht an ihrer Stelle.
  bool get clipped {
    final r = range;
    return minValue < r.lo - 1e-9 || maxValue > r.hi + 1e-9;
  }

  /// Wertebereich der Achse.
  ({double lo, double hi}) get range {
    final all = values.toList()..sort();
    var lo = all.first;
    var hi = all.last;
    if (robust && all.length >= 20) {
      lo = all[(all.length * 0.02).floor()];
      hi = all[math.min(all.length - 1, (all.length * 0.98).ceil())];
    }
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    return (lo: lo, hi: hi);
  }
}

class RunSeriesChart extends StatelessWidget {
  const RunSeriesChart({
    super.key,
    required this.layers,
    required this.totalSeconds,
    required this.pauses,
  });

  final List<ChartLayer> layers;
  final double totalSeconds;
  final List<({double start, double end})> pauses;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = layers.fold<int>(
      0,
      (n, l) => math.max(n, l.parts.where((p) => p.isNotEmpty).length),
    );
    final notes = [
      for (final l in layers)
        if (l.clipped) l10n.detClipped(l.name),
    ];
    final String base;
    if (layers.length == 1) {
      // Echter Kleinst- und Größtwert, auch wenn die Achse Ausreißer abschneidet.
      final layer = layers.single;
      base = l10n.detChartSemantics(
        layer.name,
        layer.format(layer.minValue),
        layer.format(layer.maxValue),
        parts,
      );
    } else {
      base = l10n.detCompareSemantics(layers[0].name, layers[1].name, parts);
    }
    final label = [base, ...notes].join(' ');
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = theme.textTheme.bodySmall?.fontSize ?? 12;
    // Drei Textzeilen (oben, Kleinstwerte, Zeit) wachsen mit der Schrift, die
    // Zeichenfläche bleibt gleich.
    final height = 180 + 1.5 * (3 * scaler.scale(fontSize) - 2 * fontSize);
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      color: theme.colorScheme.onSurface,
    );
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (layers.length > 1)
            Wrap(
              spacing: 16,
              children: [
                for (final l in layers)
                  Text(
                    l.name,
                    style: style.copyWith(
                      color: l.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          SizedBox(
            height: height,
            width: double.infinity,
            child: CustomPaint(
              key: const Key('chart_paint'),
              painter: SeriesChartPainter(
                layers: layers,
                totalSeconds: totalSeconds,
                pauses: pauses,
                axisColor: theme.colorScheme.outline,
                pauseColor: theme.colorScheme.outlineVariant.withValues(
                  alpha: 0.4,
                ),
                textStyle: style,
                textScaler: scaler,
                clock: (s) => formatClock(Duration(seconds: s.round())),
              ),
            ),
          ),
          for (final n in notes)
            Text(n, key: const Key('chart_clipped'), style: style),
        ],
      ),
    );
  }
}

/// Zeichnet die Teile einer Reihe als getrennte Linien (siehe [linePaths]).
class SeriesChartPainter extends CustomPainter {
  SeriesChartPainter({
    required this.layers,
    required this.totalSeconds,
    required this.pauses,
    required this.axisColor,
    required this.pauseColor,
    required this.textStyle,
    required this.clock,
    this.textScaler = TextScaler.noScaling,
  });

  final List<ChartLayer> layers;
  final double totalSeconds;
  final List<({double start, double end})> pauses;
  final Color axisColor;
  final Color pauseColor;
  final TextStyle textStyle;
  final TextScaler textScaler;
  final String Function(double seconds) clock;

  ({TextPainter painter, Offset offset}) _label(
    String text,
    Offset at, {
    Color? color,
    TextAlign align = TextAlign.left,
    double maxWidth = 80,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: color == null ? textStyle : textStyle.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.right || TextAlign.end => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    return (painter: tp, offset: Offset(dx, at.dy));
  }

  /// Alle Achsentexte mit ihrer Lage: oben Größtwert, unter dem Plot in einer
  /// Zeile die Kleinstwerte und darunter in einer eigenen Zeile die Zeit.
  List<({String text, TextPainter painter, Offset offset, Color? color})>
  _axisTexts(Size size) {
    final plot = plotRect(size);
    final span = totalSeconds <= 0 ? 1.0 : totalSeconds;
    final yMinRow = plot.bottom + 2;
    final xRow = plot.bottom + labelHeight + 2;
    final out =
        <({String text, TextPainter painter, Offset offset, Color? color})>[];
    void add(
      String text,
      Offset at, {
      Color? color,
      TextAlign? align,
      double? w,
    }) {
      final l = _label(
        text,
        at,
        color: color,
        align: align ?? TextAlign.left,
        maxWidth: w ?? 80,
      );
      out.add((text: text, painter: l.painter, offset: l.offset, color: color));
    }

    add(clock(0), Offset(plot.left, xRow));
    add(clock(span), Offset(plot.right, xRow), align: TextAlign.right);
    // Beim Vergleich je Linie in ihrer Farbe (links die erste, rechts die
    // zweite), sonst links.
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final r = layer.range;
      final top = layer.inverted ? r.lo : r.hi;
      final bottom = layer.inverted ? r.hi : r.lo;
      final right = i == 1;
      final x = right ? plot.right - 2 : plot.left + 2;
      final align = right ? TextAlign.right : TextAlign.left;
      final color = layers.length > 1 ? layer.color : null;
      add(
        layer.format(top),
        Offset(x, plot.top - labelHeight),
        color: color,
        align: align,
        w: plot.width / 2,
      );
      add(
        layer.format(bottom),
        Offset(x, yMinRow),
        color: color,
        align: align,
        w: plot.width / 2,
      );
    }
    return out;
  }

  /// Rechtecke aller Achsentexte (für Prüfungen auf Überlappung).
  List<({String text, Rect rect})> axisTextRects(Size size) => [
    for (final t in _axisTexts(size))
      (text: t.text, rect: t.offset & t.painter.size),
  ];

  double get labelHeight => textScaler.scale(textStyle.fontSize ?? 12) * 1.5;

  /// Zeichenfläche ohne die Achsenbeschriftung oben und unten (unten zwei
  /// Zeilen: Kleinstwerte, Zeit).
  Rect plotRect(Size size) {
    return Rect.fromLTRB(
      0,
      labelHeight,
      size.width,
      size.height - 2 * labelHeight,
    );
  }

  /// Die gezeichneten Linien je Reihe: ein Pfad je zusammenhängendem Teil mit
  /// mindestens zwei Punkten, einzelne Punkte als Punkt. Teile werden nie
  /// verbunden.
  List<({ChartLayer layer, List<Path> paths, List<Offset> dots})> _lines(
    Rect plot,
  ) {
    final span = totalSeconds <= 0 ? 1.0 : totalSeconds;
    double px(double seconds) =>
        plot.left + plot.width * (seconds / span).clamp(0.0, 1.0);
    return [
      for (final layer in layers)
        () {
          final r = layer.range;
          double py(double v) {
            var t = ((v - r.lo) / (r.hi - r.lo)).clamp(0.0, 1.0);
            if (!layer.inverted) t = 1 - t;
            return plot.top + plot.height * t;
          }

          final paths = <Path>[];
          final dots = <Offset>[];
          for (final part in layer.parts) {
            if (part.isEmpty) continue;
            if (part.length == 1) {
              dots.add(Offset(px(part.first.seconds), py(part.first.value)));
              continue;
            }
            final path = Path()
              ..moveTo(px(part.first.seconds), py(part.first.value));
            for (final p in part.skip(1)) {
              path.lineTo(px(p.seconds), py(p.value));
            }
            paths.add(path);
          }
          return (layer: layer, paths: paths, dots: dots);
        }(),
    ];
  }

  /// Gezeichnete Pfade (für Prüfungen).
  List<Path> linePaths(Size size) => [
    for (final l in _lines(plotRect(size))) ...l.paths,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawRect(plot, axis..style = PaintingStyle.stroke);
    final span = totalSeconds <= 0 ? 1.0 : totalSeconds;
    double px(double seconds) =>
        plot.left + plot.width * (seconds / span).clamp(0.0, 1.0);

    for (final p in pauses) {
      canvas.drawRect(
        Rect.fromLTRB(px(p.start), plot.top, px(p.end), plot.bottom),
        Paint()..color = pauseColor,
      );
    }
    canvas.save();
    canvas.clipRect(plot.inflate(1));
    for (final line in _lines(plot)) {
      for (final path in line.paths) {
        canvas.drawPath(
          path,
          Paint()
            ..color = line.layer.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeJoin = StrokeJoin.round,
        );
      }
      for (final dot in line.dots) {
        canvas.drawCircle(dot, 2.5, Paint()..color = line.layer.color);
      }
    }
    canvas.restore();

    for (final t in _axisTexts(size)) {
      t.painter.paint(canvas, t.offset);
    }
  }

  @override
  bool shouldRepaint(SeriesChartPainter old) =>
      old.layers != layers ||
      old.totalSeconds != totalSeconds ||
      old.pauses != pauses ||
      old.textScaler != textScaler ||
      old.axisColor != axisColor;
}

/// Die gezeichnete Route (ohne Karte).
class RunRouteView extends StatelessWidget {
  const RunRouteView({super.key, required this.route});

  final List<List<RoutePoint>> route;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final painter = RoutePainter(
      route: route,
      lineColor: scheme.primary,
      startColor: scheme.tertiary,
      endColor: scheme.error,
    );
    Widget legend(Key key, Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, key: key, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: l10n.detRouteSemantics(painter.pathCount),
          excludeSemantics: true,
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: CustomPaint(key: const Key('route_paint'), painter: painter),
          ),
        ),
        Wrap(
          spacing: 16,
          children: [
            legend(
              const Key('route_legend_start'),
              scheme.tertiary,
              l10n.detRouteStart,
            ),
            legend(
              const Key('route_legend_end'),
              scheme.error,
              l10n.detRouteEnd,
            ),
          ],
        ),
      ],
    );
  }
}

class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.route,
    required this.lineColor,
    required this.startColor,
    required this.endColor,
  });

  final List<List<RoutePoint>> route;
  final Color lineColor;
  final Color startColor;
  final Color endColor;

  /// Zahl der gezeichneten Linien: ein Teil mit mindestens zwei Punkten ist ein
  /// Pfad; Teile werden nie verbunden.
  int get pathCount => route.where((p) => p.length >= 2).length;

  /// Linien der Route: ein Pfad je zusammenhängendem Teil mit mindestens zwei
  /// Punkten, einzelne Punkte als Punkt, dazu Start und Ende. Teile werden
  /// nie verbunden.
  ({List<Path> paths, List<Offset> dots, Offset? start, Offset? end}) shapes(
    Size size,
  ) {
    final all = [for (final p in route) ...p];
    if (all.isEmpty) return (paths: [], dots: [], start: null, end: null);
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
    const pad = 16.0;
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
    return (paths: paths, dots: dots, start: at(all.first), end: at(all.last));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = shapes(size);
    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in s.paths) {
      canvas.drawPath(path, paint);
    }
    for (final dot in s.dots) {
      canvas.drawCircle(dot, 2.5, Paint()..color = lineColor);
    }
    if (s.start != null) {
      canvas.drawCircle(s.start!, 6, Paint()..color = startColor);
      canvas.drawCircle(s.end!, 6, Paint()..color = endColor);
    }
  }

  @override
  bool shouldRepaint(RoutePainter old) =>
      old.route != route || old.lineColor != lineColor;
}
