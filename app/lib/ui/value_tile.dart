import 'package:flutter/material.dart';

import 'estimated_mark.dart';
import 'ramuri_card.dart';
import 'ramuri_type.dart';
import 'unbreakable_unit.dart';

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
    this.valueKey,
    this.textValue = false,
  });

  final String label;
  final String value;
  final String? unit;
  final bool estimated;
  final RamuriValueSize size;
  final RamuriCardTone tone;

  /// Schlüssel auf dem Text mit Zahl und Einheit (für Tests und Hilfen).
  final Key? valueKey;

  /// [value] ist ein Satz („nicht verfügbar“), keine Zahl: gesetzt in der
  /// Schrift des Fließtexts statt in der Zahlenschrift.
  final bool textValue;

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
            final text = Theme.of(context).textTheme;
            final valueStyle = textValue
                ? text.titleSmall
                : size == RamuriValueSize.large
                ? type.value
                : type.valueSmall;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 2),
                Text.rich(
                  key: valueKey,
                  TextSpan(
                    children: [
                      TextSpan(text: value, style: valueStyle),
                      if (unit != null)
                        TextSpan(
                          text: ' $unit',
                          // Der Wortverbinder gehört nicht in die Sprachausgabe.
                          semanticsLabel: ' ${spokenUnit(unit!)}',
                          style: type.unit,
                        ),
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

/// Raster der Wertkacheln: drei Spalten, bei großer Schrift oder schmalem
/// Display zwei. Die Kacheln einer Reihe sind gleich hoch.
class RamuriTileGrid extends StatelessWidget {
  const RamuriTileGrid({super.key, required this.children, this.gap = 8});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.15;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = scaled || constraints.maxWidth < 340 ? 2 : 3;
        return Column(
          children: [
            for (var i = 0; i < children.length; i += columns) ...[
              if (i > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) SizedBox(width: gap),
                      Expanded(
                        child: i + j < children.length
                            ? children[i + j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
