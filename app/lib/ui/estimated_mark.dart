import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'ember_dot.dart';

/// Kennzeichnung „geschätzt“ mit Glutpunkt (CON-0009). Der Text kommt aus der
/// Lokalisierung, die Farbe des Wortes ist Textgrau, nie Glut.
class EstimatedMark extends StatelessWidget {
  const EstimatedMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const EmberDot(),
        const SizedBox(width: 4),
        // Flexible: bei großer Schrift in einer schmalen Kachel umbrechen
        // statt überlaufen.
        Flexible(
          child: Text(
            AppLocalizations.of(context).uiEstimated,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
