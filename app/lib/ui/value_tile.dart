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
    this.labelUnit,
  });

  final String label;
  final String value;
  final String? unit;
  final bool estimated;
  final RamuriValueSize size;
  final RamuriCardTone tone;

  /// Schlüssel auf dem Text mit Zahl und Einheit (für Tests und Hilfen).
  final Key? valueKey;

  /// [value] ist ein Satz („nicht verfügbar (Grund)“), keine Zahl: gesetzt
  /// klein in der Schrift des Fließtexts, der Grund in einer eigenen Zeile.
  final bool textValue;

  /// Einheit hinter der Beschriftung („Ø Pace min/km“); die Zahl steht dann
  /// ohne Einheit. Für Werte, deren Zahl samt Einheit in der schmalen Kachel
  /// nicht in eine Zeile passt (Pace, Puls, Punkte).
  final String? labelUnit;

  /// Innenabstand der Kachel (links und rechts je einmal).
  static const double padding = 12;

  /// Stil des Grundes bei [textValue].
  static TextStyle reasonStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!
          .copyWith(fontSize: 12, height: 1.3);

  /// Trennt „nicht verfügbar (Grund)“ und „nicht verfügbar – Grund“ in Aussage
  /// und Grund; ohne Grund ist er null.
  static (String, String?) splitReason(String value) {
    final m = RegExp(r'^(.+?)\s*(?:\((.+)\)|–\s*(.+))$').firstMatch(value);
    if (m == null) return (value, null);
    final reason = m.group(2) ?? m.group(3)!;
    return (m.group(1)!, m.group(2) != null ? '($reason)' : reason);
  }

  /// Zahl samt Einheit bleibt in einer Zeile und schrumpft nur dann, wenn sie
  /// breiter als die Kachel ist (`scaleDown`); sonst gilt die Schrift wie sie ist.
  static Widget _fitUnit(bool fit, Widget value) => fit
      ? FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: value,
        )
      : value;

  /// Das längste Wort des Grundes (für die Spaltenwahl im Raster).
  String? get longestReasonWord {
    if (!textValue) return null;
    final reason = splitReason(value).$2;
    if (reason == null) return null;
    final words = reason.split(RegExp(r'\s+'));
    return words.reduce((a, b) => a.length >= b.length ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: RamuriCard(
        tone: tone,
        radius: 18,
        padding: const EdgeInsets.all(padding),
        // Builder: auf der dunklen Karte gilt das dunkle Theme erst darunter.
        child: Builder(
          builder: (context) {
            final type = RamuriType.of(context);
            final text = Theme.of(context).textTheme;
            final valueStyle = size == RamuriValueSize.large
                ? type.value
                : type.valueSmall;
            final (head, reason) = textValue
                ? splitReason(value)
                : (value, null);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  labelWithUnit(label, labelUnit),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                _fitUnit(
                  unit != null,
                  Text.rich(
                    key: valueKey,
                    TextSpan(
                      children: [
                        if (textValue) ...[
                          TextSpan(text: head, style: text.labelMedium),
                          // Der Grund steht in einer eigenen Zeile.
                          if (reason != null)
                            TextSpan(
                              text: '\n$reason',
                              style: reasonStyle(context),
                            ),
                        ] else
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

/// Raster der Wertkacheln: drei Spalten wie im Design (auch auf 360 dp mit
/// 20 dp Seitenrand), bei großer Schrift oder unter 300 dp Breite zwei. Die
/// Kacheln einer Reihe sind gleich hoch.
class RamuriTileGrid extends StatelessWidget {
  const RamuriTileGrid({super.key, required this.children, this.gap = 8});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scaled = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.15;
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = scaled || constraints.maxWidth < 300 ? 2 : 3;
        // Passt ein Wort der Ersatztexte oder eine Zahl nicht in die schmale
        // Spalte, bricht es mitten im Wort: dann weniger Spalten.
        while (columns > 1 &&
            !_wordsFit(context, constraints.maxWidth, columns)) {
          columns--;
        }
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

  bool _wordsFit(BuildContext context, double width, int columns) {
    final inner =
        (width - gap * (columns - 1)) / columns - 2 * RamuriValueTile.padding;
    final reasonStyle = RamuriValueTile.reasonStyle(context);
    final numberStyle = RamuriType.of(context).valueSmall;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    double widthOf(String word, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    for (final child in children) {
      if (child is! RamuriValueTile) continue;
      // Auch ein Wort der Beschriftung bricht nicht im Wort (die Einheit
      // dahinter zählt als eigenes Wort).
      for (final word in [
        ...child.label.split(RegExp(r'\s+')),
        ?child.labelUnit,
      ]) {
        if (widthOf(word, labelStyle) > inner) return false;
      }
      // Auch eine Zahl bricht, wenn sie nicht passt („+120 / 0“): sie zählt
      // wie ein Wort. Nur die Zahl wird geprüft; die Einheit steht danach hinter
      // einem normalen Leerzeichen und darf umbrechen.
      final word = child.textValue ? child.longestReasonWord : child.value;
      if (word == null) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: word,
          style: child.textValue ? reasonStyle : numberStyle,
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      final fits = painter.width <= inner;
      painter.dispose();
      if (!fits) return false;
    }
    return true;
  }
}
