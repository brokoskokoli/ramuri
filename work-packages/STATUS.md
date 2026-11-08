# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, ADR-0002 bis ADR-0008 freigegeben, Plan für M1 liegt vor, WP01 und WP03 gemergt, WP01 bis WP12, R005 und R007 abgeschlossen; Abschlussprüfung M1 am 2026-11-08 bestanden (ohne Feldkriterien); Karte (OQ-0074) nachgereicht: R008 abgeschlossen, dann WP13; Screen-Design und Marke (OQ-0075) nachgereicht: WP14, dann WP15 und WP16.

## Meilensteine

| Meilenstein | Inhalt | Status |
| --- | --- | --- |
| M0 ADRs | Architekturentscheidungen; ADR-0002 bis ADR-0008 freigegeben | erledigt |
| M1 Phase 1 | Laufaufzeichnung und grundlegende Fitnessanalyse | Plan: [M1-PLAN.md](M1-PLAN.md), WP01 bis WP12 gemergt, Abschlussprüfung bestanden (2026-11-08); offen: WP13 (Karte) und WP14 bis WP16 (Screen-Design) nachgereicht |
| M2 Phase 2 | Adaptiver Trainingscoach | wartet auf Go des Maintainers |
| M3 Phase 3 | Erweiterte Gesundheits- und Erholungsanalyse | wartet auf Go des Maintainers |

## M1 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP01 | Projektgerüst und Gate | gemergt (be066c1) | Gate nur auf macOS gelaufen, Linux-CI ungeprüft; Rückfallsprache Englisch kommt mit WP05 |
| WP02 | Verschlüsselte Speicherung und Löschen | gemergt (fa0aaf9) | Nur Emulator (OQ-0072); Reste nach Neubeginn aus Stufe „teilweise“; Schema-Prüfung im Gate fehlt (kommt mit WP05) |
| WP05 | Profil, Einstellungen und Freigaben | gemergt (05db595) | Berechtigungsentzug und Meilen mit echter Strecke erst mit WP06/WP07; Drift-Gate prüft nicht `drift_schemas/*.json`; Einwilligung rechtlich ungeprüft (OQ-0048) |
| WP06 | Lauf aufzeichnen im Vordergrund | gemergt (7fce783) | E2E nur API 36, API 31 offen; Feldtest GPS-Rauschen, Alter der Fixes, fehlende Speed-Werte (K12), Display aus; Sprung in die Standort-Einstellungen bei ausgeschaltetem GPS fehlt; `endedUtcOffset` aus WP09 in `run_recorder.dart:150` nachziehen |
| WP09 | VO₂max, aerobe Effizienz und Neuberechnung | gemergt (5ee87cf) | Modellwerte nur synthetisch (NFR-0004, OQ-0020); E2E nur API 31 und Englisch; Test für `utcOffsetAt` greift nur in Zeitzonen mit Sommerzeit (Gate setzt kein TZ); Dauer von Neuberechnung und Nachholen auf schwachen Geräten ungemessen (ADR-0004); dauerhaft scheiternder Lauf wird bei jedem Start ohne Anzeige erneut versucht; OQ-0073 |
| WP03 | Vorverarbeitung und Bewegungswerte | gemergt (b29c386) | Nur synthetische Läufe, Gate nur auf macOS; OQ-0068, OQ-0069 offen |
| WP07 | Pulssensoren | gemergt (0a90750) | Echter BLE-Weg ungeprüft (ohne R006): Funkabbrüche, Timeouts, Scan bei Bluetooth aus, Adressen in Plugin-Logs, langsamer Gurt; ACC-02, Gerätekategorien FR-0007, wechselnde Adressen; bewusst getrennte Geräte verbinden beim nächsten Öffnen des Lauf-Bildschirms wieder (kein „Gerät vergessen“); nach Abbruch bis rund 10 s letzter Puls sichtbar (PAR-010) |
| WP10 | Zusammenfassung, Historie, Statistik und Transparenz | gemergt (30cf5b1) | Laufzeiten nur auf VM und Emulator (4-h-Lauf etwa 1 s), Gerät ungemessen; Meilen nur synthetisch; Deutsch und Diagrammlücken nur per Widget-Test; Screenreader liest den Glättungshinweis im Pulsdiagramm doppelt, Pace-Reihe ohne Hinweis (Soll); `PaceProcessor` kopiert Segmente je Snapshot; `RunPorts.heartRate` entfernen (aus WP07); E2E-Vorlagen in `handoff/e2e-vorlagen/` |
| WP11 | Dateiexport und Teilen | gemergt (1d358ec) | Kadenz wird nicht gespeichert, daher nicht exportiert (FR-0183, Folge aus WP06); E2E-Wiedergabe verlor rund 8 % der eingespeisten GPS-Fixes schon bei der Aufzeichnung (Emulator-Takt oder Abtastung, nicht untersucht); „übergeben“ meldet nur die Zielwahl; Strava-Import und Verhalten anderer Plattformen bei getrennten TCX-Punkten ungeprüft; Rechtsfrage FIT-Protokoll (OQ-0048); E2E nur API 36; E2E- und Prüfvorlagen (XSD, FIT-Decoder) in `handoff/e2e-vorlagen/` |
| WP12 | Archiv und Reimport | gemergt (06ff78b) | E2E nur Debug-Build und Läufe ohne Puls; Archiv über 64 KiB nur in Host-Tests; Dauer von Argon2 auf schwachen Geräten, echter Gerätewechsel und große Archive ungeprüft; Kill während des Tauschs nur per Fehlerinjektion; Fremddatei wird erst nach der Passworteingabe erkannt (Kopf vorher prüfen); Drittlizenz-Hinweise in der App nicht geregelt (OQ-0048); Ladeanzeige hinter dem Fehlerdialog (kosmetisch); E2E-Vorlagen in `handoff/e2e-vorlagen/` |
| WP13 | Karte der Route | in Arbeit | danach netzbezogene Abschlussprüfung wiederholen |
| WP14 | Erscheinungsbild, Marke und Navigation | gemergt (163d92c) | Hintergrund, Akku, Pulsgurt nur im Feld; Logcat API 36 unvollständig (FATAL EXCEPTION aus Wallpaper-Intent-Test nicht zugeordnet); Wochenstreifen nur API 36; Test für vergangene Tage im Wochenstreifen fehlt (Mutation überlebt); Willkommen-Logo einen Frame nach dem Text (Precache); Themed Icons bei Herstellerlaunchern und extreme Displaygrößen ungeprüft; Build hängt am Download von libsqlite3mc (504 am 2026-11-08); E2E-Vorlagen in `handoff/e2e-vorlagen/wp14-e2e*` |
| WP15 | Fortschritt im Design | gemergt (60f379e) | E2E nur synthetische Daten, keine Pixelvergleiche; ungeprüft am Gerät: Zonen mit echten Werten, Stufe „nicht bestimmbar“, TalkBack, Englisch/Meilen auf API 31; Umbruch der Einheit bei Schriftfaktor 1,3 auf schmalem Display, „Trainingsbelastung“ ab Faktor ~1,86 zu breit; Bestand: „Bestpace (schnellster Kilometer)“ auch bei Meilen, Zeitraumzeilen ohne Jahr; Datenzeitraum des Langzeitwerts gegen FR-0053 prüfen (WP09); **zu prüfen:** Läufe aus einem Archiv ohne gespeicherten Laufwert werden beim Start neu gerechnet und die archivierte Strecke überschrieben (FR-0198, OQ-0031); E2E-Vorlagen `handoff/e2e-vorlagen/wp15-e2e*` |
| WP16 | Lauf-Seiten im Design | wartet | auf WP13; danach Abschlussprüfung für Netz und Oberfläche wiederholen |
| WP04 | Algorithmen-Rahmen, Herzfrequenzzonen und TRIMP | gemergt (9a3d5a1) | Nur synthetische Pulswerte; OQ-0070; Modellgüte ungeprüft (NFR-0004); Stufenvergabe bei WP09 |
| WP08 | Hintergrund und Wiederanlauf | gemergt (41aebc9) | Feldtest: FR-0034 (echter Suspend, Doze, Akku, Hersteller-Kill), Schrittsensor unter Typ `location`, Pulsgurt im Hintergrund; Aufzeichnung nutzt `Clock.monotonic()` noch nicht (Uhrsprünge); Diagramme der Zusammenfassung zeichnen `interruption` nicht als Lücke (Spec regelt es nicht); Semantik von `raw_steps` offen; Soll-Tests: Pulsquelle nach Fortsetzen, Zeitquelle des Schrittsensors, Produktionsverdrahtung `app_dependencies.dart:90`; E2E-Vorlagen in `handoff/e2e-vorlagen/` |

