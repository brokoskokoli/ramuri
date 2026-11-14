# R010 – Ergebnis

## Kurzfassung
Die Kamera-Messung lässt sich verbessern, aber nicht durch mehr Bilder pro Sekunde oder feineres Hochrechnen der Kurve: Das macht der Code schon richtig, und weder 60 statt 30 Bilder pro Sekunde noch ein feineres Raster änderten etwas. In der einzigen Messung mit Brustgurt und Rohsignal steckt fast der ganze Fehler in einem Anteil, den alle Bildteile gemeinsam haben; mehr Pixel helfen dort kaum, aber ob dieser Anteil vom Finger, von der Kamera oder vom Rechenverfahren kommt, lässt sich damit nicht trennen. Drei Dinge versprechen etwas. Erstens den Schlagzeitpunkt anders bestimmen, etwa als Mittel aus „steilster Anstieg“ und dem heutigen Verfahren („mix“): In der einen Gurtmessung sank der Fehler je Schlagabstand von knapp 15 auf knapp 12 Millisekunden, in der Simulation aber nur um etwa 5 Prozent, und die Simulation bevorzugt sogar ein Verfahren, das in der echten Messung schlecht war; welches Verfahren es wird, ist also offen und wird an Morgenmessungen mit Gurt entschieden. Zweitens verrauschte Messungen für die HRV strenger aussortieren: Die heutige Grenze von 25 Millisekunden Zeitrauschen ließ eine Messung als „gut“ durch, deren HRV 35 Prozent über dem Gurt lag. Eine vorläufige Grenze von 8 Millisekunden hätte sie aussortiert; sie verspricht aber keine Genauigkeit auf 10 Prozent, denn darunter sind bei einer HRV um 40 Millisekunden noch 0 bis 35 Prozent zu viel möglich (in den zwei echten Fällen waren es 1 bis 2 Prozent). Drittens ruhig messen: Finger nur auflegen, Hand abstützen, nicht bewegen. Für WP37: aus den ganzen 120 Sekunden das 60-Sekunden-Fenster mit dem kleinsten Zeitrauschen nehmen und nicht beim ersten „guten“ Fenster aufhören; die Wahl verfälscht die HRV in der Simulation nicht, macht die Grenze aber etwas lascher (wie 9 statt 8 Millisekunden). Dazu Rohsignal samt Kamera-Angaben speichern. Danach an etwa zehn Morgenmessungen mit Gurt das Verfahren und die Grenze prüfen und vor der eigentlichen Prüfung über 28 Morgen festschreiben. Nicht tun: die Folge der Schlagabstände glätten, das drückt die HRV um ein Viertel. Wichtigste Einschränkung: Es gibt drei Messungen mit Gurt, nur eine davon mit Rohsignal; alles sind Hinweise, keine Belege.

## Lauf
- **Datum:** 2026-11-14. **Rechner:** Mac, Apple M3 Pro (arm64), Dart SDK 3.13.5, ein Kern (`nice`), Last nur durch diese Analyse und Hintergrunddienste.
- **Kommando:** `./init.sh && ./run.sh --seed 1 --reps 40`. Lauf `research/data/work/R010/20261114-135130/` auf Commit `862a445` (`dirty=0`), App-Code `app/packages/core/lib/src/ppg` Stand `36f79ad` unverändert. Laufzeit 421 s (Synthese ≈ 400 s, echte Aufnahmen ≈ 20 s). Ein erster Lauf (`20261114-133742`, Commit `9631392`) ergab dieselben Werte; der zweite fügt nur Spalten hinzu (Fehler der Differenzen, Kreuzterm, Tabelle S4b).
- **Nachbesserung nach Review 1:** `./init.sh && ./run.sh --seed 1 --reps 40 --wreps 40`, Lauf `20261114-143447` auf Commit `4d49f0b` (`dirty=0`), Laufzeit 536 s. Neu: Teil `window` (3.10) und Tabelle R3b; die Werte von `synth.txt`, `real.txt` (R1–R3) und `pairs.txt` sind gleich wie im Lauf `20261114-135130` (Synthese per Seed reproduziert, die neue Option für einen unruhigen Anfang ist im Standard aus). Zahlen in 3.9 stammen nicht aus einem Lauf, sondern vom Orchestrator.
- **Messpaare:** `./run.sh --part pairs` nach einer Korrektur der Zuordnung (Commit `c5dafd8`, Lauf `20261114-135914`, `dirty=1` nur durch diese Datei). Die Sammlung ist noch leer; ausgewertet wurde nur der Selbsttest (Verschiebung 12 wie erwartet, Fehler 5,0 ms wie eingebaut).
- **Kontrollen im Code:**
  - Die Variante „tplRise“ (eigene Vorbereitung mit Raster 100 Hz und Tiefpass 4 Hz) ergibt in 30 synthetischen Aufnahmen und in der echten Gurtmessung **bitgleich** dieselben Schlagzeiten und dasselbe Zeitrauschen wie `PpgAnalyzer` der App. Alle Varianten bauen auf den Funktionen der App auf (Import der Dateien, nicht kopiert).
  - Das App-Ergebnis der echten Gurtmessung (Quelle Kombi, Q 0,80, Zeitrauschen 7,1 ms, RMSSD 43,9 ms, 50/57 gültig) stimmt mit der Ausgabe der Vorgänger-App (`*_info.txt`) überein.
  - Zuordnung Kamera ↔ Gurt: Median |Fehler| je Intervall 6–10 ms für die Anstiegsverfahren; ein um einen Schlag verschobener Versatz ergäbe Fehler in der Größe der Schlag-zu-Schlag-Schwankung (≈ 40 ms).
  - Zerlegung RMSSD_Kamera² = RMSSD_Gurt² + mittel(Δ-Fehler²) + Kreuzterm an der App-Variante nachgerechnet: 43,9² − 41,0² = 246 ≈ 24,0² − 331 = 245.
- **Literatur:** zwei Teilrecherchen als Sub-Agenten (Messtechnik, Signalverarbeitung), Volltext oder Abstract je Quelle vermerkt. Nicht von mir selbst am Original nachgeprüft sind alle Quellen mit „(TR)“; Quellen aus R009 mit [B…] sind dort geprüft.

## 1. Was der Code heute schon tut
Gelesen: `app/packages/core/lib/src/ppg/` (Stand `36f79ad`) und `app/android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgCamera.kt`, `PpgCameraLogic.kt`, `PpgFrameStats.kt`.

| Bereich | Stand im Code | Bewertung |
| --- | --- | --- |
| Kamera-API | Camera2 direkt, Rückkamera mit Blitz, `TEMPLATE_PREVIEW`, ein YUV-`ImageReader` 320×240 (`maxImages` 2), `acquireLatestImage` | richtig gewählt; `acquireLatestImage` verwirft Bilder, wenn die Verarbeitung nicht nachkommt (Android-Doku), Lücken werden nicht gezählt |
| Bildrate | höchste **feste** AE-Zielrate zwischen 30 und 60 (60 vor 30); unter 30 Abbruch | richtig; 120/240 Bilder/s gehen mit YUV-Leser über die offizielle API nicht (Constrained High Speed nur Vorschau/Encoder) |
| Zeitstempel | `Image.getTimestamp()` (Sensor, Beginn der Belichtung der ersten Zeile) je Bild, relativ zum ersten Bild; **keine** nominale Rate | richtig; `SENSOR_INFO_TIMESTAMP_SOURCE`, Belichtungszeit und Rolling-Shutter-Versatz werden nicht protokolliert |
| Reale Rate | mittlere Rate und Streuung der Bildabstände im Fenster werden berechnet (nur Diagnose, `meanFps` im Ergebnis) | Lücken über 1,0 s → „unbrauchbar“; kleinere Lücken (verlorene Bilder) werden weder gezählt noch bewertet |
| Belichtung, Weißabgleich | Automatik 2,5 s, dann `CONTROL_AE_LOCK` und `CONTROL_AWB_LOCK`; keine manuelle Belichtungszeit/ISO; Torch mit Standardstärke | sinnvoll; Sättigung (Rot nahe 255) wird nicht gemessen |
| Bildausschnitt, Kanal | Mittel der mittleren 50 % und 4×4-Teilbereiche, jedes 2. Pixel, Rot und Grün nach BT.601; „Kombi“ = Teilbereiche mit Q ≥ 0,7·Qmax, Gewicht Q²/σ; Quelle mit dem kleinsten Zeitrauschen gewinnt | umgesetzt, entspricht dem besten Fall bei Solinski 2026 (Raster) |
| Interpolation | natürlicher kubischer Spline auf 100 Hz **mit den echten Zeitstempeln**, danach Filter; Zeitpunkte parabolisch verfeinert (Gipfel, Steigung, Korrelationsmaximum) | umgesetzt |
| Filter | Hochpass 0,5 Hz und Tiefpass 4 Hz, Butterworth 2. Ordnung, vorwärts und rückwärts | umgesetzt; 4 Hz liegt unter den Werten der meisten PRV-Arbeiten (8–35 Hz) |
| Bezugspunkt | Hauptverfahren „Vorl.Anstieg“: Vorlagenabgleich um den steilsten Anstieg, Bezug = steilster Anstieg der Vorlage. Gipfel, ganze Vorlage, steilster Anstieg werden mitgerechnet, aber nicht genutzt | umgesetzt; Fußpunkt, Tangentenschnitt, 50-%-Punkt fehlen (hier nachgemessen) |
| Artefakte, Ausreißer | Störabschnitte (Steigung > 2,5×, Ausschlag > 2×), Ausreißer nach Lipponen & Tarvainen vereinfacht (Schwelle 8–25 % des Medians), Vorlagenkorrelation < 0,6; ungültige Intervalle werden **verworfen**, RMSSD nur aus benachbarten gültigen Paaren | umgesetzt; leichte Verschiebungen unter 8 % (≈ 80 ms) erkennt die Prüfung grundsätzlich nicht |
| Glättung der RR-Folge | keine | richtig (siehe 3.6) |
| Fenster | fest 5–65 s | WP37 bringt das wandernde 60-s-Fenster |
| Qualitätsgrenzen | unbrauchbar: Q < 0,25 oder < 50 % gültig; eingeschränkt: Q < 0,3, < 70 % gültig oder Zeitrauschen > 25 ms; RMSSD nur bei „gut“ | Zeitrauschen-Grenze zu lasch (R009, hier 4) |
| Zeitrauschen | Schwankung des Abstands „Vorlagenbezug – lokaler steilster Anstieg“ von Schlag zu Schlag | misst nur einen Teil des Fehlers (hier 3.5) |
| Rauschkorrektur der RMSSD | keine | hier 3.7 |

