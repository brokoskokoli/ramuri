# R007 – Ergebnis

## Kurzfassung
Der ±3-m-Worst-Case aus WP03 (22 % Scheinstrecke, keine Pause) kommt in keinem echten Datensatz vor. Auf Dach und Stativ mit freier Sicht löst jeder Stopp eine Pause aus, die Scheinstrecke liegt bei höchstens 0,43 % der Laufstrecke. In den einzigen feldnahen Daten, die die Suche fand, liegt sie über der Grenze des Maintainers: 1,41 % aus 183 Stand-Sitzungen unter unbekannten Bedingungen, stückweise zusammengesetzt, also übertragen. Unsicherheit: 20 andere Mischungen der Sitzungen ergeben 1,40 bis 1,58 %, eine andere Auswahl der Sitzungen 1,26 bis 1,88 %. Ein einziger natürlicher Stopp ergibt gerechnet 1,19 %. Die Stoppregel greift in keiner Rechnung auf echten Daten mit den heutigen Parametern: im Median 0 von 3 Stopps ohne Pause, im Mittel höchstens 0,41, in den Spannen höchstens 0,78. Die Bewegungszeit steigt um 0 bis 4,1 %, in den Spannen bis 5,5 %.

Zwei Einschränkungen zur feldnahen Zahl. **Einlauf:** Der Median je Sitzung fällt mit späterem Schnitt weiter. Ob die Scheinstrecke dadurch unter 1 % fällt, ist nicht gezeigt: Die Rechnung durch den Preprocessor bleibt bei jedem der fünf geprüften Schnitte über 1 % (1,17 bis 2,07 %). **GPS-Filter:** Welche Zeilen dieser Daten GPS sind, ist eine Annahme. Mit dem anderen vertretbaren Kriterium sind es 272 Sitzungen und 1,69 bis 1,77 %, Mehrzeit bis 5,5 %. Beides trifft nur die übertragenen Zeilen, nicht die kontrollierten.

**Empfehlung:**
1. **PAR-002, -003, -004, -014, -015 bleiben, keine neue Version wegen dieser Werte.** Keiner dieser Werte steuert die Scheinstrecke nennenswert (Abschnitt 5: 1,37 bis 1,41 % über alle geprüften Werte), und die Stoppregel löst nicht aus.
2. **Bis zum Feldtest so lassen: Entscheidung des Maintainers vom 2026-11-05.** Lösen die übertragenen Werte über 1 % etwas aus? „Nein, bis Feldtest lassen.“ Die Parameter bleiben. Welches Gegenmittel ist belegt? **Keines.** Am besten gestützt, aber nur übertragen, ist ein Tor über `getSpeed` bei 0,5 m/s, und zwar wegen der Bewegungszeit, nicht wegen der Strecke. Es bleibt eine spätere Option: ein neuer Parameter und damit eine neue Version, falls der Feldtest es verlangt.
3. **WP06 speichert `getSpeed` und, falls vorhanden, die Tempo-Genauigkeit je Punkt.** Der Port `LocationSample` hat das Feld schon, `RawPosition` nicht. Rohdaten lassen sich nicht nachholen, und nur damit ist das Tor später ohne neue Aufnahmen prüfbar.

Mindestdistanz mit Haltepunkt und Glättung empfehle ich nicht (Abschnitt Gegenmittel).

Die Zahlen der Entscheidungsregel (mehr als 1 von 3 Stopps, 1 % Scheinstrecke, Lauf von 30 min mit 3 Stopps à 60 s) sind eine **Setzung des Maintainers, keine Studienwerte.**

## Lauf
- **Datum:** 2026-11-05. **Commit:** `0761aad`, sauber (`run.info`). Dart 3.13.5, Python 3.15 ohne Zusatzpakete. Apple-Rechner, ein Kern mit `nice`, parallel lief WP02. Laufzeit 15 min, davon 5 min Spannen. Dieser Lauf ersetzt `20261105-153842-v3`.
- **Kommando:** `./run.sh --seed 42 --runs 200 --run-speed 3 --total-s 1800 --stop-s 60 --stops 3 --burn-in-s 120 --tag r1` (Standard: `--mix-seed 42 --variants 20`).
- **Ausgabe:** `research/data/work/R007/20261105-165321-r1/`: `report.txt`, `varianten.txt` (nicht in Git). Spannen, Parameter und Einlauf stehen in `varianten.txt`, alles andere in `report.txt`.
- **Kontrollen:** ohne Rauschen genau 4860 m und 1641 s, wie von Hand gerechnet. ±3 m genau 360 m je Stopp und 1800 s Bewegungszeit, wie im Test von WP03. Der Pool der Spannen mit Mischungs-Seed 42 ist bytegleich zum Hauptlauf (das Skript bricht sonst ab). Eigene Kontrolle je Gegenmittel in `control_mitigations.csv`: Mittel 5, 10, 20 s −6,0, −13,5, −28,5 m, das ist exakt (w−1)/2 · 3 m.
- **Wiederholbarkeit:** `./run.sh --seed 42 --runs 5 --variants 2 --tag probe2` lieferte denselben Pool und für die ersten 5 Läufe von `ncount_stueckel` dieselben Zeilen wie der Hauptlauf.

## Ergebnisse

