# WP13 – Karte der Route (`app/packages/core/lib/src/map`, `app/packages/adapters/lib/src/map`, `app/lib/features/map`, `run`, `summary`, `history`, `settings`, `storage`, `tool/gate.sh`, Android-Manifest)

**Zuordnung:** M1, nachgereicht am 2026-11-07 (OQ-0074). R008 ist abgeschlossen (ADR-0009 Punkt 6; **Hinweise 1 bis 10 in `research/R008-kartenbibliothek/RESULTS.md` sind verbindlich**). **Wartet auf WP14** (Theme, Paket-ID, Manifest).

Bezug: FR-0204, FR-0205, FR-0027, FR-0037, FR-0040, FR-0041, FR-0056; SEC-0002, SEC-0004, SEC-0007, SEC-0008, SEC-0009, SEC-0010; ADR-0003, ADR-0005, ADR-0009; OQ-0074, OQ-0075, DEC-0069, DEC-0070; K31, K33. Vorlagen: `design/screens/LiveKarte.dc.html`, Route in `Detail.dc.html`, Miniatur in `Verlauf.dc.html`.

## Inhalt
1. **Netz und Gate (zuerst, in einem Commit):**
   - `INTERNET` im Manifest, Netzwerk-Sicherheitskonfiguration nur mit HTTPS.
   - Gate: `INTERNET` aus der Liste verbotener Rechte nehmen, `ACCESS_BACKGROUND_LOCATION` und `RECEIVE_BOOT_COMPLETED` bleiben verboten.
   - Neuer Gate-Schritt „Netz nur im Kartenadapter“: Netz-APIs (`dart:io` `HttpClient`/`Socket`/`WebSocket`, `package:http` u. ä., Kotlin `URL`/`HttpURLConnection`/`Socket`) nur unter `app/packages/adapters/lib/src/map/` bzw. in der von R008 gewählten Bibliothek. Fail-closed.
2. **Einwilligung:**
   - Kartenanbieter als erste echte Quelle im Freigabe-Rahmen (`core/lib/src/consent`).
   - Frage beim ersten Öffnen einer Karte, nicht beim Start. Erteilen und Widerrufen in den Einstellungen.
   - Nach dem Widerruf keine Anfrage mehr und die Frage, ob der Kartenspeicher gelöscht werden soll.
   - Die Kachelquelle entsteht nur bei erteilter Einwilligung (fail-closed).
3. **Kachelquelle und Speicher:**
   - Adapter für den Anbieter nach ADR-0009/R008: nur Kachelkoordinaten, keine Kennung, keine Cookies, neutraler User-Agent.
   - Verschlüsselter Speicher nach ADR-0009 Punkt 4: eigene `sqlite3mc`-Datei ohne WAL in `getNoBackupFilesDir()`, Grenzen 50 MB Kacheln und 20 MB Miniaturen, Verdrängung des am längsten ungenutzten Eintrags; Plattencache der Bibliothek aus.
   - Tor als eigener `http.Client` mit `resolveProvider`, ohne Weiterleitungen; Startkamera vor dem ersten Laden auf der Route, Live-Karte lädt erst mit Position.
   - Nicht in Archiv (WP12) und Dateiexport (WP11). „Alles löschen“ (SEC-0004) und der Neubeginn nach Schlüsselverlust löschen ihn mit.
4. **Gemeinsame Kartenansicht:**
   - Ein Widget für alle Ansichten. Route aus `RunDetail.route` (Teilstücke, Lücken und Pausen als Unterbrechung), Start und Ende markiert, Quellenangabe.
   - Ohne Einwilligung, ohne Netz oder bei Fehlern fällt sie auf die bestehende `RunRouteView` (ohne Karte) mit gleichem Ausschnitt zurück.
5. **Zusammenfassung und Detailansicht:** Die Karte ersetzt `RunRouteView` in `run_charts.dart`. Zoomen und Verschieben sind möglich. In der Detailansicht schaltet der Nutzer mit Einwilligung zwischen Karte und Linie um (FR-0204, OQ-0075).
6. **Lauf-Bildschirm:**
   - Zweite Seite zum Wischen in `live_run_view.dart`. Die Werte bleiben die erste Seite.
   - Die Karte folgt der Position und zeigt die bisherige Strecke aus den akzeptierten Positionen.
   - Gezeichnet wird nur, solange die Seite sichtbar und der Bildschirm an ist. Der Aufzeichnungsdienst bleibt unverändert (ADR-0005).
   - Nach `LiveKarte.dc.html`: Reiter Werte/Karte, Glutpunkt als Position, unten ein Blatt mit den wichtigsten Werten und Pause, Knopf zum Zentrieren nach Verschieben (bis dahin folgt die Karte nicht), Quellenangabe sichtbar.
7. **Historie:**
   - Miniatur je Lauf mit Positionen, nicht bedienbar, mit Kartenhintergrund bei Einwilligung, sonst nur die Linie.
   - Erzeugt bei Bedarf beim Scrollen, verschlüsselt zwischengespeichert, abgeleitet und jederzeit neu erzeugbar.
   - Läufe ohne Positionen (z. B. Laufband) ohne Miniatur.