## 2. Literatur je Maßnahme
Kurzform; Einzelheiten und Zitate in den Quellen. „VT“ = Volltext, „A“ = nur Abstract, (TR) = aus einer Teilrecherche, nicht von mir am Original nachgeprüft.

| Maßnahme | Beleg (Effekt) | Gegenbeleg / Grenze |
| --- | --- | --- |
| Bildrate, Abtastung | PPG auf 5–5000 Hz heruntergerechnet: oberhalb 25 Hz kein signifikanter Unterschied bei RMSSD (Choi & Shin 2017, A, TR). Mit kubischem Spline genügen für < 5 % RMSSD-Fehler 3,3–10 Hz, ohne Interpolation 100–500 Hz (Béres 2019, VT, TR; ideales, rauschfreies Signal). Intervallfehler: „SNR is even more important than sampling rate“, 14 → 50 Hz senkt den Fehler nur um ≈ 14 % (Zaunseder 2022, TR). 240 Bilder/s: RMSSD-Bias 2,5 ms, SD 1,8 ms über 5 min [B2]. | Keine Studie vergleicht 30 und 60 Bilder/s direkt (TR). Kritik an Choi & Shin: „nicht signifikant“ sagt wenig über den Einzelfall (Hejjel 2017, A, TR). |
| Interpolation vor der Gipfelsuche | siehe Béres 2019; ohne Interpolation erzeugt ein 33-ms-Raster σ ≈ 9,6 ms je Schlag (eigene Rechnung: T/√12) | Bei 2–10 ms Rasterabstand erzeugte der Spline selbst Fehler (Béres 2019, TR) |
| Bezugspunkt | Finger, liegend (Supine I), gegen EKG: RMSSD-Fehler Gipfel +8,0 %, Fußpunkt +5,8 %, Mitte der Amplitude +3,1 %, max. 1. Ableitung +4,4 %, Tangentenschnitt +4,4 %; gekippt +12 bis +54 % (Peralta 2019, VT, TR). Die Quellen stützen den steilsten Anstieg („slope“), nicht „mix“; mix ist ein eigener Kompromiss aus Tabelle 3.2. Smartphone 30 Hz: beste Punkte Maximum der 1. bzw. Minimum der 2. Ableitung (Ferrer-Mileo 2015, A, TR). Auf Tälern beruhende Punkte besser (Mejía-Mejía 2022, VT, TR). | Hemon & Phillips 2016 (A, TR): Tangentenschnitt am besten am Ohr. Unterschiede zwischen den guten Punkten sind klein. |
| Filter | Obere Grenze 5–15 Hz „does not have a very remarkable effect“, niedrigere untere Grenze besser (Mejía-Mejía 2021, VT, TR); synthetisch meist 20 Hz am besten, 8 Hz nur bei Bewegung (Mejía-Mejía 2023, VT, TR). | Smartphone 30 Hz: bester Tiefpass ≈ 2,7–3,5 Hz (Ferrer-Mileo 2015, A, TR). |
| Ausreißer | Nach Korrektur < 2 % Fehler bei fehlenden/zusätzlichen Schlägen, bis knapp 8 % bei leicht verschobenen; „Misaligned beats with smallest displacement factor were the most difficult to detect“ (Lipponen & Tarvainen 2019, A, TR). Schon < 5 % editierte Intervalle verändern RMSSD (Peltola 2012, VT, TR). | – |
| Glättung der RR-Folge | Interpolation/Glättung wirkt wie ein Tiefpass (Peltola 2012, TR); keine Quelle mit Zahlen gefunden. | – |
| PRV ≠ HRV | „short-term variability is somewhat overestimated by PRV“ [B10]; Finger liegend +3 bis +8 % RMSSD (Peralta 2019 Supine I, TR), in der zweiten Liegephase (Supine II) +7,7 bis +13,7 %; das ist der Unterschied PRV gegen EKG-HRV einschließlich Methodenfehler, nicht rein physiologisch; HF-Leistung +18 bis +25 % (Yuda 2020, A, TR). | Oura-Ring nachts −1,2 ms (Kinnunen 2020, A, TR); 5-min-Kamera TEE 6,35 % [B1]. |
| Rauschkorrektur RMSSD² − 6σ² | eigene Herleitung (R009, Rechnung C); keine begutachtete Validierung gefunden (TR) | – |
| Signalqualitätsindizes | Template-Korrelation, Schiefe u. a. für Puls bzw. Qualitätsklasse belegt (Li & Clifford 2012, Orphanidou 2015, Elgendi 2016; alle A, TR) | für RMSSD keine Schwellen validiert (TR) |
| Belichtung, ISO | n = 44, iPhone, 1 min: längste Belichtung 33 ms bzw. ISO 400 am besten für den Puls (ΔHR ≈ 2,6–3,0/min), Raster-Pixelauswahl am besten (Solinski 2026, A, TR) | nur Puls, keine HRV; bei 60 Bilder/s ist die Belichtung ≤ 16,7 ms |
| Torch-Stärke | über `FLASH_STRENGTH_LEVEL` im Request ab API 35; `turnOnTorchWithStrengthLevel` geht bei laufender Kamera nicht (Android-Doku, TR) | keine Studie mit Zahlen (TR) |
| Sättigung (Rot 255) | keine Studie mit Zahlen gefunden (TR) | – |
| Fingerdruck | Pulsamplitude am größten bei 0,2–0,4 N, darüber sinkend (Teng & Zhang 2004, A, TR) | Druck wurde in keiner Kamera-HRV-Studie gemessen (Mather 2024 [B8]) |
| Handhöhe | Hand 50 cm unter/über Herzhöhe: AC-Amplitude −68 % / +70 %, Form ändert sich (Hickey 2016, A, TR) | – |
| Haltung | Abweichung wächst von liegend über sitzend zu stehend [B6]; Fehler je Schlag 30-Hz-Android hängt von Haltung und Gerät ab, schlechtester Fall SDE 7,8 ± 3,8 ms [B4] | – |
| Farbkanal | Grün/Blau mit besserem Signal-Rausch-Verhältnis (Matsumura 2014, VT, TR); Rot besser, wo Grün gegen 0 geht [B3] | gerätabhängig (Mather 2024 [B8]) |
| Zeitstempel | `SENSOR_TIMESTAMP` = Beginn der Belichtung der ersten Zeile; Rolling-Shutter-Versatz und Belichtung sind feste Versätze (Android-Doku, TR) | `acquireLatestImage` verwirft Bilder (Android-Doku, TR) |
| Protokoll | „Try not to move your finger and not to change the amount of pressure on the camera“ (HRV4Training-Blog 2024, TR); Kamera-App mit gutem Algorithmus RMSSD-MAPE ≈ 9 %, schlechte App 112 % (Stone 2021, TR) | Nutzen von Echtzeit-Rückmeldung nicht untersucht (TR) |

**Folgerung aus der Literatur:** Bildrate und Interpolation sind bei ≥ 25–30 Bildern/s mit Spline kein Engpass, das Signal-Rausch-Verhältnis schon. Der Bezugspunkt zählt: Gipfel und reiner Fußpunkt sind schlechter, steilster Anstieg, Mitte der Amplitude und Tangentenschnitt liegen nahe beieinander. Mit guter Technik liegt die PRV-RMSSD am Finger liegend etwa 3 bis 14 % über der EKG-HRV (Peralta 2019, beide Liegephasen; PRV-Effekt samt Methodenfehler); +35 % liegen deutlich darüber und sind überwiegend Messfehler.

