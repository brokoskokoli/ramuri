import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Schriftfamilien aus `pubspec.yaml` (FR-0205).
const String ramuriHeadingFamily = 'Sora';
const String ramuriBodyFamily = 'Manrope';

const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

TextStyle _sora(
  double size,
  FontWeight weight,
  Color color, {
  double tracking = 0,
  double? height,
}) => TextStyle(
  fontFamily: ramuriHeadingFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: size * tracking,
  height: height,
  fontFeatures: _tabular,
);

TextStyle _manrope(
  double size,
  FontWeight weight,
  Color color, {
  double tracking = 0,
  double? height,
}) => TextStyle(
  fontFamily: ramuriBodyFamily,
  fontSize: size,
  fontWeight: weight,
  color: color,
  letterSpacing: size * tracking,
  height: height,
);

/// Alle Schriftgrößen der App. Material-Stufen:
/// - `display*`: große Zahlen in Sora (96, 64, 40), tabellarisch
/// - `headline*`: Seitentitel (Sora 34, 28) und Kartentitel (Manrope 26)
/// - `title*`: App-Leiste (Sora 20), Abschnitte (Manrope 18, 15)
/// - `body*`: Fließtext 16, 15, 13
/// - `label*`: Knöpfe 17, Chips 14, Beschriftungen 12
///
/// Die Design-Überschriften stehen in Sora 800. Die Schrift reicht zwar bis 800,
/// gebündelt sind aber nur 500 bis 700 (siehe `assets/fonts/README.md`); dort gilt 700,
/// wie das Design im Browser mit nur diesen Schnitten gerendert wird.
TextTheme ramuriTextTheme(RamuriColors c) => TextTheme(
  displayLarge: _sora(96, FontWeight.w700, c.text, tracking: -0.04, height: 1),
  displayMedium: _sora(64, FontWeight.w700, c.text, tracking: -0.03, height: 1),
  displaySmall: _sora(40, FontWeight.w700, c.text),
  headlineLarge: _sora(34, FontWeight.w700, c.text, tracking: -0.02),
  headlineMedium: _sora(28, FontWeight.w700, c.text),
  headlineSmall: _manrope(26, FontWeight.w800, c.text, tracking: -0.01),
  titleLarge: _sora(20, FontWeight.w700, c.text, tracking: -0.01),
  titleMedium: _manrope(18, FontWeight.w700, c.text),
  titleSmall: _manrope(15, FontWeight.w800, c.text),
  bodyLarge: _manrope(16, FontWeight.w400, c.text, height: 1.4),
  bodyMedium: _manrope(15, FontWeight.w400, c.text, height: 1.4),
  bodySmall: _manrope(13, FontWeight.w400, c.textMuted, height: 1.4),
  labelLarge: _manrope(17, FontWeight.w800, c.text),
  labelMedium: _manrope(14, FontWeight.w700, c.text),
  labelSmall: _manrope(12, FontWeight.w700, c.textMuted),
);

/// Schriftstile, die Material nicht kennt: Kennzahlen mit Einheit.
@immutable
class RamuriType extends ThemeExtension<RamuriType> {
  const RamuriType({
    required this.countdown,
    required this.distance,
    required this.value,
    required this.valueSmall,
    required this.unitLarge,
    required this.unit,
    required this.eyebrow,
    required this.hero,
    required this.pageTitle,
  });

  factory RamuriType.from(RamuriColors c) => RamuriType(
    countdown: _sora(104, FontWeight.w700, c.text, tracking: -0.04, height: 1),
    distance: _sora(52, FontWeight.w700, c.text, tracking: -0.03),
    value: _sora(28, FontWeight.w700, c.text),
    valueSmall: _sora(22, FontWeight.w700, c.text),
    unitLarge: _manrope(20, FontWeight.w700, c.textMuted),
    unit: _manrope(13, FontWeight.w700, c.textMuted),
    eyebrow: _manrope(12, FontWeight.w700, c.accent, tracking: 0.06),
    hero: _sora(48, FontWeight.w700, c.text, tracking: -0.03, height: 1),
    // Design: Sora 800; gebündelt bis 700, dort gilt 700 (siehe oben).
    pageTitle: _sora(34, FontWeight.w800, c.text, tracking: -0.02),
  );

  /// Restmeter im Intervall (104).
  final TextStyle countdown;

  /// Strecke im Lauf (52).
  final TextStyle distance;

  /// Kennzahl groß (28) und klein (22).
  final TextStyle value;
  final TextStyle valueSmall;

  /// Einheit hinter einer großen Zahl (20) und hinter einer Kachelzahl (13).
  final TextStyle unitLarge;
  final TextStyle unit;

  /// Kleine Überschrift über einer Karte; wird in Großbuchstaben gesetzt.
  final TextStyle eyebrow;

  /// Große Kennzahl einer Karte, etwa VO₂max (48).
  final TextStyle hero;

  /// Seitenüberschrift im Design (34, Sora 800).
  final TextStyle pageTitle;

  static RamuriType of(BuildContext context) =>
      Theme.of(context).extension<RamuriType>()!;

  @override
  RamuriType copyWith({
    TextStyle? countdown,
    TextStyle? distance,
    TextStyle? value,
    TextStyle? valueSmall,
    TextStyle? unitLarge,
    TextStyle? unit,
    TextStyle? eyebrow,
    TextStyle? hero,
    TextStyle? pageTitle,
  }) => RamuriType(
    countdown: countdown ?? this.countdown,
    distance: distance ?? this.distance,
    value: value ?? this.value,
    valueSmall: valueSmall ?? this.valueSmall,
    unitLarge: unitLarge ?? this.unitLarge,
    unit: unit ?? this.unit,
    eyebrow: eyebrow ?? this.eyebrow,
    hero: hero ?? this.hero,
    pageTitle: pageTitle ?? this.pageTitle,
  );

  @override
  RamuriType lerp(ThemeExtension<RamuriType>? other, double t) {
    if (other is! RamuriType) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return RamuriType(
      countdown: l(countdown, other.countdown),
      distance: l(distance, other.distance),
      value: l(value, other.value),
      valueSmall: l(valueSmall, other.valueSmall),
      unitLarge: l(unitLarge, other.unitLarge),
      unit: l(unit, other.unit),
      eyebrow: l(eyebrow, other.eyebrow),
      hero: l(hero, other.hero),
      pageTitle: l(pageTitle, other.pageTitle),
    );
  }
}
