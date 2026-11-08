import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Ein Tag der [RamuriWeekStrip].
@immutable
class RamuriWeekDay {
  const RamuriWeekDay({
    required this.label,
    required this.semanticLabel,
    required this.done,
    this.today = false,
    this.future = false,
  });

  /// Kurzer Name (Mo), sichtbar unter dem Kreis.
  final String label;

  /// Für die Bedienungshilfe, etwa „Montag, gelaufen“.
  final String semanticLabel;

  /// Es wurde gelaufen: Kreis in Minze mit Haken.
  final bool done;

  /// Der heutige Tag: gestrichelter Ring (ohne Lauf), Beschriftung kräftig
  /// in Textfarbe (auch mit Lauf).
  final bool today;

  /// Ein Tag nach heute: weißer Kreis mit Rand.
  final bool future;
}

/// Woche als Reihe von sieben Kreisen mit Namen darunter (Design „Heute“).
/// Die Tage ([days], Montag bis Sonntag) kommen fertig vom Aufrufer; jeder
/// Tag ist als Ganzes beschriftet.
class RamuriWeekStrip extends StatelessWidget {
  const RamuriWeekStrip({super.key, required this.days});

  final List<RamuriWeekDay> days;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final label = Theme.of(context).textTheme.labelSmall!;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Semantics(
              key: Key('week_day_$i'),
              container: true,
              excludeSemantics: true,
              label: days[i].semanticLabel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dot(c, days[i]),
                  const SizedBox(height: 6),
                  Text(
                    days[i].label,
                    style: days[i].today
                        ? label.copyWith(color: c.text)
                        : label,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Gelaufen: Minze mit Haken. Heute (ohne Lauf): gestrichelter Ring auf
  /// Tönung. Künftig: weiß mit Rand. Vergangen ohne Lauf: grau.
  static Widget _dot(RamuriColors c, RamuriWeekDay day) {
    if (day.done) {
      return Container(
        key: const Key('week_dot_done'),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.action),
        child: Icon(Icons.check_rounded, size: 18, color: c.onAction),
      );
    }
    if (day.today) {
      return CustomPaint(
        key: const Key('week_dot_today'),
        size: const Size(34, 34),
        painter: _DashedRing(fill: c.tint, line: c.accent),
      );
    }
    return Container(
      key: Key(day.future ? 'week_dot_future' : 'week_dot_past'),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: day.future ? c.surface : c.outline,
        border: day.future ? Border.all(color: c.outline, width: 2) : null,
      ),
    );
  }
}

class _DashedRing extends CustomPainter {
  const _DashedRing({required this.fill, required this.line});

  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    final ring = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const dashes = 14;
    const sweep = 2 * 3.141592653589793 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(ring, i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.fill != fill || old.line != line;
}
