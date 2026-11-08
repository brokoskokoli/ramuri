import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Feste Dunkel-Fläche für Seiten, die in beiden Modi dunkel bleiben
/// (Willkommen, Intervall; FR-0205). Setzt das dunkle Theme für alles darunter
/// und füllt den Grund.
class RamuriDarkScope extends StatelessWidget {
  const RamuriDarkScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: RamuriTheme.dark,
      // Helle Symbole der Statusleiste auf dem dunklen Grund, auch im hellen
      // System.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: ramuriOverlayStyle(Brightness.dark),
        child: Builder(
          builder: (context) => Material(
            color: RamuriColors.of(context).background,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Stil der Systemleisten zu einem Grund der Helligkeit [surface]: auf hellem
/// Grund dunkle Symbole, auf dunklem helle.
SystemUiOverlayStyle ramuriOverlayStyle(Brightness surface) {
  final darkSurface = surface == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: darkSurface ? Brightness.light : Brightness.dark,
    statusBarBrightness: surface,
  );
}
