# R007 – Ergebnis

## Kurzfassung
Der ±3-m-Worst-Case aus WP03 (22 % Scheinstrecke, keine Pause) kommt in keinem echten Datensatz vor. Auf Dach und Stativ mit freier Sicht löst jeder Stopp eine Pause aus, die Scheinstrecke liegt bei höchstens 0,43 % der Laufstrecke. In den einzigen feldnahen Daten, die es offen gibt, liegt sie knapp über der Grenze des Maintainers: 1,31 % (95-%-Intervall 1,17 bis 1,46 %) aus 183 Stand-Sitzungen unter unbekannten Bedingungen, stückweise zusammengesetzt, und 1,19 % aus einem einzigen natürlichen Stopp. Die Stoppregel greift nirgends in echten Daten: im Median 0 von 3 Stopps ohne Pause, im Mittel höchstens 0,38. Die Bewegungszeit steigt um 0 bis 3,4 %.

**Empfehlung:**
1. **PAR-002, -003, -004, -014, -015 bleiben, keine neue Version wegen dieser Werte.** Keiner dieser Werte ändert die Scheinstrecke (Schwellenraster unten: 1,31 % bei jeder Schwelle), und die Stoppregel löst nicht aus.
2. **Bis zum Feldtest so lassen, sofern der Maintainer die übertragenen 1,2 bis 1,3 % nicht als Auslöser wertet.** Das ist die offene Entscheidung (siehe Offene Punkte). Wertet er sie als Auslöser, ist ein Tor über `getSpeed` bei 0,5 m/s das belegte Gegenmittel: ein neuer Parameter und damit eine neue Version.
3. **Unabhängig davon speichert WP06 `getSpeed` und, falls vorhanden, die Tempo-Genauigkeit je Punkt.** Der Port `LocationSample` hat das Feld schon, `RawPosition` nicht. Rohdaten lassen sich nicht nachholen, und nur damit lässt sich das Tor im Feldtest ohne neue Aufnahmen prüfen.

Mindestdistanz mit Haltepunkt und Glättung empfehle ich nicht (Abschnitt Gegenmittel).

Die Zahlen der Entscheidungsregel (mehr als 1 von 3 Stopps, 1 % Scheinstrecke, Lauf von 30 min mit 3 Stopps à 60 s) sind eine **Setzung des Maintainers, keine Studienwerte.**

## Lauf
- **Datum:** 2026-11-05. **Commit:** `db3b0fb`, sauber (`run.info`). Dart 3.13.5, Python 3.15 ohne Zusatzpakete. Apple-Rechner, ein Kern mit `nice`, parallel lief WP02. Laufzeit rund 7 min.
- **Kommando:** `./run.sh --seed 42 --runs 200 --run-speed 3 --total-s 1800 --stop-s 60 --stops 3 --burn-in-s 120 --tag v3`
- **Ausgabe:** `research/data/work/R007/20261105-153842-v3/report.txt` (nicht in Git).
- **Schwellenraster:** Harness desselben Standes direkt auf der Quelle `ncount_stueckel`, je 200 Läufe mit `--standstill-below` und `--movement-from`. Über alle Quellen wiederholbar mit `./run.sh --standstill-below 1.0 --movement-from 1.2`.
- **Kontrollen:** ohne Rauschen genau 4860 m und 1641 s, wie von Hand gerechnet. ±3 m genau 360 m je Stopp und 1800 s Bewegungszeit, wie im Test von WP03.
- **Wiederholbarkeit:** `./run.sh --seed 42 --runs 5` lieferte für die ersten 5 Läufe von `oneplus_nord2t` dieselben Zeilen wie der Hauptlauf. Ein zweites `./init.sh` lädt nichts neu.

## Ergebnisse

