# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, ADR-0002 bis ADR-0008 freigegeben, Plan für M1 liegt vor, WP01 startet, R005 wartet auf den Start seiner Sitzung.

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
| WP01 | Projektgerüst und Gate | in Arbeit | – |
| WP02 bis WP07, WP09 bis WP12 | siehe [M1-PLAN.md](M1-PLAN.md) | geplant | – |
| WP08 | Hintergrund und Wiederanlauf | wartet | R005 |

## Offen außerhalb der Pakete

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005 Punkt 3, ADR-0003 (verschlüsseltes WAL), Lizenzbaum, WP08 | wartet | Sitzung gestartet, wartet auf den Vertrauensdialog |
