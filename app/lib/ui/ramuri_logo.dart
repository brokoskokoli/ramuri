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
    final defaultWidth = switch (style) {
      RamuriLogoStyle.stackedOnDark => 168.0,
      RamuriLogoStyle.horizontal => 110.0,
    };
    return Image(
      image: ramuriLogoImage(style, Theme.of(context).brightness),
      width: width ?? defaultWidth,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Bildquelle des Logos in [style] auf einem Grund der Helligkeit
/// [brightness] (nur für [RamuriLogoStyle.horizontal] von Belang).
ImageProvider ramuriLogoImage(RamuriLogoStyle style, Brightness brightness) =>
    AssetImage(switch (style) {
      RamuriLogoStyle.stackedOnDark =>
        'assets/brand/ramuri-logo-stacked-on-dark.png',
      RamuriLogoStyle.horizontal =>
        brightness == Brightness.dark
            ? 'assets/brand/ramuri-logo-horizontal-on-dark.png'
            : 'assets/brand/ramuri-logo-horizontal-on-light.png',
    });

/// Lädt das Logo in [style] vorab in den Bildspeicher, damit es im selben
/// Bild wie der Text daneben erscheint statt ein Bild später. Ein Fehler
/// bleibt folgenlos: dann lädt [RamuriLogo] das Bild selbst.
Future<void> precacheRamuriLogo(
  BuildContext context, {
  RamuriLogoStyle style = RamuriLogoStyle.horizontal,
}) => precacheImage(
  ramuriLogoImage(style, Theme.of(context).brightness),
  context,
  onError: (_, _) {},
);