### 1. Einordnung nach Beleg
| Art | Quelle | Stopps ohne Pause, Median (Mittel) | Scheinstrecke, Median | Anteil an 4860 m | Mehr-Bewegungszeit |
| --- | --- | --- | --- | --- | --- |
| **belegt, Stand kontrolliert** | OnePlus Nord 2T, 16 Sitzungen, Stativ | 0 (0,00) | 0,0 m (Mittel 0,5 m) | 0,00 % | 0 s |
| belegt, Stand kontrolliert | Samsung S4, S5 | 0 (0,00) | 0,1 m | 0,00 % | 0 s |
| fraglich (eingefrorene Positionen, siehe Zweifel) | Samsung S3 mini, Y | 0 (0,00) | 0,0 m | 0,00 % | 0 s |
| belegt, Stand kontrolliert | Samsung S6 | 0 (0,00) | 20,7 m (P90 26,5 m) | 0,43 % | 0 s |
| belegt, Stand kontrolliert | Samsung S7 | 0 (0,00) | 20,3 m (P90 27,5 m) | 0,42 % | 0 s |
| **übertragen, feldnah** | 183 Sitzungen, ab Sekunde 10, gestückelt | 0 (0,38; 12,7 % der Stopps) | 63,8 m (P10 48,3, P90 106,1) | **1,31 %** | 56 s (3,4 %) |
| übertragen, ein Stopp | Gehspur, 126 s Chip-Tempo 0, Xiaomi | Pause nach 24 s | 19,3 m je 60 s (11,0 bis 22,1) | **1,19 %** bei 3 Stopps | – |
| übertragen, ein Stopp | Busspur, 139 s Chip-Tempo 0 | Pause nach 21 s | 2,8 m je 60 s (1,7 bis 6,9) | 0,17 % bei 3 Stopps | – |
| **Synthetik, Vergleich** | ±3 m im Wechsel | 3 (3,00) | 1080 m | 22,22 % | 159 s (9,7 %) |

Je Zeile 200 Läufe, außer den beiden natürlichen Stopps. Ausgelöst wird damit nur die Streckenklausel und nur in den übertragenen Zeilen. Bei 2,5 m/s statt 3 m/s sinkt die Grenze auf 40,5 m: Samsung S6 dann 0,51 %, gestückelt 1,58 % (gerechnet).

**Warum „übertragen“:** Die 454 Sitzungen dauern nur 30 s, also kein ganzer Stopp. 335 haben GPS-Zeilen, 183 mindestens 20. Sie beginnen beim Start der Aufzeichnung. In den ersten 10 s beträgt die Rate im Median 71,8 m/min, ab Sekunde 10 nur noch 21,2 m/min (95-%-Intervall über Sitzungen 19,0 bis 23,6). Für die Simulation zählt nur der Teil ab Sekunde 10; ein 60-s-Fenster überspannt rund drei Sitzungen. Ob dieser Teil einem Stopp entspricht, ist nicht belegt: Himmel, Haltung und Ort fehlen, auch Innenräume sind möglich.

### 2. Rauschen im Stand (Rohdaten)
| Quelle | Punkte | Schritte ohne Versatz | Δs/Δt P50 / P90 / P99 (m/s) | unter 0,5 m/s | m/min | σ je Achse (m), ρ je s |
| --- | --- | --- | --- | --- | --- | --- |
| OnePlus Nord 2T | 28 062 | 99,6 % | 0 / 0 / 0 | 99,9 % | 0,20 | 0,00, 0,995 |
| Samsung S3 mini / Y | 106 111 / 116 451 | 100,0 / 99,7 % | 0 / 0 / 0 | 100 % | 0,01 / 0,03 | 1,4 / 1,3, 1,000 |
| Samsung S4 / S5 | 129 194 / 129 273 | 63,5 / 56,3 % | 0 / 0,002 / 0,04 | 100 % | 0,06 / 0,20 | 0,5 / 0,9, 0,999 |
| Samsung S6 / S7 | 129 304 / 117 938 | 0 % | 0,09 / 0,23 / 0,49 | 99,3 / 99,1 % | 7,0 | 4,6 / 3,0, 1,000 |
| Natürlicher Stopp Gehspur | 126 | 0 % | 0,23 / 0,62 / 0,81 | 78,6 % | 16,3 | – |
| 183 Sitzungen, ab 10 s | 2435 | 15,6 % | 0,24 / 0,81 / 4,92 | 74,3 % | 25,9 (Median je Sitzung 21,2) | – |
| ±3 m, Synthetik | 3479 | 0 % | 6 / 6 / 6 | 0 % | 360 | 1,5, −1,000 |