### 1. Einordnung nach Beleg
| Art | Quelle | Stopps ohne Pause, Median (Mittel) | Scheinstrecke, Median | Anteil an 4860 m | Mehr-Bewegungszeit |
| --- | --- | --- | --- | --- | --- |
| **belegt, Stand kontrolliert** | OnePlus Nord 2T, 16 Sitzungen, Stativ | 0 (0,00) | 0,0 m (Mittel 0,5 m) | 0,00 % | 0 s |
| belegt, Stand kontrolliert | Samsung S4, S5 | 0 (0,00) | 0,1 m | 0,00 % | 0 s |
| fraglich (eingefrorene Positionen, siehe Zweifel) | Samsung S3 mini, Y | 0 (0,00) | 0,0 m | 0,00 % | 0 s |
| belegt, Stand kontrolliert | Samsung S6 | 0 (0,00) | 20,7 m (P90 26,5 m) | 0,43 % | 0 s |
| belegt, Stand kontrolliert | Samsung S7 | 0 (0,00) | 20,3 m (P90 27,5 m) | 0,42 % | 0 s |
| **übertragen, feldnah** | 183 Sitzungen, ab 10 s, gestückelt | 0 (0,41; 13,5 % der Stopps) | 68,6 m (P10 51,7, P90 142,2) | **1,41 %** (Spannen unten) | 68 s (4,1 %) |
| übertragen, ein Stopp | Gehspur, 126 s Chip-Tempo 0, Xiaomi | Pause nach 24 s | 19,3 m je 60 s (11,0 bis 22,1) | **1,19 %** bei 3 Stopps | – |
| übertragen, ein Stopp | Busspur, 139 s Chip-Tempo 0 | Pause nach 21 s | 2,8 m je 60 s (1,7 bis 6,9) | 0,17 % bei 3 Stopps | – |
| **Synthetik, Vergleich** | ±3 m im Wechsel | 3 (3,00) | 1080 m | 22,22 % | 159 s (9,7 %) |

Je Zeile 200 Läufe, außer den beiden natürlichen Stopps. Ausgelöst wäre damit nur die Streckenklausel und nur in den übertragenen Zeilen; auf Entscheidung des Maintainers folgt daraus bis zum Feldtest nichts. Das Ergebnis der Regel ist gegenüber dem ersten Lauf unverändert, die Dachzeilen auch. Bei 2,5 m/s statt 3 m/s sinkt die Grenze auf 40,5 m: Samsung S6 dann 0,51 %, gestückelt 1,69 % (gerechnet).

**Warum „übertragen“:** Die 454 Sitzungen dauern nur 30 s, also kein ganzer Stopp. 335 haben GPS-Zeilen, 183 mindestens 20. Die Zeitachse t = 0 ist die erste GPS-Zeile, im Median 6,1 s nach dem Start der Aufzeichnung (`StartTime`, P90 10,1 s, Maximum 163 s). In den ersten 10 s beträgt die Rate im Median je Sitzung 71,8 m/min, ab 10 s nur noch 21,2 m/min (95-%-Intervall über Sitzungen 19,0 bis 23,6; das gilt für diese Stand-Rate, nicht für die 1,41 %). Für die Simulation zählt nur der Teil ab 10 s; jede Sitzung trägt rund 13 Schritte bei, ein 60-s-Fenster überspannt also knapp fünf Sitzungen. Ob dieser Teil einem Stopp entspricht, ist nicht belegt: Himmel, Haltung und Ort fehlen, auch Innenräume sind möglich.

**Filterannahme:** Die Daten haben keine Provider-Spalte. Als GPS gelten hier FIX-Zeilen auf der vollen Sekunde. Das ist eine Annahme und nicht beweisbar. Der Filter verwirft 1626 von 7992 Zeilen mit Tempo-Genauigkeit über 0 (Genauigkeit im Median 6,4 m, 1434 davon mehr als 50 ms neben der vollen Sekunde), die dem Takt nach eher GPS sind. Die Auswahl senkt die feldnahe Zahl, die Gegenrechnung steht unten.

**Wie unsicher die feldnahe Zahl ist (alles durch den Preprocessor, je 200 Läufe, keine Vertrauensintervalle außer wo genannt):**

| Spanne | Was variiert | Sitzungen | Scheinstrecke, Median der Läufe | Stopps ohne Pause, Median je Lauf (Mittel) | Mehrzeit |
| --- | --- | --- | --- | --- | --- |
| Hauptlauf | Mischung 42 | 183 | **1,41 %** (68,6 m, Mittel der Läufe 80,5 m = 1,66 %) | 0 (0,41) | 68 s |
| Mischungen, 20 | Anordnung der Sitzungen | 183 | 1,40 bis 1,58 %, Median 1,45 % | 0 (0,13 bis 0,55) | 58 bis 78 s |
| Ziehungen, 5 | Fenster, Pool des Hauptlaufs | 183 | 1,38 bis 1,43 % | – | – |
| Sitzungen mit Zurücklegen, 40 | Auswahl der Sitzungen und Anordnung | 183 gezogen | 1,26 bis 1,88 %, P2,5 bis P97,5: 1,29 bis 1,69 % | 0 (0,08 bis 0,62) | – |
| Schnitt ab 15 s nach erster GPS-Zeile, 5 Mischungen | Einlauf | 183 | 1,19 bis 1,41 % | 0 (0,06 bis 0,39) | 46 bis 59 s |
| Schnitt ab 20 s nach erster GPS-Zeile, 5 | Einlauf | **nur 81** | 1,17 bis 2,07 % | 0 (0,00 bis 0,20) | 34 bis 70 s |
| Schnitt ab 20 s nach `StartTime`, 5 | Einlauf | 172 | 1,46 bis 1,65 % | 0 (0,10 bis 0,57) | 60 bis 71 s |
| Schnitt ab 25 s nach `StartTime`, 5 | Einlauf | 156 | 1,43 bis 1,90 % | höchstens 1 (0,14 bis 0,78) | 60 bis 81 s |
| Filter Tempo-Genauigkeit über 0, 5 | GPS-Auswahl | 272 | 1,69 bis 1,77 % | 0 (0,53 bis 0,61) | 78 bis 90 s (4,8 bis 5,5 %) |

