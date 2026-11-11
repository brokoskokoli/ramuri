import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Seitengerüst der Ruhepuls-Screens (Design `ruhepuls/*`): Kopfzeile oben,
/// Inhalt scrollbar, Fußzeile (Knöpfe) unten angeheftet.
class RestingPage extends StatelessWidget {
  const RestingPage({
    super.key,
    required this.header,
    required this.sections,
    this.footer,
  });

  final Widget header;
  final List<Widget> sections;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        sections[i],
                      ],
                    ],
                  ),
                ),
              ),
              if (footer != null) ...[const SizedBox(height: 12), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Runder Knopf mit Symbol, 48 dp (Zurück, Schließen, Ton).
class RestingRoundButton extends StatelessWidget {
  const RestingRoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.toggled,
  });

  final IconData icon;
  final String label;

  /// `null`: nicht bedienbar.
  final VoidCallback? onPressed;

  /// Nicht `null`: Umschalter mit diesem Zustand.
  final bool? toggled;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Semantics(
      button: true,
      toggled: toggled,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      enabled: onPressed != null,
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: RamuriTheme.minTarget,
            child: Icon(
              icon,
              size: 22,
              color: onPressed == null ? c.outlineStrong : c.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// „Abbrechen“ als Pille mit Rand, mindestens 48 dp hoch.
class RestingCancelButton extends StatelessWidget {
  const RestingCancelButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Material(
      color: c.surface,
      shape: StadiumBorder(side: BorderSide(color: c.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RamuriTheme.minTarget,
            minWidth: RamuriTheme.minTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              widthFactor: 1,
              child: Text(
                AppLocalizations.of(context).measureCancel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Textlink, mindestens 48 dp hoch.
class RestingTextLink extends StatelessWidget {
  const RestingTextLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.alignment = Alignment.center,
  });

  final String label;
  final VoidCallback onPressed;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RamuriTheme.minTarget),
        child: Align(
          alignment: alignment,
          child: Text(
            label,
            style: RamuriType.of(context).link.copyWith(color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// Karte mit abgerundeter Fläche (Design: Radius 20 bis 24).
class RestingCard extends StatelessWidget {
  const RestingCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? RamuriColors.of(context).surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Drei Balken für die Signalqualität (1 bis 3 gefüllt).
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: i < level ? c.accent : c.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: SizedBox(width: 5, height: 6.0 + 5 * i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// „m:ss“ für eine Dauer.
String restingClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String restingPostureLabel(AppLocalizations l10n, RestingPosture p) =>
    switch (p) {
      RestingPosture.sitting => l10n.measurePostureSitting,
      RestingPosture.lying => l10n.measurePostureLying,
    };

/// Länge des Messfensters in ganzen Sekunden (Anzeige „von 60 s“).
int restingWindowSeconds() =>
    (ppgStandardWindow.end - ppgStandardWindow.start).round();

/// Erklärbild: Rückseite des Handys, Fingerkuppe auf Kamera und Blitz (Design
/// `Main.dc.html`). Die Beschriftungen liegen als Text darüber.
class FingerIllustration extends StatelessWidget {
  const FingerIllustration({super.key});

  static const double _w = 350;
  static const double _h = 178;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final label = Theme.of(context).textTheme.labelMedium!
        .copyWith(color: c.textMuted);
    return Semantics(
      image: true,
      label: l10n.measureFingerSemantics,
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: _w,
            height: _h,
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _FingerPainter(c))),
                Positioned(
                  left: 0,
                  width: 64,
                  top: 54,
                  child: Text(
                    l10n.measureFingerCamera,
                    textAlign: TextAlign.end,
                    style: label,
                  ),
                ),
                Positioned(
                  left: 282,
                  top: 94,
                  child: Text(l10n.measureFingerFlash, style: label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FingerPainter extends CustomPainter {
  _FingerPainter(this.c);

  final RamuriColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Handy
    fill.color = c.tint;
    final phone = RRect.fromRectAndRadius(
      const Rect.fromLTWH(92, 14, 170, 200),
      const Radius.circular(30),
    );
    canvas.drawRRect(phone, fill);
    canvas.drawRRect(
      phone,
      line
        ..color = c.text
        ..strokeWidth = 2,
    );
    // Kameramodul, Linse
    fill.color = c.panel;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(106, 30, 62, 96),
        const Radius.circular(18),
      ),
      fill,
    );
    fill.color = c.textMuted;
    canvas.drawCircle(const Offset(128, 100), 13, fill);
    fill.color = c.panel;
    canvas.drawCircle(const Offset(128, 100), 6, fill);
    // Glut-Schein hinter dem Finger (Schätz-Akzent des Designs)
    fill.color = c.ember.withValues(alpha: 0.16);
    canvas.drawCircle(const Offset(140, 62), 40, fill);
    // Finger
    const from = Offset(140, 62);
    const to = Offset(330, -40);
    canvas.drawLine(
      from,
      to,
      line
        ..color = c.text
        ..strokeWidth = 58,
    );
    canvas.drawLine(
      from,
      to,
      line
        ..color = c.background
        ..strokeWidth = 54,
    );
    // Kamera und Blitz unter dem Finger (gestrichelt angedeutet)
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..color = c.text
      ..strokeWidth = 1.5;
    _dashedCircle(canvas, const Offset(128, 62), 13, 8, dash);
    _dashedCircle(canvas, const Offset(154, 56), 6, 6, dash);
    // Hinweislinien
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..color = c.textMuted
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(114, 62), const Offset(70, 62), guide);
    canvas.drawLine(const Offset(160, 60), const Offset(196, 104), guide);
    canvas.drawLine(const Offset(196, 104), const Offset(276, 104), guide);
  }

  void _dashedCircle(Canvas canvas, Offset o, double r, int n, Paint p) {
    final step = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: o, radius: r),
        i * step,
        step * 0.5,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_FingerPainter old) => old.c != c;
}

/// Ring der Ruhephase: Spur und Restanteil.
class RestRing extends StatelessWidget {
  const RestRing({
    super.key,
    required this.fraction,
    required this.child,
    this.size = 264,
  });

  /// Restanteil von 0 bis 1.
  final double fraction;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(fraction.clamp(0.0, 1.0), c.track, c.accent),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.track, this.ring);

  final double fraction;
  final Color track;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p);
    if (fraction > 0) {
      p.color = ring;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, p);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.ring != ring;
}

/// Pulskurve der letzten Sekunden aus den Rohwerten des Controllers.
class PulseCurve extends StatelessWidget {
  const PulseCurve({super.key, required this.values, required this.strong});

  final List<double> values;

  /// Gutes Signal: Kurve in Glut, sonst gedämpft.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: CustomPaint(
        painter: _CurvePainter(values, strong ? c.emberDot : c.outlineStrong),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (values.length < 2) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        p,
      );
      return;
    }
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final span = hi - lo;
    final path = Path();
    const pad = 6.0;
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = span <= 0 || !span.isFinite
          ? size.height / 2
          : size.height -
                pad -
                (values[i] - lo) / span * (size.height - 2 * pad);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      !identical(old.values, values) || old.color != color;
}
