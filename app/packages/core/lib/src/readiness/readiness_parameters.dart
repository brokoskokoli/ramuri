// Zahlen der Abweichungsbewertung (Readiness, Teil A). Jeder Wert nennt seine
// PAR-Nummer (docs/phase-2-3-rules.md, Abschnitt 7 für K-1); keine dieser Zahlen
// steht außerhalb dieser Datei. Alle Werte sind vorläufige Startwerte (FR-0054).

/// FR-0113: Skalierung der MAD auf die Standardabweichung bei Normalverteilung.
const double readinessMadScale = 1.4826;

/// PAR-161, PAR-162, PAR-161K, PAR-162K: Fenster des rollenden Mittels `x` in
/// Tagen (7 Nächte bzw. 7 Tage), einschließlich heute.
const int readinessWindowDays = 7;

/// PAR-161, PAR-162, PAR-161K, PAR-162K: Mindestzahl gültiger Werte `k` im
/// Fenster; heute muss darunter sein.
const int readinessMinWindowValues = 3;

/// PAR-161, PAR-162, PAR-161K, PAR-162K: Referenz sind die Tageswerte der 28
/// Tage vor heute (ohne heute).
const int readinessReferenceDays = 28;

/// PAR-161, PAR-162, PAR-161K, PAR-162K, OQ-0006: Mindestzahl gültiger
/// Referenzwerte derselben Reihe.
const int readinessMinReferenceValues = 14;

/// PAR-161 (FR-0114): MAD von `ln(RMSSD)` unter dieser Grenze ergibt kein `z`.
/// Gilt auch für die Kamera (PAR-161K).
const double readinessHrvMadMinLn = 0.02;

/// PAR-162 (FR-0114): MAD des Ruhepulses aus Health Connect (ganzzahlig) unter
/// dieser Grenze in bpm ergibt kein `z`.
const double readinessRestingHrMadMinBpm = 1.0;

/// PAR-162K (FR-0114): MAD des Kamera-Ruhepulses (eine Nachkommastelle) unter
/// dieser Grenze in bpm ergibt kein `z`.
const double readinessCameraRestingHrMadMinBpm = 0.5;

/// PAR-161K: Hat die Kamerareihe in den letzten 7 Tagen weniger gültige Werte
/// als dies, gilt der Hinweis „wenige Messungen“.
const int readinessFewMeasurementsBelow = 5;