Keine der 98 Rechnungen hinter dieser Tabelle liegt unter 1 %, die kleinste bei 1,17 %. Der Median von 1 Stopp beim Schnitt 25 s (eine von 5 Mischungen) löst die Regel nicht aus, sie verlangt mehr als 1. Mit dem Filter „Tempo-Genauigkeit über 0“ hat das Tor im Streckenfehler Median 19,8 bis 23,2 m bei P90 52,9 bis 76,1 m, Mehrzeit 1 bis 5 s. Die Mediane der Läufe sind stabil, das P90 nicht: Über die Mischungen schwankt es zwischen 97 und 153 m, über die Ziehungen zwischen 99 und 144 m. Grund: Rund 5 % der Stopps treffen Sitzungen mit einzelnen großen Sprüngen (bis 139 m je Stopp, Median 22 m), und ein P90 je Lauf aus 3 Stopps liegt genau an dieser Kante.

### 2. Rauschen im Stand (Rohdaten)
| Quelle | Punkte | Schritte ohne Versatz | Δs/Δt P50 / P90 / P99 (m/s) | unter 0,5 m/s | m/min | σ je Achse (m), ρ je s |
| --- | --- | --- | --- | --- | --- | --- |
| OnePlus Nord 2T | 28 062 | 99,6 % | 0 / 0 / 0 | 99,9 % | 0,20 | 0,00, 0,995 |
| Samsung S3 mini / Y | 106 111 / 116 451 | 100,0 / 99,7 % | 0 / 0 / 0 | 100 % | 0,01 / 0,03 | 1,4 / 1,3, 1,000 |
| Samsung S4 / S5 | 129 194 / 129 273 | 63,5 / 56,3 % | 0 / 0,002 / 0,04 | 100 % | 0,06 / 0,20 | 0,5 / 0,9, 0,999 |
| Samsung S6 / S7 | 129 304 / 117 938 | 0 % | 0,09 / 0,23 / 0,49 | 99,3 / 99,1 % | 7,0 | 4,6 / 3,0, 1,000 |
| Natürlicher Stopp Gehspur | 126 | 0 % | 0,23 / 0,62 / 0,81 | 78,6 % | 16,3 | – |
| 183 Sitzungen, ab 10 s, gestückelt | 2254 | 9,1 % | 0,26 / 0,85 / 5,69 | 72,3 % | 27,9 (Median je Sitzung 21,2) | – |
| ±3 m, Synthetik | 3479 | 0 % | 6 / 6 / 6 | 0 % | 360 | 1,5, −1,000 |

**Befund:** Das OnePlus meldet im Stand fast durchgehend dieselbe Position mit Tempo 0, während sich die gemeldete Genauigkeit ändert: Das spricht für ein Halten im Chip, nicht für einen Fehler des Loggers. S4 und S5 tun das in rund 60 % der Schritte. Beim S3 mini und Y ist es anders zu lesen: Szot et al. berichten für das S3 mini, die Position ändere sich erst beim Speichern der Datei, und halten seine Werte für unzuverlässig; das Y hielt die Position periodisch [3]. Echtes Rauschen ist sehr stark autokorreliert (ρ ≥ 0,995 je Sekunde), wie von Ranacher et al. beschrieben [4]. Große Positionsfehler (σ 4,6 m) erzeugen darum nur kleine Schritte (0,09 m/s). Zum Vergleich mit dem Fehler am Referenzpunkt: Szot et al. messen DRMS von 1,0 bis 8,0 m [3].

**AR(1)-Raster (übertragen, Synthetik):** Ab wann löst Rauschen die Regel aus? Bei σ = 1 m ist ρ = 0,98 noch innerhalb (0,93 %, 0 Stopps), ρ = 0,95 nicht mehr (1,47 %, 2 Stopps). Bei σ = 2 m reicht ρ = 0,98 nicht (1,85 %, 3 Stopps), ρ = 0,995 ja (0,94 %). Bei σ = 3 m und ρ = 0,995: 1,38 %, 1 Stopp. Bei σ = 5 m und ρ = 0,995: 2,30 %, 3 Stopps. Die gemessenen S6 und S7 haben größere σ, aber höhere ρ: Sie liegen unter der Grenze. Das Raster stützt die Reihenfolge, liefert aber keine Messung.

### 3. Gegenmittel (nur Analysecode, **alles übertragen**)
Keine Zeile dieser Tabelle ist ein Beleg für die Wirkung auf einem Handy im Lauf. Die gestückelten Spalten stammen aus den 30-s-Sitzungen, auf S6, S7 und ±3 m fehlen Tempodaten, auf dem OnePlus ist schon „keins“ 0 m, im simulierten Laufteil ist das Tempo ideal, und der Schaden an Bewegung stammt aus Spuren ohne Referenz.

