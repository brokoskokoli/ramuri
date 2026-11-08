import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Wahl-Chip (Zeitraum, Befinden): Pille mit Rand; gewählt mit Tönung und
/// Akzentrand. Sichtbar 44 dp hoch, die Fläche zum Tippen mindestens 48 dp.
class RamuriChip extends StatelessWidget {
  const RamuriChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final style = Theme.of(context).textTheme.labelMedium!;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: onPressed,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RamuriTheme.minTarget,
            minWidth: RamuriTheme.minTarget,
          ),
          child: Center(
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? c.tint : c.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? c.accent : c.outline,
                  width: 1.5,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Center(
                    widthFactor: 1,
                    child: Text(label, style: style),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
