# Rnnn – <Titel>

**Status:** geplant · **Auftraggeber:** <Maintainer / Project Supervisor / WPnn> · **Datum:** <JJJJ-MM-TT>

## Frage
<Was soll geklärt werden, in 1–3 Sätzen. Welche Entscheidung hängt daran.>

## Hintergrund
<Bezug zum Konzept bzw. Arbeitspaket, frühere Analysen, Quellen der Vorrecherche.>

## Methode
<Vorgehen, Metriken, Vergleichsbasis, Kandidaten. Warum diese Methode für die Entscheidung aussagekräftig ist.>

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| <Modell X> | `research/data/models/<name>/` (Katalog: `research/DATA.md`) | <URL, Version> | <~GB> | ja, `./init.sh` |
| <eigene Aufnahmen> | `research/input/<sammlung>/` (siehe deren README) | Maintainer | <~MB> | **nein**, nur lesen |

## Ausführung
Voraussetzungen: <Software mit Versionen, Hardware, ungefähre Laufzeit>.

```bash
./init.sh            # stellt research/data/ für diese Analyse her (idempotent)
./run.sh [Parameter] # führt die Analyse aus
```

| Parameter | Standard | Bedeutung |
| --- | --- | --- |
| `--seed N` | `42` | Zufallsstartwert |
| <…> | <…> | <…> |

Beispiel: `./run.sh --seed 42 <…>`

Ausgaben: `research/data/work/Rnnn/<lauf-kennung>/` (wegwerfbar), Ergebnisgrafiken nach `figures/`.
