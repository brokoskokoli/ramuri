# Kamera-PPG: Algorithmus (Port von `PpgAnalyzer.kt`)

- **Verfahren:** `camera-ppg`, Version 1 (`ppgMethod`, `ppgMethodVersion`), Kategorie B (Heuristik, NFR-0002).
- **Quelle:** `PpgAnalyzer.kt` im Tag `algo-v0.4-frozen` des Referenzprojekts `puls` (ADR-0011). Das Tag enthält kein `ALGORITHMUS.md`; diese Beschreibung ist aus dem Quelltext des Tags und `docs/METHODIK.md` (Abschn. 4 und 5) abgeleitet und hier die maßgebliche Beschreibung des Ports. Die Referenz ist nicht durch klinische Studien belegt, sie wurde an einem EKG-Gurt geprüft (R009).
- **Code:** `ppg_parameters.dart` (alle Konstanten), `ppg_signal.dart` (Spline, Filter, Spektrum), `ppg_analyzer.dart` (Pipeline, Einzelergebnisse), `ppg_evaluator.dart` (Eingabe `PpgFrame`, Ausgabe `PpgMeasurement`, Bewertung). Jeder Wert in `ppg_parameters.dart` verweist auf einen Abschnitt hier. Gültigkeit eines Werts im Alltag (Haltung, Morgenfenster, RMSSD nur bei „gut“): PAR-160K.

## 1. Überblick

Bildstatistik je Bild → Auswahlfenster → 100-Hz-Raster (Spline) → invertieren, Bandpass 0,5 bis 4 Hz → Grundfrequenz und Qualität Q → Gipfel und steilster Anstieg → Vorlagenabgleich → Störabschnitte → Intervalle mit Ausreißerprüfung → Kennwerte → Quelle wählen → Bewertung. Es läuft für Rot, Grün und (wenn Teilbereiche vorliegen) eine gewichtete Kombination der 32 Teilbereiche; die Quelle mit dem kleinsten Zeitrauschen gewinnt.

## 2. Eingabe

Je Bild `PpgFrame`: Sensor-Zeit `t` (s seit Aufnahmebeginn), Mittelwerte `r`, `g` der Bildmitte und je 16 Teilbereiche `r16`, `g16` (4×4, zeilenweise; Reihenfolge r0 bis r15, g0 bis g15, sie bestimmt die Summationsreihenfolge der Kombination). Keine Pixel.

Zeitbasis wie in der Referenz: 0 s = Beginn der Aufnahme mit Einschwingphase, **Messfenster 5 bis 65 s**, Filter ab 3 s, Bilder bis 66,5 s (`ppgStandardWindow`). Bilder außerhalb [3 s, 66,5 s] und solche, deren Zeit nicht streng steigt, werden verworfen. Weniger als 51 Bilder im Bereich oder ein nicht abgedecktes Messfenster ergeben „unzureichende Daten“ (Referenz: Ausnahme). Die Referenz-App schreibt `t_s` relativ zum Messbeginn (Einschwingphase negativ); der Abgleich addiert 5 s.

## 3. Vorverarbeitung

Kubischer natürlicher Spline auf ein Raster mit 100 Hz (ab dem ersten vollen Rasterpunkt). Mittelwert abziehen, Vorzeichen umkehren (mehr Blut = weniger Licht). Bandpass: Hochpass 0,5 Hz, dann Tiefpass 4 Hz, je Butterworth 2. Ordnung als Biquad (Q = 1/√2), vorwärts und rückwärts (phasenfrei), Ränder ungerade über 3 s gespiegelt. Ausgabe: Ausschnitt des Messfensters. Mittlere Bildrate und Zeitstreuung der Bilder (nur Diagnose) aus den Bildabständen im Messfenster.

## 4. Grundfrequenz und Signalqualität Q

Goertzel-Leistung des Hann-gefensterten Signals von 0,50 bis 4,00 Hz in 0,01-Hz-Schritten. Grundfrequenz f0 = Maximum zwischen 0,7 und 3,5 Hz (parabolisch verfeinert). **Q** = Leistungsanteil bei f0 ± 0,08 Hz und 2·f0 ± 0,12 Hz an der Gesamtleistung (0 bis 1).

