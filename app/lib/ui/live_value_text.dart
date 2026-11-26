import 'package:flutter/material.dart';

import 'unbreakable_unit.dart';

/// Wert in der Schrift der Zahl, dahinter die Einheit klein und unumbrechbar.
/// Der Schlüssel [id] sitzt auf dem Text, damit Tests und Hilfen ihn finden.
/// Mit [shrink] schrumpft Zahl samt Einheit nur dann, wenn beides nicht in die
/// Breite passt (`scaleDown`), und bleibt in einer Zeile.
class LiveValueText extends StatelessWidget {
  const LiveValueText({
    super.key,
    required this.id,
    required this.value,
    required this.valueStyle,
    required this.unitStyle,
    this.unit,
    this.textAlign,
    this.shrink = false,
  });

  final String id;
  final String value;
  final String? unit;
  final TextStyle valueStyle;
  final TextStyle unitStyle;
  final TextAlign? textAlign;
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final unit = this.unit;
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value, style: valueStyle),
          if (unit != null)
            TextSpan(
              text: ' ${unbreakableUnit(unit)}',
              // Der Wortverbinder soll nicht in der Sprachausgabe landen.
              semanticsLabel: ' $unit',
              style: unitStyle,
            ),
        ],
      ),
      key: Key(id),
      textAlign: textAlign,
      // Geschrumpft wird in einer Zeile; der Umbruch würde im IntrinsicHeight
      // eine Scheinzeile messen.
      softWrap: !shrink,
    );
    if (!shrink) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: text,
    );
  }
}
