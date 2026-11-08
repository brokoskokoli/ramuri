import 'package:flutter/material.dart';

import 'estimated_mark.dart';
import 'ramuri_card.dart';
import 'ramuri_type.dart';

/// Größe der Zahl einer [RamuriValueTile].
enum RamuriValueSize { small, large }

/// Wertkachel: Beschriftung, Zahl in Sora (tabellarisch) und Einheit. Die
/// Zahl kommt fertig formatiert vom Aufrufer. Mit [estimated] folgt die
/// Kennzeichnung „geschätzt“.
class RamuriValueTile extends StatelessWidget {
  const RamuriValueTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.estimated = false,
    this.size = RamuriValueSize.small,
    this.tone = RamuriCardTone.surface,
  });

  final String label;
  final String value;
  final String? unit;
  final bool estimated;
  final RamuriValueSize size;
  final RamuriCardTone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: RamuriCard(
        tone: tone,
        radius: 18,
        padding: const EdgeInsets.all(12),
        // Builder: auf der dunklen Karte gilt das dunkle Theme erst darunter.
        child: Builder(
          builder: (context) {
            final type = RamuriType.of(context);
            final valueStyle = size == RamuriValueSize.large
                ? type.value
                : type.valueSmall;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: value, style: valueStyle),
                      if (unit != null)
                        TextSpan(text: ' $unit', style: type.unit),
                    ],
                  ),
                ),
                if (estimated) ...[
                  const SizedBox(height: 2),
                  const EstimatedMark(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