## Umsetzung
- Alle Kartenansichten nutzen Theme und Bausteine aus WP14 und sehen aus wie die Vorlagen; die übrige Gestaltung von Lauf, Zusammenfassung, Detail und Verlauf macht WP16.
- Bibliothek, Kachelformat, Art des Speichers und Weg zu den Miniaturen kommen aus R008 und ADR-0009 Punkt 6. Weicht die Umsetzung davon ab, vorher melden.
- Lizenz der neuen Abhängigkeiten (vollständiger Baum) und Namensnennung des Kartenmaterials nennen. Neue Abhängigkeiten auf eigene Netzzugriffe und Telemetrie prüfen.
- Keine Koordinaten, Kachelkoordinaten oder URLs mit Kachelkoordinaten in Logs.
- **Teile für die Coder-Aufträge:**
  - Teil A: Punkte 1 bis 3
  - Teil B: Punkte 4 und 5
  - Teil C: Punkt 6
  - Teil D: Punkt 7

  Je ein Auftrag ohne Übergabe, in dieser Reihenfolge. Mutationstests sind Pflicht für Einwilligung, Gate-Schritt und Verschlüsselung des Speichers.
- Nicht dazu: Offline-Kartenpakete, Routenplanung, Karte in der Statistik, Höhenfärbung der Linie, Grenze für mobile Daten.
- Parallel: nach WP14; parallel zu WP15 möglich (keine gemeinsamen Dateien). Berührt `live_run_view.dart`, `run_charts.dart`, `history_screen.dart`, die Einstellungen, `tool/gate.sh` und das Manifest.

## Hinweise aus WP14
- Theme und Bausteine liegen in `app/lib/ui/`. Noch fehlende Tokens und Bausteine legt dieses Paket dort an, nicht in den Seiten: Töne `#E2EAE8`, `#D3EEE9`, `#3A4F4D`, `#FFE6DA`, `#8DBDB4`, Schriftgrößen 48/44/30, Umschalter in voller Breite, Live-Zonenanzeige, Wochenbalken (`../running-app-wt/handoff/hinweise/wp14/wp14-review-1.md`, Zusatzfrage 8; `wp14-a.md` dort für abgeleitete Töne).
- Verlauf und Fortschritt werden bei jedem Tab-Wechsel neu aufgebaut; Zeitraumwahl und Scrollposition gehen dabei verloren. Sie bleiben beim Tab-Wechsel erhalten (Abnahme), die Daten trotzdem frisch.
- Bildschirmfotos je API und Modus; Vorlagen in `../running-app-wt/handoff/e2e-vorlagen/wp14-e2e*`.

## Abnahmekriterien
- [ ] FR-0204, OQ-0075: Zentrieren-Knopf, Werte-Blatt und Umschalter Linie/Karte funktionieren; Kartenseiten wie die Vorlagen, hell und dunkel.
- [ ] FR-0204: Lauf-Bildschirm (zweite Seite), Zusammenfassung, Detailansicht und Historie zeigen die Route; mit Einwilligung auf Kartenmaterial, ohne Einwilligung als Linie; Quellenangabe sichtbar.
- [ ] FR-0056: Pausen und GPS-Lücken erscheinen auf Karte und Miniatur nicht als gerade Verbindung (Test mit Lauf mit Lücke und Pause).
- [ ] SEC-0008, SEC-0002: Ohne Einwilligung entsteht keine Kachelquelle und keine Verbindung (Unit-Test mit Mutationsbeleg); Gate-Schritt „Netz nur im Kartenadapter“ wird rot, wenn anderer Code Netz nutzt (Mutationsbeleg).
- [ ] SEC-0007: Nach dem Widerruf keine Anfrage mehr; Frage nach dem Löschen des Kartenspeichers; Löschen wirkt.
- [ ] ADR-0009 Punkt 2: Beim ersten Laden ohne Bedienung fragt das Tor nur Kacheln im Ausschnitt der Route an; eine Live-Karte ohne Position fragt keine an (Gate-Test mit Mutationsbeleg, Gegenprobe nur `initialCameraFit`).
- [ ] Gate-Tests aus R008 Hinweis 1, 2, 8, 10: Tor zählt jede Ressourcenart (tile > 0), keine Datei außerhalb des Speichers, Klartext-Scan mit Gegenprobe, kein `-wal`, Grenzen je Art; Versionen exakt gepinnt.
- [ ] SEC-0009: Kacheln und Miniaturen liegen nicht im Klartext auf dem Datenträger (Suche nach Kachel- und Bildsignaturen im App-Verzeichnis); Größengrenze greift.
- [ ] SEC-0004, SEC-0010, WP12: „Alles löschen“ löscht den Kartenspeicher; er ist von System-Backups ausgeschlossen; Archiv und Dateiexport enthalten nichts davon.
- [ ] ADR-0005: Aufzeichnung unverändert bei fehlendem Netz, Fehlern des Anbieters und Seitenwechsel; die Karte zeichnet bei ausgeschaltetem Bildschirm nicht.
- [ ] Release-APK: `INTERNET` vorhanden, `ACCESS_BACKGROUND_LOCATION` und `RECEIVE_BOOT_COMPLETED` fehlen, Test-Sensor fehlt.
- [ ] E2E (separater Agent), API 31 und 36:
  - Netzwerkmitschnitt über Mobilfunk mit WLAN aus und Positivkontrolle vor und nach jeder Phase (R008 Hinweis 9): ohne Einwilligung kein Kartenhost und 0 Bytes für die App-UID, sonst nur bekannter Systemverkehr; mit Einwilligung nur der Anbieter
  - Live-Seite während eines eingespeisten Laufs
  - Flugmodus: Rückfall auf Linie
  - Historie mit 50 Läufen flüssig scrollbar, grobe Bildrate berichtet
  - Widerruf und Löschen
  - Größe des Kartenspeichers nach 50 Miniaturen berichtet
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll durch den Orchestrator). Gate grün.

## Ungeprüft
Akku und Datenverbrauch auf echtem Gerät, Verhalten bei schwachem Mobilfunk, Verfügbarkeit des Anbieters über längere Zeit.
