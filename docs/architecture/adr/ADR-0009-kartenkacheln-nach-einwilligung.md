# ADR-0009 — Kartenkacheln aus dem Netz nach Einwilligung

- **Status:** Accepted (Maintainer, 2026-11-07 für die Punkte 1 bis 5; 2026-11-08 für Punkt 6 und die Nachträge aus R008, K34)
- **Datum:** 2026-11-07
- **Quellen:** SRC-003 (OQ-0074), R008 (`research/R008-kartenbibliothek/RESULTS.md`)
- **Betroffene Anforderungen:** FR-0204, FR-0027, FR-0037, FR-0040, FR-0041, SEC-0002, SEC-0007, SEC-0008, SEC-0009, ADR-0001, ADR-0003, ADR-0005

## Kontext
Bisher nutzt die App kein Netz. Das Release-APK fordert kein `INTERNET`, und das Gate prüft das. Damit galt SEC-0008 technisch: Ohne Netzrecht kann nichts das Gerät verlassen. Der Maintainer will die Route auf einer Karte sehen, während des Laufs, in Zusammenfassung und Detailansicht und als Miniatur in der Historie (OQ-0074). Kartenmaterial für beliebige Orte passt nicht in die App. Jede Kachelanfrage verrät dem Anbieter grob, wo der Nutzer läuft. SEC-0008 erlaubt das nur mit Einwilligung.

## Entscheidung
**1. Netz nur für Kartenkacheln, nur nach Einwilligung.** Das Release-APK fordert `INTERNET`. An die Stelle des fehlenden Netzrechts treten diese Sicherungen:
- Netzzugriff gibt es nur in einem Adapter für Kartenkacheln (`app/packages/adapters/lib/src/map/`). Das Gate prüft, dass kein anderer App-Code Netz-APIs nutzt.
- Die Kachelquelle entsteht nur bei erteilter Einwilligung, sonst schlägt jede Anfrage fehl (fail-closed, mit Mutationsbeleg).
- Nur HTTPS, Klartext-HTTP ist in der Netzwerk-Sicherheitskonfiguration verboten.
- Ein Netzwerkmitschnitt im Emulator zeigt ohne Einwilligung keinen Kartenhost und keinen Verkehr der App (Bytes je App-UID 0), sonst nur den bekannten Systemverkehr des Abbilds; mit Einwilligung nur den Kartenanbieter. Mitgeschnitten wird über Mobilfunk mit WLAN aus, mit Positivkontrolle vor und nach jeder Phase (R008: `-tcpdump` sieht das WLAN nicht). Er gehört zu jeder Meilenstein-Abschlussprüfung.

`ACCESS_BACKGROUND_LOCATION` und `RECEIVE_BOOT_COMPLETED` bleiben verboten.

**2. Anbieter:** Vorgesehen ist OpenFreeMap: Vektorkacheln aus OpenStreetMap-Daten (ODbL), ohne Schlüssel und ohne Konto. R008 prüft Nutzungsbedingungen, Eignung für Apps, Verfügbarkeit und Alternativen. Schlüssel kommen weder ins Repository noch in die App. Anfragen enthalten nur die Kachelkoordinaten, keine Kennung und keine Cookies. Der User-Agent nennt nur die App. Beim ersten Laden einer Karte fragt die App nur Kacheln im Ausschnitt der Route an; eine Live-Karte ohne Position fragt keine Kachel an (R008: sonst lädt die Bibliothek am Standardzentrum). Nachtrag R008: OpenFreeMap erlaubt verteilte Apps ausdrücklich, hat aber kein SLA (Einzelbetreiber, drei Störungen 2025/26); die App muss ohne Kacheln voll funktionieren. Langfristiger Ausweich sind selbst gehostete PMTiles, kurzfristiger Notbehelf VersaTiles (ungeprüft). Der Einwilligungstext nennt, dass Anbieter und Cloudflare IP-Adresse und geladene Kartenausschnitte sehen (Fehlerlogs mit URL bis 7 Tage).

**3. Einwilligung:** Der Kartenanbieter ist die erste echte Quelle im Freigabe-Rahmen aus WP05 (SEC-0002, SEC-0007). Er wird getrennt von anderen Quellen freigegeben und ist in den Einstellungen widerrufbar. Die Oberfläche dafür kommt mit WP13. Gefragt wird beim ersten Öffnen einer Karte, nicht beim Start der App. Einwilligungen gehören nicht ins Archiv (K30): Nach einem Reimport wird neu gefragt.

