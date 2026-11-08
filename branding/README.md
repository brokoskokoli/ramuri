# ramuri: Logo und Icon

Logo der App **ramuri** (Konzept „Puls“). Ein Pulsausschlag geht in eine steigende Formkurve über. Der abgesetzte Punkt ist der heutige Stand: eine Schätzung, kein Messwert, darum berührt er die Linie nicht.

Die Dateien sind noch nicht in die App eingebunden. Das geschieht über ein Arbeitspaket.

## Dateien

| Ordner | Inhalt |
|---|---|
| `svg/` | Icon (abgerundet und quadratisch), Zeichen, Wortmarke, Logo horizontal und gestapelt, je für hellen und dunklen Grund |
| `png/` | Icon 1024 und 192 px, Play-Store-Icon 512 px (quadratisch, die Maske setzt Google), Logo horizontal 1200 px breit |
| `android/res/` | Adaptive Icon (Vordergrund, Hintergrund, monochrome Ebene für Themed Icons) und Benachrichtigungssymbol `ic_stat_ramuri`, fertig zum Übernehmen nach `app/android/app/src/main/res/` |
| `build_brand.py` | erzeugt `svg/` und `android/` |

Der Schriftzug liegt als Pfad vor. Die Dateien brauchen also keine installierte Schrift.

## Zeichen

- Raster 100 × 100, optische Mitte bei (50 | 50)
- Linie: Strichstärke 8, runde Enden und Ecken
- Punkt: Durchmesser 13, Lücke zur Linie mindestens 4
- Im Icon auf 78 % verkleinert, im Adaptive Icon (108 dp) auf 66 %, damit es im Schutzkreis von 66 dp liegt

## Farben

| Name | Wert | Einsatz |
|---|---|---|
| Nacht | `#0E1A1A` | Icon-Grund, Text auf hellem Grund (16,3 : 1 auf Papier) |
| Tiefgrün | `#0F5E5A` | Linie auf hellem Grund, Primärfarbe (Weiß darauf 7,6 : 1) |
| Minze | `#7FD6C6` | Linie auf dunklem Grund (10,4 : 1 auf Nacht) |
| Glut | `#FF7A45` | Punkt auf dunklem Grund (6,9 : 1 auf Nacht) |
| Glut dunkel | `#E0561F` | Punkt auf hellem Grund (3,5 : 1 auf Papier) |
| Papier | `#F3F6F5` | heller Grund |

Glut ist nie Textfarbe auf hellem Grund.

## Schrift

Wortmarke: Sora SemiBold (600), Laufweite −3 %, immer kleingeschrieben. Sora steht unter der SIL Open Font License 1.1 (Copyright 2019 The Sora Project Authors). Hier liegen nur die in Pfade umgewandelten Buchstaben, nicht die Schrift selbst.

## Regeln

- Schutzraum rund um das Logo: zwei Punktdurchmesser
- Mindestgröße: Icon 16 px, Logo horizontal 80 px breit
- Zeichen nicht verzerren, drehen oder umfärben. Erlaubt sind nur die Farbpaare oben und die einfarbige Fassung.

## Neu erzeugen

Die SVG- und Android-Dateien werden aus `build_brand.py` erzeugt. Von Hand werden sie nicht geändert.

```sh
python3 -m venv /tmp/ramuri-brand && /tmp/ramuri-brand/bin/pip install fonttools
curl -L -o /tmp/Sora.ttf "https://github.com/google/fonts/raw/main/ofl/sora/Sora%5Bwght%5D.ttf"
/tmp/ramuri-brand/bin/python -I branding/build_brand.py /tmp/Sora.ttf branding
```

Die PNG-Dateien entstehen danach mit `rsvg-convert`, zum Beispiel:

```sh
rsvg-convert -w 512 branding/svg/ramuri-icon-square.svg -o branding/png/ramuri-icon-play-512.png
```