## 3. Messungen
Rohtabellen: `synth.txt`, `real.txt`, `pairs.txt` im Laufordner. Abkürzungen der Varianten: **tplRise** = App (Vorl.Anstieg), **slope** = steilster Anstieg, **mix** = Mittel aus tplRise und slope je Schlag, **tpl** = Vorlage ganzer Schlag, **peak** = Gipfel, **foot** = Minimum vor dem Anstieg, **tangent** = Tangentenschnitt, **d50** = Mitte der Amplitude. „TP“ = Tiefpass, „HP“ = Hochpass, „Raster“ = Rate nach dem Spline (App: 100 Hz). **Fehler/Intervall** = Kamera-Schlagabstand minus Gurt-RR. **Δ-Fehler** = Fehler der Differenz zweier aufeinanderfolgender Abstände, er geht direkt in RMSSD ein: RMSSD_Kamera² = RMSSD_Gurt² + mittel(Δ-Fehler²) + Kreuzterm.

### 3.1 Echte Messung mit Gurt (Vorgänger-App, 2026-11-09 20:16, 60 Bilder/s, n = 1)
Datei `messung_20261109_201643_*`, Quelle Kombi, Q 0,80, Zeitrauschen 7,1 ms, 57 Intervalle; Gurt im selben Fenster 58 Intervalle, RMSSD 43,5 ms. Spalten „Paare“ = Intervalle, für die beide Seiten gültig und zugeordnet sind (RMSSD auf denselben Paaren); „ganzes Fenster“ = RMSSD der Variante über alle ihre gültigen Intervalle gegen den Gurt im ganzen Fenster (so vergleicht die Validierung).

| Variante | Fehler/Intervall RMS (ms) | Median \|Fehler\| (ms) | Δ-Fehler RMS (ms) | Kreuzterm (ms²) | RMSSD Δ % (Paare) | RMSSD Δ % (ganzes Fenster) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **App (tplRise)** | 14,8 | 10,4 | 24,0 | −331 | +7,1 | +1,0 |
| slope | **10,3** | **6,2** | **17,0** | −124 | +4,8 | −1,2 |
| mix | 11,7 | 7,5 | 19,3 | −228 | +4,2 | −1,7 |
| d50 | 13,7 | 8,2 | 22,5 | −146 | +10,2 | +3,9 |
| tangent | 16,3 | 10,1 | 25,2 | +49 | +18,6 | +11,8 |
| tpl | 28,2 | 15,2 | 46,6 | −209 | +47,2 | +38,8 |
| peak | 44,6 | 26,8 | 68,1 | −877 | +72,9 | +72,9 |
| foot | 36,1 | 18,3 | – | – | +70,3 | +135,5 |
| tplRise TP 8 Hz | 12,1 | 7,9 | 19,6 | −229 | +4,6 | −1,5 |
| tplRise TP 12 Hz | 11,9 | 6,7 | 19,7 | −71 | +7,7 | +10,0 |
| slope TP 8 Hz | 14,8 | 8,8 | 24,2 | +67 | +16,6 | +14,5 |
| tplRise HP 0,3 Hz | 14,5 | 10,0 | 23,8 | −302 | +7,6 | +1,5 |
| tplRise Raster 60 / 250 / 1000 Hz | 14,7 / 14,4 / 14,5 | – | 24,0 / 23,5 / 23,6 | – | +7,2 / +6,7 / +6,8 | +1,0 / +0,6 / +0,7 |
| tplRise, RR-Folge Median-3 geglättet | 17,7 | 12,6 | 25,7 | −1353 | **−23,4** | **−27,7** |
| tplRise, Ausreißergrenze min 5 % statt 8 % | 14,8 | 10,4 | – | – | +7,1 | +1,0 |
| Nur Rot: tplRise / slope | 18,5 / 11,9 | – | 30,8 / 19,1 | – | +14,4 / +6,2 | +8,1 / +0,6 |
| Nur Grün: tplRise / slope | 15,2 / 12,8 | – | 24,7 / 22,2 | – | +11,6 / +11,6 | +12,6 / +12,7 |

**Ausgedünnt** (App-Verfahren vollständig): 30 Bilder/s (2 Phasen) Fehler/Intervall 14,5–15,0 ms, RMSSD +0,5 / +1,1 % (ganzes Fenster); 15 Bilder/s (4 Phasen) 14,7–16,1 ms, −0,7 bis +4,3 %. 60 Bilder/s: 14,8 ms, +1,0 %.

**Deutung:** Der kleine Gesamtfehler der App in dieser Messung (+1 %) ist zum Teil Glück: Der Rauschanteil (24,0² = 576 ms²) wird durch einen negativen Kreuzterm (−331 ms²) zur Hälfte aufgehoben. Ein negativer Kreuzterm heißt: Die Kamera-Differenzen sind etwas kleiner als die des Gurts, etwa weil die Pulslaufzeit mit der Atmung gegenläufig schwankt. Auf diese Aufhebung kann man sich nicht verlassen; was zählt, ist der Rauschanteil, und der ist bei slope (17,0) und mix (19,3) deutlich kleiner als bei der App (24,0), also ein Rauschbeitrag von etwa 290 bzw. 370 statt 580 ms².

### 3.2 Echte Messungen ohne Referenz (10 Aufnahmen der Vorgänger-App)
Das App-Verfahren bewertet 4 Aufnahmen als „gut“ (Zeitrauschen 4,5 / 5,0 / 7,2 / 7,1 ms), eine als „eingeschränkt“ und fünf als „unbrauchbar“ (frühe 30-Bilder/s-Aufnahmen mit Q 0,19–0,31). Rauschmaß ohne Referenz: zwei Teile desselben Bildes (Kombi aus linker und rechter Bildhälfte, bzw. Rot gegen Grün) unabhängig ausgewertet, RMS der Differenz der Schlagabstände / √2.

| Aufnahme, Paar | tplRise | slope | mix | d50 | tangent | tplRise TP 8 Hz | slope TP 8 Hz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 181909 Rot/Grün | 7,2 | 5,8 | 5,9 | 7,5 | 8,4 | 6,5 | 10,5 |
| 182114 Rot/Grün | 6,5 | 12,3 | 6,5 | 17,7 | 11,9 | 5,6 | 5,6 |
| 191603 Rot/Grün | 7,3 | 5,4 | 5,7 | 10,9 | 11,2 | 6,6 | 8,1 |
| 191755 Rot/Grün | 16,1 | 17,6 | 16,1 | 14,9 | 24,6 | 17,9 | 21,5 |
| 193253 Rot/Grün | 7,9 | 7,5 | 7,4 | 7,7 | 9,5 | 8,1 | 13,9 |
| 194921 links/rechts | 36,8 | 37,1 | 33,6 | 43,9 | 33,0 | 38,7 | 40,3 |
| 194921 Rot/Grün | 14,1 | 18,7 | 15,8 | 17,0 | 20,7 | 15,1 | 27,6 |
| 201643 links/rechts | 5,2 | 5,4 | 4,9 | 5,8 | 6,2 | 4,5 | 8,6 |
| 201643 Rot/Grün | 4,7 | 4,6 | 4,3 | 5,4 | 8,9 | 4,0 | 13,8 |

(ms; je Zeile 20–52 zugeordnete Intervalle; Zeilen ohne ≥ 10 Paare fehlen.) **mix** ist in 9 von 9 Zeilen höchstens 1,7 ms schlechter als das bessere von tplRise und slope und in 5 Zeilen das beste; slope allein schwankt (182114: 12,3 gegen 6,5). Ein Tiefpass von 8 Hz hilft tplRise in 6 von 9 Zeilen leicht und schadet slope fast immer.

**Gemeinsamer und unabhängiger Fehler (nur die eine Gurtmessung 201643):** Das unabhängige Rauschen zweier Bildhälften ist ≈ 5,2 ms je Intervall und Hälfte, das Vollbild aus beiden Hälften trägt also nur ≈ 5,2/√2 ≈ 3,7 ms bei; ohne diesen Anteil blieben √(14,8² − 3,7²) ≈ 14,3 der 14,8 ms gegen den Gurt. Mehr Pixel oder eine andere Gewichtung der Teilbereiche bringen **in dieser Messung** also wenig. **Woher** der gemeinsame Anteil kommt, trennt die Zerlegung nicht: Er enthält Physiologie und Finger (Pulslaufzeit, Pulsform, Druck, kleine Bewegungen), aber ebenso alles, was das ganze Bild gleich trifft (Torch, Belichtung, Zeitstempel), und Fehler des Verfahrens an der Pulsform: slope senkt den Fehler gegen den Gurt von 14,8 auf 10,3 ms bei gleichem Hälftenrauschen (5,4 gegen 5,2 ms). Ein Teil des „gemeinsamen“ Fehlers ist also Verfahren, nicht Finger.

