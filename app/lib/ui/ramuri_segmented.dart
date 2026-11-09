import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_theme.dart';

/// Ein Abschnitt eines [RamuriSegmentedToggle].
class RamuriSegment<T> {
  const RamuriSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// Aussehen eines [RamuriSegmentedToggle].
enum RamuriSegmentedStyle {
  /// Weiße Pille, der gewählte Abschnitt dunkel (Karte/Werte).
  dark,

  /// Graue Spur über die volle Breite, der gewählte Abschnitt weiß (Design
  /// „Lauf vorbereiten“). Der Verlauf nutzt [dark]: gewählt dunkel
  /// (`Verlauf.dc.html:24-26`). [soft] bleibt für „Geplante Einheit / Freier
  /// Lauf“ (`Start.dc.html:28`, Phase 2) und ist bis dahin ungenutzt.
  soft,
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
    this.expanded = false,
    this.style = RamuriSegmentedStyle.dark,
  });

  final List<RamuriSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  /// Volle Breite: der Umschalter füllt die Zeile, die Abschnitte teilen sie
  /// gleich auf (Design „Verlauf“, „Fortschritt“). Vorgabe: so schmal wie der Inhalt.
  final bool expanded;
  final RamuriSegmentedStyle style;

  Widget segmentButton(
    RamuriSegment<T> s,
    RamuriColors c,
    TextStyle labelStyle,
  ) => _SegmentButton(
    expanded: expanded,
    label: s.label,
    selected: s.value == selected,
    onTap: () => onChanged(s.value),
    colors: c,
    style: labelStyle,
    look: style,
  );

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium!;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: style == RamuriSegmentedStyle.soft
              ? c.segmentTrack
              : c.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              for (final s in segments)
                if (expanded)
                  Expanded(child: segmentButton(s, c, labelStyle))
                else
                  segmentButton(s, c, labelStyle),
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
    required this.look,
    this.expanded = false,
  });

  final RamuriSegmentedStyle look;
  final bool expanded;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RamuriColors colors;
  final TextStyle style;

  Widget _fit(Widget text) =>
      expanded ? FittedBox(fit: BoxFit.scaleDown, child: text) : text;

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
        color: selected
            ? (look == RamuriSegmentedStyle.soft
                  ? colors.surface
                  : colors.panel)
            : Colors.transparent,
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
              // Teilen sich vier Abschnitte eine schmale Zeile (Verlauf), bleibt
              // wenig Platz; die Beschriftung schrumpft dann statt mitten im Wort
              // umzubrechen.
              padding: EdgeInsets.symmetric(horizontal: expanded ? 4 : 18),
              child: Center(
                widthFactor: expanded ? null : 1,
                child: _fit(
                  Text(
                    label,
                    maxLines: expanded ? 1 : null,
                    style: style.copyWith(
                      color: selected && look == RamuriSegmentedStyle.dark
                          ? colors.action
                          : colors.text,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
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
