# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, Projektgerüst angelegt, ADRs in Arbeit.

## Meilensteine

| Meilenstein | Inhalt | Status |
| --- | --- | --- |
| M0 ADRs | Architekturentscheidungen aus `docs/architecture/overview.md` | in Arbeit |
| M1 Phase 1 | Laufaufzeichnung und grundlegende Fitnessanalyse | geplant, startet nach ADR-Freigabe |
| M2 Phase 2 | Adaptiver Trainingscoach | wartet auf Go des Maintainers |
| M3 Phase 3 | Erweiterte Gesundheits- und Erholungsanalyse | wartet auf Go des Maintainers |

## Offen außerhalb der Pakete

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