Die Scheinstrecke in den Stopps ist bei Glättung kein fairer Vergleich, weil das Mittel die Strecke vor dem Stopp in den Stopp hineinschiebt. Darum zählt hier der **Streckenfehler** des ganzen Laufs je Lauf gegenüber der rauschfreien Kontrolle **desselben Gegenmittels**. Das gleitende Mittel endet auch ohne Rauschen (w−1)/2 · v hinter dem letzten Punkt, gegen die Kontrolle ohne Gegenmittel würde sich dieser Rand mit dem Rauschen verrechnen. Die Mehrzeit bleibt gegen die Kontrolle ohne Gegenmittel, weil sie den Schaden mit einschließt. Spalte „Mischungen“: Median der Läufe über die Mischungen 1 bis 20, ohne den Hauptlauf.

| Gegenmittel | Gestückelt: Streckenfehler, Median | P10 bis P90 | Mittel | Mischungen | Läufe über 48,6 m | Stopps ohne Pause (Mittel) | Mehrzeit | Samsung S6: Median | ±3 m: Median | Schaden an echter Bewegung |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| keins | 68,6 m (1,41 %) | 51,7 bis 142,2 | 80,6 | 67,8 bis 76,7 | 94,5 % | 0,41 | 68 s | 20,7 m | 1080 m | – |
| Tor `getSpeed` 0,5 m/s | 20,8 m (0,43 %) | 5,8 bis 79,2 | 31,4 | 13,5 bis 19,8 | 14,5 % | 0,00 | 5 s | keine Tempodaten | keine Tempodaten | Gehspur Strecke −1,2 %, Bewegungszeit −1,0 % gegen „keins“; Rad −0,9 % und −0,3 % |
| Tor `getSpeed` 0,3 m/s | 22,3 m (0,46 %) | 8,4 bis 86,4 | 34,6 | – | 17,0 % | 0,00 | 10 s | keine Tempodaten | keine Tempodaten | Gehspur −1,1 %, −0,6 %; Rad −0,6 %, −0,3 % |
| Strecke aus `getSpeed` | 11,7 m (0,24 %) | 5,9 bis 78,8 | 24,2 | 10,1 bis 13,5 | 12,0 % | 0,00 | 0 s | keine Tempodaten | keine Tempodaten | Gehspur −7,4 %, Rad −4,0 % gegen „keins“; ohne Referenz offen, welche richtig ist |
| Mindestdistanz 5 m, nur Strecke | 20,8 m (0,43 %) | 1,1 bis 93,1 | 30,4 | 15,9 bis 24,1 | 16,5 % | 0,41 | 68 s | 1,5 m | 717 m | Gehspur −3,4 %, Rad −2,4 % |
| Mindestdistanz 8 m, nur Strecke | 11,2 m (0,23 %) | −2,0 bis 75,8 | 23,5 | 8,8 bis 17,0 | 12,5 % | 0,41 | 68 s | −0,2 m | 0 m (Pause trotzdem nie) | Gehspur −4,1 %, Rad −3,5 %; PAR-002 und -003 verwerfen die Sprünge von 8 m und mehr (Rad 34 weich, 3 hart) |
| Mindestdistanz mit Haltepunkt, 3 bis 10 m | wie oben | | | | | höchstens 0,03 | **rund −1226 s** | wie oben | – | **Bewegungszeit bricht zusammen:** Gehspur 10 s statt 3189 s |
| Mittel 5 s | 45,6 m (0,94 %) | 31,8 bis 114,1 | 56,6 | – | 40,5 % | 0,04 | 35 s | 16,9 m | 201,6 m (3 Stopps) | Mehrzeit 9 s auch bei perfekten Daten |
| Mittel 10 s | 34,6 m (0,71 %) | 24,0 bis 100,3 | 45,6 | 32,5 bis 38,3 | 19,5 % | 0,00 | 27 s | 14,3 m | 1,8 m | Mehrzeit 18 s auch bei perfekten Daten; Gehspur −4,4 %, Rad −5,9 % |
| Mittel 20 s | 22,2 m (0,46 %) | 13,3 bis 89,9 | 33,5 | 21,3 bis 26,3 | 13,0 % | 0,04 | 35 s | 10,2 m | 0,9 m | Mehrzeit 33 s auch bei perfekten Daten; Gehspur −5,9 %, Rad −11,2 % |
| Strecke ruht in erkannter Pause (aus dem Anteil gerechnet, nicht simuliert) | rund 45 m (0,9 %) | | | | | 0,41 | 68 s | rund 3,7 m | 1080 m | keiner erkennbar |

**Welches Gegenmittel ist belegt?** Keines. Am besten gestützt, übertragen, ist das Tor, und zwar wegen der Bewegungszeit: Mehrzeit 5 s statt 68 s und keine Stopps ohne Pause. Im Streckenfehler ist es nicht das beste: Im Median gleich mit Mindestdistanz 5 m nur Strecke (je 20,8 m, Mittel 31,4 und 30,4 m), Mindestdistanz 8 m und das Integral liegen darunter, Mittel 20 s liegt gleichauf (22,2 m). In 14,5 % der Läufe liegt das Tor noch über der Grenze von 48,6 m (keins 94,5 %).