**194921 (Gegenbeispiel zur Verallgemeinerung):** Die App bewertet diese Aufnahme mit Zeitrauschen 7,2 ms als „gut“, die Hälften weichen aber um 36,8 ms ab und Rot gegen Grün um 14,1 ms; hier überwiegt der unabhängige Anteil. Tabelle R3b (`real.txt`) zeigt warum: Die linke Hälfte allein ist schlecht (Zeitrauschen 17,6 ms, 26/54 gültig, RMSSD 124 ms), die rechte allein ergibt genau das App-Ergebnis (7,2 ms, 58/59, 42,9 ms); die Kombi der App hat die schlechten Teilbereiche über die Gewichtung praktisch ausgeschlossen. Rot und Grün über das ganze Bild enthalten die schlechte Hälfte (Zeitrauschen 9,3 / 10,0 ms, RMSSD 50,6 / 55,3 ms). Daraus folgt zweierlei: (a) Der Hälftenvergleich misst hier die schlechtere Hälfte, nicht das Ergebnis der App; ob dieses gut ist, lässt sich ohne Gurt nicht sagen. (b) Ein App-Zeitrauschen ≤ 8 ms schließt nicht aus, dass ein großer Teil des Bildes verrauscht ist; die Aussage „der gemeinsame Anteil überwiegt“ gilt nur für 201643, nicht allgemein. Als zusätzliche Prüfgröße an den Entwicklungsmorgen (Empfehlung 2) gehört deshalb die Abweichung zweier unabhängiger Hälften **der von der App genutzten Teilbereiche** dazu; dafür muss das Rohsignal die 16 Teilbereiche enthalten.

### 3.3 Synthese
720 Aufnahmen im Hauptraster (30/60 Bilder/s × RMSSD 20/40/70 ms × Störung 0,04/0,10/0,20 der Pulsamplitude, je 40), Pulswelle mit Atemmodulation von Schlagabstand, Amplitude und Pulslaufzeit, weißem PTT-Rauschen 2 ms, Formschwankung 3 %, Störsignal im Pulsband 0,5–6 Hz, Bildrauschen, Belichtung als Mittel über 90 % des Bildabstands. Die Störstufen ergeben App-Zeitrauschen im Median 3,2–3,6 / 6,5–6,8 / 13,3–13,4 ms und Q 0,91 / 0,88 / 0,78, decken also die echten Aufnahmen (4,5–7,2 ms) und den Feldfall (15 ms) ab.

**Bezugspunkt, Filter, Raster** (60 Bilder/s, Störung 0,10, RMSSD 20/40/70 gemischt, n = 120; Fehler gegen R-Zacken; ln = ln(RMSSD Kamera / RMSSD Referenz) auf denselben Paaren):

| Variante | Fehler/Intervall RMS (ms) | Median \|Fehler\| | ln Mittel | ln SD |
| --- | ---: | ---: | ---: | ---: |
| **App (tplRise)** | 17,5 | 11,6 | 0,297 | 0,246 |
| slope | 15,5 | 10,0 | 0,248 | 0,212 |
| mix | 15,8 | 10,5 | 0,258 | 0,220 |
| d50 | 17,5 | 11,5 | 0,310 | 0,243 |
| tpl (Vorlage ganzer Schlag) | 17,1 | 11,1 | 0,243 | 0,251 |
| tangent | 24,0 | 15,2 | 0,457 | 0,299 |
| peak | 24,2 | 14,1 | 0,417 | 0,305 |
| tplRise TP 8 Hz | 16,3 | 10,7 | 0,263 | 0,220 |
| slope TP 8 Hz | 14,5 | 9,3 | 0,219 | 0,196 |
| tplRise Raster 250 / 1000 Hz | 17,4 / 17,5 | 11,4 / 11,5 | 0,296 / 0,296 | 0,245 |
| tplRise Raster = Bildrate (ohne Hochrechnen) | 17,6 | 11,6 | 0,300 | 0,248 |
| Median-3 geglättet | 25,6 | 12,8 | **−0,477** | 0,258 |

Über alle 720 Aufnahmen: **tpl 21,9 ms / ln 0,306 (bestes Verfahren)**; mix 22,2 / 0,325; slope 22,7 / 0,325; tplRise 23,5 / 0,355; d50 23,9 / 0,378; tangent 30,8 / 0,506; peak 33,4 / 0,495; foot 85,7 ms und 121 von 720 Aufnahmen mit < 10 Paaren. Tiefpass 3 bis 12 Hz: tplRise 23,7 bis 22,5 ms (ln 0,363 bis 0,334). Hochpass 0,3 statt 0,5 Hz und Ausreißergrenze 5 statt 8 %: keine Änderung (≤ 0,1 ms). **30 gegen 60 Bilder/s** (Störung 0,10): tplRise 17,5 gegen 17,5 ms, slope 15,8 gegen 15,5 ms.

**Zeitstempel und Bildverlust (S7, 40 Aufnahmen je Fall, RMSSD 40, Störung 0,10):** Mit Sensor-Zeitstempeln bleibt der Fehler bei 0–3 % verlorenen Bildern und 0–2 ms Jitter bei 16,7–18,7 ms. Nähme man die Nennrate (Index ÷ Bildrate), stiege er bei 1 % Verlust auf 22,8–26,7 ms und bei 3 % auf 48,8–51,6 ms (ln 0,31–0,40 statt 0,16–0,25); ohne Verlust ist die Nennrate gleich gut. **Annahme des Modells:** Die Sensor-Zeitstempel sind in der Synthese per Konstruktion exakt (Zeitstempel = wahrer Belichtungsbeginn); „mit Sensor-Zeitstempeln unschädlich“ gilt also nur, wenn die echten Zeitstempel so genau sind, was hier nicht geprüft ist. Die Vorgänger-App maß auf dem Handy des Maintainers 0 verlorene Bilder in 3992 (puls METHODIK 6.3).

**Pulslaufzeit (S8, 60 Bilder/s, Störung 0,04):** Weißes PTT-Rauschen von 0 / 2 / 5 ms ergibt Fehler je Intervall 9,6–9,7 / 9,7–10,0 / 11,4–11,6 ms und ln-Fehler bei RMSSD 40 von 0,10 / 0,07 / 0,11 (bei RMSSD 20: 0,22 / 0,25 / 0,33). Die Physiologie setzt also eine kleine Untergrenze, der Großteil kommt vom Signal.

**Eine Druckstörung (S9):** slope 14,8 ms, mix 15,2 ms, tplRise 17,1 ms, tangent 24,9 ms; Reihenfolge wie ohne Störung.

### 3.4 Synthese gegen echte Messung
Bei gleichem Zeitrauschen (≈ 7 ms) ist der Fehler je Intervall in der Synthese etwas größer (17,5 gegen 14,8 ms) und der RMSSD-Fehler deutlich größer (ln ≈ +0,25 bis +0,30 gegen +0,01 bis +0,07). Grund: In der Synthese sind die Zeitfehler fast unabhängig von Schlag zu Schlag und ohne Kreuzterm; in der echten Messung ist der Kreuzterm negativ. Die Synthese überschätzt den RMSSD-Fehler also eher.

**Reihenfolge der Varianten (Fehler je Intervall):**

| | echt (201643) | Synthese 60 B/s, Störung 0,10 | Synthese alle 720 |
| --- | --- | --- | --- |
| beste | slope 10,3 < mix 11,7 < tplRise TP 8 Hz 12,1 < d50 13,7 | slope TP 8 Hz 14,5 < slope 15,5 < mix 15,8 < tplRise TP 8 Hz 16,3 < tpl 17,1 | tpl 21,9 < mix 22,2 < slope 22,7 < tplRise TP 8 Hz 22,8 |
| App | tplRise 14,8 (≈ slope TP 8 Hz 14,8) | tplRise 17,5 (= d50) | tplRise 23,5 |
| schlechter | tangent 16,3 < **tpl 28,2** < foot 36,1 < peak 44,6 | tangent 24,0 < peak 24,2 | d50 23,9 < tangent 30,8 < peak 33,4 < foot 85,7 |

**Übereinstimmend** sind nur: Gipfel, Tangentenschnitt und Fußpunkt sind schlecht; die Glättung der RR-Folge ist stark schädlich; Raster und Bildrate wirken nicht. **Nicht übereinstimmend** sind gerade die Varianten, zwischen denen zu wählen ist: tpl ist synthetisch über alle Aufnahmen das beste Verfahren, echt das drittschlechteste (+90 % gegen die App); slope mit Tiefpass 8 Hz ist synthetisch bei 60 B/s das beste, echt nicht besser als die App; d50 ist echt besser als die App, synthetisch gleich bzw. schlechter. slope und mix sind in beiden besser als die App, synthetisch aber nur um 3–11 % statt 21–30 %. **Die Synthese stützt die Wahl zwischen tplRise, slope, mix und Tiefpass also nicht;** dafür zählt nur die echte Messung (n = 1), und die Entscheidung gehört an die Entwicklungsmorgen mit Rohsignal (Empfehlung 2). Vermutlicher Grund: Die Pulsform der Synthese (zwei Gammakurven, 3 % Formschwankung) ist einfacher als die echte, und gerade die Vorlage über den ganzen Schlag profitiert davon.

