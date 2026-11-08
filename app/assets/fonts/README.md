# Schriften

Sora (Überschriften, Zahlen) und Manrope (Text) für FR-0205. Beide stehen unter der SIL Open Font License 1.1 (`OFL-Sora.txt`, `OFL-Manrope.txt`), die App zeigt sie in den Lizenzangaben (`lib/ui/font_licenses.dart`). Die Schriften werden nie zur Laufzeit geladen.

## Herkunft

Variable Fonts aus <https://github.com/google/fonts>, Commit `86aced91de05cd4f96a06838124cca45be337b2b`:

- `ofl/sora/Sora[wght].ttf`, `ofl/sora/OFL.txt` (Copyright 2019 The Sora Project Authors)
- `ofl/manrope/Manrope[wght].ttf`, `ofl/manrope/OFL.txt` (Copyright 2019 The Manrope Project Authors laut Font-Datei, 2018 laut OFL.txt)

Beide Dateien nennen keinen Reserved Font Name (weder in der Copyright-Zeile der OFL.txt noch im Namenseintrag der Font-Datei).

## Statische Schnitte

Grund: `fontWeight` wirkt bei Variable Fonts in Flutter nicht zuverlässig. Je Gewicht eine Datei, in `pubspec.yaml` mit `weight`.

- Sora 500, 600, 700
- Manrope 400, 500, 600, 700, 800

Erzeugt mit fonttools 4.68.0 (`varLib.instancer`), Namenseinträge (ID 1, 2, 4, 6) und `usWeightClass` angepasst:

```sh
python3 -m venv venv && venv/bin/pip install fonttools==4.68.0
mkdir vf   # dort "Sora[wght].ttf" und "Manrope[wght].ttf" ablegen
venv/bin/python -I app/assets/fonts/instance_fonts.py vf app/assets/fonts
```

Die statischen Schnitte sind Ableitungen der Originale. Ohne Reserved Font Name steht der Name frei zur Verfügung, die Lizenz bleibt OFL 1.1 mit den Copyright-Zeilen der Originale.