**Herkunft des Rests beim Tor:** Das Tor hält den Punkt im Stopp. Beim ersten Laufpunkt nach dem Stopp wird der aufgelaufene Versatz auf einmal gezählt. Dieser Punkt liegt außerhalb des Stoppfensters, also nicht in der Scheinstrecke (Median 9,3 m). Je Lauf ist der Streckenfehler im Median 7,5 m größer als die Scheinstrecke (Mittel 8,6 m), alles in den 25 s nach den Stopps, im übrigen Lauf 0,0 m. Für das Tor ist darum der Streckenfehler die richtige Zahl, nicht die Scheinstrecke.

**Modellgrenze:** Im Modell bleibt der Versatz dauerhaft bestehen und läuft über die Sitzungsstücke als Zufallsweg auf. Ein echter Stopp kehrt dagegen zur wahren Position zurück. Der Nachholschritt beim Tor und die Länge des Versatzes sind also Modellgrößen, das Tor kann auf echten Stopps besser oder schlechter liegen. Die Mindestdistanz hat ein kleineres Gegenstück: Je nach Phase verliert sie am Laufende bis zur Hüpfweite (Median −3,0 m im übrigen Lauf bei 5 m), die eigene Kontrolle gleicht das nur für eine Phase aus.

Hauptlauf und Mischungen passen beim Tor nicht ganz zusammen: 20,8 m im Hauptlauf liegen über allen 20 Mischungen (13,5 bis 19,8 m). Das Tor hängt stärker an einzelnen Sitzungen als „keins“; die 20,8 m sind eher der hohe Rand. Ein früherer Lauf mit anderer Ziehung (`abcbecb`) ergab für Samsung S6 ohne Gegenmittel 20,2 statt 20,7 m; so groß ist dort die Streuung durch die Ziehung.

**Warum die Mindestdistanz mit Haltepunkt scheitert:** Bei 3 m/s und 5 m entsteht die Folge 0, 6, 0, 6 m/s. Die Unterbrechung setzt PAR-015 jede Sekunde zurück, die 3 s zum Fortsetzen kommen nie zustande. Das ist ein Zusammenspiel mit dem vorhandenen Code und kein Fehler der Simulation. Ein neues Zeitfenster für die Bewegung wäre ein anderes Verfahren. Bei 8 m fallen zudem echte 0,6 und 0,8 m/s dauerhaft in Pause (Bewegungsanteil 3 %).

**Warum nicht Glättung:** Sie drückt den Streckenfehler auf rund die Hälfte (10 s) bis ein Drittel (20 s), kostet aber auch bei perfektem Signal Bewegungszeit (18 s und 33 s) und kürzt echte Kurven (Rad −11,2 % bei 20 s). Das 5-s-Mittel löst im Worst Case die Regel weiter aus (201,6 m, 3 Stopps). Ein negativer Streckenfehler, wie ihn der erste Lauf bei 20 s zeigte, war der Rand und kein Überschießen.

### 4. `getSpeed`
**Verfügbarkeit über `LocationManager` mit `GPS_PROVIDER` ohne Play-Dienste: belegt, mit einer Einschränkung.**
- Plattform: `GnssLocationProvider` im Framework setzt `setHasSpeedSupport(true)` und importiert nichts aus den Play-Diensten [2].
- Prüfpflicht: Der CTS-Test `GnssLocationValuesTest` fordert über `TestLocationManager` mit `GPS_PROVIDER`: „All but the first GNSS location from LocationManager must have speeds.“ [2]. Die erste Position darf also ohne Tempo kommen, der Adapter braucht diesen Fall.
- Messung: Beim OnePlus tragen 33 000 von 33 000 `Fix,GPS`-Zeilen ein Tempo und eine Tempo-Genauigkeit. GNSSLogger schreibt dort `location.getSpeed()` des Providers `GPS` [5]. Über 454 Sitzungen haben 6366 von 6420 Zeilen eine Tempo-Genauigkeit über 0. Dort lässt sich „kein Tempo“ nicht von 0 unterscheiden, weil die App beides als 0 schreibt.
- **Einschränkung:** Alle Aufnahmen stammen von Handys mit Play-Diensten. Dass der Weg ohne sie läuft, folgt aus dem Code, nicht aus einem Test auf einem Gerät ohne sie. Geprüft werden kann das hier nicht (keine Geräte).

**Was `getSpeed` ist:** Die Dokumentation sagt nur, das Tempo könne genauer sein als Distanz durch Zeit, „such as if the Doppler measurements from GNSS satellites are taken into account“ [1]. Die Herkunft ist nicht zugesagt, der Wert ist nie negativ. Studien messen die rohen Doppler-Werte, nicht `getSpeed`: Im Stand ist der horizontale Fehler 0,020 m/s beim Mi8 [6]; beim Huawei nova5 im cm/s- und beim Redmi K40 im dm/s-Bereich, also je Gerät (nur das Abstract gelesen) [7]. Keine Studie prüft `getSpeed` bei Geh- und Lauftempo gegen eine Referenz (Suche erfolglos).

**Gemessen im Stand (übertragen):** In 183 Sitzungen ab 10 s ist Δs/Δt in 28,2 % der Schritte mindestens 0,5 m/s, `getSpeed` nur in 3,9 %. Ist `getSpeed` genau 0 (66,7 %), zeigt Δs/Δt trotzdem in 20,9 % der Fälle 0,5 m/s oder mehr. Mit den ersten 10 s sind es 44,0, 4,9, 62,5 und 36,1 %. Beim Gehen liegen beide nah beieinander (Median 1,34 und 1,43 m/s, Differenz im Median 0,12 m/s). Alle 10 Abschnitte der Gehspur ab 10 s unter 0,5 m/s haben ein mittleres Chip-Tempo von höchstens 0,22 m/s. Das Tempo ist also ein brauchbarer Zeuge, aber der Zeuge ist derselbe Chip und nicht die Wahrheit.

