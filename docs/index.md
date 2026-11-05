# Dokumentationsindex

Einstieg in die Spezifikation der Adaptive Running & Fitness App. Der Status jeder Anforderung steht im Register; der Status einer Spec steht in ihrem Kopf.

## Lesereihenfolge

1. [Produktdefinition](product.md): Vision, Prinzipien, Phasen, Begriffe
2. [Anforderungsregister](requirements.md): alle Anforderungen mit Status und Phase
3. [Offene Fragen](migration/open-questions.md): Konflikte und Blocker
4. Die für die Aufgabe relevante Spec, dazu Qualität und Architektur nach Bedarf

## Funktionale Spezifikationen

| ID | Spec |
|---|---|
| FEAT-001 | [Nutzerprofil](specs/profile.md) |
| FEAT-002 | [Sensoren und Fitnessgeräte](specs/sensors.md) |
| FEAT-003 | [Import von Gesundheitsdaten](specs/health-import.md) |
| FEAT-004 | [Aufzeichnung von Läufen](specs/run-recording.md) |
| FEAT-005 | [Historie und Statistiken](specs/history-statistics.md) |
| FEAT-006 | [Datenqualität und Berechnungsgrundlagen](specs/data-quality.md) |
| FEAT-007 | [Herzfrequenz und Zonen](specs/heart-rate-zones.md) |
| FEAT-008 | [VO₂max-Schätzung](specs/vo2max.md) |
| FEAT-009 | [Aerobe Effizienz](specs/aerobic-efficiency.md) |
| FEAT-010 | [Trainingsbelastung](specs/training-load.md) |
| FEAT-011 | [Readiness](specs/readiness.md) |
| FEAT-012 | [Energiereserve](specs/energy-reserve.md) |
| FEAT-013 | [Leistungsprognosen](specs/performance-prediction.md) |
| FEAT-014 | [Trainingsziele](specs/goals.md) |
| FEAT-015 | [Erstellung des Trainingsplans](specs/training-plan.md) |
| FEAT-016 | [Plananpassung](specs/plan-adaptation.md) |
| FEAT-017 | [Trainingskalender](specs/calendar.md) |
| FEAT-018 | [Erklärungen](specs/explanations.md) |
| FEAT-019 | [Export und Strava](specs/export-sync.md) |

## Weitere Dokumente

- Architektur: [Überblick](architecture/overview.md), [Fachliches Datenmodell](architecture/data-model.md), [ADR-0001: Nur lokale Datenhaltung](architecture/adr/ADR-0001-nur-lokale-datenhaltung.md)
- Verträge: [Schnittstellen](contracts/README.md)
- Qualität: [Tests und Abnahme](quality/testing.md), [Sicherheit und Datenschutz](quality/security.md), [Nichtfunktionales](quality/non-functional.md)
- [Modellparameter (Startwerte, Version 3)](model-parameters.md)
- [Planungsregeln und Startwerte, Version 4](planning-rules.md)
- [Regeln für Phase 2 und 3, Version 4](phase-2-3-rules.md)
- [Referenzen](references.md)
- [Änderungsprotokoll der Umsetzung](changelog.md)
- Migration: [Quelleninventar](migration/source-inventory.md), [Traceability](migration/traceability.md), [Migrationsbericht](migration/migration-report.md)

## Vergaberegel für IDs

| Präfix | Bedeutung | Maßgebliche Stelle |
|---|---|---|
| `FR-0001` | Funktionale Anforderung | `specs/` |
| `NFR-0001` | Nichtfunktionale Anforderung | `quality/non-functional.md` |
| `SEC-0001` | Sicherheitsinvariante | `quality/security.md` |
| `CON-0001` | Constraint | `product.md` |
| `DEC-0001` | Fachliche Entscheidung | `product.md` |
| `ACC-01` | Abnahmekriterium aus der Quelle | `quality/testing.md` |
| `OQ-0001` | Offene Frage | `migration/open-questions.md` |
| `FEAT-001` | Feature-Spezifikation | `specs/` |
| `SRC-001` | Quelle | `migration/source-inventory.md` |
| `PAR-001` | Parameter oder Regel | `model-parameters.md`, `planning-rules.md`, `phase-2-3-rules.md` |

IDs sind projektweit eindeutig und werden nie umnummeriert oder wiederverwendet. Neue Anforderungen erhalten die nächste freie Nummer. Veraltete behalten ihre ID und erhalten den Status `Deprecated`. ADRs tragen `ADR-0001` und folgende.

## Änderungen

Änderungen folgen dem Ablauf in SRC-002 §11: Änderungsantrag, Spec und Kriterien anpassen, Auswirkungen auf Architektur, Verträge, Sicherheit und Tests prüfen, Register und Traceability aktualisieren, Freigabe einholen. Ein geänderter Spezifikationsstatus sagt nichts über den Implementierungsstand aus.
