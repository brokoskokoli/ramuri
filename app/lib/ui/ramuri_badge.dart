import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Kleine Marke in Glut („Schätzung“ auf der VO₂max-Karte, Design
/// Fortschritt). Fläche [RamuriColors.emberSoft], Schrift [RamuriColors.onEmber];
/// beide Töne liegen im Kontrasttest.
class RamuriBadge extends StatelessWidget {
  const RamuriBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.emberSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall!
              .copyWith(color: c.onEmber, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