**4. Speicher:** Geladene Kacheln und Miniaturen zeigen, wo der Nutzer läuft. Sie werden deshalb wie die Datenbank nur verschlüsselt abgelegt (SEC-0009, ADR-0003): in einer eigenen `sqlite3mc`-Datei in `getNoBackupFilesDir()` mit dem Schlüssel aus ADR-0003, ohne WAL (`journal_mode = DELETE`, `secure_delete = ON`), mit je einer Größengrenze für Kacheln (50 MB) und Miniaturen (20 MB) und Verdrängung des am längsten ungenutzten Eintrags (R008). Namen und Einzelgrößen verraten keine Kachelkoordinaten. Der Plattencache der Bibliothek ist aus. Sie gehören nicht in Archiv und Dateiexport. „Alles löschen“ löscht sie, beim Widerruf fragt die App danach.

**5. Nur Oberfläche:** Die Karte lebt nur in der Oberfläche und nur im Vordergrund. Der Aufzeichnungsdienst (ADR-0005) kennt sie nicht und läuft unverändert, wenn die Karte nicht lädt.

**6. Bibliothek und Darstellung (nach R008):** `flutter_map` 8.3.2 mit `flutter_map_vector_tiles` 2.11.0, Vektorkacheln von OpenFreeMap im Stil „liberty“ ohne Rasterquellen. Nur diese Wahl erfüllt die Kriterien ohne nativen Code: Ein eigener `http.Client` ist das Tor für jede Anfrage (nur GET, nur HTTPS, nur freigegebene Hosts, keine Weiterleitungen, vor der Einwilligung keine Anfrage), `StyleReader` bekommt ihn samt `resolveProvider`. Lizenzen BSD/MIT/Apache-2.0, APK etwa +2,6 MB. `maplibre_gl` lädt nativ am Dart-Code vorbei (+13 MB), `vector_map_tiles` braucht einen Patch.
- Miniaturen: unsichtbare Karte, `RepaintBoundary.toImage` nach Ladeende, Bild im Kartenspeicher, nacheinander und höchstens 4 Anfragen parallel.
- Auflagen wegen der Reife (Paket drei Monate alt, eine Person): Version exakt pinnen, Update nur als eigener Schritt über die Gate-Tests (Tor zählt jede Ressourcenart, kein Klartext außerhalb des Speichers, Fremdkachel-Test). Rückfall 1: Fork der gepinnten Version. Rückfall 2: `maplibre_gl` mit eigener OkHttp-`Call.Factory`.
- Nachtrag WP13 (K37): Miniaturen 360 × 180; `last_used` ist ein Zugriffszähler; Vorschlagswerte ohne Messung: Rückfall auf die Linie nach 2 Kachelfehlern ohne Treffer, Stil und TileJSON höchstens 7 Tage alt, 20 s je Anfrage, 2 MiB je Antwort. Abhängigkeiten mit Netzzugriff stehen in `tool/net_allowed_packages.txt`; das Gate wird rot bei jedem neuen Paket bis zu seiner Prüfung und Eintragung. Am Emulator belegt: `journal_mode = DELETE`, kein Klartext (API 31 und 36), Mitschnitt ohne Einwilligung 0 Bytes für die App-UID.
- Nicht belegt: Flüssigkeit der Historie und Akku auf echten Geräten (Emulator mit Software-GL); der Speicher nur als Probe am Rechner, auf Android in WP13 zu belegen.

## Erwogene Alternativen
- **Route ohne Kartenmaterial (bisher, OQ-0065):** kein Netz, aber nicht der Wunsch des Maintainers. Bleibt als Rückfall ohne Einwilligung.
- **Nur selbst importierte Offline-Kartendatei:** kein Netzrecht, aber umständlich für den Nutzer. Ohne Datei gäbe es keine Karte. Vom Maintainer verworfen.
- **Kacheln von `tile.openstreetmap.org`:** Die Nutzungsregeln der OSMF schließen den Einsatz in verteilten Apps ohne Absprache aus.
- **Kommerzielle Anbieter mit Schlüssel:** Ein Schlüssel in der App ist auslesbar und bindet an ein Konto.

## Konsequenzen
- Die harte Garantie „kein Netzrecht“ entfällt. Mit `INTERNET` könnte auch eine Abhängigkeit senden. Neue Abhängigkeiten werden deshalb auf Netzzugriffe geprüft, und der Mitschnitt läuft in jeder Abschlussprüfung.
- Die Prüfung im Gate ändert sich von „kein `INTERNET`“ zu „Netz nur im Kartenadapter“. Beides gehört in denselben Commit wie das neue Recht.
- Mobile Daten werden nur mit Einwilligung genutzt. Eine Grenze für mobile Daten ist nicht vorgesehen.

## Offene Punkte

- Abhängigkeit des Builds vom Download von `libsqlite3mc` über GitHub-Releases (am 2026-11-08 HTTP 504, R008-Review); ein Build mit leerem Hook-Cache scheitert dann.
- Rechtliche Einordnung von Einwilligung und Namensnennung (OQ-0048).