### 3.5 Misst das Zeitrauschen der App den wahren Fehler?
Synthetisch (720 Aufnahmen): Korrelation mit dem wahren Zeitfehler je Schlag r = 0,86, aber das wahre ist im Median **1,85-mal** so groß (10–90 %: 1,41–2,66). Echte Gurtmessung: Δ-Fehler 24,0 ms entspricht bei unabhängigen Fehlern σ ≈ 24,0/√6 ≈ 9,8 ms je Schlag, die App schätzt 7,1 ms (Faktor ≈ 1,4). Grund: Das Zeitrauschen vergleicht zwei Bezugspunkte **desselben** Signals; Fehler, die beide gemeinsam haben (Störsignal im Band, Formänderung), sieht es nicht. Ein Zweikanal-Schätzer (zwei Kanäle mit unabhängigem Rauschen) traf in der Synthese besser (Faktor 1,12, r = 0,94), versagt aber an der echten Messung (≈ 5 ms gegen ≈ 10 ms), weil dort der Fehler überwiegend gemeinsam ist (3.2). Das App-Zeitrauschen korreliert mit dem RMSSD-Fehler mit r = 0,60 (synthetisch); es taugt als Grenze, nicht als genaues Maß.

### 3.6 Glättung der RR-Folge
Median über 3 Intervalle: RMSSD −23 bis −28 % in der echten Messung, ln −0,42 im Mittel der Synthese (bei RMSSD 70: −0,57). Das ist kein Rauschfilter, sondern ein neuer, vom Niveau abhängiger Fehler. **Nicht einbauen.**

### 3.7 Rauschkorrektur RMSSD_korr = √(RMSSD² − 6·σ²) (S6, synthetisch, 60 Bilder/s, je 40 Aufnahmen)

| RMSSD wahr | Störung | ohne | σ = App | σ = 1,85 × App | σ aus 2 Kanälen |
| ---: | ---: | --- | --- | --- | --- |
| 20 | 0,04 / 0,10 / 0,20 | 0,23 / 0,57 / 1,15 | 0,17 / 0,44 / 0,90 | −0,02 / −0,08 / 0,58 (2 / 10 / 18 nicht def.) | 0,10 / 0,04 / 0,51 |
| 40 | 0,04 / 0,10 / 0,20 | 0,06 / 0,18 / 0,57 | 0,04 / 0,11 / 0,43 | −0,01 / −0,10 / −0,11 | 0,01 / −0,04 / 0,06 |
| 70 | 0,04 / 0,10 / 0,20 | 0,02 / 0,09 / 0,28 | 0,01 / 0,06 / 0,19 | −0,01 / −0,01 / −0,15 | 0,00 / 0,00 / 0,00 |

(Mittel des ln-Fehlers; „nicht def.“ = Korrektur ≤ 0.) Mit dem App-Zeitrauschen entfernt die Korrektur etwa ein Drittel des Aufschlags, mit dem hochskalierten korrigiert sie zu stark und erhöht die Streuung (SD bei RMSSD 40, Störung 0,10: 0,12 → 0,23). Echte Gurtmessung mit σ = App 7,1 ms: 43,9 → 40,3 ms, also −7 % gegen den Gurt im ganzen Fenster statt +1 %. **Für die App nicht reif;** offline an Messpaaren mit Rohsignal prüfen.

### 3.8 Messpaare
Die Sammlung `morgenmessungen-maintainer` ist leer. Der Auswerter (`--part pairs`) ist fertig und am synthetischen Selbsttest geprüft; er ordnet die Kamera-Intervalle ohne Zeitstempel über die Folge der Abstände zu und meldet Fehler je Intervall, RMSSD beider Seiten auf denselben Paaren und die Wirkung der Glättung. Maßnahmen am Signal (Bezugspunkt, Filter) lassen sich an Messpaaren erst mit dem Rohsignal aus WP37 nachmessen.

### 3.9 Feldmessungen mit Gurt vom 2026-11-14 (Kennzahlen vom Orchestrator)
Die Daten selbst liegen mir nicht vor (Sammlung leer); der Orchestrator hat die Kennzahlen lokal aus dem Messpaar-Export gerechnet. Es sind **zwei andere Messungen** als die Gurtmessung 201643 aus 3.1 (diese stammt vom 2026-11-09 aus der Vorgänger-App). Damit gibt es drei Fälle mit Gurt:

| Fall | Haltung, Stufe | Zeitrauschen App | Kamera-RMSSD | Gurt-RMSSD | Abweichung | Median \|Fehler\| je Intervall, Anteil ≤ 20 ms | Überschuss RMSSD_K² − RMSSD_G² |
| --- | --- | ---: | ---: | ---: | ---: | --- | ---: |
| A 201643 (11-09, Vorgänger-App) | sitzend, „gut“ | 7,1 ms | 43,9 ms | 43,5 ms | +1,0 % | 10,4 ms | 35 ms² |
| B 11-14 (Messung mit unruhigem Anfang) | sitzend, „eingeschränkt“ | 5,5 ms | 39,8 ms (nachgerechnet) | 39,1 ms | +1,8 % | 8,2 ms, 92 % | 55 ms² |
| C 11-14 Messung 3 (außerhalb des Morgenfensters) | liegend, „gut“ | 15,0 ms | 79,1 ms | 58,7 ms (Fenster 5–66 s; 58,6 nach bester Ausrichtung) | **+34,8 %** | 24,9 ms, 41 % | 2811 ms² |

Fall C weiter: Kamera-Ruhepuls 60,4/min gegen Gurt 61,4/min (−1,6 %), 82 % gültige Intervalle (erstes Drittel 45 %, danach 100 %).

**Nachgerechnet mit der Formel aus R009** (Überschuss ≈ 6σ², Kreuzterm 0; σ = App-Zeitrauschen bzw. das 1,4- oder 1,85-Fache aus 3.5):

| Fall | erwartet mit σ App | mit 1,4 × σ | mit 1,85 × σ | gemessen | σ, das den Überschuss erklärt |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | +8 % | +15 % | +24 % | +1,0 % | 2,4 ms (0,3 × App) |
| B | +6 % | +11 % | +19 % | +1,8 % | 3,0 ms (0,6 × App) |
| C | +18 % | +33 % | +53 % | +34,8 % | 21,6 ms (1,44 × App) |

**Deutung:** (1) Die 25-ms-Grenze versagt in Fall C eindeutig: „gut“ bei +35 %, während der Ruhepuls stimmt. (2) Fall C bestätigt die Formel mit dem App-Zeitrauschen **nicht**: σ = 15 ms erklärt nur 1350 der 2811 ms² Überschuss (erwartet +18 %, gemessen +35 %). Mit dem 1,4-Fachen passt sie (+33 %), mit dem 1,85-Fachen schießt sie über. Aus dem Fehler je Intervall (Median 24,9 ms; mit dem Verhältnis RMS/Median 1,42 aus Fall A RMS ≈ 35 ms, σ je Schlag ≈ 25 ms, 6σ² ≈ 3800 ms²) wäre sogar mehr zu erwarten; vermutlich hebt auch hier ein negativer Kreuzterm einen Teil auf (Kreuzterm und Δ-Fehler hat der Export nicht, das ist eine Vermutung). (3) In den beiden Fällen mit kleinem Zeitrauschen (A, B) liegt die Kamera nur 1–2 % über dem Gurt, deutlich unter jeder Vorhersage der Formel; in A ist der Kreuzterm nachweislich negativ (−331 ms², 3.1), in B muss er es ebenfalls sein (Fehler je Intervall Median 8,2 ms ergäbe sonst ≈ 400 ms² Überschuss statt 55). (4) Ergebnis: Die Formel mit App-σ ist bei kleinem σ zu pessimistisch und bei großem σ zu optimistisch; sie taugt als grobe Richtschnur, nicht als Vorhersage. Drei Fälle, ein Handy, eine Person; Fall C liegend und außerhalb des Morgenfensters, die beiden anderen sitzend.

### 3.10 Fensterwahl über 120 s (Teil `window`, synthetisch, nach Review 1)
`window.txt`: 60 Bilder/s, 40 Aufnahmen à 120 s je Fall, je Aufnahme 54 Fenster à 60 s (Beginn 5–58 s, Schritt 1 s), App-Verfahren unverändert. ln-Fehler gegen die R-Zacken **im selben Fenster**; „σ wahr“ = SD der Abweichung der App-Schlagzeiten von den Fußpunkten (nur Schläge an gültigen Intervallen). Auszug RMSSD 40 ms (RMSSD 20 und 70 verhalten sich gleich gerichtet):

