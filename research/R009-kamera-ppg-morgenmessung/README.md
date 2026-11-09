# R009 – Ruhepuls und HRV-Morgenmessung mit der Handykamera

**Status:** abgeschlossen (Review ausstehend) · **Auftraggeber:** Project Supervisor (für FR-0214, FR-0215, M3), Auftrag mit dem Maintainer geklärt · **Datum:** 2026-11-09

## Frage
Wie misst man Ruhepuls und RMSSD mit der Handykamera (60 s, Finger auf Rückkamera und Blitz), damit die Werte (a) als Ruhepuls im Profil (FR-0214) und (b) als tägliche Morgenmessung für die Erholungseinschätzung (FR-0215) taugen? Wie wertet man die täglichen Werte aus, und wie prüft man die Messung gegen einen EKG-Brustgurt (Polar H9)?

Daran hängen: das Messprotokoll in WP27 (FR-0214), die Freigabe von FR-0215 und der Plan für M3 (Readiness ohne Uhr). Kriterien: Belege aus Primärquellen, umsetzbar mit 60 s Kamera am Finger, keine Diagnose- oder Sicherheitsversprechen (FR-0118, FR-0149).

## Hintergrund
- **Konzept:** FR-0214 (`docs/specs/profile.md`, Ablauf mit Ruhephase 4 min, 60 s Messung, Algorithmus aus `../puls`), FR-0215 (`docs/specs/readiness.md`, Draft), OQ-0078 und DEC-0073 (Kamera statt nur Uhrdaten), OQ-0006 (Zahl nur mit aktueller HRV **und Schlaf** und 14 gültigen Messungen in 28 Tagen), OQ-0029 (Bänder).
- **Regeln:** `docs/phase-2-3-rules.md` Abschnitt 5, PAR-160 bis PAR-173. Sie sind für nächtliche HRV aus Health Connect geschrieben (PAR-160: Median in der Hauptschlafphase, ohne Schlafsitzung kein Wert). Eine morgendliche Kamera-Messung passt dort nicht hinein; die Regeln verlangen außerdem, nächtliche und morgendliche Werte nicht zu mischen (FR-0115, [N23]).
- **R8** (`docs/migration/research-reviews/values-applied.md`): Sensitivitätsrechnung zu `z` mit 7-Nächte-Mittel. Diese Analyse erweitert sie um fehlende Tage und Messfehler der Kamera.
- **Vorarbeit `../puls`:** `docs/METHODIK.md` und `docs/ALGORITHMUS.md` (Stand `algo-v0.4-frozen`). Dort sind die Quellen [6] bis [10] als „nicht im Volltext geprüft“ markiert; sie werden hier im Original geprüft. Die eigene Vergleichsmessung des Maintainers gegen Polar H9 wird nur qualitativ erwähnt (eine einzelne Messung), keine Zahlen (öffentliches Repo, SEC-0001 bis SEC-0010).

## Methode
Zwei Teile, wie mit dem Maintainer vereinbart („Literatur + kleine Rechnungen“).

1. **Literatur (Primärquellen, im Original geprüft; nur Abstract frei → so vermerkt):**
   1. Protokoll: Zeitpunkt, vor/nach Toilettengang, Haltung, Ruhephase, spontane vs. geführte Atmung, 60 s vs. 5 min, ln RMSSD.
   2. Ruhepuls: Definition, morgens vs. tagsüber, Haltung.
   3. Smartphone-Kamera-PPG vs. EKG in Ruhe, Grenzen „PRV ≠ HRV“.
   4. Auswertung täglicher Werte: 7-Tage-Mittel, Normalbereich, kleinste relevante Änderung (SWC), fehlende Tage, CV.
   5. Übertragung auf PAR-160 bis PAR-163, PAR-169 ff. und OQ-0006 als **Vorschlag einer neuen Regelversion** in `RESULTS.md` (das Regelwerk selbst wird nicht geändert).
   6. Validierungsplan gegen Polar H9 (Bland-Altman, Akzeptanzgrenzen, Fallzahl) für 2–4 Wochen täglich morgens, eine Person (n = 1).
