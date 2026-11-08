import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Glutpunkt: wie im Logo der aktuelle Stand, vor „geschätzt“ ein Schätzwert
/// (CON-0009). Reine Verzierung, ohne Semantik.
class EmberDot extends StatelessWidget {
  const EmberDot({super.key, this.size = 7});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RamuriColors.of(context).emberDot,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
