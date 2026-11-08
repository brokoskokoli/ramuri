import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Mindestspanne der y-Achse in Einheiten der Werte. Sie ist auf VO₂max
/// (ml/kg/min) abgestimmt: Bei 2,0 füllt eine Änderung um 0,1 nur 5 % der Höhe
/// (gut 2 dp bei 44 dp), wirkt also nicht wie ein großer Sprung. Ein Wert aus
/// dem Gefühl, nicht aus der Spec; andere Größen übergeben ihre eigene Spanne.
const double ramuriSparklineMinSpan = 2.0;

/// Kleine Verlaufslinie ohne Achsen (Design „Fortschritt“, Trend der VO₂max).
/// Sie zeigt sich erst ab zwei Werten; sonst bleibt der Platz leer
/// ([SizedBox.shrink]), denn aus einem Punkt gibt es keinen Trend.
///
/// Ist der Abstand zwischen größtem und kleinstem Wert kleiner als [minSpan],
/// wird die y-Achse auf [minSpan] um die Mitte der Werte geweitet; die Linie
/// bleibt dann flach. Die Linie nutzt die Aktionsfarbe (Minze), gedacht für
/// dunkle Karten. [semanticLabel] liefert der Aufrufer (etwa „Trend leicht
/// steigend“).
class RamuriSparkline extends StatelessWidget {
  const RamuriSparkline({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.width = 120,
    this.height = 44,
    this.minSpan = ramuriSparklineMinSpan,
  }) : assert(minSpan > 0);

  /// Werte, ältester zuerst.
  final List<double> values;
  final String semanticLabel;
  final double width;
  final double height;
  final double minSpan;

  static const double _strokeWidth = 3;

  /// Punkte der Linie in der Zeichenfläche [size]; höhere Werte liegen oben.
  /// Leer unter zwei Werten.
  @visibleForTesting
  static List<Offset> pointsFor(
    List<double> values,
    Size size, {
    double minSpan = ramuriSparklineMinSpan,
  }) {
    if (values.length < 2) return const [];
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    const pad = _strokeWidth / 2 + 1;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    return [
      for (var i = 0; i < values.length; i++)
        Offset(
          pad + w * i / (values.length - 1),
          pad + h * (1 - (values[i] - lo) / (hi - lo)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox.shrink();
    final c = RamuriColors.of(context);
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: CustomPaint(
        key: const Key('sparkline'),
        size: Size(width, height),
        painter: SparklinePainter(
          points: pointsFor(values, Size(width, height), minSpan: minSpan),
          color: c.action,
        ),
      ),
    );
  }
}

/// Zeichnet die Linie der [RamuriSparkline].
@visibleForTesting
class SparklinePainter extends CustomPainter {
  const SparklinePainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = RamuriSparkline._strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter old) =>
      old.color != color || old.points.length != points.length || !_same(old);

  bool _same(SparklinePainter o) {
    for (var i = 0; i < points.length; i++) {
      if (o.points[i] != points[i]) return false;
    }
    return true;
  }
}
