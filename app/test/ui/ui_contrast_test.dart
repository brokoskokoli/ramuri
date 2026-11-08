import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

/// Relative Leuchtdichte nach WCAG 2.x (sRGB, ohne Alpha).
double luminance(Color color) {
  expect(color.a, 1.0, reason: 'Textfarben und Gründe sind deckend');
  double lin(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(color.r) + 0.7152 * lin(color.g) + 0.0722 * lin(color.b);
}

/// Kontrastverhältnis nach WCAG 2.x.
double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Map<String, Color> tokens(RamuriColors c) => {
  'background': c.background,
  'surface': c.surface,
  'field': c.field,
  'track': c.track,
  'tint': c.tint,
  'accentPanel': c.accentPanel,
  'text': c.text,
  'textMuted': c.textMuted,
  'textSoft': c.textSoft,
  'accent': c.accent,
  'onAccent': c.onAccent,
  'action': c.action,
  'onAction': c.onAction,
  'actionSoft': c.actionSoft,
  'panel': c.panel,
  'panelRaised': c.panelRaised,
  'onPanel': c.onPanel,
  'onPanelMuted': c.onPanelMuted,
  'onPanelSoft': c.onPanelSoft,
  'ember': c.ember,
  'emberDot': c.emberDot,
  'emberSoft': c.emberSoft,
  'onEmber': c.onEmber,
  'danger': c.danger,
  'onDanger': c.onDanger,
  'outlineStrong': c.outlineStrong,
  'weekBarOlder': c.weekBarOlder,
  'weekBarLast': c.weekBarLast,
  'weekBarCurrent': c.weekBarCurrent,
};

/// Text-Grund-Paare (Vordergrund, Grund), die die Seiten verwenden dürfen.
const textPairs = <(String, String)>[
  ('text', 'background'),
  ('text', 'surface'),
  ('text', 'field'),
  ('text', 'tint'),
  ('text', 'accentPanel'),
  ('textMuted', 'background'),
  ('textMuted', 'surface'),
  ('textMuted', 'field'),
  ('textMuted', 'tint'),
  ('textMuted', 'accentPanel'),
  ('textMuted', 'track'),
  ('textSoft', 'accentPanel'),
  ('accent', 'background'),
  ('accent', 'surface'),
  ('accent', 'field'),
  ('accent', 'tint'),
  ('accent', 'accentPanel'),
  ('onAccent', 'accent'),
  ('onAction', 'action'),
  ('onAction', 'actionSoft'),
  ('action', 'panel'),
  ('action', 'panelRaised'),
  ('onPanel', 'panel'),
  ('onPanel', 'panelRaised'),
  ('onPanelMuted', 'panel'),
  ('onPanelMuted', 'panelRaised'),
  ('onPanelSoft', 'panel'),
  ('onEmber', 'ember'),
  ('onDanger', 'danger'),
  ('danger', 'background'),
  ('danger', 'surface'),
  ('danger', 'field'),
  ('danger', 'tint'),
];

const minRatio = 4.5;

/// Nicht-Text (Balken, Linien) mindestens 3 : 1 auf Karte (WCAG 1.4.11), soweit
/// das Design es zulässt: hell sind ältere und laufende Woche Pastell aus dem
/// Design (1,4 und 1,7 : 1); dort trägt die Beschriftung die Aussage.
const minNonText = 3.0;

/// Fehlerliste: Paare unter [minRatio].
List<String> weakPairs(RamuriColors c, {String name = ''}) {
  final t = tokens(c);
  return [
    for (final (fg, bg) in textPairs)
      if (contrast(t[fg]!, t[bg]!) < minRatio)
        '$name $fg auf $bg: ${contrast(t[fg]!, t[bg]!).toStringAsFixed(2)}',
  ];
}

/// Glut als Textfarbe auf hellem Grund: Liste der Verstöße.
List<String> emberTextOnLight(
  Iterable<(String, Color, Color)> pairs,
  RamuriColors c,
) {
  final embers = {c.ember, c.emberDot, c.emberSoft};
  return [
    for (final (name, fg, bg) in pairs)
      if (embers.contains(fg) && luminance(bg) > 0.4) name,
  ];
}

/// Alle Textfarben eines Themes mit dem Grund, auf dem sie stehen.
List<(String, Color, Color)> themeTextColors(ThemeData theme) {
  final c = theme.extension<RamuriColors>()!;
  final type = theme.extension<RamuriType>()!;
  final styles = <String, TextStyle?>{
    for (final e in {
      'display': theme.textTheme.displayLarge,
      'headline': theme.textTheme.headlineLarge,
      'title': theme.textTheme.titleLarge,
      'body': theme.textTheme.bodyMedium,
      'bodySmall': theme.textTheme.bodySmall,
      'label': theme.textTheme.labelLarge,
      'labelSmall': theme.textTheme.labelSmall,
      'countdown': type.countdown,
      'value': type.value,
      'unit': type.unit,
      'eyebrow': type.eyebrow,
    }.entries)
      e.key: e.value,
  };
  return [
    for (final e in styles.entries) (e.key, e.value!.color!, c.surface),
    for (final e in styles.entries) (e.key, e.value!.color!, c.background),
  ];
}

void main() {
  test('Kontrast der Rechnung: bekannte Werte', () {
    expect(
      contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 0.001),
    );
    // Markenwerte laut branding/README.md: Nacht auf Papier 16,3 : 1.
    expect(
      contrast(RamuriColors.light.text, RamuriColors.light.background),
      closeTo(16.3, 0.1),
    );
    expect(
      contrast(RamuriColors.light.onAccent, RamuriColors.light.accent),
      closeTo(7.6, 0.1),
    );
  });

  for (final (name, colors) in [
    ('hell', RamuriColors.light),
    ('dunkel', RamuriColors.night),
  ]) {
    test('alle Text-Grund-Paare $name mindestens 4,5 : 1', () {
      expect(weakPairs(colors, name: name), isEmpty);
    });
  }

  test('Dunkel-Fläche nutzt dieselben Werte wie das dunkle Theme', () {
    expect(
      RamuriTheme.dark.extension<RamuriColors>(),
      same(RamuriColors.night),
    );
    expect(
      RamuriTheme.light.extension<RamuriColors>(),
      same(RamuriColors.light),
    );
  });

  test('ColorScheme-Paare beider Themes mindestens 4,5 : 1', () {
    for (final theme in [RamuriTheme.light, RamuriTheme.dark]) {
      final s = theme.colorScheme;
      final pairs = {
        'primary': (s.onPrimary, s.primary),
        'primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
        'secondary': (s.onSecondary, s.secondary),
        'secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
        'error': (s.onError, s.error),
        'surface': (s.onSurface, s.surface),
        'surfaceVariant': (s.onSurfaceVariant, s.surface),
        'inverse': (s.onInverseSurface, s.inverseSurface),
        'scaffold': (s.onSurface, theme.scaffoldBackgroundColor),
      };
      pairs.forEach((name, p) {
        expect(
          contrast(p.$1, p.$2),
          greaterThanOrEqualTo(minRatio),
          reason: '${theme.brightness} $name',
        );
      });
    }
  });

  test(
    'Schriftstile beider Themes: Text mindestens 4,5 : 1 auf Karte und Grund',
    () {
      for (final theme in [RamuriTheme.light, RamuriTheme.dark]) {
        for (final (name, fg, bg) in themeTextColors(theme)) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(minRatio),
            reason: '${theme.brightness} $name',
          );
        }
      }
    },
  );

  test('Glut ist nie Textfarbe auf hellem Grund', () {
    for (final theme in [RamuriTheme.light, RamuriTheme.dark]) {
      final c = theme.extension<RamuriColors>()!;
      expect(emberTextOnLight(themeTextColors(theme), c), isEmpty);
      final t = tokens(c);
      expect(
        emberTextOnLight([
          for (final (fg, bg) in textPairs) ('$fg/$bg', t[fg]!, t[bg]!),
        ], c),
        isEmpty,
      );
    }
    // Die Regel greift: Glut als Text auf Papier wird erkannt.
    final c = RamuriColors.light;
    expect(emberTextOnLight([('x', c.emberDot, c.background)], c), ['x']);
    expect(emberTextOnLight([('x', c.ember, c.panel)], c), isEmpty);
    // Auch der Listenteil sieht alle drei Glutfarben über tokens().
    final t = tokens(c);
    for (final name in ['ember', 'emberDot', 'emberSoft']) {
      expect(emberTextOnLight([(name, t[name]!, t['background']!)], c), [
        name,
      ], reason: name);
    }
  });

  test('Wochenbalken und Sparkline: Kontrast und Unterscheidbarkeit', () {
    for (final (name, c, onCard) in [
      ('hell', RamuriColors.light, RamuriColors.light.surface),
      ('dunkel', RamuriColors.night, RamuriColors.night.surface),
    ]) {
      final t = tokens(c);
      // Letzte volle Woche immer kräftig; dunkel alle Balken.
      expect(
        contrast(t['weekBarLast']!, onCard),
        greaterThanOrEqualTo(minNonText),
        reason: '$name last',
      );
      if (name == 'dunkel') {
        for (final k in ['weekBarOlder', 'weekBarCurrent']) {
          expect(
            contrast(t[k]!, onCard),
            greaterThanOrEqualTo(minNonText),
            reason: '$name $k',
          );
        }
      } else {
        // Design-Werte, nur Mindestabstand zur Karte (sonst unsichtbar).
        for (final k in ['weekBarOlder', 'weekBarCurrent']) {
          expect(
            contrast(t[k]!, onCard),
            greaterThanOrEqualTo(1.4),
            reason: '$name $k',
          );
        }
      }
      // Die drei Rollen sind untereinander unterscheidbar.
      for (final (a, b) in [
        ('weekBarOlder', 'weekBarLast'),
        ('weekBarOlder', 'weekBarCurrent'),
        ('weekBarCurrent', 'weekBarLast'),
      ]) {
        expect(
          contrast(t[a]!, t[b]!),
          greaterThanOrEqualTo(1.15),
          reason: '$name $a/$b',
        );
      }
      // Nulllinie hebt sich von der Karte ab.
      expect(
        contrast(t['outlineStrong']!, onCard),
        greaterThanOrEqualTo(1.5),
        reason: '$name Nulllinie',
      );
      // Sparkline (Aktionsfarbe) auf der dunklen Karte.
      expect(
        contrast(c.action, c.panel),
        greaterThanOrEqualTo(minNonText),
        reason: '$name Sparkline',
      );
    }
  });

  test('Prüfung findet schwache Paare (Gegenprobe)', () {
    final weak = RamuriColors.light.copyWith(
      textMuted: const Color(0xFF9AA9A7),
    );
    expect(weakPairs(weak), isNotEmpty);
    // Glut-Punkt auf Papier hat knapp 3,5 : 1: als Text nicht zulässig.
    expect(
      contrast(RamuriColors.light.emberDot, RamuriColors.light.background),
      lessThan(minRatio),
    );
  });
}