| Fall | Regel | σ App Median | σ wahr Median | ln Mittel (alle) | bestanden 8 ms | ln Mittel (bestanden) |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| ruhig, Störung 0,10 | fest 5–65 s | 6,4 | 11,9 | 0,200 | 33/40 | 0,205 |
| | zufälliges Fenster | 6,5 | 11,6 | 0,211 | 38/40 | 0,205 |
| | kleinstes Zeitrauschen | 5,5 | 11,2 | 0,204 | 40/40 | 0,204 |
| | erstes ≤ 8 ms, sonst kleinstes | 6,4 | 11,7 | 0,201 | 40/40 | 0,201 |
| | Orakel (kleinstes wahres σ) | 6,1 | 10,6 | 0,172 | 40/40 | 0,172 |
| ruhig, Störung 0,20 | fest 5–65 s | 14,9 | 24,9 | 0,539 | 1/40 | 0,426 |
| | kleinstes Zeitrauschen | 11,0 | 23,7 | 0,479 | 2/40 | 0,305 |
| Anfang 30 s Störung ×4, dann 0,10 | fest 5–65 s | 11,7 | 26,5 | 0,447 | 3/40 | 0,347 |
| | erstes „gut“ (25 ms), sonst kleinstes | 11,8 | 25,8 | 0,434 | 3/40 | 0,347 |
| | erstes ≤ 8 ms, sonst kleinstes | 7,3 | 14,6 | 0,253 | 39/40 | 0,254 |
| | kleinstes Zeitrauschen | 5,6 | 11,6 | 0,194 | 39/40 | 0,194 |
| | Orakel (kleinstes wahres σ) | 6,1 | 11,1 | 0,174 | 35/40 | 0,166 |

**Deutung:**
- **Mehrfachvergleich (ruhiges Signal):** Das Minimum über 54 Fenster drückt das App-Zeitrauschen um etwa 15 % (6,4 → 5,5 ms), das wahre kaum (11,9 → 11,2 ms); das Verhältnis wahr/App steigt von ≈ 1,85 auf ≈ 2,1 (alle Fälle in `window.txt`). Eine Grenze von 8 ms wirkt nach der Fensterwahl also so lasch wie eine von etwa 9 ms am festen Fenster: Es bestehen mehr Aufnahmen (Störung 0,10: 33 → 40 von 40; RMSSD 20: 28 → 39). Die RMSSD selbst wird dadurch **nicht** verzerrt: Der ln-Fehler der gewählten Fenster ist gleich wie am festen oder zufälligen Fenster (0,204 gegen 0,200 / 0,211), auch unter den bestandenen. Bei starker Störung (0,20) kommen durch Glück einzelne Fenster unter 8 ms durch (RMSSD 20: 5 von 40, ln-Fehler 0,85); das sind wenige, aber grob falsche Werte.
- **Unruhiger Anfang:** Hier wirkt die Wahl stark und richtig: ln-Fehler 0,45 → 0,19, fast so gut wie das Orakel (0,17); bestanden 3 → 39 von 40.
- **Früher Abbruch:** „Ende, sobald ein Fenster ‚gut‘ ist“ mit der heutigen 25-ms-Grenze (WP37 heute) nimmt fast immer das erste Fenster und ist so schlecht wie das feste Fenster (0,43). Mit „erstes ≤ 8 ms“ ist der Fehler kleiner, aber deutlich größer als bei der Suche über die ganzen 120 s (0,25 gegen 0,19; RMSSD 70: 0,12 gegen 0,07), weil das erste passende Fenster oft noch einen Teil des unruhigen Anfangs enthält.
- **Grenzen der Simulation:** Im ruhigen Fall ist das wahre Rauschen über alle Fenster gleich, die Wahl kann dort nur Glück auswählen; in echten Messungen schwankt es (Finger, Atmung, Bewegung), dann gewinnt die Wahl mehr. Ob echte ruhige Abschnitte eine andere RMSSD haben als unruhige (z. B. Atemanhalten), kann die Synthese nicht zeigen.

## 4. Qualitätsgrenze für RMSSD
Die heutige Grenze („Zeitrauschen > 25 ms → eingeschränkt“) wirkt praktisch nicht: In der Synthese bestehen 100 % der Aufnahmen auch bei Störung 0,20 (App-Zeitrauschen bis ≈ 18 ms), und Fall C (3.9) mit 15 ms und +35 % RMSSD kam als „gut“ durch.

**Synthese (S4, nur Aufnahmen mit Q ≥ 0,3 und ≥ 70 % gültig; ln-Fehler gegen den Gurt im ganzen Fenster; je RMSSD 240 Aufnahmen):**

| Grenze | RMSSD 20: bestanden, ln Mittel, Anteil > 0,2 | RMSSD 40 | RMSSD 70 |
| --- | --- | --- | --- |
| keine / 25 ms | 100 %, 0,65, 92 % | 100 %, 0,29, 53 % | 100 %, 0,13, 25 % |
| 15 ms | 89 %, 0,59, 91 % | 87 %, 0,24, 46 % | 92 %, 0,11, 21 % |
| 10 ms | 69 %, 0,45, 89 % | 68 %, 0,15, 31 % | 70 %, 0,06, 6 % |
| 8 ms | 59 %, 0,41, 87 % | 60 %, 0,14, 29 % | 59 %, 0,05, 2 % |
| 5 ms | 33 %, 0,29, 76 % | 33 %, 0,09, 11 % | 33 %, 0,03, 0 % |

Eine relative Grenze (geschätzter Rauschanteil 6σ²/RMSSD² ≤ 0,1 bzw. 0,2, S4b) war nicht besser als eine feste Grenze in ms. Die Synthese überschätzt den Fehler (3.4); die absoluten ln-Werte sind deshalb Obergrenzen, die Wirkung der Grenze ist aber deutlich.

**Abgleich mit echten Messungen (3.9):** Die Formel aus R009 (Überschuss ≈ 6σ², σ = App-Zeitrauschen) sagt die drei Gurtfälle nicht voraus: In A und B (σ 7,1 / 5,5 ms) erwartet sie +8 / +6 %, gemessen sind +1,0 / +1,8 % (negativer Kreuzterm); in C (σ 15 ms) erwartet sie +18 %, gemessen sind +35 %; dort passt erst das 1,4-Fache des App-Werts. Die Grenzwerte aus der Formel (für höchstens +10 % bei RMSSD 40 ms σ ≤ 7,7 ms, bei 30 ms ≤ 5,8 ms, bei 60 ms ≤ 11,5 ms) gelten deshalb nur, wenn App-σ dem wahren Fehler entspräche. Das tut es nicht (3.5: wahr ≈ 1,4- bis 1,85-mal App; nach der Fensterwahl ≈ 2,1-mal, 3.10).

**Was 8 ms erwarten lässt (ehrlich, mit Spanne):** Bei RMSSD um 40 ms und App-σ knapp unter 8 ms:
- Formel ohne Kreuzterm mit wahrem σ = 1,4- bis 1,85 × App: **+21 bis +35 %** (bei 30 ms +36 bis +57 %, bei 60 ms +10 bis +17 %). Das ist die ungünstige Seite.
- Synthese (kein Kreuzterm, Fehler eher überschätzt, 3.4): im Mittel über alle Aufnahmen unter 8 ms **+15 %** (ln 0,14, S4), 29 % der Aufnahmen über +22 %; nach der Fensterwahl bei Störung 0,10 im Mittel +23 % (ln 0,20), bei Störung 0,04 +5 %.
- Echte Fälle mit σ ≤ 8 ms (A, B): **+1 bis +2 %** (n = 2, beide mit negativem Kreuzterm, auf den man sich nicht verlassen kann).

Zusammengefasst: Unter 8 ms ist bei RMSSD um 40 ms ein Aufschlag von **etwa 0 bis +35 %** zu erwarten, typisch eher +5 bis +20 %. Die Grenze garantiert also **nicht** „höchstens +10 %“. Sie siebt aber grobe Ausreißer aus wie Fall C (σ 15 ms, +35 %), was die heutige 25-ms-Grenze nicht tut.

**Bewertung:** Eine vorläufige, strengere Grenze ist begründbar **als Grobsieb gegen grobe Ausreißer**, nicht als Genauigkeitszusage. **Vorschlag: vorläufig 8 ms für RMSSD** (Ruhepuls bleibt bei 25 ms), jetzt einführen statt auf die Entwicklungsmorgen zu warten. Gründe: (1) Fall C zeigt, dass die heutige Grenze Werte mit +35 % als „gut“ ausgibt; das ist das größere Risiko. (2) Die Grenze kostet wenig: Alle fünf bekannten echten Messungen mit gutem Signal (vier der Vorgänger-App, Fall B; σ 4,5–7,2 ms) liegen darunter, und mit der Fensterwahl bestehen in der Synthese bei mittlerer Störung fast alle Aufnahmen (3.10). (3) Die Entwicklungsmorgen werden mit dem Rohsignal ohnehin offline ausgewertet, die Grenze verändert diese Daten nicht. Zwischen 8 und 10 ms entscheiden die Daten nicht (S4: ln 0,14 gegen 0,15 bei RMSSD 40, bestanden 60 gegen 68 %); 8 ms ist die vorsichtigere Wahl und gleicht den Mehrfachvergleich der Fensterwahl (≈ 15 %) teilweise aus. Der Wert wird an den Entwicklungsmorgen geprüft (Empfehlung 2) und vor der Validierung festgeschrieben; den endgültigen Wert liefert die Validierung (R009 Abschnitt 6). Bei kleinem RMSSD (≈ 20 ms) hilft keine Grenze genug (S4: auch bei 5 ms ln 0,29); das bestätigt die Vorsicht aus R009. Ein App-σ ≤ 8 ms schließt außerdem nicht aus, dass Teile des Bildes verrauscht sind (194921, 3.2).

