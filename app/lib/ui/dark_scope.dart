import 'package:flutter/material.dart';

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
      child: Builder(
        builder: (context) =>
            Material(color: RamuriColors.of(context).background, child: child),
      ),
    );
  }
}