**Befund:** Das OnePlus meldet im Stand fast durchgehend dieselbe Position mit Tempo 0, während sich die gemeldete Genauigkeit ändert: Das spricht für ein Halten im Chip, nicht für einen Fehler des Loggers. S4 und S5 tun das in rund 60 % der Schritte. Beim S3 mini und Y ist es anders zu lesen: Szot et al. berichten, die Position ändere sich dort erst beim Speichern der Datei, und halten die Werte des S3 mini selbst für unzuverlässig [3]. Echtes Rauschen ist sehr stark autokorreliert (ρ ≥ 0,995 je Sekunde), wie von Ranacher et al. beschrieben [4]. Große Positionsfehler (σ 4,6 m) erzeugen darum nur kleine Schritte (0,09 m/s). Zum Vergleich mit dem Fehler am Referenzpunkt: Szot et al. messen DRMS von 1,0 bis 8,0 m [3].

**AR(1)-Raster (übertragen, Synthetik):** Ab wann löst Rauschen die Regel aus? Bei σ = 1 m ist ρ = 0,98 noch innerhalb (0,93 %, 0 Stopps), ρ = 0,95 nicht mehr (1,47 %, 2 Stopps). Bei σ = 2 m reicht ρ = 0,98 nicht (1,85 %, 3 Stopps), ρ = 0,995 ja (0,94 %). Bei σ = 3 m und ρ = 0,995: 1,38 %, 1 Stopp. Bei σ = 5 m und ρ = 0,995: 2,30 %, 3 Stopps. Die gemessenen S6 und S7 haben größere σ, aber höhere ρ: Sie liegen unter der Grenze. Das Raster stützt die Reihenfolge, liefert aber keine Messung.

### 3. Gegenmittel (nur Analysecode)
Die Scheinstrecke in den Stopps ist bei Glättung kein fairer Vergleich, weil das Mittel die Strecke vor dem Stopp in den Stopp hineinschiebt. Darum zählt hier der **Streckenfehler** des ganzen Laufs gegenüber der Kontrolle.