## 5. Empfehlung
**Überblick je Maßnahme**

| Maßnahme | Beleg | Stand im Code | Gemessen hier | Aufwand | Nutzen | Wann |
| --- | --- | --- | --- | --- | --- | --- |
| Bezugspunkt „mix“ (Mittel aus Vorl.Anstieg und steilstem Anstieg) | für slope: Peralta 2019, Ferrer-Mileo 2015; mix selbst: nur Tabelle 3.2 | beide Zeitpunkte werden schon berechnet | echt (n = 1): 14,8 → 11,7 ms je Intervall, Rauschbeitrag 580 → 370 ms²; synth.: −5,5 % über alle, −10 % bei 60 B/s und Störung 0,10; Synthese stützt die Wahl nicht (3.4); ohne Referenz robust | klein (wenige Zeilen, `ppgMethodVersion` 2) | mittel, unsicher | Kandidat; Wahl an Entwicklungsmorgen (Schritt 2) |
| Strengere Grenze Zeitrauschen für RMSSD (vorläufig 8 ms) | R009 Rechnung C, hier 3.9, 4 | 25 ms | Fall C (+35 %) wäre ausgesiebt; darunter typisch +5 bis +20 %, Spanne 0 bis +35 % bei RMSSD 40 | klein (eine Konstante, PAR) | groß gegen grobe Ausreißer, keine Genauigkeitszusage | jetzt (mit WP37), Prüfung an Entwicklungsmorgen |
| Wanderndes Fenster: kleinstes Zeitrauschen über die ganzen 120 s | WP37-Befund (unruhiger Anfang), hier 3.10 | fest 5–65 s | synth.: unruhiger Anfang ln 0,45 → 0,19; ruhig keine Verzerrung der RMSSD, Grenze wirkt ≈ 15 % lascher; Abbruch beim ersten „gut“ (25 ms) ≈ festes Fenster | in WP37 geplant (Abbruchregel ändern) | groß für Ausbeute und Fehler | WP37 |
| Rohsignal mit Kamera-Einstellungen speichern | – | fehlt | Voraussetzung für jede weitere Messung am Signal | in WP37 geplant | Voraussetzung | WP37 |
| Protokoll: Finger leicht auflegen, Hand abgestützt auf Herzhöhe, nicht bewegen, gleiche Haltung | Teng & Zhang 2004, Hickey 2016, HRV4Training; hier 3.2 (in 201643 überwiegt der gemeinsame Fehler, Ursache nicht getrennt) | Hinweise teils vorhanden | nicht messbar ohne Rohsignal | klein (Texte) | wahrscheinlich groß, unbelegt | sofort |
| Tiefpass 8 Hz für Vorl.Anstieg | Mejía-Mejía 2021/2023 (höher besser) gegen Ferrer-Mileo 2015 (≈ 3 Hz) | 4 Hz | echt 14,8 → 12,1 ms; synth. −7 %; schadet „slope“ | klein | klein, unsicher | mit „mix“ zusammen prüfen |
| Bildlücken zählen, `acquireNextImage` | Android-Doku | Lücken < 1 s unbemerkt | mit Sensor-Zeitstempeln unschädlich (S7; Annahme: Zeitstempel exakt) | klein | klein (Diagnose) | WP37 (Zählung im Rohsignal) |
| Höhere Bildrate (120/240), feineres Raster, Hochrechnen | Choi & Shin 2017, Béres 2019 | 60 vor 30, Spline 100 Hz | keine Wirkung (echt und synth.) | groß (120/240 nicht mit YUV) | keiner | nicht tun |
| Manuelle Belichtung/ISO, Torch-Stärke | Solinski 2026 (nur Puls) | AE/AWB-Sperre | nicht messbar | mittel | unklar | erst mit Rohsignal-Daten |
| Glättung der RR-Folge | – | keine | −23 bis −28 % (echt), ln −0,42 (synth.) | – | schädlich | nie |
| Rauschkorrektur √(RMSSD² − 6σ²) | eigene Herleitung | keine | synth. ⅓ des Aufschlags weg, sonst Überkorrektur; echt n = 1 −7 % | klein | unsicher | offline an Messpaaren prüfen |
| Strengere Ausreißergrenze (5 statt 8 %) | Lipponen 2019 (kleine Verschiebungen schwer erkennbar) | 8 % | keine Wirkung | – | keiner | nicht tun |

**Priorisierte Empfehlung (Ablauf bis zur Validierung)**
1. **WP37 (läuft bald):**
   a. Rohsignal je Messung speichern wie geplant, **mit den 16 Teilbereichen** (für die Hälftenprüfung aus 3.2), dazu die Kamera-Angaben (Bildrate, Belichtungszeit, ISO, `SENSOR_INFO_TIMESTAMP_SOURCE`, `SENSOR_ROLLING_SHUTTER_SKEW`, Torch-Stärke, Gerätemodell, Bildlücken, Anteil gesättigter Werte), wie in WP37 schon aufgenommen.
   b. Wanderndes Fenster: unter den Fenstern, die Q und den Anteil gültiger Intervalle erfüllen, das mit dem **kleinsten Zeitrauschen über die ganzen 120 s** wählen. **Kein früher Abbruch beim ersten „guten“ Fenster** mit der 25-ms-Grenze: Das ist in der Simulation praktisch das feste Fenster (3.10). Wenn ein früher Abbruch gewünscht ist, dann erst bei Zeitrauschen ≤ 8 ms, mit erkennbar größerem Fehler (ln 0,25 statt 0,19 bei unruhigem Anfang); empfohlen ist, bis zur Festschreibung (Schritt 3) immer 120 s aufzunehmen. Zeitrauschen, Q und Anteil gültig **aller Kandidatenfenster** speichern (wenige Zahlen je Messung), damit der Mehrfachvergleich später nachgerechnet werden kann.
   c. Eigene RMSSD-Grenze für das Zeitrauschen, **vorläufig 8 ms** (Ruhepuls weiter 25 ms), als Konstante mit PAR-Nummer; Begründung und erwarteter Aufschlag wie in 4 (Grobsieb, keine Genauigkeitszusage).
   d. Kein Wechsel des Bezugspunkts in WP37 selbst (Verfahrensversion bleibt 1).
2. **Direkt nach WP37 (Folgeanalyse an etwa 10 Entwicklungsmorgen mit Rohsignal und Gurt):** offline vergleichen: App, slope, mix, d50, mit und ohne Tiefpass 8 Hz; je Variante Fehler je Intervall, Δ-Fehler, **Kreuzterm**, RMSSD gegen den Gurt; Grenze 8 gegen 10 ms; Hälftenprüfung der genutzten Teilbereiche; Fensterwahl gegen festes Fenster. Gewählt wird die Variante mit dem kleinsten Δ-Fehler gegen den Gurt. Code ist hier vorhanden (`--part real`, ein Leser für das WP37-Format kommt dazu).
3. **Danach, vor dem Start der 28-Morgen-Validierung:** gewählte Variante als `camera-ppg` Version 2 festschreiben (ALGORITHMUS.md, `ppgMethodVersion`), RMSSD-Grenze bestätigen oder anpassen, Fenster- und Abbruchregel festschreiben; Validierung nur an neuen Morgen (R009 Abschnitt 6; die Morgen aus Schritt 2 zählen nicht).
4. **Protokoll sofort** in den Messhinweisen schärfen: Finger nur auflegen, nicht drücken; Hand bzw. Unterarm abstützen, Handy auf Herzhöhe; während der Messung nicht bewegen und nicht sprechen; jeden Tag dieselbe Haltung.
5. **Nicht tun:** RR-Folge glätten; höhere Bildrate oder feineres Raster als Genauigkeitsmaßnahme; Ausreißergrenze verschärfen; Rauschkorrektur ungeprüft in die App; den Bezugspunkt nach der Synthese wählen.

**Vorgeschlagene Konzeptänderungen (Entscheidung beim Maintainer, Änderung durch den Project Supervisor):** PAR-160K bzw. ALGORITHMUS.md Abschnitt 10: eigene RMSSD-Grenze für das Zeitrauschen, vorläufig 8 ms; WP37: Fensterwahl nach kleinstem Zeitrauschen über 120 s, kein früher Abbruch mit der 25-ms-Grenze (Abnahmekriterium „endet nach etwa 65 s“ entsprechend ändern), Zeitrauschen aller Kandidatenfenster speichern, Rohsignal mit 16 Teilbereichen; neues Paket oder Research-Auftrag „Verfahren Version 2“ (Schritte 2 und 3).

