# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, ADR-0002 bis ADR-0008 freigegeben, Plan für M1 liegt vor, WP01 und WP03 gemergt, WP01 bis WP12, R005 und R007 abgeschlossen; Abschlussprüfung M1 am 2026-11-08 bestanden (ohne Feldkriterien); Karte (OQ-0074) nachgereicht: R008 abgeschlossen, dann WP13; Screen-Design und Marke (OQ-0075) nachgereicht: WP14, dann WP15 und WP16.

## Meilensteine

| Meilenstein | Inhalt | Status |
| --- | --- | --- |
| M0 ADRs | Architekturentscheidungen; ADR-0002 bis ADR-0008 freigegeben | erledigt |
| M1 Phase 1 | Laufaufzeichnung und grundlegende Fitnessanalyse | Plan: [M1-PLAN.md](M1-PLAN.md), WP01 bis WP12 gemergt, Abschlussprüfung bestanden (2026-11-08); WP13 (Karte) und WP14 bis WP17 (Screen-Design) gemergt, Abschlussprüfung für Netz und Oberfläche wiederholt (2026-11-09) |
| M2 Phase 2 | Adaptiver Trainingscoach | Go am 2026-11-09, in Arbeit; Plan: [M2-PLAN.md](M2-PLAN.md) |
| M3 Phase 3 | Erweiterte Gesundheits- und Erholungsanalyse | wird nach M2 geplant; Grundlage R009/K-1 (DEC-0074, K46), Morgenmessung per Handykamera als Datenquelle (OQ-0078); RMSSD bis zur Validierung gegen H9 gesperrt. Health Connect und Pulsgurt bleiben Ergänzungen; DFA α1 später als eigener Research-Auftrag |

