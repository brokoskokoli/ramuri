# Umsetzungsstand

Einzige Stelle für den Stand der Meilensteine und Arbeitspakete. Gepflegt vom Orchestrator auf `main`. Paket-Branches ändern diese Datei nicht.

Status: `geplant` · `in Arbeit` · `Review` · `wartet` (Grund in „Offen“) · `gemergt` (Commit) · `verworfen`

Stand: 2026-11-04, ADR-0002 bis ADR-0007 freigegeben, R005 läuft, Plan für M1 in Arbeit.

## Meilensteine

| Meilenstein | Inhalt | Status |
| --- | --- | --- |
| M0 ADRs | Architekturentscheidungen; ADR-0002 bis ADR-0007 freigegeben, ADR-0008 (Archiv) folgt | in Arbeit |
| M1 Phase 1 | Laufaufzeichnung und grundlegende Fitnessanalyse | Plan in Arbeit |
| M2 Phase 2 | Adaptiver Trainingscoach | wartet auf Go des Maintainers |
| M3 Phase 3 | Erweiterte Gesundheits- und Erholungsanalyse | wartet auf Go des Maintainers |

## Offen außerhalb der Pakete

- Rechtliche Prüfung vor einem Release (OQ-0048), beauftragt der Maintainer.
- Feldtests: vorerst keine (Emulator). Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben unbelegt.

## Research-Aufträge

| Nr. | Titel | Für | Status | Offen |
| --- | --- | --- | --- | --- |
| R005 | Durchstich der Aufzeichnung | ADR-0005 Punkt 3, ADR-0003 (verschlüsseltes WAL), Lizenzbaum | in Arbeit | – |
