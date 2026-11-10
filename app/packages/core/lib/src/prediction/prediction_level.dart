/// Qualitätsstufe der Prognose (FR-0053, PAR-143 bis PAR-146). Keine
/// statistische Genauigkeit (FR-0054).
enum PredictionLevel { notDeterminable, provisional, sufficient, good }

/// Begrenzender Grund einer Stufe (PAR-159: Wort mit Grund). Die Oberfläche
/// bildet jeden Wert auf einen Text ab; `core` kennt keine Texte.
enum PredictionReason {
  // Nicht bestimmbar (PAR-143).
  /// Keine Referenz.
  noReference,

  /// Nur eine VO₂max-Schätzung (FR-0134).
  onlyVo2max,

  /// Referenz über 26 Wochen alt.
  referenceTooOld,

  /// Seit der Referenz eine Pause ab 8 Wochen.
  pauseSinceReference,

  /// Referenz verletzt FR-0129 (Distanz, Zeit oder Datum).
  invalidReference,

  // Begrenzung der Stufe (PAR-144 bis PAR-146).
  /// Referenz älter als für die nächste Stufe erlaubt.
  referenceAge,

  /// Distanzverhältnis zu groß für die nächste Stufe.
  distanceRatio,

  /// Referenz ist ein bestätigter Lauf, keine eingetragene Zeit.
  referenceIsConfirmedRun,

  /// Referenz ist eine Testzeit, für „gut“ nötig ist eine Wettkampfzeit.
  referenceIsTest,

  /// Ziel ist der Marathon (PAR-144).
  marathon,

  /// Zu wenig regelmäßige Läufe in den letzten 8 Wochen.
  regularity,

  /// Längste Einheit der letzten 6 Wochen zu kurz im Vergleich zur Zeit.
  longestRun,

  /// Zielprognose: PAR-206 „knapp“ oder „eher später“ (FR-0133).
  goalFeasibility,

  /// Alle Bedingungen der höchsten Stufe sind erfüllt.
  none,
}