## M2 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP18 | Subjektive Angaben und Nachtragen | gemergt (755b39d) | Python-Testvektor für Archivformat 2 fehlt; Reimport nimmt nachgetragene Trainings mit Datum in der Zukunft an (Grenze mit WP19); Speicherfehler beim Schließen der Zusammenfassung verliert die Notiz still; sRPE kann nach fehlgeschlagener Neuberechnung veraltet bleiben; Warnsignal-Antwort ohne Wirkung bis WP23; Bestpace-Ersatztext bei Faktor 1,3 noch 3 Zeilen; Hinweise in `handoff/hinweise/wp18/` | |
| WP19 | Belastungsverlauf und Belastungsprofil | in Arbeit | Zusätzlich: Datum in der Zukunft beim Reimport nachgetragener Trainings abweisen wie bei der Eingabe (aus WP18) |
| WP20 | Leistungsprognose | in Arbeit | |
| WP21 | Planmodell und Planerzeugung | geplant | |
| WP22 | Plan-Seite, Ziele und Kalender | geplant | |
| WP23 | Plananpassung, Warnsignal, Erklärungen, Basis-Erholung | geplant | |
| WP24 | Geführte Einheit und Ansagen | geplant | |
| WP25 | Laufband und Zusatzmetriken | geplant | |
| WP26 | RR-Intervalle speichern | geplant | Start nach WP20 |
| WP27 | Ruhepuls mit der Handykamera | geplant | Erst Screens (Claude Design), dann Umsetzung; Messprotokoll aus R009 in FR-0214 übernommen |

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
| WP13 | Karte der Route | gemergt (60c3249) | Ungeprüft: Pinch-Zoom, schwaches Netz und Fehlalarm des Rückfalls (N=2), Lese- und Schreibzeiten des Kartenspeichers am Gerät, Akku, Datenverbrauch, Bildrate auf echtem Gerät, Verfügbarkeit des Anbieters; Ursache flacher Miniaturen im E2E nicht belegt (Absicherung eingebaut); Kartenspeicher-Größe in den Einstellungen nur beim Öffnen gelesen; API 31 Flugmodus nur per UID-Zähler; Lizenzen und Namensnennung in `handoff/hinweise/wp13/wp13-lizenzen.md` (OQ-0048); E2E- und Mitschnitt-Vorlagen `handoff/e2e-vorlagen/wp13-e2e-*` |
| WP14 | Erscheinungsbild, Marke und Navigation | gemergt (163d92c) | Hintergrund, Akku, Pulsgurt nur im Feld; Logcat API 36 unvollständig (FATAL EXCEPTION aus Wallpaper-Intent-Test nicht zugeordnet); Wochenstreifen nur API 36; Test für vergangene Tage im Wochenstreifen fehlt (Mutation überlebt); Willkommen-Logo einen Frame nach dem Text (Precache); Themed Icons bei Herstellerlaunchern und extreme Displaygrößen ungeprüft; Build hängt am Download von libsqlite3mc (504 am 2026-11-08); E2E-Vorlagen in `handoff/e2e-vorlagen/wp14-e2e*` |
| WP15 | Fortschritt im Design | gemergt (60f379e) | E2E nur synthetische Daten, keine Pixelvergleiche; ungeprüft am Gerät: Zonen mit echten Werten, Stufe „nicht bestimmbar“, TalkBack, Englisch/Meilen auf API 31; Umbruch der Einheit bei Schriftfaktor 1,3 auf schmalem Display, „Trainingsbelastung“ ab Faktor ~1,86 zu breit; Bestand: „Bestpace (schnellster Kilometer)“ auch bei Meilen, Zeitraumzeilen ohne Jahr; Datenzeitraum des Langzeitwerts gegen FR-0053 prüfen (WP09); geprüft (2026-11-08): Die Neuberechnung von Läufen ohne Laufwert nach einem Import ist vorgesehen (nachgeholte erste Berechnung; Vorverarbeitung ist abgeleitet nach ADR-0004); der Sprung der Strecke kam aus widersprüchlichen synthetischen Daten des E2E-Generators; E2E-Vorlagen `handoff/e2e-vorlagen/wp15-e2e*` |
| WP16 | Lauf-Seiten im Design | gemergt (e0cca13) | Nachschliff in WP17; ungeprüft: TalkBack, Handschuhe und Bedienung im Laufen, Hintergrund und Akku am echten Gerät, Pinch-Zoom nur im Widget-Test; Bilder hell/dunkel nicht vom letzten Stand; GPS-Lücke im E2E nur über Standort aus; bei Sensorabbruch erste Ansicht nur Chip „Puls verbindet neu“, „Puls getrennt“ nicht erzeugt; Kilometertabelle bei Schriftfaktor 2,0 auf 0,61 verkleinert; Reviews und E2E in `handoff/hinweise/wp16/`, Vorlagen `handoff/e2e-vorlagen/wp16-e2e-*` |
| WP17 | Nachschliff Lauf-Seiten | gemergt (cc601aa) | Ursache 18:52/18:50 aus dem Code hergeleitet, Bruchteile nicht gemessen; reale GPS-Lücke auf dem Emulator nicht erzeugbar; Puls und Punkte mit Wert nur im Widget-Test; API 31 S3 teilweise; Statistik nennt ohne Puls und Profil weiter den Profilgrund; Kartenblatt springt 13 dp bei „noch keine Daten“; Überlauf 20 dp im Kartenblatt bei 360×480, Faktor 2,0; TalkBack ungeprüft; Reviews in `handoff/hinweise/wp17/`, Vorlagen `handoff/e2e-vorlagen/wp17-e2e-*` |
| WP04 | Algorithmen-Rahmen, Herzfrequenzzonen und TRIMP | gemergt (9a3d5a1) | Nur synthetische Pulswerte; OQ-0070; Modellgüte ungeprüft (NFR-0004); Stufenvergabe bei WP09 |
| WP08 | Hintergrund und Wiederanlauf | gemergt (41aebc9) | Feldtest: FR-0034 (echter Suspend, Doze, Akku, Hersteller-Kill), Schrittsensor unter Typ `location`, Pulsgurt im Hintergrund; Aufzeichnung nutzt `Clock.monotonic()` noch nicht (Uhrsprünge); Diagramme der Zusammenfassung zeichnen `interruption` nicht als Lücke (Spec regelt es nicht); Semantik von `raw_steps` offen; Soll-Tests: Pulsquelle nach Fortsetzen, Zeitquelle des Schrittsensors, Produktionsverdrahtung `app_dependencies.dart:90`; E2E-Vorlagen in `handoff/e2e-vorlagen/` |

