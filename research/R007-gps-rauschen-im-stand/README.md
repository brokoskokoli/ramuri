# R007 – GPS-Rauschen im Stand

**Status:** abgeschlossen, Nachbesserung nach Review Runde 1 · **Auftraggeber:** Project Supervisor (OQ-0068, vor WP06) · **Datum:** 2026-11-05

## Frage
Wie stark verfälscht GPS-Rauschen im Stand auf Android-Smartphones Strecke und Bewegungszeit, wenn die Geschwindigkeit aus Δs/Δt bei 1 Hz stammt, und welches Gegenmittel ist belegt: Mindestdistanz, Glättung oder `Location.getSpeed()`? Daran hängen OQ-0068 und die Frage, ob PAR-002 bis -004, -014, -015 vor WP06 eine neue Parameterversion brauchen.

**Entscheidungsregel (Setzung des Maintainers, keine Studienwerte):** Neue Version, wenn im Median mehr als 1 von 3 Stopps keine Pause auslöst oder die Scheinstrecke über 1 % der Laufstrecke liegt. Bezug: typischer Lauf von 30 min mit 3 Stopps à 60 s, simuliert durch den vorhandenen `RunPreprocessor`.

## Hintergrund
WP03 hat mit einem synthetischen Worst Case gezeigt: ±3 m abwechselnd bei 1 Hz über 60 s ergibt 360 m Strecke, der Zustand bleibt `moving` (`app/packages/core/test/preprocessing/motion_prefix_test.dart`, OQ-0068). PAR-014 und PAR-015 nennen als Validierungsbedarf das Rauschen im Stand (`docs/model-parameters.md`). ADR-0005 legt `LocationManager` mit `GPS_PROVIDER` ohne Play-Dienste fest. FR-0029 und FR-0052 wirken über die Bewegungszeit auf TRIMP. Bezug zum Code: `PositionProcessor` zählt Strecke unabhängig vom Autopause-Zustand, `MovementTimeProcessor` rechnet aus denselben Segmenten.

Quellen der Vorrecherche stehen in [RESULTS.md](RESULTS.md).

