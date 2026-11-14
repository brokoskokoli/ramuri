# R010 – Genauigkeit der Kamera-PPG verbessern (Messtechnik und Signalverarbeitung)

**Status:** läuft · **Auftraggeber:** Maintainer über den Project Supervisor · **Datum:** 2026-11-14

## Frage
Wie lässt sich die Genauigkeit der Kamera-Morgenmessung (Finger auf Kamera und Licht, 60 s) für Ruhepuls und vor allem RMSSD erhöhen, durch Messtechnik (Bildrate, Belichtung, Torch, Fingerdruck, Haltung, Bildausschnitt, Farbkanal, Zeitstempel) und durch Signalverarbeitung (Interpolation, Bezugspunkt, Filter, Ausreißer, Fensterwahl, Glättung, Rauschkorrektur)? Was ist belegt, was ist im Code schon umgesetzt, was fehlt, und was bringt es messbar? Daran hängt, was WP37 (wanderndes 60-s-Fenster, Rohsignal im Entwicklermodus) und spätere Pakete umsetzen und ob eine strengere Qualitätsgrenze (Zeitrauschen) begründbar ist.

## Hintergrund
- R009 (Vorarbeit, Literatur [B…]): Kamera-Ruhepuls belegt, RMSSD aus 60 s gemischt belegt; Zeitrauschen σ_t erhöht RMSSD² um etwa 6·σ_t²; die Grenze „Zeitrauschen > 25 ms → eingeschränkt“ ist für RMSSD zu lasch.
- Erste Feldmessungen 2026-11-14 mit Polar H9 parallel (nur Kennzahlen, ausgewertet vom Orchestrator): eine Messung nach unruhigem Anfang mit Schlagabständen im Median ~8 ms vom Gurt und fast gleicher RMSSD; eine als „gut“ bewertete Messung mit Zeitrauschen ~15 ms, Median-Abweichung je Schlag ~25 ms und Kamera-RMSSD rund 35 % über dem Gurt.
- App-Code: `app/packages/core/lib/src/ppg/` (Port von `PpgAnalyzer.kt`, Stand `algo-v0.4-frozen` des Vorgängerprojekts `puls`), Aufnahme `app/android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/PpgCamera*.kt`, `PpgFrameStats.kt`.
- Entscheidung K70 (Maintainer, 2026-11-14): `~/ai/puls` darf gelesen werden (nichts davon ins Repo); Sammlung `research/input/morgenmessungen-maintainer/` nur lokal, nur Dateinamen und Kennzahlen in Ergebnissen.

## Methode
1. **Bestand im Code** (lesen): Was davon ist schon umgesetzt (Zeitstempel, reale Bildrate, Interpolation, Bezugspunkt, Filter, Ausreißer, Qualitätsgrenzen)?
2. **Literatur** je Maßnahme: Quelle, Aufbau, Effektgröße, Gegenbelege (Volltext oder nur Abstract vermerkt).
3. **Synthetische Messung** (`run.sh --part synth`): Pulskurve mit bekannter Schlagfolge (RR mit Atemmodulation, realistische RMSSD 20–70 ms), Pulslaufzeit-Schwankung, Formänderung, Grundlinienwanderung, Bildrauschen in mehreren Stufen, Belichtung als Integrationsfenster, 30 und 60 Bilder/s, Zeitstempel mit Jitter und Bildverlusten. Ausgewertet wird **mit dem Dart-Code der App selbst** (Import der Dateien aus `app/packages/core/lib/src/ppg/`, unverändert) und mit Varianten (Bezugspunkt, Tiefpass, Raster, nominale Rate statt Zeitstempel, Nachbearbeitung der RR-Folge, Rauschkorrektur). Kennzahlen: Fehler je Schlagabstand gegen die wahre Folge (RMS), RMSSD-Abweichung (ln-Verhältnis), Zusammenhang „geschätztes Zeitrauschen ↔ RMSSD-Fehler“.
4. **Echte Messungen aus `~/ai/puls`** (`--part real`): 10 Aufnahmen vom 2026-11-09 (7 × 30 Bilder/s nur Rot/Grün, 3 × 60 Bilder/s, 2 davon mit Teilbereichen), eine davon mit gleichzeitigem Polar H9. An dieser: Abweichung Kamera gegen Gurt je Schlagabstand und RMSSD für App und Varianten, außerdem 60 → 30 Bilder/s ausgedünnt. An den übrigen ohne Referenz: Übereinstimmung zwischen unabhängigen Teilbereichsgruppen als Rauschmaß.
5. **Messpaare** (`--part pairs`): falls Exporte in der Sammlung liegen, Abweichung Kamera gegen Gurt je Schlagabstand und RMSSD, vorher/nachher für Maßnahmen, die nur die RR-Folge betreffen (das Rohsignal kommt erst mit WP37).
6. **Qualitätsgrenze:** aus 3–5 abgeleitet, welche Grenze für das Zeitrauschen welchen RMSSD-Fehler zulässt.

Warum aussagekräftig: Die Synthese kennt die Wahrheit und trennt Ursachen; die echte Gurtmessung prüft, ob das Ergebnis auch auf einem echten Signal trägt (n = 1, nur Hinweis). Eine Freigabe im Sinne der Validierung aus R009 ist das nicht.

**Achtung Validierung (R009, Abschnitt 6):** Messungen, an denen hier Verfahren verglichen oder Schwellen gewählt werden, gelten als Entwicklungsdaten und zählen nicht für die Validierung einer daraus abgeleiteten Verfahrensänderung.

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| Synthetische Aufnahmen | erzeugt im Lauf unter `research/data/work/R010/<lauf>/` | eigener Generator (`src/`), Seed | < 1 MB | ja, `./run.sh` |
| Kamera-Aufnahmen und Gurt-RR der Vorgänger-App | `~/ai/puls/messungen/files/` (außerhalb des Repos, nur lesen, K70) | Maintainer, privat | ~3 MB | **nein**, nur lesen |
| Messpaare | `research/input/morgenmessungen-maintainer/` (siehe deren README) | Maintainer, privat | anfangs leer | **nein**, nur lesen |

`init.sh` lädt nichts herunter; es prüft nur Dart und die Eingaben und meldet, was fehlt.

## Ausführung
Voraussetzungen: Dart SDK ≥ 3.13 (liegt mit Flutter vor), keine Pakete außer dem App-Code. Laufzeit siehe `RESULTS.md`.

```bash
./init.sh            # prüft Dart und Eingaben (idempotent, ändert nichts)
./run.sh [Parameter] # führt die Analyse aus
```

| Parameter | Standard | Bedeutung |
| --- | --- | --- |
| `--seed N` | `1` | Zufallsstartwert der Synthese |
| `--reps N` | `40` | synthetische Aufnahmen je Fall |
| `--part synth\|real\|pairs\|all` | `all` | nur einen Teil rechnen |
| `--puls DIR` | `~/ai/puls/messungen/files` | Ordner mit den Aufnahmen der Vorgänger-App |

Beispiel: `./run.sh --seed 1 --reps 40` (vollständig), kurze Probe: `./run.sh --reps 3 --part synth`.

Ausgaben: `research/data/work/R010/<datum-zeit>/` (`run.info`, je Teil eine `.txt`), wegwerfbar. Ausgaben zu echten Messungen enthalten nur Kennzahlen, keine Zeitreihen.