## Offen außerhalb der Pakete

- Abschlussprüfung M1, Wiederholung für Netz und Oberfläche (2026-11-09, main e5d2b16, Bericht nur lokal in `handoff/m1-abschluss-2/`): Ohne Einwilligung auf API 31 und 36 kein Kartenhost, keine Schriftanfrage, 0 Bytes für die App-UID. Mit Einwilligung auf API 36 nur `tiles.openfreemap.org`; auf API 31 teilweise, Google-Systemhosts im selben Mitschnitt, nicht je UID trennbar. Widerruf mit Löschfrage und 0 B auf beiden; Flugmodus auf API 36 erfüllt, auf API 31 teilweise (Einwilligungsstand nicht belegt). Release-Prüfung per aapt erfüllt. Alle Seiten hell und dunkel per Bild; Abgleich mit `design/screens` nur Stichprobe. Export und Archiv/Reimport als Kurzprobe erfüllt. Nicht geprüft: Kennung in den Anfragen (TLS), Pulsszenarien und ACC-03 in dieser Runde, Löschen des Kartenspeichers auf Dateiebene. Kosmetisch offen: Ersatztext bei Bestpace bricht in 7 Zeilen, flacher Lauf zeigt „0 m 0 m“. Vorlagen `handoff/e2e-vorlagen/m1-abschluss-2/`.
- Abschlussprüfung M1 (2026-11-08, Bericht nur lokal in `handoff/m1-abschluss/`): ACC-01, 03, 04, 05, 06, 13, 15 und der Rundgang mit Reimport auf API 31 erfüllt; ACC-14 ohne Flugmodus geprüft; Release-APK ohne `INTERNET`, Hintergrundstandort, Boot-Start und Test-Sensor. Zwei Funde behoben (8d61242 doppelter Punkt, 7db2340 Abbruch-Hinweis, K32). Lizenzen: alle Dart-Pakete BSD/MIT/Apache-2.0 (`bluez`, `dbus` MPL-2.0 nur Linux); bei Gradle nur 26 von 53 Lizenzen belegt (androidx, jsr305, Flutter-Engine offen), Lizenztext von sqlite3mc liegt nicht bei; Drittlizenz-Hinweise in der App ungeregelt (OQ-0048). Nach WP13 netzbezogenen Teil wiederholen (Mitschnitt).

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005 Punkt 3, ADR-0003 (verschlüsseltes WAL), Lizenzbaum, WP08 | abgeschlossen (1aa053a) | Feldthemen: Hersteller-Energiesparen, Akku, Stromausfall, echtes Schlafverhalten, FR-0034, Schrittsensor |
| R007 | GPS-Rauschen im Stand (Literatur, `getSpeed`) | OQ-0068, FR-0029, FR-0052, vor WP06 | abgeschlossen (3e04586) | Feldtest mit protokollierten Stopps; OQ-0071 |
| R008 | Kartenbibliothek und Kachelanbieter | ADR-0009 Punkt 6, WP13 | abgeschlossen (e5c00fa) | flutter_map + flutter_map_vector_tiles, OpenFreeMap, eigene sqlite3mc-Datei; offen: echtes Gerät (Bildrate, Akku), VersaTiles mit Tor, Speicher auf Android; Daten ~4,8 GB in research/data |
| R009 | Ruhepuls und HRV-Morgenmessung mit der Handykamera | FR-0214 (WP27), FR-0215, Plan für M3, OQ-0006 | gemergt (a204ad2) | Kamera-Ruhepuls in Ruhe belegt, RMSSD aus 60 s Kamera gemischt belegt und bis zur Validierung gegen Polar H9 gesperrt; ins Konzept übernommen (DEC-0074, K-1, K46). Offen: Validierung gegen H9 (Folgeanalyse), RMSSD-Qualitätsgrenze, Validierung im Sitzen, MAD-Grenze 0,5 prüfen, Zahlenwerte K47 |