| Gegenmittel | Gestückelt: Streckenfehler | Gestückelt: Stopps ohne Pause (Mittel) | Gestückelt: Mehrzeit | Samsung S6: Streckenfehler | ±3 m: Streckenfehler | Schaden an echter Bewegung |
| --- | --- | --- | --- | --- | --- | --- |
| keins | 63,8 m (1,31 %) | 0,38 | 56 s | 20,7 m | 1080 m | – |
| Tor `getSpeed` 0,5 m/s | 16,9 m (0,35 %) | 0,00 | 3 s | keine Tempodaten | keine Tempodaten | Gehspur Strecke −1,2 %, Bewegungszeit −1,0 % gegen „keins“; Rad −0,9 % und −0,3 % |
| Tor `getSpeed` 0,3 m/s | 21,3 m (0,44 %) | 0,00 | 8 s | keine Tempodaten | keine Tempodaten | Gehspur −1,1 %, −0,6 %; Rad −0,6 %, −0,3 % |
| Strecke aus `getSpeed` | 11,0 m (0,23 %) | 0,00 | 0 s | keine Tempodaten | keine Tempodaten | Gehspur −7,4 %, Rad −4,0 % gegen „keins“; ohne Referenz offen, welche richtig ist |
| Mindestdistanz 5 m, nur Strecke | 17,0 m (0,35 %) | 0,38 | 56 s | 1,5 m | 717 m | Gehspur −3,4 %, Rad −2,4 % |
| Mindestdistanz 8 m, nur Strecke | 9,4 m (0,19 %) | 0,38 | 56 s | −0,2 m | 0 m (Pause trotzdem nie) | Gehspur −4,1 %, Rad −3,5 %; PAR-002 und -003 verwerfen die Sprünge von 8 m und mehr (Rad 34 weich, 3 hart) |
| Mindestdistanz mit Haltepunkt, 3 bis 10 m | wie oben | 0,00 | **−1227 s** | wie oben | – | **Bewegungszeit bricht zusammen:** Gehspur 10 s statt 3189 s |
| Mittel 10 s | 18,8 m (0,39 %) | 0,00 | 29 s | 0,8 m | −11,7 m | Mehrzeit 18 s auch bei perfekten Daten; Gehspur −4,4 %, Rad −5,9 % |
| Mittel 20 s | −7,2 m (−0,15 %) | 0,05 | 35 s | −18,3 m | −27,6 m | Mehrzeit 33 bis 34 s; Gehspur −5,9 %, Rad −11,2 % |
| Strecke ruht in erkannter Pause (aus den Anteilen gerechnet, nicht simuliert) | rund 39 m (0,8 %) | 0,38 | 56 s | rund 3,7 m | 1080 m | keiner erkennbar |

Ein früherer Lauf mit anderer Ziehung (`abcbecb`) ergab für Samsung S6 ohne Gegenmittel 20,2 statt 20,7 m; so groß ist die Streuung durch die Ziehung.

**Warum die Mindestdistanz mit Haltepunkt scheitert:** Bei 3 m/s und 5 m entsteht die Folge 0, 6, 0, 6 m/s. Die Unterbrechung setzt PAR-015 jede Sekunde zurück, die 3 s zum Fortsetzen kommen nie zustande. Das ist ein Zusammenspiel mit dem vorhandenen Code und kein Fehler der Simulation. Ein neues Zeitfenster für die Bewegung wäre ein anderes Verfahren. Bei 8 m fallen zudem echte 0,6 und 0,8 m/s dauerhaft in Pause (Bewegungsanteil 3 %).

**Warum nicht Glättung:** Sie drückt den Streckenfehler, kostet aber auch bei perfektem Signal Bewegungszeit (18 s und 33 s) und kürzt echte Kurven (Rad −11,2 % bei 20 s). Das 5-s-Mittel löst im Worst Case die Regel weiter aus (195,6 m, 3 Stopps).

### 4. `getSpeed`
**Verfügbarkeit über `LocationManager` mit `GPS_PROVIDER` ohne Play-Dienste: belegt, mit einer Einschränkung.**
- Plattform: `GnssLocationProvider` im Framework setzt `setHasSpeedSupport(true)` und importiert nichts aus den Play-Diensten [2].
- Prüfpflicht: Der CTS-Test `GnssLocationValuesTest` fordert über `TestLocationManager` mit `GPS_PROVIDER`: „All but the first GNSS location from LocationManager must have speeds.“ [2]. Die erste Position darf also ohne Tempo kommen, der Adapter braucht diesen Fall.
- Messung: Beim OnePlus tragen 33 000 von 33 000 `Fix,GPS`-Zeilen ein Tempo und eine Tempo-Genauigkeit. GNSSLogger schreibt dort `location.getSpeed()` des Providers `GPS` [5]. Über 454 Sitzungen haben 6366 von 6420 Zeilen eine Tempo-Genauigkeit über 0. Dort lässt sich „kein Tempo“ nicht von 0 unterscheiden, weil die App beides als 0 schreibt.
- **Einschränkung:** Alle Aufnahmen stammen von Handys mit Play-Diensten. Dass der Weg ohne sie läuft, folgt aus dem Code, nicht aus einem Test auf einem Gerät ohne sie. Geprüft werden kann das hier nicht (keine Geräte).

