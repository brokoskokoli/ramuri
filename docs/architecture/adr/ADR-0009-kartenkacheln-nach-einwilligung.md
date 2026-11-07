# ADR-0009 — Kartenkacheln aus dem Netz nach Einwilligung

- **Status:** Accepted (Maintainer, 2026-11-07) für die Punkte 1 bis 5; Punkt 6 offen bis R008
- **Datum:** 2026-11-07
- **Quellen:** SRC-003 (OQ-0074)
- **Betroffene Anforderungen:** FR-0204, FR-0027, FR-0037, FR-0040, FR-0041, SEC-0002, SEC-0007, SEC-0008, SEC-0009, ADR-0001, ADR-0003, ADR-0005

## Kontext
Bisher nutzt die App kein Netz. Das Release-APK fordert kein `INTERNET`, und das Gate prüft das. Damit galt SEC-0008 technisch: Ohne Netzrecht kann nichts das Gerät verlassen. Der Maintainer will die Route auf einer Karte sehen, während des Laufs, in Zusammenfassung und Detailansicht und als Miniatur in der Historie (OQ-0074). Kartenmaterial für beliebige Orte passt nicht in die App. Jede Kachelanfrage verrät dem Anbieter grob, wo der Nutzer läuft. SEC-0008 erlaubt das nur mit Einwilligung.

## Entscheidung
**1. Netz nur für Kartenkacheln, nur nach Einwilligung.** Das Release-APK fordert `INTERNET`. An die Stelle des fehlenden Netzrechts treten diese Sicherungen:
- Netzzugriff gibt es nur in einem Adapter für Kartenkacheln (`app/packages/adapters/lib/src/map/`). Das Gate prüft, dass kein anderer App-Code Netz-APIs nutzt.
- Die Kachelquelle entsteht nur bei erteilter Einwilligung, sonst schlägt jede Anfrage fehl (fail-closed, mit Mutationsbeleg).
- Nur HTTPS, Klartext-HTTP ist in der Netzwerk-Sicherheitskonfiguration verboten.
- Ein Netzwerkmitschnitt im Emulator zeigt ohne Einwilligung keine Verbindung und mit Einwilligung nur den Kartenanbieter. Er gehört zu jeder Meilenstein-Abschlussprüfung.

`ACCESS_BACKGROUND_LOCATION` und `RECEIVE_BOOT_COMPLETED` bleiben verboten.

**2. Anbieter:** Vorgesehen ist OpenFreeMap: Vektorkacheln aus OpenStreetMap-Daten (ODbL), ohne Schlüssel und ohne Konto. R008 prüft Nutzungsbedingungen, Eignung für Apps, Verfügbarkeit und Alternativen. Schlüssel kommen weder ins Repository noch in die App. Anfragen enthalten nur die Kachelkoordinaten, keine Kennung und keine Cookies. Der User-Agent nennt nur die App.

**3. Einwilligung:** Der Kartenanbieter ist die erste echte Quelle im Freigabe-Rahmen aus WP05 (SEC-0002, SEC-0007). Er wird getrennt von anderen Quellen freigegeben und ist in den Einstellungen widerrufbar. Die Oberfläche dafür kommt mit WP13. Gefragt wird beim ersten Öffnen einer Karte, nicht beim Start der App. Einwilligungen gehören nicht ins Archiv (K30): Nach einem Reimport wird neu gefragt.

**4. Speicher:** Geladene Kacheln und Miniaturen zeigen, wo der Nutzer läuft. Sie werden deshalb wie die Datenbank nur verschlüsselt abgelegt (SEC-0009, ADR-0003), mit fester Größengrenze und Verdrängung der ältesten Einträge. Sie gehören nicht in Archiv und Dateiexport. „Alles löschen“ löscht sie, beim Widerruf fragt die App danach.

**5. Nur Oberfläche:** Die Karte lebt nur in der Oberfläche und nur im Vordergrund. Der Aufzeichnungsdienst (ADR-0005) kennt sie nicht und läuft unverändert, wenn die Karte nicht lädt.

**6. Bibliothek und Darstellung (offen bis R008):** Kandidaten sind `flutter_map` mit `vector_map_tiles` sowie `maplibre_gl`. Kriterien:
- Lizenz verträglich mit GPL-3.0
- keine Telemetrie und keine Verbindungen außer zum Kartenanbieter
- Vektorkacheln von OpenFreeMap
- verschlüsselter Kachelspeicher machbar
- Miniaturen in einer langen Liste flüssig
- Zuwachs der APK-Größe
- Akku während der Live-Seite

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
- Punkt 6 nach R008.
- Rechtliche Einordnung von Einwilligung und Namensnennung (OQ-0048).
