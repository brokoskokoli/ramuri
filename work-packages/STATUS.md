# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, ADR-0002 bis ADR-0008 freigegeben, Plan für M1 liegt vor, WP01 und WP03 gemergt, WP01 bis WP07 und WP09, R005 und R007 abgeschlossen, WP10 läuft.

## Meilensteine

| Meilenstein | Inhalt | Status |
| --- | --- | --- |
| M0 ADRs | Architekturentscheidungen; ADR-0002 bis ADR-0008 freigegeben | erledigt |
| M1 Phase 1 | Laufaufzeichnung und grundlegende Fitnessanalyse | Plan: [M1-PLAN.md](M1-PLAN.md), WP01 bis WP12 geplant |
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
| WP10 | Zusammenfassung, Historie, Statistik und Transparenz | in Arbeit | L2, L4, L5 offen (Paket) |
| WP11, WP12 | siehe [M1-PLAN.md](M1-PLAN.md) | geplant | Annahmen aus den Vorpaketen in den Paketen vermerkt; `AppDependencies` ist noch leer |
| WP04 | Algorithmen-Rahmen, Herzfrequenzzonen und TRIMP | gemergt (9a3d5a1) | Nur synthetische Pulswerte; OQ-0070; Modellgüte ungeprüft (NFR-0004); Stufenvergabe bei WP09 |
| WP08 | Hintergrund und Wiederanlauf | geplant | R005 liegt vor; wartet auf WP06, WP07 |

## Offen außerhalb der Pakete

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005 Punkt 3, ADR-0003 (verschlüsseltes WAL), Lizenzbaum, WP08 | abgeschlossen (1aa053a) | Feldthemen: Hersteller-Energiesparen, Akku, Stromausfall, echtes Schlafverhalten, FR-0034, Schrittsensor |
| R007 | GPS-Rauschen im Stand (Literatur, `getSpeed`) | OQ-0068, FR-0029, FR-0052, vor WP06 | abgeschlossen (3e04586) | Feldtest mit protokollierten Stopps; OQ-0071 |
