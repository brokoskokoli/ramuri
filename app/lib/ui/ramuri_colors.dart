import 'package:flutter/material.dart';

/// Benannte Farben der App (FR-0205). Die einzige Stelle mit Farbwerten:
/// hell nach dem Screen-Design (`design/`), dunkel abgeleitet aus Nacht, Minze,
/// Tiefgrün und Glut. Seiten lesen die Farben über [RamuriColors.of].
///
/// Regeln:
/// - Glut ([ember], [emberDot]) ist nie Textfarbe auf hellem Grund; als Fläche
///   trägt sie [onEmber], als Punkt steht [emberDot].
/// - Text-Grund-Paare erfüllen mindestens 4,5 : 1 (Test `ui_contrast_test`).
@immutable
class RamuriColors extends ThemeExtension<RamuriColors> {
  const RamuriColors({
    required this.background,
    required this.surface,
    required this.field,
    required this.track,
    required this.tint,
    required this.accentPanel,
    required this.outline,
    required this.outlineStrong,
    required this.text,
    required this.textMuted,
    required this.textSoft,
    required this.accent,
    required this.onAccent,
    required this.action,
    required this.onAction,
    required this.actionSoft,
    required this.panel,
    required this.panelRaised,
    required this.panelTrack,
    required this.panelLine,
    required this.onPanel,
    required this.onPanelMuted,
    required this.onPanelSoft,
    required this.ember,
    required this.emberDot,
    required this.emberSoft,
    required this.onEmber,
    required this.danger,
    required this.onDanger,
    required this.zone1,
    required this.zone2,
    required this.zone3,
    required this.zone4,
    required this.zone5,
    required this.weekBarOlder,
    required this.weekBarLast,
    required this.weekBarCurrent,
    required this.segmentTrack,
    required this.zoneDone,
    required this.textLabel,
    required this.emberTint,
    required this.accentFaint,
  });

  /// Seitengrund (Papier / Nacht).
  final Color background;

  /// Karten und Kacheln.
  final Color surface;

  /// Eingabefelder.
  final Color field;

  /// Spuren von Balken und Ringen.
  final Color track;

  /// Gewählter Zustand (Chip, Navigation).
  final Color tint;

  /// Hervorgehobene Fläche (große Kennzahl-Karte).
  final Color accentPanel;
  final Color outline;
  final Color outlineStrong;

  final Color text;
  final Color textMuted;

  /// Text auf [accentPanel].
  final Color textSoft;

  /// Akzent für Links, Überschriftenzeilen, Symbole (Tiefgrün / Minze).
  final Color accent;
  final Color onAccent;

  /// Hauptknopf (Minze) und sein Text.
  final Color action;
  final Color onAction;

  /// Helle Minze für Zone 1 und Hervorhebungen.
  final Color actionSoft;

  /// Dunkle Karte (auch auf hellem Grund) und ihre Texte.
  final Color panel;
  final Color panelRaised;
  final Color panelTrack;
  final Color panelLine;
  final Color onPanel;
  final Color onPanelMuted;
  final Color onPanelSoft;

  /// Glut als Fläche, [emberDot] als Punkt (auf hellem Grund die dunklere
  /// Glut), [emberSoft] als helle Glut für Zone 3.
  final Color ember;
  final Color emberDot;
  final Color emberSoft;
  final Color onEmber;

  final Color danger;
  final Color onDanger;

  final Color zone1;
  final Color zone2;
  final Color zone3;
  final Color zone4;
  final Color zone5;

  /// Wochenbalken (Fortschritt): ältere Wochen, letzte volle Woche (die
  /// kräftigste) und laufende Woche (noch unvollständig, heller als die letzte
  /// volle). Hell sind es Minze hell, Tiefgrün und Minze (Design); dunkel
  /// abgeleitet, so dass die letzte volle Woche die hellste ist (Minze rund 80 % Richtung Weiß).
  final Color weekBarOlder;
  final Color weekBarLast;
  final Color weekBarCurrent;

  /// Grund des Umschalters in voller Breite und ungefüllte Stücke der
  /// Live-Zonenanzeige (Design: `#E2EAE8`).
  final Color segmentTrack;

  /// Zonenstücke unterhalb der aktuellen Zone (Design: `#D3EEE9`).
  final Color zoneDone;

  /// Beschriftung über großen Zahlen auf hellem Grund, etwas kräftiger als
  /// [textMuted] (Design: `#3A4F4D`).
  final Color textLabel;

  /// Hellglut als Fläche, etwa unter Symbolen im Verlauf (Design: `#FFE6DA`).
  final Color emberTint;

  /// Gedämpftes Minzgrün für Linien und Flächen ohne Text (Design: `#8DBDB4`).
  final Color accentFaint;

