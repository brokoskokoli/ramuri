import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Ein Abschnitt eines [RamuriSegmentedToggle].
class RamuriSegment<T> {
  const RamuriSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Umschalter zwischen Ansichten (etwa Werte und Karte): Pille mit einem
/// gewählten Abschnitt. Jeder Abschnitt ist mindestens 48 dp hoch und breit.
class RamuriSegmentedToggle<T> extends StatelessWidget {
  const RamuriSegmentedToggle({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<RamuriSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in segments)
                _SegmentButton(
                  label: s.label,
                  selected: s.value == selected,
                  onTap: () => onChanged(s.value),
                  colors: c,
                  style: labelStyle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.style,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RamuriColors colors;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: Material(
        color: selected ? colors.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
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
                  label,
                  style: style.copyWith(
                    color: selected ? colors.action : colors.text,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
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
