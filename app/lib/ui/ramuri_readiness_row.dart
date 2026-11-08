import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Zeile einer Bereitschaftsliste (Design „Lauf vorbereiten“): Symbolkachel,
/// Titel mit Zeile darunter und rechts ein Zustand oder eine Aktion. Mindestens
/// 56 dp hoch, wächst mit der Schrift. [trailing] bringt seine 48 dp
/// Tippfläche selbst mit.
class RamuriReadinessRow extends StatelessWidget {
  const RamuriReadinessRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.muted = false,
    this.divider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Symbolkachel grau statt Minze (Zustand ohne Wert, etwa kein Sensor).
  final bool muted;

  /// Trennlinie unter der Zeile; die letzte Zeile hat keine.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: c.track)) : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: muted ? c.track : c.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  icon,
                  size: 20,
                  color: muted ? c.textMuted : c.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.titleSmall),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.labelSmall),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: RamuriTheme.minTarget,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
