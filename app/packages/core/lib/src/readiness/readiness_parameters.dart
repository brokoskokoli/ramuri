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

// ---- Teil C1: Teilskalen, Gesamtwert, Bänder (Modell `readiness` v1) ----

/// NFR-0001: Methode und Version des Gesamtmodells (Gewichte, Teilskalen,
/// Kappung, Bänder, Entscheidung Zahl/Einschätzung).
const String readinessMethod = 'readiness';
const int readinessMethodVersion = 1;

/// PAR-163: Steigung der Teilskala HRV/Ruhepuls unter `z` = 0 (Mittelpunkt 60).
const double readinessZBase = 60;
const double readinessZSlopeBelow = 25;

/// PAR-163: Steigung ab `z` = 0, höchstens [readinessZMax].
const double readinessZSlopeAbove = 20;
const double readinessZMax = 90;

/// PAR-165: Teilskala Schlafdauer. Unter [readinessSleepAnchorHours] fällt `S`
/// um [readinessSleepSlopeBelow] je Stunde ab [readinessSleepAnchorScore].
const double readinessSleepAnchorHours = 7;
const double readinessSleepAnchorScore = 70;
const double readinessSleepSlopeBelow = 25;

/// PAR-165: zwischen 7 und 8 h steigt `S` um diesen Wert je Stunde, ab
/// [readinessSleepCapHours] ist `S` gleich [readinessSleepCapScore].
const double readinessSleepSlopeAbove = 10;
const double readinessSleepCapHours = 8;
const double readinessSleepCapScore = 80;

/// PAR-167: Anteile von Dauer und Effizienz an der Teilskala Schlaf. Die
/// Effizienz-Teilskala selbst (PAR-166) liegt in `HealthProcessing`.
const double readinessSleepDurationShare = 0.8;
const double readinessSleepEfficiencyShare = 0.2;

/// PAR-168: Teilskala Trainingsbelastung `S = 60 + 2 · (TSB% + 10)`, höchstens
/// 60, mindestens 0.
const double readinessLoadMaxScore = 60;
const double readinessLoadSlope = 2;
const double readinessLoadNeutralTsbPercent = -10;

/// PAR-169: Befinden 1 bis 5 ergibt diese Teilskala; höchstens 3 Tage alt.
const List<double> readinessWellbeingScores = [10, 35, 60, 75, 90];
const int readinessWellbeingMaxAgeDays = 3;

/// PAR-170 (FR-0110): Gewichte der Faktoren.
const double readinessWeightHrv = 25;
const double readinessWeightRestingHr = 20;
const double readinessWeightSleep = 30;
const double readinessWeightLoad = 15;
const double readinessWeightWellbeing = 10;

/// PAR-170: Höchstwert, wenn der Belastungsfaktor fehlt (OQ-0059).
const int readinessCapWithoutLoad = 74;

/// FR-0109: Wertebereich.
const int readinessMinValue = 0;
const int readinessMaxValue = 100;

/// FR-0116 (OQ-0029): Untergrenzen der Bänder, gerundeter Wert.
const int readinessBandWellRecoveredFrom = 75;
const int readinessBandNormalFrom = 50;
const int readinessBandElevatedFrom = 25;
