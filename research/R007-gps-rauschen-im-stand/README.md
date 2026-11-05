# R007 – GPS-Rauschen im Stand

**Status:** läuft · **Auftraggeber:** Project Supervisor (OQ-0068, vor WP06) · **Datum:** 2026-11-05

## Frage
Wie stark verfälscht GPS-Rauschen im Stand auf Android-Smartphones Strecke und Bewegungszeit, wenn die Geschwindigkeit aus Δs/Δt bei 1 Hz stammt, und welches Gegenmittel ist belegt: Mindestdistanz, Glättung oder `Location.getSpeed()`? Daran hängen OQ-0068 und die Frage, ob PAR-002 bis -004, -014, -015 vor WP06 eine neue Parameterversion brauchen.

**Entscheidungsregel (Setzung des Maintainers, keine Studienwerte):** Neue Version, wenn im Median mehr als 1 von 3 Stopps keine Pause auslöst oder die Scheinstrecke über 1 % der Laufstrecke liegt. Bezug: typischer Lauf von 30 min mit 3 Stopps à 60 s, simuliert durch den vorhandenen `RunPreprocessor`.

## Methode
Literatur zuerst, dann offene Stand-Rohdaten (Fix-Ebene, möglichst Android) per Dart-Harness durch den `RunPreprocessor`. Gegenmittel nur im Analysecode. Der ±3-m-Worst-Case läuft als Vergleich mit. Einzelheiten folgen beim Abschluss.