## 5. Schlagzeitpunkte

1. **Gipfel:** lokale Maxima über 0; nach Höhe absteigend greifend mit Mindestabstand max(0,27 s; 0,55 Perioden); danach nur Gipfel mit mindestens 30 % des Medians der Höhen. Zeit parabolisch verfeinert.
2. **Steilster Anstieg:** je Gipfel maximale Steigung (zentrale Differenz) in den letzten 0,6 Perioden vor dem Gipfel, aber nach dem vorigen Gipfel.
3. **Vorlagenabgleich:** Ausschnitte um jeden Anker werden zeilenweise zum Median gemittelt (Vorlage). Jeder Schlag wird per Pearson-Korrelation ±0,12 s an die Vorlage geschoben (parabolisch verfeinert). Drei Durchgänge; ab dem zweiten bilden nur Schläge mit Korrelation ≥ 0,7 die Vorlage. Zwei Varianten: ganzer Schlag (Anker Gipfel, −0,35 bis +0,55 Perioden, Bezug: Vorlagengipfel) und **Anstieg** (Anker steilster Anstieg, −0,18 bis +0,15 Perioden, Bezug: steilster Anstieg der Vorlage). Hauptverfahren ist „Vorl.Anstieg“; Schläge unter Korrelation 0,6 gelten als Artefakt.

Vier Verfahren in fester Reihenfolge: Vorl.Anstieg, Vorlage, Gipfel, max.Steigung.

## 6. Störabschnitte

Ein Abtastwert ist gestört, wenn die Steigung betragsmäßig über 2,5 × der mittleren (Median) maximalen Anstiegssteigung der Schläge liegt oder der Ausschlag über 2 × der mittleren Gipfelhöhe. Gestörte Stellen mit weniger als 0,3 s Abstand werden verbunden und um 0,3 s nach beiden Seiten erweitert. Mit weniger als 3 Gipfeln gibt es keine Erkennung.

## 7. Intervalle und Ausreißerprüfung

Intervall = Abstand zweier Schlagzeitpunkte. Abweichung jedes Intervalls vom lokalen Median (±5 Intervalle) = mRR. Schwelle th = 5,2 × (Quartilsabstand der mRR)/2, begrenzt auf 8 bis 25 % des Medians aller Intervalle; |mRR| > th = Ausreißer (verpasster oder zusätzlicher Schlag). Ein Nachbar eines Ausreißers, der in Gegenrichtung um mehr als th/2 ausschlägt (Muster kurz–lang), gilt als fehlplatziert. **Ungültig** sind außerdem Intervalle außerhalb 0,27 bis 2,0 s, mit einem Schlag unter Korrelation 0,6 (nur Vorlagenverfahren) und solche, die einen Störabschnitt berühren.

## 8. Kennwerte

Über gültige Intervalle im Abschnitt (gesamt, erste Hälfte, zweite Hälfte der 60 s): Puls = 60000 / mittleres Intervall (ms), RMSSD aus Differenzen **aufeinanderfolgender** gültiger Intervalle, SDNN, pNN50 (Differenz > 50 ms), kleinster und größter Puls. Nicht berechenbar = NaN (im Port) bzw. `null` in `PpgMeasurement`. **Zeitrauschen** (ms): Abstand „Vorlagenbezug Anstieg – lokaler steilster Anstieg“ ist je Schlag fast konstant; seine Schwankung von Schlag zu Schlag (RMS der Differenzen / √2, ab 5 Paaren) schätzt das Messrauschen.

## 9. Quelle wählen

Rot, Grün und „Kombi“ werden getrennt ausgewertet. **Kombi:** jeder der 32 Teilbereiche wird gefiltert und bewertet; Bereiche mit Q ≥ 0,7 × Qmax gehen mit Gewicht Q²/σ in die Summe der Rohreihen ein (σ = Streuung des gefilterten Signals). **Wahl:** unter den Quellen mit Q ≥ 0,25, endlichem Zeitrauschen und ≥ 60 % gültigen Intervallen die mit dem kleinsten Zeitrauschen (bei Gleichstand die erste); gibt es keine, die mit dem höchsten Q.

