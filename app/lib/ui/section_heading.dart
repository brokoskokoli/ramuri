import 'package:flutter/material.dart';

import 'ramuri_type.dart';

/// Abschnittsüberschrift. Mit [eyebrow] die kleine Überschrift in
/// Großbuchstaben über einer Karte. [trailing] steht rechts (etwa ein Link).
class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.text, {
    super.key,
    this.trailing,
    this.eyebrow = false,
  });

  final String text;
  final Widget? trailing;
  final bool eyebrow;

  @override
  Widget build(BuildContext context) {
    final style = eyebrow
        ? RamuriType.of(context).eyebrow
        : Theme.of(context).textTheme.titleSmall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(eyebrow ? text.toUpperCase() : text, style: style),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