### 5. Parameter
Pool des Hauptlaufs, gleiche Ziehung, je 200 Läufe, jede Zeile gegen ihre Kontrolle mit denselben Parametern. Die Werte sind nur Vergleich, keine Vorschläge.

| Parameter | Scheinstrecke | Stopps ohne Pause, Median (Mittel), Anteil | Mehrzeit |
| --- | --- | --- | --- |
| heute (PAR-014 0,5 und 0,8, PAR-015 10 s) | 1,41 % | 0 (0,41), 13,5 % | 68 s |
| PAR-014 0,7 und 0,8 | 1,41 % | 0 (0,03), 0,8 % | 41,5 s |
| PAR-014 0,8 und 0,8 | 1,41 % | 0 (0,03), 0,8 % | 33,5 s |
| PAR-014 1,0 und 1,2 | 1,41 % | 0 (0,00), 0,0 % | 14 s |
| PAR-002 und -003 aus | 1,41 % | 0 (0,40), 13,3 % | 68 s |
| PAR-003 ab 5 m/s statt 8 | 1,37 % | 0 (0,41), 13,8 % | 68 s |
| PAR-004 5 s statt 10 | 1,41 % | 0 (0,41), 13,5 % | 68 s |
| PAR-015 5 s statt 10 | 1,41 % | 0 (0,01), 0,2 % | 33,5 s |
| PAR-015 20 s statt 10 | 1,41 % | **2 (1,85), 61,7 %** | 101,5 s |

Die Parameter ändern die Scheinstrecke praktisch nicht: `PositionProcessor` zählt unabhängig vom Autopause-Zustand, und die Sprungfilter greifen kaum. PAR-014 und PAR-015 steuern dagegen die Stoppklausel und die Bewegungszeit. Mit PAR-015 = 20 s würde die Stoppregel im gestückelten Pool auslösen; das ist nicht der heutige Wert, zeigt aber, dass PAR-015 nicht höher gehen sollte, ohne das zu prüfen. Eine höhere obere Schwelle von PAR-014 kollidiert mit seiner Begründung (langsames Gehen 0,82 m/s) und bringt die Stoppregel nicht zum Kippen, die ohnehin nicht auslöst.

**PAR-002, -003, -004 im Stand:** Sie greifen praktisch nicht. OnePlus über 8,4 h: 7 hart, 16 weich, 2 Lücken. Samsung über 206 h: kein einziger Sprung. In den 183 Sitzungen 85 hart und 50 weich von 4348 Punkten, fast alles in den ersten 10 s (ohne Schritte über 5 m/s bleibt die Rate ab Sekunde 10 fast gleich, 21,0 gegen 21,2 m/min). Die Lücken der Samsung-Daten sind Abbrüche des Loggers, die Fensterwahl schließt sie aus. Über PAR-004 sagt das also wenig.

### 6. Wirkung auf FR-0029, FR-0052 und TRIMP
Der Mehr-Bewegungszeit-Anteil ist auf dem Dach 0 %, gestückelt 4,1 % (Spannen bis 5,5 %), im Worst Case 9,7 %. Die Pause kommt auf dem Dach im Median nach den vorgesehenen 10 s, im Einzelfall bis 42 s (S7), gestückelt im Median nach 19 s, im Einzelfall erst zum Stoppende. TRIMP zählt Minuten je Zone: Ist der Puls im Stand nicht höher als im Lauf, sind diese Anteile eine obere Schranke für den Fehler (gerechnet, nicht simuliert). In der Gehspur gibt es keine falsche Pause, die dem Chip-Tempo widerspricht, aber auch nur 8 Pausen in 56 min und keine Referenz.