## Methode
1. **Literatur:** Android-Dokumentation und AOSP/CTS zu `getSpeed`, Studien zu Standrauschen, Doppler und Streckenverzerrung.
2. **Offene Stand-Rohdaten durch den echten `RunPreprocessor`** (`src/harness.dart`, importiert `core`, ändert nichts an `app/`). Ein Lauf ist eine Gerade: 405 s mit `--run-speed`, Stopp 60 s, im Wechsel, zusammen 1800 s mit 3 Stopps. In jedem Stopp läuft die Spur mit den echten Inkrementen eines zufällig gezogenen 60-s-Fensters weiter, aus derselben Quelle. So entsteht an den Nahtstellen kein Sprung. Ein Fenster gilt nur ohne Abstand über 2 s und nach 120 s Einlauf je Sitzung. Der Laufteil ist rauschfrei, damit die Scheinstrecke nur aus dem Stand kommt.
3. **Kennzahlen je Lauf:** Stopps ohne Pause (kein Bewegungsintervall deckt den Stopp ganz ab, also keine Pause bis zum Stoppende), Scheinstrecke (Summe `countedDistanceMeters` in den Stopps), Mehr-Bewegungszeit gegenüber der rauschfreien Kontrolle ohne Gegenmittel, Streckenfehler des ganzen Laufs gegenüber der rauschfreien Kontrolle **desselben** Gegenmittels (ein Gegenmittel kann die Strecke auch ohne Rauschen ändern, `control_mitigations.csv`). Dazu verworfene Punkte nach Grund und Anteil der Scheinstrecke, der in die erkannte Pause fällt.
4. **Gegenmittel nur im Analysecode,** als kausaler Filter vor dem Preprocessor: Mindestdistanz (3, 5, 8, 10 m und max(3 m, Genauigkeit), jeweils mit Haltepunkt und als Variante `_nurstrecke`, bei der die Bewegungszeit aus den Rohpunkten kommt), gleitendes Mittel (5, 10, 20 s), Tor über `getSpeed` (0,3 und 0,5 m/s), Strecke als Integral über `getSpeed`.
5. **Schaden der Gegenmittel an echter Bewegung:** echte Standinkremente plus Vorschub mit 0,6 bis 3 m/s (falsche Pausen, Streckenverhältnis), dazu eine echte Geh-, Rad- und Busspur.
6. **Feldnaher Vergleich (übertragen):** Die 30-s-Sitzungen sind zu kurz für einen Stopp. Für `ncount_stueckel` werden ihre Teile ab 10 s nach der ersten GPS-Zeile in zufälliger Reihenfolge aneinandergehängt (`src/stueckel.py`, Seed `--mix-seed`, getrennt vom Seed der Ziehung). An der Naht entsteht kein Punkt und kein Zeitschritt. Jede Sitzung trägt rund 13 Schritte bei, ein 60-s-Fenster überspannt also rund fünf Sitzungen. Dazu natürliche Stopps aus der Geh- und Busspur.
7. **Vergleich und Kalibrierung:** ±3-m-Worst-Case und ein AR(1)-Raster (σ 1 bis 8 m, ρ 0,8 bis 0,995 je Sekunde). Beides ist Synthetik und in den Ergebnissen als übertragen gekennzeichnet.
8. **Spannen um den gestückelten Wert (`src/varianten.py`, `varianten.txt`):** alle durch denselben Harness. Mischungen der Sitzungen (Unsicherheit durch die Anordnung), Ziehungen der Fenster, Sitzungen mit Zurücklegen (Unsicherheit durch die Auswahl der Sitzungen), Einlauf-Schnitte (10, 15, 20 s nach erster GPS-Zeile, 20, 25 s nach `StartTime`), GPS-Filter „Tempo-Genauigkeit über 0“ statt „volle Sekunde“. Die Schnitte dokumentieren die Spanne, sie sind keine Suche nach einem besseren Schnitt. Dazu die Einlauf-Raten ohne Simulation.
9. **Parameter:** Vergleich anderer Werte von PAR-002, -003, -004, -014 und -015 auf dem Pool des Hauptlaufs, ohne den App-Code zu ändern (Teil von `varianten.py`, einzeln über `--standstill-below` und `--movement-from` auch für alle Quellen).

**Kontrolle (Handrechnung):** Ohne Rauschen 4860 m = 1620 s · 3 m/s. Bewegungszeit 1641 s = 1800 − 3 · (60 − 10 + 3), weil die Pause 10 s nach Stoppbeginn einsetzt und das Fortsetzen 3 s braucht. ±3 m ergibt 360 m je Stopp und 1800 s Bewegungszeit, wie im Test von WP03. Der Harness schreibt die Kontrolle nach `control.txt`.

**Warum diese Methode:** Die Regel des Maintainers ist am `RunPreprocessor` definiert, also läuft genau dieser Code. Echte Inkremente enthalten die Autokorrelation und das Halten der Position durch den Chip, die eine Annahme über Rauschen nicht kennt.

## Daten
Katalog: [research/DATA.md](../DATA.md). Keine Sammlung aus `input/`, keine privaten Daten, keine Konten. Koordinaten aus den Datensätzen werden nicht zitiert.

