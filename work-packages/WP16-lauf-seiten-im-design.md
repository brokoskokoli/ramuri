# WP16 – Lauf-Seiten im Design (`app/lib/features/run`, `summary`, `history`, `export`)

**Zuordnung:** M1, nachgereicht am 2026-11-08 (OQ-0075). Nach WP13 (gleiche Dateien).

Bezug: FR-0025, FR-0026, FR-0027, FR-0028, FR-0029, FR-0030, FR-0037, FR-0040, FR-0041, FR-0042, FR-0194, FR-0195, FR-0202, FR-0204, FR-0205, FR-0210, FR-0211, FR-0212; OQ-0037, OQ-0065, OQ-0075; K33. Vorlagen: `design/screens/Start.dc.html`, `Live.dc.html`, `Summary.dc.html`, `Verlauf.dc.html`, `Detail.dc.html`.

## Inhalt
1. **Lauf vorbereiten (Teil A, FR-0210):** Seite nach `Start.dc.html` in `run_flow_screen.dart`: GPS-Zustand, Pulssensor mit „Koppeln“ (zur Sensorsuche und zurück), Quelle der Schrittfrequenz, Autopause-Schalter (Vorgabe aus, zuletzt gewählt; aus `live_run_view.dart` hierher), „Los“. Sperrzustände nach FR-0195 bleiben.
2. **Lauf (Teil B):** Werte-Seite nach `Live.dc.html`, Pause-Zustand wie im Design; „Beenden“ nur pausiert, neben „Weiter“, mit Rückfrage (FR-0028). Bewegungszeit, Höhe, Schrittfrequenz, Runden, Sensorwechsel und alle Hinweise bleiben im Stil des Designs. Die Kartenseite aus WP13 bleibt die zweite Seite.
3. **Zusammenfassung (Teil C):** nach `Summary.dc.html` mit „Fertig“ und „Details“; Einordnung nach OQ-0037 (letzte 5 Läufe, Pace); Höhenprofil, Runden, Datenhinweise und Quellen der Messwerte bleiben. Keine subjektiven Angaben (Phase 2).
4. **Detailansicht (Teil C):** nach `Detail.dc.html`: Route mit Umschalter aus WP13, Kilometermarken, Pace und Puls mit GPS-Lücke, Höhenprofil mit Anstieg und Gefälle, Kilometertabelle (FR-0211), Export. Zonen, TRIMP, Runden und VO₂max des Laufs bleiben.
5. **Verlauf (Teil D):** nach `Verlauf.dc.html`: Zeitraum Woche/Monat/Jahr/Alle mit Summen, Gruppen nach Wochen (FR-0212), Zeile mit Miniatur aus WP13, Strecke, Dauer, Pace und Puls (FR-0040). Löschen bleibt erreichbar.

## Umsetzung
- Kilometerwerte (FR-0211) und Summen (FR-0212) als reine Berechnung in `app/packages/core` mit Tests, die Oberfläche nur anzeigend.
- Teil A, B, C, D je ein Coder-Auftrag ohne Übergabe. Mutationsbelege für Autopause-Vorgabe, Rückfrage beim Beenden und die Kilometertabelle.
- Laufnamen, „Aus dem Plan“, Ansagen, Belastungsbereich „im Ziel“ und Abschnittshinweise aus dem Design sind Phase 2 und kommen nicht.
- **Parallel:** läuft allein nach WP13. Berührt `live_run_view.dart`, `run_flow_screen.dart`, `run_summary_body.dart`, `run_charts.dart`, `run_detail_screen.dart`, `history_screen.dart`. Neue Texte mit Präfix `start`/`live`/`summary`/`detail`/`history`.

## Hinweise aus WP14
- Theme und Bausteine liegen in `app/lib/ui/`. Noch fehlende Tokens und Bausteine legt dieses Paket dort an, nicht in den Seiten: Töne `#E2EAE8`, `#D3EEE9`, `#3A4F4D`, `#FFE6DA`, `#8DBDB4`, Schriftgrößen 48/44/30, Umschalter in voller Breite, Live-Zonenanzeige, Wochenbalken (`../running-app-wt/handoff/hinweise/wp14/wp14-review-1.md`, Zusatzfrage 8; `wp14-a.md` dort für abgeleitete Töne).
- Verlauf und Fortschritt werden bei jedem Tab-Wechsel neu aufgebaut; Zeitraumwahl und Scrollposition gehen dabei verloren. Sie bleiben beim Tab-Wechsel erhalten (Abnahme), die Daten trotzdem frisch.
- Bildschirmfotos je API und Modus; Vorlagen in `../running-app-wt/handoff/e2e-vorlagen/wp14-e2e*`.

## Abnahmekriterien
- [ ] Jede der fünf Seiten wie ihr Screen, hell und dunkel; Abweichungen nach FR-0205 benannt.
- [ ] FR-0210: Autopause beim ersten Lauf aus, danach wie zuletzt gewählt; gilt für den gestarteten Lauf (Test mit Mutationsbeleg). Ohne Standortrecht kein Start.
- [ ] FR-0028: Beenden nur im pausierten Zustand und erst nach Bestätigung (Test mit Mutationsbeleg); Pausenzeit weiter nach FR-0052.
- [ ] FR-0026, FR-0027, FR-0202: alle Pflichtanzeigen im Lauf vorhanden (Test).
- [ ] FR-0037: alle Inhalte der Zusammenfassung vorhanden; „Fertig“ ändert keine Daten.
- [ ] FR-0211: Summe der Kilometerzeiten gleich Bewegungszeit, „–“ statt 0 ohne Puls, Lücken gekennzeichnet, Meilen (Tests in core).
- [ ] FR-0212: Summen gleich der Statistik für denselben Zeitraum (Test).
- [ ] Verlauf: Zeitraum und Scrollposition bleiben beim Tab-Wechsel erhalten, die Liste ist danach aktuell (Test).
- [ ] E2E (separater Agent), API 31 und 36, hell und dunkel: eingespeister Lauf mit Pause, GPS-Lücke und Sensorabbruch durch alle fünf Seiten, Bildschirmfotos neben dem Design; Aufzeichnung bei ausgeschaltetem Bildschirm unverändert. Gate grün.

## Ungeprüft
Bedienung mit Handschuhen und im Laufen auf echtem Gerät.