## Bewertung und Zweifel
- **Auffällig: Die Daten widersprechen sich um den Faktor 3 und mehr.** Dach: bis 7 m/min. Feldnah: 21 m/min. Das ist der wichtigste Befund. Die Regel fällt je nach Datensatz anders aus. Die beiden Enden sind vermutlich bester und schlechter Fall, ein echter Stopp an der Ampel fehlt in den offenen Daten.
- **Der Schnitt bei 10 s entfernt den Einlauf vielleicht nicht vollständig, nachgewiesen ist eine Wirkung auf die Regel nicht.** Der Median je Sitzung fällt weiter: ab 10, 15, 20 s nach der ersten GPS-Zeile 21,2 / 18,5 / 14,6 m/min (n = 183, 183, 81). Die gepoolte Rate, der die Summe über viele Stücke eher folgt, fällt nicht mit: 30,8 / 24,7 / 25,0 m/min. Der Abfall hängt zudem an der Achse. Gleiche Sitzungen und gleich lange Fenster, ab erster GPS-Zeile (n = 79): 20,5 / 13,3 / 14,1 m/min in 10–15, 15–20, 20–25 s, ab rund 15 s also kein Abfall mehr (Differenz der letzten beiden 0,4, 95 % −0,6 bis 3,0). Seit `StartTime` (n = 146): 38,4 / 27,6 / 18,8 / 15,1 m/min bis 30 s, jeder Schritt signifikant. **Ob die Scheinstrecke dadurch unter 1 % fällt, ist nicht gezeigt.** Die Rechnung durch den Preprocessor bleibt bei jedem Schnitt über 1 % (Tabelle in Abschnitt 1, 1,17 bis 2,07 %). Früher hier genannte Prozentwerte aus dem Median je Sitzung mal 3 (1,17 und 0,94 %) sind **kein Wert der Regel** und gestrichen. Die Schnitte dokumentieren die Spanne, gesucht wurde kein besserer Schnitt; der ab 20 s beruht auf nur 81 Sitzungen. Der Einlauf wird auf Entscheidung des Maintainers (2026-11-05) nicht weiter aufgeklärt. Auch der natürliche Stopp (1,19 %) liegt am Aufnahmebeginn.
- **Die Auswahl der GPS-Zeilen ist eine Annahme und wirkt in die Gegenrichtung.** Mit Tempo-Genauigkeit über 0 als Kriterium: 272 statt 183 Sitzungen, Median ab 10 s 25,6 statt 21,2 m/min, Scheinstrecke 1,69 bis 1,77 %, Mehrzeit 78 bis 90 s. Welche Auswahl richtig ist, lässt sich ohne Provider-Spalte nicht beweisen.
- **Die Dachdaten sind ein Bestfall.** Freie Sicht, kein Körper, keine Bewegung. Das Halten der Position kann davon abhängen, dass das Handy wirklich stillliegt. Auf einem Läufer, der atmet und das Handy am Arm hat, könnte es ausbleiben. Das ist Vermutung und hier nicht prüfbar.
- **Der Übergang fehlt.** Gezogen wird aus dem Stand, kein Chip kommt in der Simulation aus 3 m/s. Filter im Chip könnten nach dem Stoppen nachlaufen; das verschiebt die Pause um einige Sekunden. Der Laufteil ist rauschfrei, mit Rauschen träfen Mindestdistanz und Glättung anders. Das Tor sieht im Lauf nur das ideale Tempo.
- **S3 mini und Y zählen nicht.** Ihre eingefrorenen Positionen sind vermutlich ein Effekt des Loggers; das ist meine Deutung, die Studie sagt nur, was in Abschnitt 2 steht [3]. Sie stehen darum getrennt, und die Aussage „kontrolliert höchstens 0,43 %“ stützt sich nicht auf sie.
- **Alte Chips.** Die Samsung-Modelle stammen von 2012 bis 2016. Modern ist das OnePlus von 2022, also ein Gerät. Die 183 Sitzungen decken viele Chips ab (Qualcomm 18,3, MediaTek 26,4, Samsung 19,7 m/min im Median), aber nur 30 s.
- **Stichprobe.** Je 200 Läufe ziehen aus demselben Pool; die Spanne der Läufe ist kein Vertrauensintervall. Die Unsicherheit des gestückelten Ergebnisses steht in der Spannentabelle: Die Mischungen zeigen nur die Anordnung, die Sitzungen mit Zurücklegen (40 Wiederholungen, grob) auch die Auswahl. Der Hauptlauf (1,41 %) liegt am unteren Rand der Mischungen (Median 1,45 %); das ist Zufall der Mischung 42. Im Pool fallen die ersten 120 s nicht in die Ziehung, das ändert wenig (ohne das 1,46 statt 1,41 %, bei Schnitt 20 s 1,38 %). Beim OnePlus sind 16 Sitzungen ein Gerät, bei Samsung je ein Gerät in zwei Kampagnen. Der natürliche Stopp der Gehspur ist ein einzelner, 60-s-Fenster überlappen sich, und er liegt am Beginn der Aufnahme. Dort ist noch Einlauf möglich; in den letzten 30 s steht die Position fast.
- **Kennzeichnung Stopp.** Die natürlichen Stopps sind aus Chip-Tempo 0 abgeleitet, was fürs Tor zirkulär ist. Ob dort jemand wirklich stand, sagt die Spur nicht (Nettoversatz 1,5 und 3,2 m).
- **Genauigkeit.** NMEA-Daten melden keine, gesetzt sind 5 m. PAR-001 ist dort also nicht geprüft, PAR-003 nur mit dieser Annahme. Die Busspur fällt durch PAR-003 (357 weich, 38 hart); das ist für einen Bus gewollt und sagt nichts über Läufe.
- **Fehler im eigenen Aufbau, behoben:** Im ersten Lauf (`20261105-153842-v3`) enthielt der gestückelte Pool je Sitzung einen undokumentierten Nullschritt an der Naht (183 von 2560 Punkten), die Scheinstrecke war dadurch 1,31 statt 1,41 %, die Mehrzeit 56 statt 68 s (Review). Der Streckenfehler der Glättung lief gegen die falsche Kontrolle (auf dem Pool dieses Laufs Mittel 10 s 21,1 statt 34,6 m, Mittel 20 s −6,3 statt 22,2 m). Das Intervall neben den 1,31 % gehörte zur Stand-Rate, nicht zur Kennzahl. Die Begründung des GPS-Filters war falsch. Eine Sitzung hatte unsortierte Zeilen, drei hatten Zeit-Dubletten; jetzt wird sortiert und nicht steigende Zeit übersprungen, beim Hauptschnitt ändert das den Pool nicht. Davor unterwegs behoben: Ein Komma im Namen eines Gegenmittels verschob CSV-Spalten, der Lauf ist verworfen. Die Mindestdistanz mit Haltepunkt zeigte −1227 s; das ist echt, siehe oben, und führte zur Variante „nur Strecke“.
- **Selbst angesehen:** Einzelschritte von S6, S7, OnePlus und dem natürlichen Stopp. Dazu die größten Schritte des Pools und die Verteilung der Scheinstrecke je Stopp. Die Handrechnung der Kontrollen stimmt. σ im gestückelten Pool (33,9 m) ist bedeutungslos, weil Sitzungen aneinanderhängen; die Tabelle nennt es darum nicht.
- **Gegenprobe zur Vermutung aus OQ-0068:** „Echtes Rauschen ist autokorreliert und meist kleiner“ bestätigt sich in beiden Datenarten.