## 10. Bewertung (PAR-160K)

Hauptverfahren der gewählten Quelle, Anteil gültiger Intervalle = gültig / alle.

| Stufe | Bedingung |
| --- | --- |
| unbrauchbar | Q < 0,25 oder Anteil < 50 % |
| eingeschränkt | sonst Q < 0,3 oder Anteil < 70 % oder Zeitrauschen > 25 ms (oder nicht schätzbar) |
| gut | sonst |

Gründe (`PpgQualityReason`): weakSignal, tooManyDisturbances (unbrauchbar); lowSignalQuality, someDisturbances, timingNoise (eingeschränkt); insufficientData, invalidInput (unbrauchbar, vor der Auswertung). Es werden alle zutreffenden Gründe der Stufe genannt. **Bei „unbrauchbar“ gibt `PpgMeasurement` weder Puls noch RMSSD aus.** Ob ein Wert im Alltag zählt (Ruhepuls bei „gut“ oder „eingeschränkt“, RMSSD nur bei „gut“ und unter der RMSSD-Grenze aus der Validierung), regelt PAR-160K beim Verwender. Die Grenze „Zeitrauschen > 25 ms“ ist für RMSSD zu lasch (R009, Abschn. 3); sie bleibt hier wie in der Referenz.

## 11. Abweichungen vom Referenzcode

- Bei „unbrauchbar“ keine Zahlen (die Referenz gibt Zahlen mit Urteil aus).
- Zu wenige Bilder oder nicht abgedecktes Fenster: Ergebnis „unbrauchbar, unzureichende Daten“ statt Ausnahme; nicht endliche Eingaben oder falsche Teilbereichszahl: „unbrauchbar, ungültige Eingabe“ (die Referenz prüft das nicht, NaN würde die Bewertung verfälschen).
- Nicht übernommen, weil nur für die Darstellung der Referenz-App: Zeitachse und Kurven (`t`, `raw`, `filtered`), Überlagerungsschläge, Vorlagenzeitachse, Textform von `comboInfo` und `verdict`.
- Gleich bleiben Reihenfolge der Fließkommaoperationen, `Math.round` (Abrunden von x + 0,5), Kotlin-`coerceIn` (NaN bleibt NaN) und die Stabilität der Sortierung. Unterschiede bleiben bei Bibliotheksfunktionen (`sin`, `cos`, `exp`) im Bereich der letzten Stelle.

## 12. Prüfen der Implementierung

- `test/ppg/ppg_reference_test.dart`: die 6 synthetischen Tests der Referenz (15 Szenarien) und Abgleich aller Kanäle, Verfahren und Kennwerte mit der Ausgabe der Kotlin-Referenz (`fixtures/reference_synthetic.json`, nur synthetisch). Toleranz Puls 0,1/min, RMSSD 0,5 ms; Zählwerte exakt. Der Generator der Referenz (Kotlin `Random`, XorWow) ist in `ppg_synth.dart` nachgebaut und gegen die Referenz bitgleich geprüft.
- Neuerzeugen der Fixture: `PpgAnalyzer.kt` und der Generator aus `PpgAnalyzerTest.kt` (Tag `algo-v0.4-frozen`) mit `kotlinc` übersetzen und die Szenarien aus `ppg_reference_test.dart` ausgeben (Namen und Parameter dort).
- `test/ppg/ppg_evaluator_test.dart`: Schwellen der Bewertung an den Grenzen, Ausreißer, Störabschnitte, „kein Ergebnis bei schlechtem Signal“, Fehlerfälle der Eingabe.
- `test/ppg/ppg_real_data_test.dart`: lokaler Abgleich auf echten Messungen, nur mit `PPG_REAL_FRAMES_DIR` und `PPG_REAL_REFERENCE` (Referenzausgabe nur im Scratch), meldet nur Abweichungen. Echte Messwerte kommen nie ins Repo.