**Was `getSpeed` ist:** Die Dokumentation sagt nur, das Tempo könne genauer sein als Distanz durch Zeit, „such as if the Doppler measurements from GNSS satellites are taken into account“ [1]. Die Herkunft ist nicht zugesagt, der Wert ist nie negativ. Studien messen die rohen Doppler-Werte, nicht `getSpeed`: Im Stand ist der horizontale Fehler 0,020 m/s beim Mi8 [6], beim Huawei nova5 und Redmi K40 je nach Rechnung im cm/s- bzw. dm/s-Bereich [7]. Keine Studie prüft `getSpeed` bei Geh- und Lauftempo gegen eine Referenz (Suche erfolglos).

**Gemessen im Stand (übertragen):** In 183 Sitzungen ist Δs/Δt in 44,0 % der Schritte mindestens 0,5 m/s, `getSpeed` nur in 4,9 %. Ist `getSpeed` genau 0 (62,5 %), zeigt Δs/Δt trotzdem in 36,1 % der Fälle 0,5 m/s oder mehr. Beim Gehen liegen beide nah beieinander (Median 1,34 und 1,43 m/s, Differenz im Median 0,12 m/s). Alle 10 Abschnitte der Gehspur ab 10 s unter 0,5 m/s haben ein mittleres Chip-Tempo von höchstens 0,22 m/s. Das Tempo ist also ein brauchbarer Zeuge, aber der Zeuge ist derselbe Chip und nicht die Wahrheit.

### 5. Schwellen und die übrigen Parameter
| PAR-014 unten, oben | Stopps ohne Pause, gestückelt | Mehrzeit | Scheinstrecke |
| --- | --- | --- | --- |
| 0,5, 0,8 (heute) | 12,7 % | 56 s | 1,31 % |
| 0,7, 0,8 | 1,7 % | 35,5 s | 1,31 % |
| 0,8, 0,8 | 1,7 % | 30,5 s | 1,31 % |
| 1,0, 1,2 | 0,0 % | 14 s | 1,31 % |

Höhere Schwellen senken die Bewegungszeit, die Strecke bleibt gleich: `PositionProcessor` zählt unabhängig vom Autopause-Zustand. Eine höhere obere Schwelle kollidiert mit der Begründung von PAR-014 (langsames Gehen 0,82 m/s) und bringt die Stoppregel nicht zum Kippen, die ohnehin nicht auslöst.

**PAR-002, -003, -004 im Stand:** Sie greifen praktisch nicht. OnePlus über 8,4 h: 7 hart, 16 weich, 2 Lücken. Samsung über 206 h: kein einziger Sprung. In den 183 Sitzungen 85 hart und 50 weich von 4348 Punkten, fast alles in den ersten 10 s (ohne Schritte über 5 m/s bleibt die Rate ab Sekunde 10 fast gleich, 21,0 gegen 21,2 m/min). Die Lücken der Samsung-Daten sind Abbrüche des Loggers, die Fensterwahl schließt sie aus. Über PAR-004 sagt das also wenig.

### 6. Wirkung auf FR-0029, FR-0052 und TRIMP
Der Mehr-Bewegungszeit-Anteil ist auf dem Dach 0 %, gestückelt 3,4 %, im Worst Case 9,7 %. Die Pause kommt auf dem Dach im Median nach den vorgesehenen 10 s, im Einzelfall bis 42 s (S7), gestückelt im Median nach 16,5 s, im Einzelfall bis 59 s. TRIMP zählt Minuten je Zone: Ist der Puls im Stand nicht höher als im Lauf, sind diese Anteile eine obere Schranke für den Fehler (gerechnet, nicht simuliert). In der Gehspur gibt es keine falsche Pause, die dem Chip-Tempo widerspricht, aber auch nur 8 Pausen in 56 min und keine Referenz.

