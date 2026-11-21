# Architekturüberblick

**Status:** Gilt für die logische Sicht. Die Quelle schließt Softwarearchitektur und Technologien aus (CON-0002); dieses Dokument leitet deshalb nur eine **logische Sicht** aus den Anforderungen ab, die Bausteine sind fachliche Zuständigkeiten. Die technischen Entscheidungen stehen in den ADRs (Tabelle [Architekturentscheidungen](#architekturentscheidungen)), die technische Sicht des Codes – Pakete, Ordner, Regeln und wohin neuer Code gehört – in der [Code-Landkarte](code-map.md).

## Systemkontext und logische Bausteine

```mermaid
flowchart LR
  Sensor[Herzfrequenzgeräte] --> Rec
  GPS[Smartphone-GPS] --> Rec
  Health[Gesundheitsplattformen] -- nur mit Zustimmung --> Import
  subgraph App
    Rec[Aufzeichnung] --> Quality[Qualität und Vorverarbeitung]
    Import[Import] --> Quality
    Quality --> Models[Fitness- und Belastungsmodelle]
    Models --> Plan[Trainingsplanung und Anpassung]
    Goals[Profil und Ziele] --> Models
    Goals --> Plan
    Plan --> Cal[Kalender]
    Models --> Explain[Statistik und Erklärungen]
    Plan --> Explain
    Rec --> Export[Export und Synchronisierung]
    Privacy[Einwilligungen] -.-> Import
    Privacy -.-> Export
  end
  Export --> Files[GPX, TCX, FIT, verschlüsseltes Archiv]
```

| Baustein | Zuständigkeit | Spezifikation |
|---|---|---|
| Aufzeichnung | GPS und Sensoren, Live-Anzeige, Steuerung | [run-recording.md](../specs/run-recording.md), [sensors.md](../specs/sensors.md) |
| Import | Gesundheitsplattformen | [health-import.md](../specs/health-import.md) |
| Qualität und Vorverarbeitung | Plausibilität, Synchronisation, Qualitätsangaben | [data-quality.md](../specs/data-quality.md) |
| Fitness- und Belastungsmodelle | Zonen, VO₂max, Effizienz, Belastung, Readiness, Energiereserve, Prognose | [vo2max.md](../specs/vo2max.md), [training-load.md](../specs/training-load.md), [readiness.md](../specs/readiness.md), [energy-reserve.md](../specs/energy-reserve.md), [performance-prediction.md](../specs/performance-prediction.md) |
| Profil und Ziele | Basiswerte, Trainingsziele | [profile.md](../specs/profile.md), [goals.md](../specs/goals.md) |
| Planung und Kalender | Planerstellung, Anpassung, Termine | [training-plan.md](../specs/training-plan.md), [plan-adaptation.md](../specs/plan-adaptation.md), [calendar.md](../specs/calendar.md) |
| Statistik und Erklärungen | Auswertung und Begründung | [history-statistics.md](../specs/history-statistics.md), [explanations.md](../specs/explanations.md) |
| Export und Synchronisierung | Dateien, Teilen, Gesamtexport und Reimport | [export-sync.md](../specs/export-sync.md) |
| Einwilligungen | Freigabe, Widerruf, Löschung | [security.md](../quality/security.md) |

## Vertrauensgrenzen

Aus der Quelle ergeben sich diese Grenzen, an denen Daten die App erreichen oder verlassen:

- **Sensoren → App:** Messwerte gelten nicht als fehlerfrei und durchlaufen die Vorverarbeitung (FR-0045). Ein selbst gestarteter Lauf mit gekoppeltem Sensor braucht keine weitere Einwilligung (OQ-0025).
- **Gesundheitsplattform → App:** nur mit Zustimmung und getrennter Freigabe (SEC-0001, SEC-0002).
- **App → Dritte:** nur mit Einwilligung (SEC-0008). Fitnessberechnungen dürfen keine externe Übertragung erzwingen (SEC-0006).

Einen eigenen Server und ein Konto gibt es nicht (ADR-0001).

## Architekturentscheidungen

Status und Datum stehen wie im Kopf der jeweiligen ADR-Datei; `tool/spec_tool.py check` prüft das und dass jede ADR in [index.md](../index.md) verlinkt ist. Eine neue ADR kommt mit ihrem Status in diese Tabelle.

| ADR | Entscheidung | Abhängig von | Status | Datum |
|---|---|---|---|---|
| [ADR-0001](adr/ADR-0001-nur-lokale-datenhaltung.md) | Nur lokale Datenhaltung, kein Konto und kein Server | CON-0008, SEC-0006, FR-0192 | Accepted | 2026-11-03 |
| [ADR-0002](adr/ADR-0002-flutter-mindestversion-projektaufbau.md) | Android-Technologie, Mindestversion, Projektaufbau und Option für iOS | CON-0001, OQ-0035 | Accepted | 2026-11-04 |
| [ADR-0003](adr/ADR-0003-speicherung-und-verschluesselung.md) | Speicherung und Verschlüsselung auf dem Gerät | SEC-0009, SEC-0010 | Accepted | 2026-11-04 |
| [ADR-0004](adr/ADR-0004-algorithmen-rohdaten-versionierung.md) | Austauschbare Algorithmen, Aufbewahrung von Rohdaten und Versionierung der Modelle | NFR-0001, NFR-0005, OQ-0043 | Accepted | 2026-11-04 |
| [ADR-0005](adr/ADR-0005-aufzeichnung-hintergrund-wiederanlauf.md) | Aufzeichnung im Hintergrund und Wiederanlauf | FR-0034, OQ-0021 | Accepted | 2026-11-04 |
| [ADR-0006](adr/ADR-0006-bluetooth-sensoren.md) | Anbindung von Bluetooth-Sensoren | FR-0008, OQ-0018 | Accepted | 2026-11-04 |
| [ADR-0007](adr/ADR-0007-health-connect.md) | Anbindung von Health Connect | FR-0200, OQ-0047 | Accepted | 2026-11-04 |
| [ADR-0008](adr/ADR-0008-verschluesselung-des-archivs.md) | Verschlüsselung des passwortgeschützten Archivs | SEC-0011, FR-0192, FR-0198 | Accepted | 2026-11-04 |
| [ADR-0009](adr/ADR-0009-kartenkacheln-nach-einwilligung.md) | Kartenkacheln aus dem Netz nach Einwilligung | FR-0204, SEC-0008, OQ-0074 | Accepted | 2026-11-07 |
| [ADR-0010](adr/ADR-0010-plan-speicherung-und-neuberechnung.md) | Speicherung und Neuberechnung des Trainingsplans | FR-0156, PAR-203, NFR-0001 | Accepted | 2026-11-10 |
| [ADR-0011](adr/ADR-0011-kamera-ppg.md) | Puls mit der Handykamera (Kamera-PPG) | FR-0214, FR-0215, OQ-0078 | Accepted | 2026-11-10 |

Die Einordnung der Berechnungsverfahren in die Kategorien aus NFR-0002 steht in [algorithm-categories.md](algorithm-categories.md).

Eine Datei `deployment.md` entfällt, weil es nach ADR-0001 keinen Serverbetrieb gibt.
