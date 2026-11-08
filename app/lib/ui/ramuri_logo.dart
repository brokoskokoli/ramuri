import 'package:flutter/material.dart';

/// Gestaltung des Logos.
enum RamuriLogoStyle {
  /// Zeichen über der Wortmarke, nur auf dunklem Grund (Willkommen).
  stackedOnDark,

  /// Zeichen neben der Wortmarke; Hell oder Dunkel folgt dem Theme.
  horizontal,
}

/// Das Logo als PNG aus `assets/brand/` (Herkunft: `assets/brand/README.md`).
/// [semanticLabel] liest die Bedienungshilfe vor (Name der App).
class RamuriLogo extends StatelessWidget {
  const RamuriLogo({
    super.key,
    required this.semanticLabel,
    this.style = RamuriLogoStyle.horizontal,
    this.width,
  });

  final String semanticLabel;
  final RamuriLogoStyle style;

  /// Breite in dp; sonst 168 (gestapelt) beziehungsweise 110 (horizontal).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (asset, defaultWidth) = switch (style) {
      RamuriLogoStyle.stackedOnDark => (
        'assets/brand/ramuri-logo-stacked-on-dark.png',
        168.0,
      ),
      RamuriLogoStyle.horizontal => (
        dark
            ? 'assets/brand/ramuri-logo-horizontal-on-dark.png'
            : 'assets/brand/ramuri-logo-horizontal-on-light.png',
        110.0,
      ),
    };
    return Image.asset(
      asset,
      width: width ?? defaultWidth,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.medium,
    );
  }
}