## Bewertung und Zweifel
- **Auffällig: Die Daten widersprechen sich um den Faktor 3 und mehr.** Dach: bis 7 m/min. Feldnah: 21 m/min. Das ist der wichtigste Befund. Die Regel fällt je nach Datensatz anders aus. Die beiden Enden sind vermutlich bester und schlechter Fall, ein echter Stopp an der Ampel fehlt in den offenen Daten.
- **Die Dachdaten sind ein Bestfall.** Freie Sicht, kein Körper, keine Bewegung. Das Halten der Position kann davon abhängen, dass das Handy wirklich stillliegt. Auf einem Läufer, der atmet und das Handy am Arm hat, könnte es ausbleiben. Das ist Vermutung und hier nicht prüfbar.
- **Der Übergang fehlt.** Gezogen wird aus dem Stand, kein Chip kommt in der Simulation aus 3 m/s. Filter im Chip könnten nach dem Stoppen nachlaufen; das verschiebt die Pause um einige Sekunden. Der Laufteil ist rauschfrei, mit Rauschen träfen Mindestdistanz und Glättung anders. Das Tor sieht im Lauf nur das ideale Tempo.
- **S3 mini und Y zählen nicht.** Ihre eingefrorenen Positionen sind laut Studie vermutlich ein Effekt des Loggers [3]. Sie stehen darum getrennt, und die Aussage „kontrolliert höchstens 0,43 %“ stützt sich nicht auf sie.
- **Alte Chips.** Die Samsung-Modelle stammen von 2012 bis 2016. Modern ist das OnePlus von 2022, also ein Gerät. Die 183 Sitzungen decken viele Chips ab (Qualcomm 18,3, MediaTek 26,4, Samsung 19,7 m/min im Median), aber nur 30 s.
- **Stichprobe.** Je 200 Läufe ziehen aus demselben Pool; die Spanne der Läufe ist kein Vertrauensintervall. Fürs gestückelte Ergebnis gilt das Bootstrap-Intervall über Sitzungen. Beim OnePlus sind 16 Sitzungen ein Gerät, bei Samsung je ein Gerät in zwei Kampagnen. Der natürliche Stopp der Gehspur ist ein einzelner, 60-s-Fenster überlappen sich, und er liegt am Beginn der Aufnahme. Dort ist noch Einlauf möglich; in den letzten 30 s steht die Position fast.
- **Kennzeichnung Stopp.** Die natürlichen Stopps sind aus Chip-Tempo 0 abgeleitet, was fürs Tor zirkulär ist. Ob dort jemand wirklich stand, sagt die Spur nicht (Nettoversatz 1,5 und 3,2 m).
- **Genauigkeit.** NMEA-Daten melden keine, gesetzt sind 5 m. PAR-001 ist dort also nicht geprüft, PAR-003 nur mit dieser Annahme. Die Busspur fällt durch PAR-003 (357 weich, 38 hart); das ist für einen Bus gewollt und sagt nichts über Läufe.
- **Kein Fehler im Aufbau gefunden, zwei unterwegs behoben:** Ein Komma im Namen eines Gegenmittels verschob CSV-Spalten, der Lauf ist verworfen. Die Mindestdistanz mit Haltepunkt zeigte −1227 s; das ist echt, siehe oben, und führte zur Variante „nur Strecke“.
- **Selbst angesehen:** Einzelschritte von S6, S7, OnePlus und dem natürlichen Stopp. Die Handrechnung der Kontrollen stimmt. σ im gestückelten Pool (33,9 m) ist bedeutungslos, weil Sitzungen aneinanderhängen; die Tabelle nennt es darum nicht.
- **Gegenprobe zur Vermutung aus OQ-0068:** „Echtes Rauschen ist autokorreliert und meist kleiner“ bestätigt sich in beiden Datenarten.