  /// Farbe der Herzfrequenzzone 1 bis 5.
  Color zone(int number) => switch (number) {
    1 => zone1,
    2 => zone2,
    3 => zone3,
    4 => zone4,
    5 => zone5,
    _ => throw RangeError.range(number, 1, 5, 'number'),
  };

  /// Hell: das Screen-Design.
  static const RamuriColors light = RamuriColors(
    background: Color(0xFFF3F6F5),
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFF7FAF9),
    track: Color(0xFFEBF1EF),
    tint: Color(0xFFDDF2EE),
    accentPanel: Color(0xFFCBEDE6),
    outline: Color(0xFFDAE4E1),
    outlineStrong: Color(0xFFB5C9C6),
    text: Color(0xFF0E1A1A),
    textMuted: Color(0xFF4F6361),
    textSoft: Color(0xFF2A3F3D),
    accent: Color(0xFF0F5E5A),
    onAccent: Color(0xFFFFFFFF),
    action: Color(0xFF7FD6C6),
    onAction: Color(0xFF0E1A1A),
    actionSoft: Color(0xFFA9E3D8),
    panel: Color(0xFF0E1A1A),
    panelRaised: Color(0xFF172828),
    panelTrack: Color(0xFF284040),
    panelLine: Color(0xFF3A5452),
    onPanel: Color(0xFFFFFFFF),
    onPanelMuted: Color(0xFFB5C9C6),
    onPanelSoft: Color(0xFFCDDEDB),
    ember: Color(0xFFFF7A45),
    emberDot: Color(0xFFE0561F),
    emberSoft: Color(0xFFFFB896),
    onEmber: Color(0xFF0E1A1A),
    danger: Color(0xFFA8261B),
    onDanger: Color(0xFFFFFFFF),
    zone1: Color(0xFFA9E3D8),
    zone2: Color(0xFF0F5E5A),
    zone3: Color(0xFFFFB896),
    zone4: Color(0xFFFF7A45),
    zone5: Color(0xFFE0561F),
    weekBarOlder: Color(0xFFA9E3D8),
    weekBarLast: Color(0xFF0F5E5A),
    weekBarCurrent: Color(0xFF7FD6C6),
    segmentTrack: Color(0xFFE2EAE8),
    zoneDone: Color(0xFFD3EEE9),
    textLabel: Color(0xFF3A4F4D),
    emberTint: Color(0xFFFFE6DA),
    accentFaint: Color(0xFF8DBDB4),
  );

  /// Dunkel: Nacht als Grund, Minze als Akzent. Abgeleitet, nicht im Design
  /// (OQ-0075). Dieselben Werte gelten für die feste Dunkel-Fläche
  /// ([RamuriDarkScope]).
  static const RamuriColors night = RamuriColors(
    background: Color(0xFF0E1A1A),
    surface: Color(0xFF172828),
    field: Color(0xFF0E1A1A),
    track: Color(0xFF284040),
    tint: Color(0xFF1F3E3B),
    accentPanel: Color(0xFF17403B),
    outline: Color(0xFF284040),
    outlineStrong: Color(0xFF3A5452),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFFB5C9C6),
    textSoft: Color(0xFFCDDEDB),
    accent: Color(0xFF7FD6C6),
    onAccent: Color(0xFF0E1A1A),
    action: Color(0xFF7FD6C6),
    onAction: Color(0xFF0E1A1A),
    actionSoft: Color(0xFFA9E3D8),
    panel: Color(0xFF1F3534),
    panelRaised: Color(0xFF284040),
    panelTrack: Color(0xFF335150),
    panelLine: Color(0xFF4A6563),
    onPanel: Color(0xFFFFFFFF),
    onPanelMuted: Color(0xFFB5C9C6),
    onPanelSoft: Color(0xFFCDDEDB),
    ember: Color(0xFFFF7A45),
    emberDot: Color(0xFFFF7A45),
    emberSoft: Color(0xFFFFB896),
    onEmber: Color(0xFF0E1A1A),
    danger: Color(0xFFFFB4A6),
    onDanger: Color(0xFF0E1A1A),
    zone1: Color(0xFF4A9385),
    zone2: Color(0xFF7FD6C6),
    zone3: Color(0xFFFFB896),
    zone4: Color(0xFFFF7A45),
    zone5: Color(0xFFE0561F),
    weekBarOlder: Color(0xFF4A9385),
    weekBarLast: Color(0xFFE6F7F3),
    weekBarCurrent: Color(0xFF7FD6C6),
    segmentTrack: Color(0xFF284040),
    zoneDone: Color(0xFF2F5F58),
    textLabel: Color(0xFFCDDEDB),
    emberTint: Color(0xFF3D2B25),
    accentFaint: Color(0xFF4A9385),
  );

  /// Die Farben des umgebenden Themes.
  static RamuriColors of(BuildContext context) {
    final colors = Theme.of(context).extension<RamuriColors>();
    assert(colors != null, 'RamuriTheme fehlt im Widget-Baum');
    return colors ?? light;
  }

  @override
  RamuriColors copyWith({
    Color? background,
    Color? surface,
    Color? field,
    Color? track,
    Color? tint,
    Color? accentPanel,
    Color? outline,
    Color? outlineStrong,
    Color? text,
    Color? textMuted,
    Color? textSoft,
    Color? accent,
    Color? onAccent,
    Color? action,
    Color? onAction,
    Color? actionSoft,
    Color? panel,
    Color? panelRaised,
    Color? panelTrack,
    Color? panelLine,
    Color? onPanel,
    Color? onPanelMuted,
    Color? onPanelSoft,
    Color? ember,
    Color? emberDot,
    Color? emberSoft,
    Color? onEmber,
    Color? danger,
    Color? onDanger,
    Color? zone1,
    Color? zone2,
    Color? zone3,
    Color? zone4,
    Color? zone5,
    Color? weekBarOlder,
    Color? weekBarLast,
    Color? weekBarCurrent,
    Color? segmentTrack,
    Color? zoneDone,
    Color? textLabel,
    Color? emberTint,
    Color? accentFaint,
  }) {
    return RamuriColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      field: field ?? this.field,
      track: track ?? this.track,
      tint: tint ?? this.tint,
      accentPanel: accentPanel ?? this.accentPanel,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      textSoft: textSoft ?? this.textSoft,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
      actionSoft: actionSoft ?? this.actionSoft,
      panel: panel ?? this.panel,
      panelRaised: panelRaised ?? this.panelRaised,
      panelTrack: panelTrack ?? this.panelTrack,
      panelLine: panelLine ?? this.panelLine,
      onPanel: onPanel ?? this.onPanel,
      onPanelMuted: onPanelMuted ?? this.onPanelMuted,
      onPanelSoft: onPanelSoft ?? this.onPanelSoft,
      ember: ember ?? this.ember,
      emberDot: emberDot ?? this.emberDot,
      emberSoft: emberSoft ?? this.emberSoft,
      onEmber: onEmber ?? this.onEmber,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      zone1: zone1 ?? this.zone1,
      zone2: zone2 ?? this.zone2,
      zone3: zone3 ?? this.zone3,
      zone4: zone4 ?? this.zone4,
      zone5: zone5 ?? this.zone5,
      weekBarOlder: weekBarOlder ?? this.weekBarOlder,
      weekBarLast: weekBarLast ?? this.weekBarLast,
      weekBarCurrent: weekBarCurrent ?? this.weekBarCurrent,
      segmentTrack: segmentTrack ?? this.segmentTrack,
      zoneDone: zoneDone ?? this.zoneDone,
      textLabel: textLabel ?? this.textLabel,
      emberTint: emberTint ?? this.emberTint,
      accentFaint: accentFaint ?? this.accentFaint,
    );
  }

  @override
  RamuriColors lerp(ThemeExtension<RamuriColors>? other, double t) {
    if (other is! RamuriColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return RamuriColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      field: l(field, other.field),
      track: l(track, other.track),
      tint: l(tint, other.tint),
      accentPanel: l(accentPanel, other.accentPanel),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textSoft: l(textSoft, other.textSoft),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      action: l(action, other.action),
      onAction: l(onAction, other.onAction),
      actionSoft: l(actionSoft, other.actionSoft),
      panel: l(panel, other.panel),
      panelRaised: l(panelRaised, other.panelRaised),
      panelTrack: l(panelTrack, other.panelTrack),
      panelLine: l(panelLine, other.panelLine),
      onPanel: l(onPanel, other.onPanel),
      onPanelMuted: l(onPanelMuted, other.onPanelMuted),
      onPanelSoft: l(onPanelSoft, other.onPanelSoft),
      ember: l(ember, other.ember),
      emberDot: l(emberDot, other.emberDot),
      emberSoft: l(emberSoft, other.emberSoft),
      onEmber: l(onEmber, other.onEmber),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      zone1: l(zone1, other.zone1),
      zone2: l(zone2, other.zone2),
      zone3: l(zone3, other.zone3),
      zone4: l(zone4, other.zone4),
      zone5: l(zone5, other.zone5),
      weekBarOlder: l(weekBarOlder, other.weekBarOlder),
      weekBarLast: l(weekBarLast, other.weekBarLast),
      weekBarCurrent: l(weekBarCurrent, other.weekBarCurrent),
      segmentTrack: l(segmentTrack, other.segmentTrack),
      zoneDone: l(zoneDone, other.zoneDone),
      textLabel: l(textLabel, other.textLabel),
      emberTint: l(emberTint, other.emberTint),
      accentFaint: l(accentFaint, other.accentFaint),
    );
  }
}
