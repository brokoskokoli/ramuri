import 'package:flutter/material.dart';

import 'ramuri_colors.dart';
import 'ramuri_type.dart';

/// Runder Startknopf (Design „Lauf vorbereiten“): 132 dp, Minze, Beschriftung
/// in 30, ein 12 dp breiter Ring in [RamuriColors.tint]. Ohne [onPressed] ist
/// er grau und tut nichts (etwa ohne Standortrecht, FR-0195).
class RamuriStartButton extends StatelessWidget {
  const RamuriStartButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
  });

  static const double size = 132;
  static const double ring = 12;

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final enabled = onPressed != null;
    final style = RamuriType.of(context).startButton
        .copyWith(color: enabled ? c.onAction : c.textMuted);
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(ring),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? c.action : c.track,
            boxShadow: [BoxShadow(color: c.tint, spreadRadius: ring)],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Text(label, style: style, textAlign: TextAlign.center),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