2. **Kleine Rechnungen** (lokal, reproduzierbar, nur synthetische Daten, nur Python-Standardbibliothek, fester Seed):
   - **A – Fallzahl Bland-Altman:** Wie genau sind Bias und Übereinstimmungsgrenzen (LoA) nach 10–42 Tagen mit je einer gepaarten Messung? Wahrscheinlichkeit, dass das obere Konfidenzende der LoA innerhalb einer Akzeptanzgrenze liegt (Ansatz nach Lu et al. 2016), mit der Näherung `SE(LoA) ≈ √(3/n)·SD` (Bland und Altman 1999) als Gegenprobe. Zusätzlich: Was ändert eine Autokorrelation der Differenzen (z. B. Fingertemperatur über Tage)?
   - **B – 7-Tage-Mittel bei fehlenden Tagen und Kamera-Streuung (wie R8):** lnRMSSD und Ruhepuls als AR(1)-Reihe um einen persönlichen Mittelwert, dazu Messfehler der Kamera, fehlende Tage (zufällig, nur Werktage) und gelegentliche Fehlmessungen, die die Qualitätsprüfung passieren. `z` nach PAR-161/162 (Mittel aus `k` gültigen Werten der letzten 7 Tage, Referenz Median/MAD der 28 Tage davor, Nenner `/√k`). Gemessen: Anteil der Tage mit `z` (Verfügbarkeit), Breite von `z` ohne echte Änderung (Fehlalarme), Anteil erkannter echter Abfälle nach 1, 3, 5, 7 Tagen, Wirkung der Regel „MAD unter 1 bpm → kein `z`“ beim Ruhepuls.
   - **C – Streuung durch das kurze Fenster:** synthetische RR-Reihen (stationär, mit Atmungsschwankung) liefern die Streuung von ln RMSSD über 60 s gegenüber 300 s. Das ist eine Untergrenze für den Fehler eines 60-s-Werts, weil echte Reihen nicht stationär sind; es dient nur der Plausibilität gegenüber der Literatur.

**Warum aussagekräftig:** Das Protokoll und die Auswertungsregeln müssen sich auf Studien stützen, die genau diese Art Messung (kurz, morgens, Smartphone) gegen EKG bzw. gegen Trainingsfolgen geprüft haben. Die Rechnungen zeigen nur, wie empfindlich die vorgeschlagenen Regeln auf Messfehler und Lücken reagieren; sie sagen nichts darüber, wie groß Fehler und Lücken in Wirklichkeit sind. Das klärt erst die Validierung.

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| Synthetische Reihen und Ergebnisse | `research/data/work/R009/<lauf>/` | selbst erzeugt (Seed) | < 1 MB | ja, `./run.sh` |

Keine Sammlung aus `research/input/`, keine Downloads, keine Messwerte des Maintainers.

## Ausführung
Voraussetzungen: Python ≥ 3.10, nur Standardbibliothek. Laufzeit mit Standardwerten wenige Minuten auf einem Mac.

```bash
./init.sh            # legt research/data/work/R009/ an (keine Downloads)
./run.sh [Parameter] # führt A, B und C aus
```

| Parameter | Standard | Bedeutung |
| --- | --- | --- |
| `--seed N` | `1` | Zufallsstartwert (wie R8) |
| `--reps N` | `4000` | Wiederholungen je Fall in A und B |
| `--part A\|B\|C\|all` | `all` | nur einen Teil rechnen |

Beispiel: `./run.sh --seed 1 --reps 4000` (vollständig), kurze Probe: `./run.sh --reps 300 --part B`.

Ausgaben: `research/data/work/R009/<datum-zeit>/` (`run.info`, `A.txt`, `B.txt`, `C.txt`), wegwerfbar. Die Tabellen in `RESULTS.md` stammen aus dem dort genannten Lauf.