## Offene Punkte und Folgeanalysen
- **Entschieden (Maintainer, 2026-11-05):** Lösen die übertragenen Werte über 1 % etwas aus? „Nein, bis Feldtest lassen.“ Die Parameter bleiben, keine neue Version vor WP06. WP06 speichert `getSpeed` je Punkt, ein Tor ist später ohne neue Aufnahmen prüfbar.
- **Entschieden (Maintainer, 2026-11-05):** Der Einlauf wird nicht weiter aufgeklärt und kein besserer Schnitt gesucht. Nach dem Review: „Fehler beheben, neu rechnen.“ Die Spanne der Schnitte ist dokumentiert.
- **Spätere Option:** neuer Parameter Tor `getSpeed` 0,5 m/s mit neuer Version, falls der Feldtest es verlangt.
- **Vorschläge fürs Konzept, nicht umgesetzt:**
  - OQ-0068: Antwort gemäß Kurzfassung, im Feldtest zu bestätigen.
  - WP06: `getSpeed` samt `hasSpeed`-Fall und Tempo-Genauigkeit über `LocationSample` hinaus bis in die gespeicherten Rohpunkte tragen; `RawPosition` hat das Feld heute nicht.
  - `docs/model-parameters.md`, Validierungsbedarf PAR-014, PAR-015: um die Schlussfolgerung ergänzen, dass diese Werte die Scheinstrecke nicht steuern, PAR-015 aber die Stoppklausel.
  - Eine eigene Frage: Soll Strecke während der erkannten Pause zählen? Das wäre eine Änderung des Verfahrens, keine Parameteränderung, und brächte gestückelt rund 0,9 % (gerechnet, im Mittel der Läufe rund 1,1 %). Das reicht aber nur, wenn die Pause auch auslöst.
  - Kommentar im Test `motion_prefix_test.dart`: Der Worst Case ist kein realistischer Fall, sondern die obere Schranke.
- **Feldtest (Maintainer, kein Teil dieses Auftrags):** protokollierte Ampelstopps mit Handy am Körper, je mindestens zwei Chipfamilien, `getSpeed` mitschreiben. Daraus ergeben sich Scheinstrecke, verpasste Pausen, Tor gegen Rohdaten und das Verhalten des Chips beim Übergang von Lauf zu Stand.
- **Offen trotz Suche:** keine offene Aufnahme von echten Stopps mit Referenz, keine Validierung von `getSpeed` bei Laufgeschwindigkeit.
- **Nicht genutzt und nicht geöffnet:** Hervanta-Datensatz (Zenodo 8340005, 670 MB, wegen der Grenze von 1 GB). Er könnte weitere feldnahe Daten enthalten. Eine Folgeanalyse könnte dort prüfen, ob es Gehphasen gibt.

## Quellen (Abruf 2026-11-05)
1. Android Developers, `Location`: https://developer.android.com/reference/android/location/Location
2. AOSP: `GnssLocationProvider.java` (frameworks/base), `GnssLocationValuesTest.java` und `TestLocationManager.java` (cts), `GnssLocation.aidl` (hardware/interfaces), Zweig `main`: https://android.googlesource.com/
3. Szot, Specht, Specht, Dąbrowski 2019, PLOS ONE 14(4), e0215562: https://pmc.ncbi.nlm.nih.gov/articles/PMC6472772/. Daten: https://zenodo.org/records/1312834
4. Ranacher et al. 2016, Int J Geogr Inf Sci: https://pmc.ncbi.nlm.nih.gov/articles/PMC4786863/. Die Gleichungen liegen dort als Bilder vor und wurden nicht gelesen; zitiert ist nur der Text.
5. GNSSLogger, `FileLogger.java`, `MeasurementProvider.java`: https://github.com/google/gps-measurement-tools
6. Angrisano, Cappello, Del Pizzo, Gaglione 2022, Sensors 22(21), 8514. Xiaomi Mi8, statisch, Doppler und TDCP, RMS horizontal 0,0202 m/s (Doppler): https://pmc.ncbi.nlm.nih.gov/articles/PMC9655395/
7. Li et al. 2022, ISPRS Archives XLVI-3/W1-2022, 89 (nur Abstract gelesen): https://doi.org/10.5194/isprs-archives-XLVI-3-W1-2022-89-2022
8. Merry und Bettinger 2019, PLOS ONE: https://pmc.ncbi.nlm.nih.gov/articles/PMC6638960/. Einzelne Fixes im Abstand von Minuten, sagt nichts über aufeinanderfolgende Punkte; darum nicht zur Kalibrierung genutzt.
9. Daten: Agarwal et al., Mendeley Data kybmdyrzb3 v1; Parmar, Saini, Chhatre 2026, Zenodo 20092798; Medina und Lohan 2025, Zenodo 14712684.
