# ramuri: Screen-Design

Entwurf der App-Oberfläche: 11 Screens für ein Android-Handy (390 × 844 pt), in den Farben und der Schrift des Logos aus [`branding/`](../branding/README.md).

**Status:** Vorschlag. Das Design ist keine Anforderung. Maßgeblich bleiben die Specs in [`docs/specs/`](../docs/specs/). Wo das Design davon abweicht, steht es unten unter „Abweichungen“.

Alle Zahlen und Namen in den Screens sind erfundene Beispielwerte, keine echten Lauf- oder Gesundheitsdaten.

## Dateien

| Datei | Inhalt |
|---|---|
| `screens/canvas.json` | Anordnung der Screens auf dem Design-Canvas |
| `screens/*.dc.html` | je ein Screen als HTML mit Inline-Styles |

Die Dateien stammen aus einem Claude-Design-Canvas. Sie brauchen dessen Laufzeit (`support.js`), um als Prototyp zu laufen. Ohne sie bleiben Aufbau, Texte, Farben und Maße im Quelltext lesbar.

## Screens

| Datei | Screen | Bezug |
|---|---|---|
| `Splash.dc.html` | Startbildschirm mit Logo | – |
| `Main.dc.html` | Heute: Erholung, geplante Einheit, Woche, letzter Lauf | FR-0106, FR-0025 |
| `Start.dc.html` | Lauf vorbereiten: geplant oder frei, GPS, Pulssensor, Schrittfrequenz, Auto-Pause, Ansagen | FR-0025, FR-0029, FR-0031, FR-0035, FR-0195, FR-0202 |
| `Live.dc.html` | Live-Lauf mit Werten, Pause, Weiter, Beenden | FR-0026, FR-0028, FR-0030 |
| `LiveKarte.dc.html` | Live-Lauf mit Karte und aktueller Position | siehe Abweichungen |
| `Intervall.dc.html` | Intervalltraining: Restmeter, Soll/Ist-Pace, Pulswarnung, nächster Abschnitt | FR-0027, FR-0032, FR-0033 |
| `Summary.dc.html` | Nach dem Lauf: Kennzahlen, Zonen, Vergleich, Anstrengung, Befinden, Notiz | FR-0037, FR-0038 |
| `Verlauf.dc.html` | Verlauf mit Zeitraumfilter und Liste | FR-0040, FR-0044 |
| `Detail.dc.html` | Lauf-Detail: Route (Linie oder Karte), Pace und Puls mit GPS-Lücke, Höhe, Kilometer, Export | FR-0041, FR-0042, FR-0194 |
| `Fortschritt.dc.html` | Wochenkilometer, VO₂max-Schätzung, Prognose, Belastung | FR-0043, FR-0067 |
| `Plan.dc.html` | Ziel mit Phasen, angepasste Woche | FR-0141, CON-0006 |

## Gestaltung

- **Farben:** die Markenfarben aus `branding/README.md`. Minze `#7FD6C6` ist die Hauptfarbe für Buttons und die aktive Zone. Nacht `#0E1A1A` steht für Text und dunkle Flächen, Tiefgrün `#0F5E5A` für Links und Akzente auf hellem Grund, Papier `#F3F6F5` ist der Grund. Glut `#FF7A45`/`#E0561F` steht für Puls, Warnungen und den aktuellen Stand. Helle Zwischentöne sind daraus abgeleitet.
- **Glutpunkt:** Wie im Logo steht der Punkt für den aktuellen Stand. Er markiert die eigene Position auf der Karte und, vor dem Wort „geschätzt“, geschätzte Werte (CON-0009).
- **Schrift:** Sora für Überschriften und Zahlen (wie die Wortmarke), Manrope für Text.
- **Kontrast:** Textpaare mindestens 5,2 : 1, Bedienelemente mindestens 44 px. Glut ist nie Textfarbe auf hellem Grund.

## Abweichungen von der Spec

- **Karte:** `LiveKarte.dc.html` und die Ansicht „Karte“ in `Detail.dc.html` zeigen Kartenmaterial. Die Spec zeichnet die Route bisher ohne Karte (Festlegung OQ-0065 in FR-0037 und FR-0041). Die Karten-Ansichten gelten erst nach einer Entscheidung des Maintainers. Bis dahin ist nur die Linie ohne Karte umsetzbar.
