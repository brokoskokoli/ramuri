# ramuri: Screen-Design

Entwurf der App-Oberfläche: 11 Screens für ein Android-Handy (390 × 844 pt), in den Farben und der Schrift des Logos aus [`branding/`](../branding/README.md).

**Status:** Verbindlich für Aussehen und Verhalten (Entscheidung des Maintainers vom 2026-11-08, OQ-0075, [FR-0205](../docs/specs/app-design.md)). Was eine Seite zeigt und berechnet, legen die Specs in [`docs/specs/`](../docs/specs/) fest. Wo das Design ihnen widerspricht, gilt die Spec in der Optik des Designs.

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

Entschieden in OQ-0075 (Einzelheiten in FR-0205 bis FR-0212):

- **Karte:** Die Karten-Ansichten gelten seit OQ-0074 (FR-0204, WP13). Die Live-Karte bekommt zusätzlich die Quellenangabe des Kartenmaterials.
- **Navigation:** In Phase 1 nur Heute, Verlauf und Fortschritt; Plan ab Phase 2. Einstellungen, Profil, Sensoren und Daten über das Profil-Symbol.
- **Heute:** In Phase 1 ohne Erholung, geplante Einheit und Wochenziel.
- **Start:** Autopause ist standardmäßig aus (OQ-0065).
- **Einheiten (OQ-0076):** Bei Pace, Puls und Punkten steht die Einheit in der Beschriftung statt an der Zahl.
- **Live:** Beenden nach Pause mit Rückfrage. Bewegungszeit, Höhe, Schrittfrequenz, Runden, Sensorwechsel und Hinweise bleiben, auch wenn das Design sie nicht zeigt.
- **Summary:** „Fertig“ statt „Speichern“ (der Lauf ist schon gespeichert); Einordnung gegen die letzten 5 Läufe nach Pace (OQ-0037); Höhenprofil und Runden bleiben. Subjektive Angaben erst in Phase 2.
- **Fortschritt:** VO₂max ohne „±3“, Datenqualität in den Stufen von FR-0053, Effizienz in % nach FR-0087; Zeitraumwahl und übrige Kennzahlen bleiben.
- **Splash:** Text ohne das Versprechen, dass alle Daten auf dem Handy bleiben (Kartenkacheln nach Einwilligung).
- **Intervall, Plan, Erholung (OQ-0077):** Es gilt die Spec in der Optik des Designs. Ziele als Zeit, Kilometer nur als „ca.“; Phasen Einstieg, Grundlage, Aufbau, Spezifisch, Reduktion, Ziel; RPE-Wörter nach PAR-105; Befinden in 5 Stufen; Pulshinweise nach PAR-107. Die Karte „Erholung“ zeigt ohne Gesundheitsdaten nur einen Texthinweis, keine Zahl und keinen Zustand.
- **Dunkelmodus:** kommt dazu, abgeleitet aus den Markenfarben.