## Offene Punkte und Folgeanalysen
- **Entscheidung des Maintainers:** Zählen die übertragenen 1,2 bis 1,3 % als „über 1 %“? Die Regel nennt die Datenbasis nicht. Wenn ja: neuer Parameter Tor `getSpeed` 0,5 m/s, neue Version vor WP06. Wenn nein: so lassen bis Feldtest.
- **Vorschläge fürs Konzept, nicht umgesetzt:**
  - OQ-0068: Antwort gemäß Kurzfassung, im Feldtest zu bestätigen.
  - WP06: `getSpeed` samt `hasSpeed`-Fall und Tempo-Genauigkeit über `LocationSample` hinaus bis in die gespeicherten Rohpunkte tragen; `RawPosition` hat das Feld heute nicht.
  - `docs/model-parameters.md`, Validierungsbedarf PAR-014, PAR-015: um die Schlussfolgerung ergänzen, dass diese Werte die Scheinstrecke nicht steuern.
  - Eine eigene Frage: Soll Strecke während der erkannten Pause zählen? Das wäre eine Änderung des Verfahrens, keine Parameteränderung, und brächte gestückelt rund 0,8 %. Das reicht aber nur, wenn die Pause auch auslöst.
  - Kommentar im Test `motion_prefix_test.dart`: Der Worst Case ist kein realistischer Fall, sondern die obere Schranke.
- **Feldtest (Maintainer, kein Teil dieses Auftrags):** protokollierte Ampelstopps mit Handy am Körper, je mindestens zwei Chipfamilien, `getSpeed` mitschreiben. Daraus ergeben sich Scheinstrecke, verpasste Pausen, Tor gegen Rohdaten und das Verhalten des Chips beim Übergang von Lauf zu Stand.
- **Offen trotz Suche:** keine offene Aufnahme von echten Stopps mit Referenz, keine Validierung von `getSpeed` bei Laufgeschwindigkeit.
- **Nicht genutzt:** Hervanta-Datensatz (Zenodo 8340005, 670 MB, wegen der Grenze von 1 GB). Eine Folgeanalyse könnte dort prüfen, ob es Gehphasen gibt.

## Quellen (Abruf 2026-11-05)
1. Android Developers, `Location`: https://developer.android.com/reference/android/location/Location
2. AOSP: `GnssLocationProvider.java` (frameworks/base), `GnssLocationValuesTest.java` und `TestLocationManager.java` (cts), `GnssLocation.aidl` (hardware/interfaces), Zweig `main`: https://android.googlesource.com/
3. Szot, Specht, Specht, Dąbrowski 2019, PLOS ONE 14(4), e0215562: https://pmc.ncbi.nlm.nih.gov/articles/PMC6472772/. Daten: https://zenodo.org/records/1312834
4. Ranacher et al. 2016, Int J Geogr Inf Sci: https://pmc.ncbi.nlm.nih.gov/articles/PMC4786863/. Die Gleichungen liegen dort als Bilder vor und wurden nicht gelesen; zitiert ist nur der Text.
5. GNSSLogger, `FileLogger.java`, `MeasurementProvider.java`: https://github.com/google/gps-measurement-tools
6. Xiaomi Mi8, statisch, Doppler und TDCP, RMS horizontal 0,0202 m/s: https://pmc.ncbi.nlm.nih.gov/articles/PMC9655395/
7. Li et al. 2022, ISPRS Archives XLVI-3/W1-2022, 89: https://doi.org/10.5194/isprs-archives-XLVI-3-W1-2022-89-2022
8. Merry und Bettinger 2019, PLOS ONE: https://pmc.ncbi.nlm.nih.gov/articles/PMC6638960/. Einzelne Fixes im Abstand von Minuten, sagt nichts über aufeinanderfolgende Punkte; darum nicht zur Kalibrierung genutzt.
9. Daten: Agarwal et al., Mendeley Data kybmdyrzb3 v1; Parmar, Saini, Chhatre 2026, Zenodo 20092798; Medina und Lohan 2025, Zenodo 14712684.