## Offen außerhalb der Pakete

- Abschlussprüfung M1 (2026-11-08, Bericht nur lokal in `handoff/m1-abschluss/`): ACC-01, 03, 04, 05, 06, 13, 15 und der Rundgang mit Reimport auf API 31 erfüllt; ACC-14 ohne Flugmodus geprüft; Release-APK ohne `INTERNET`, Hintergrundstandort, Boot-Start und Test-Sensor. Zwei Funde behoben (8d61242 doppelter Punkt, 7db2340 Abbruch-Hinweis, K32). Lizenzen: alle Dart-Pakete BSD/MIT/Apache-2.0 (`bluez`, `dbus` MPL-2.0 nur Linux); bei Gradle nur 26 von 53 Lizenzen belegt (androidx, jsr305, Flutter-Engine offen), Lizenztext von sqlite3mc liegt nicht bei; Drittlizenz-Hinweise in der App ungeregelt (OQ-0048). Nach WP13 netzbezogenen Teil wiederholen (Mitschnitt).

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005 Punkt 3, ADR-0003 (verschlüsseltes WAL), Lizenzbaum, WP08 | abgeschlossen (1aa053a) | Feldthemen: Hersteller-Energiesparen, Akku, Stromausfall, echtes Schlafverhalten, FR-0034, Schrittsensor |
| R007 | GPS-Rauschen im Stand (Literatur, `getSpeed`) | OQ-0068, FR-0029, FR-0052, vor WP06 | abgeschlossen (3e04586) | Feldtest mit protokollierten Stopps; OQ-0071 |
| R008 | Kartenbibliothek und Kachelanbieter | ADR-0009 Punkt 6, WP13 | abgeschlossen (e5c00fa) | flutter_map + flutter_map_vector_tiles, OpenFreeMap, eigene sqlite3mc-Datei; offen: echtes Gerät (Bildrate, Akku), VersaTiles mit Tor, Speicher auf Android; Daten ~4,8 GB in research/data |
