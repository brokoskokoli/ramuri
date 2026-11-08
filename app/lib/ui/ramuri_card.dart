import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Farbe einer [RamuriCard].
enum RamuriCardTone {
  /// Weiße Karte (hell) beziehungsweise Nachtgrün (dunkel).
  surface,

  /// Hervorgehobene Minzfläche für die große Kennzahl.
  accent,

  /// Dunkle Karte, auch auf hellem Grund. Der Inhalt sieht das dunkle Theme.
  panel,
}

/// Karte nach dem Design: gerundete Fläche ohne Schatten. Mit [onTap] ist sie
/// mindestens 48 dp hoch und bedienbar.
class RamuriCard extends StatelessWidget {
  const RamuriCard({
    super.key,
    required this.child,
    this.tone = RamuriCardTone.surface,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
    this.onTap,
  });

  final Widget child;
  final RamuriCardTone tone;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final (background, foreground) = switch (tone) {
      RamuriCardTone.surface => (c.surface, c.text),
      RamuriCardTone.accent => (c.accentPanel, c.text),
      RamuriCardTone.panel => (c.panel, c.onPanel),
    };
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RamuriTheme.minTarget,
            minWidth: RamuriTheme.minTarget,
          ),
          child: content,
        ),
      );
    }
    Widget card = Material(
      color: background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: content,
        ),
      ),
    );
    if (tone == RamuriCardTone.panel) {
      card = Theme(data: RamuriTheme.dark, child: card);
    }
    return card;
  }
}