## Bewertung und Zweifel
- **Nur eine echte Messung mit Referenz und Rohsignal** (n = 1, Vorgänger-App, ein Handy, eine Person, 46–50 Paare). Alle Aussagen über echte Verbesserungen sind Hinweise. Die Unterschiede zwischen slope, mix und App (10,3 / 11,7 / 14,8 ms) beruhen auf einer Messung; ihre Unsicherheit ist nicht quantifiziert (eine Bootstrap-Schätzung über 46 Paare wäre wegen der Abhängigkeit benachbarter Intervalle optimistisch). Die Synthese stützt diese Reihenfolge **nicht** (3.4: dort ist tpl am besten, das echt schlecht war); nur schwach gestützt ist sie durch die referenzfreie Tabelle 3.2. Die zwei Feldfälle vom 2026-11-14 haben kein Rohsignal und prüfen deshalb nur die Grenze, nicht die Varianten.
- **Die Synthese ist ein Modell.** Störsignal, Pulsform und PTT-Schwankung sind gewählt, nicht gemessen. Sie überschätzt den RMSSD-Fehler gegenüber der echten Messung (3.4) und hat keine Bewegungsartefakte außer einer Druckstufe. Gestützt sind deshalb vor allem Vergleiche zwischen Varianten auf denselben Aufnahmen, nicht die absoluten Werte. Die Stufen wurden so gewählt, dass das App-Zeitrauschen die echten Werte abdeckt.
- **Feldfälle vom 2026-11-14 (3.9):** Ich kenne nur die vom Orchestrator gerechneten Kennzahlen, nicht die Daten; Kreuzterm und Δ-Fehler fehlen, die Deutung „negativer Kreuzterm“ ist dort eine Vermutung. Fall C ist liegend und außerhalb des Morgenfensters, B sitzend und nur „eingeschränkt“ (RMSSD nachgerechnet). Die frühere Aussage, Fall C bestätige die Formel, war falsch (sie beruhte auf einem angenommenen Gurtwert von 40 ms; gemessen sind 58,7 ms).
- **Erwarteter Aufschlag unter 8 ms:** Die Spanne 0 bis +35 % beruht auf drei Quellen, die sich widersprechen (Formel, Synthese ohne Kreuzterm, zwei echte Fälle mit negativem Kreuzterm). Welche näher an der Wirklichkeit liegt, zeigen erst die Entwicklungsmorgen.
- **Fensterwahl (3.10)** ist nur synthetisch geprüft, mit zwei einfachen Verläufen (ruhig, unruhiger Anfang); echte Schwankungen des Rauschens und mögliche Unterschiede der echten RMSSD zwischen Abschnitten sind nicht abgebildet.
- **Auswahl an denselben Daten:** Varianten und Grenze sind an der einzigen Gurtmessung und an der Synthese verglichen. Der Faktor 1,85 in 3.7 ist an denselben Synthesedaten bestimmt. Diese Messungen gelten als Entwicklungsdaten; geprüft wird nur an neuen Morgen.
- **Literatur** stammt zum großen Teil aus Teilrecherchen (TR) und ist von mir nicht am Original nachgeprüft; mehrere Quellen nur als Abstract. Keine Studie vergleicht 30 und 60 Bilder/s direkt, keine misst Fingerdruck, Torch-Stärke oder Sättigung bei Kamera-HRV.
- **Selbst angesehen:** App-Ausgabe der Gurtmessung gegen die Vorgänger-App, Zuordnung (Median-Fehler 6–10 ms, kein Schlagversatz), Zerlegung von RMSSD² an einem Beispiel, Bitgleichheit der Basisvariante mit der App, Selbsttest der Messpaar-Zuordnung (ein erster, periodischer Testfall deckte eine Mehrdeutigkeit der Zuordnung auf; korrigiert durch robuste Kosten). Die Spalte „ganzes Fenster“ für foot (+135 %) liegt weit über „Paare“ (+70 %), weil foot viele Intervalle ohne Gegenstück erzeugt; foot ist ohnehin verworfen.
- **Nicht geprüft:** andere Handys; Genauigkeit der echten Sensor-Zeitstempel (in der Synthese per Konstruktion exakt).

## Offene Punkte und Folgeanalysen
1. Messpaare und Rohsignal aus WP37 auswerten (Schritt 2 oben): Vergleich der Bezugspunkte und der Grenze an ≥ 10 Morgen mit Gurt.
2. Wanderndes Fenster: synthetisch geprüft (3.10); an den Entwicklungsmorgen mit den gespeicherten Kandidatenfenstern nachprüfen, ob die Wahl echt keine Verzerrung bringt.
3. Rauschkorrektur und ein besserer Schätzer für das Zeitrauschen (etwa Restabweichung jedes Schlags zur Vorlage) an echten Messpaaren.
4. Belichtung, ISO und Torch-Stärke erst, wenn die Kamera-Angaben im Rohsignal vorliegen (Vergleich über Tage).
5. Für R009 Offene Punkte 6 (Korrektur RMSSD² − 6σ²): beantwortet als „synthetisch teilweise wirksam, nicht reif“.

## Quellen
Aus R009 (dort geprüft): [B1] Plews 2017, [B2] Bánhalmi 2018, [B3] Peng 2015, [B4] Guede-Fernández 2015, [B6] Esco 2017, [B8] Mather 2024, [B10] Schäfer & Vagedes 2013, [B19] Holmes 2020.

Neu (TR = Teilrecherche, nicht von mir am Original geprüft; VT/A wie dort angegeben):
- Choi A, Shin H 2017, Physiol Meas 38:586, doi:10.1088/1361-6579/aa5efa – A, TR; Kommentar Hejjel L 2017, doi:10.1088/1361-6579/aa9303 – A, TR
- Béres S, Holczer L, Hejjel L 2019, Meas Sci Rev 19:232, doi:10.2478/msr-2019-0030 – VT, TR
- Hejjel L, Rőth E 2004, Physiol Meas 25, doi:10.1088/0967-3334/25/6/006 – A, TR
- Zaunseder S et al. 2022, Biomed Signal Process Control, arXiv:2202.13651 – TR
- Peralta E et al. 2019, Physiol Meas 40:025007, doi:10.1088/1361-6579/ab009b – VT (Postprint), TR
- Mejía-Mejía E, May JM, Kyriacou PA 2022, Comput Methods Programs Biomed 218:106724, doi:10.1016/j.cmpb.2022.106724 – VT, TR
- Mejía-Mejía E, May JM, Kyriacou PA 2021, IEEE EMBC, doi:10.1109/EMBC46164.2021.9629521 – VT, TR
- Mejía-Mejía E, Kyriacou PA 2023, Biomed Signal Process Control 80:104291, doi:10.1016/j.bspc.2022.104291 – VT, TR
- Ferrer-Mileo V et al. 2015, IEEE EMBC, doi:10.1109/EMBC.2015.7319686 – A, TR
- Hemon MC, Phillips JP 2016, J Clin Monit Comput 30:157, doi:10.1007/s10877-015-9695-6 – A, TR
- Lipponen JA, Tarvainen MP 2019, J Med Eng Technol 43:173, doi:10.1080/03091902.2019.1640306 – A, TR
- Peltola MA 2012, Front Physiol 3:148, PMC3358711 – VT, TR
- Yuda E et al. 2020, J Physiol Anthropol, PMC7035641 – A, TR
- Kinnunen H et al. 2020, Physiol Meas, doi:10.1088/1361-6579/ab840a – A, TR
- Li Q, Clifford GD 2012, Physiol Meas 33:1491 – A, TR; Orphanidou C et al. 2015, IEEE JBHI 19:832 – A, TR; Elgendi M 2016, Bioengineering, PMC5597264 – A, TR
- Solinski M et al. 2026, Computing in Cardiology 2026 (angenommen), cinc.org/2026/Program/accepted/512.html – A, TR
- Teng XF, Zhang YT 2004, Physiol Meas 25:1323, doi:10.1088/0967-3334/25/5/020 – A, TR
- Hickey M, Phillips JP, Kyriacou PA 2016, J Clin Monit Comput, doi:10.1007/s10877-015-9761-0 – A, TR
- Matsumura K et al. 2014, PLoS One 9:e91205, PMC3949790 – VT, TR
- Stone JD et al. 2021, Front Sports Act Living 3:585870, doi:10.3389/fspor.2021.585870 – VT (Teile), TR
- Altini M, HRV4Training-Blog „Heart rate variability using the phone camera – Android edition“, 2024 – VT, TR
- Android Developers: `CaptureResult.SENSOR_TIMESTAMP`, `CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE`, `SENSOR_ROLLING_SHUTTER_SKEW`, `ImageReader.acquireLatestImage`, `CaptureRequest.FLASH_STRENGTH_LEVEL`, `CameraManager.turnOnTorchWithStrengthLevel`, `CameraDevice.createConstrainedHighSpeedCaptureSession` – VT, TR
- Vorgänger-App `~/ai/puls`, `docs/METHODIK.md` Abschnitte 6.3–6.5 (Bildrate, Zeitlupe, Gurt) – selbst gelesen, nicht im Repo