| Was | Wo unter `data/datasets/` | Herkunft, Lizenz | Download | Inhalt und Eignung |
| --- | --- | --- | --- | --- |
| Samsung Galaxy S3 mini, S4, S5, S6, S7, Y | `zenodo-1312834/` | Szot et al. 2019, Zenodo 1312834, CC BY 4.0 | 57 MB | Stand auf einem Dach, freie Sicht, 1 Hz, GPGGA, Kampagnen 24 h und 12 h. Ohne Genauigkeit (gesetzt: 5 m) und ohne Tempo. Chips von 2012 bis 2016 |
| OnePlus Nord 2T | `mendeley-kybmdyrzb3-v1/` | Agarwal et al., Mendeley kybmdyrzb3 v1, CC BY 4.0 | 565 MB, entpackt 3,4 GB | Stativ, Dach, 16 Sitzungen à 30 min und 5 à 10 min. `Fix,GPS`-Zeilen aus `GPS_PROVIDER` mit Tempo und Genauigkeit |
| 454 Sitzungen, 285 Modelle | `zenodo-20092798/` | Parmar et al. 2026, Zenodo 20092798, CC BY 4.0 | 11 MB | Je 30 s Stand ohne Kontrolle der Bedingungen, FIX-Zeilen. Keine Provider-Spalte. **Annahme:** Nur Zeilen auf der vollen Sekunde gelten als GPS. Das ist nicht beweisbar, der Filter verwirft auch Zeilen mit Tempo-Genauigkeit über 0, die dem Takt nach eher GPS sind (Zahlen und Gegenrechnung in [RESULTS.md](RESULTS.md)). 335 Sitzungen haben Zeilen auf der vollen Sekunde |
| GNSSLogger Gehen, Rad, Bus | `zenodo-14712684/` | Medina und Lohan 2025, Zenodo 14712684, CC BY 4.0 | 141 MB | Je eine Spur, Xiaomi und andere, NMEA-RMC mit 1 Hz und Chip-Tempo. Ohne Genauigkeit (gesetzt: 5 m), ohne Referenz. Natürliche Stopps: Abschnitte ab 60 s mit Chip-Tempo 0 |

Genutzt, aber nicht nachgeladen: nichts aus anderen Analysen. Verworfen: Google GSDC und der Kaggle-Datensatz (Konto, fahrend), Zenodo 8340005 (670 MB, über der Download-Grenze, nicht geöffnet).

## Ausführung
Voraussetzungen: Dart 3.13.5 (Flutter-SDK des Projekts), Python 3 ohne Zusatzpakete, 4 GB Platte. Rechenzeit etwa 15 min auf einem Kern (`nice`), davon rund 5 min für die Spannen (`--variants 0` lässt sie weg). `app/` wird nur gelesen.

```bash
./init.sh            # lädt und entpackt nach research/data/datasets/ (idempotent)
./run.sh [Parameter] # normiert, baut und startet den Harness, wertet aus
```

| Parameter | Standard | Bedeutung |
| --- | --- | --- |
| `--seed N` | `42` | Zufallsstartwert |
| `--mix-seed N` | `42` | Reihenfolge der gestückelten Sitzungen im Hauptlauf |
| `--variants N` | `20` | Mischungen für die Spannen in `varianten.txt`, doppelt so viele Stichproben, 0 = keine |
| `--runs N` | `200` | simulierte Läufe je Quelle |
| `--run-speed V` | `3` | Lauftempo in m/s |
| `--total-s N` | `1800` | Laufdauer in s |
| `--stop-s N` | `60` | Dauer eines Stopps in s |
| `--stops N` | `3` | Zahl der Stopps |
| `--burn-in-s N` | `120` | Einlaufzeit je Stand-Sitzung, die nicht gezogen wird |
| `--standstill-below V` | `0.5` | PAR-014 untere Schwelle, nur zum Vergleich |
| `--movement-from V` | `0.8` | PAR-014 obere Schwelle, nur zum Vergleich |
| `--tag T` | leer | Zusatz im Namen des Laufordners |

Beispiel: `./run.sh --seed 42 --runs 200 --run-speed 3 --total-s 1800 --stop-s 60 --stops 3 --burn-in-s 120`

Ausgaben: `research/data/work/R007/<zeit><tag>/`: `report.txt` (alle Tabellen), `varianten.txt` und `varianten.csv` (Spannen, Parameter, Einlauf), `runs.csv`, `stops.csv`, `slow.csv`, `traces.csv`, `control.txt`, `control_mitigations.csv`, `run.info`, `norm/`, `var/` (Einzelläufe der Spannen). Ergebnis in [RESULTS.md](RESULTS.md).
