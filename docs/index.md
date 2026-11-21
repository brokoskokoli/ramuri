# Dokumentationsindex

Einstieg in die Spezifikation von ramuri (Adaptive Running & Fitness App). Der Status jeder Anforderung steht im Register; der Status einer Spec steht in ihrem Kopf.

## Lesereihenfolge

1. [Produktdefinition](product.md): Vision, Prinzipien, Phasen, Begriffe
2. [Anforderungsregister](requirements.md): alle Anforderungen mit Status und Phase
3. Die für die Aufgabe relevante Spec, dazu Qualität und Architektur nach Bedarf

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
| FEAT-020 | [Oberfläche, Marke und Navigation](specs/app-design.md) |

## Weitere Dokumente

- Architektur: [Überblick](architecture/overview.md) (logische Sicht), [Code-Landkarte](architecture/code-map.md) (Pakete, Ordner, Regeln, wohin neuer Code gehört), [Fachliches Datenmodell](architecture/data-model.md), [Kategorien der Berechnungsverfahren](architecture/algorithm-categories.md)
- Architekturentscheidungen mit Status (Datum und Bezüge im [Überblick](architecture/overview.md#architekturentscheidungen)):
  - [ADR-0001: Nur lokale Datenhaltung](architecture/adr/ADR-0001-nur-lokale-datenhaltung.md) — Accepted
  - [ADR-0002: Flutter, Android-Mindestversion und Projektaufbau](architecture/adr/ADR-0002-flutter-mindestversion-projektaufbau.md) — Accepted
  - [ADR-0003: Speicherung und Verschlüsselung](architecture/adr/ADR-0003-speicherung-und-verschluesselung.md) — Accepted
  - [ADR-0004: Algorithmen, Rohdaten und Versionierung](architecture/adr/ADR-0004-algorithmen-rohdaten-versionierung.md) — Accepted
  - [ADR-0005: Aufzeichnung im Hintergrund und Wiederanlauf](architecture/adr/ADR-0005-aufzeichnung-hintergrund-wiederanlauf.md) — Accepted
  - [ADR-0006: Bluetooth-Sensoren](architecture/adr/ADR-0006-bluetooth-sensoren.md) — Accepted
  - [ADR-0007: Health Connect](architecture/adr/ADR-0007-health-connect.md) — Accepted
  - [ADR-0008: Verschlüsselung des Archivs](architecture/adr/ADR-0008-verschluesselung-des-archivs.md) — Accepted
  - [ADR-0009: Kartenkacheln nach Einwilligung](architecture/adr/ADR-0009-kartenkacheln-nach-einwilligung.md) — Accepted
  - [ADR-0010: Plan: Speicherung und Neuberechnung](architecture/adr/ADR-0010-plan-speicherung-und-neuberechnung.md) — Accepted
  - [ADR-0011: Kamera-PPG](architecture/adr/ADR-0011-kamera-ppg.md) — Accepted
- Verträge: [Schnittstellen](contracts/README.md)
- Qualität: [Tests und Abnahme](quality/testing.md), [Sicherheit und Datenschutz](quality/security.md), [Nichtfunktionales](quality/non-functional.md)
- [Modellparameter (Startwerte, Version 4)](model-parameters.md)
- [Planungsregeln und Startwerte, Version 4](planning-rules.md)
- [Regeln für Phase 2 und 3, Version 4](phase-2-3-rules.md)
- [Referenzen](references.md)

## Außerhalb dieses Repos

Die offenen Fragen und Entscheidungen des Maintainers (`OQ-nnnn`), das Quelleninventar (`SRC-nnn`) mit dem Ursprungskonzept, die Traceability, der Migrationsbericht und das Änderungsprotokoll der Umsetzung (K-Einträge) pflegt der Maintainer außerhalb dieses Repos; hier stehen nur ihre IDs. Bis Commit `5f91aa4` lagen sie unter `docs/migration/` und `docs/changelog.md`; Textverweise auf diese Pfade und auf `research/…` beziehen sich auf jenen Stand. Entscheidungen, die für das Verhalten gelten, stehen als DEC in [product.md](product.md) oder in der jeweiligen Spec. `tool/spec_tool.py check` prüft OQ- und SRC-IDs nur auf ihre Form.

## Vergaberegel für IDs

| Präfix | Bedeutung | Maßgebliche Stelle |
|---|---|---|
| `FR-0001` | Funktionale Anforderung | `specs/` |
| `NFR-0001` | Nichtfunktionale Anforderung | `quality/non-functional.md` |
| `SEC-0001` | Sicherheitsinvariante | `quality/security.md` |
| `CON-0001` | Constraint | `product.md` |
| `DEC-0001` | Fachliche Entscheidung | `product.md` |
| `ACC-01` | Abnahmekriterium aus der Quelle | `quality/testing.md` |
| `OQ-0001` | Offene Frage oder Entscheidung des Maintainers | außerhalb dieses Repos |
| `FEAT-001` | Feature-Spezifikation | `specs/` |
| `SRC-001` | Quelle | außerhalb dieses Repos (Quelleninventar) |
| `PAR-001` | Parameter oder Regel | `model-parameters.md`, `planning-rules.md`, `phase-2-3-rules.md` |

IDs sind projektweit eindeutig und werden nie umnummeriert oder wiederverwendet. Neue Anforderungen erhalten die nächste freie Nummer. Veraltete behalten ihre ID und erhalten den Status `Deprecated`. ADRs tragen `ADR-0001` und folgende.

## Änderungen

Änderungen folgen dem Ablauf in SRC-002 §11: Änderungsantrag, Spec und Kriterien anpassen, Auswirkungen auf Architektur, Verträge, Sicherheit und Tests prüfen, Register und Traceability aktualisieren, Freigabe einholen. Ein geänderter Spezifikationsstatus sagt nichts über den Implementierungsstand aus.
