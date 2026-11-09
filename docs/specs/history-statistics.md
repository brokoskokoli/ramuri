---
id: FEAT-005
title: Trainingshistorie und Statistiken
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0040, FR-0041, FR-0042, FR-0043, FR-0044, FR-0211, FR-0212]
---

# Trainingshistorie und Statistiken

## Ziel
Der Nutzer sieht alle Läufe und wertet sie über verschiedene Zeiträume aus.

## Funktionale Anforderungen

### FR-0040 — Trainingshistorie
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5, Z. 193; §25 Nr. 4, Z. 1399
- **Verwandt:** ACC-04, FR-0204, FR-0212, OQ-0074, OQ-0075

Alle Laufeinheiten werden in einer Trainingshistorie dargestellt, mit Strecke, Dauer, Pace und vorhandenen Herzfrequenzdaten.

**Festlegung (OQ-0074, OQ-0075):** Jeder Lauf mit Positionen zeigt eine Miniatur seiner Route nach FR-0204. Über der Liste wählt der Nutzer den Zeitraum nach FR-0212.

**Akzeptanzkriterien:**
- [ ] Jeder aufgezeichnete Lauf erscheint mit Strecke, Dauer und Pace (ACC-04).
- [ ] Vorhandene Herzfrequenzdaten werden angezeigt; fehlende nicht als 0.

### FR-0041 — Detailansicht eines Laufs
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5.1, Z. 197
- **Verwandt:** FR-0204, FR-0211, OQ-0065, OQ-0074, OQ-0075

Jeder Lauf verfügt über eine Detailansicht mit GPS-Route, Zeitverlauf und Messwertdiagrammen.

**Festlegung (OQ-0065, OQ-0074, OQ-0075):** Die Route erscheint auf einer Karte nach FR-0204: mit Einwilligung auf Kartenmaterial, sonst ohne. Dazu kommen Kilometerwerte nach FR-0211.

**Akzeptanzkriterien:**
- [ ] Die Detailansicht zeigt GPS-Route, Zeitverlauf und Messwertdiagramme.

### FR-0042 — Pace und Herzfrequenz zeitlich vergleichen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5.1, Z. 199

Im Diagramm sollen beispielsweise Pace und Herzfrequenz zeitlich miteinander verglichen werden können.

**Akzeptanzkriterien:**
- [ ] Messwerte wie Pace und Herzfrequenz lassen sich im Diagramm zeitlich vergleichen.

### FR-0043 — Statistische Kennzahlen
- **Status:** Approved | **Phase:** 1 (je Kennzahl abhängig von der liefernden Funktion)
- **Quelle:** SRC-001 §5.2, Z. 203–212
- **Verwandt:** FR-0055, OQ-0039, OQ-0065, OQ-0075

Die Statistik umfasst diese Bereiche.

| Bereich | Kennzahlen |
|---|---|
| Umfang | Laufkilometer, Laufzeit, Trainingshäufigkeit |
| Geschwindigkeit | Durchschnittspace, Bestpace, Runden |
| Herzfrequenz | Durchschnitt, Maximum, Zonenverteilung |
| Fitness | Geschätzte VO₂max, aerobe Effizienz |
| Belastung | TRIMP, kurzfristige und langfristige Trainingsbelastung |
| Entwicklung | Wochen- und Monatsvergleiche |
| Leistung | Persönliche Bestzeiten, prognostizierte Wettkampfzeiten |
| Erholung | Training Readiness und optional Energiereserve |

In der Oberfläche heißt die langfristige Trainingsbelastung „langfristiges Belastungsniveau“ (OQ-0039). Kennzahlen anderer Phasen (etwa ATL/CTL, Prognosen, Readiness) erscheinen erst, wenn die liefernde Funktion verfügbar ist.

**Festlegung (OQ-0065):** Persönliche Bestzeiten werden bis zu ihrer Definition nicht angezeigt.

**Festlegung (OQ-0075):** Der Bereich „Fortschritt“ zeigt nach Design oben die Kilometer der letzten 8 Wochen als Balken, darunter VO₂max und aerobe Effizienz in der Darstellung ihrer Specs und danach die übrigen Kennzahlen mit der Zeitraumwahl (FR-0044).

**Akzeptanzkriterien:**
- [ ] Jede Kennzahl ist entweder berechnet oder als nicht verfügbar erkennbar (FR-0057).

### FR-0044 — Auswertungszeiträume
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5.2, Z. 214

Die App soll Statistiken nach einzelnen Läufen, Kalenderwochen, Monaten und frei wählbaren Zeiträumen anbieten.

**Akzeptanzkriterien:**
- [ ] Alle vier Zeitraumarten sind wählbar.
- [ ] Die Summe der Läufe einer Woche entspricht der Wochenstatistik.

### FR-0211 — Kilometerwerte in der Detailansicht
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0041, FR-0056, FR-0204, OQ-0075, OQ-0076

Die Detailansicht zeigt eine Tabelle je vollem Kilometer mit Pace und Durchschnittspuls, Kilometermarken auf der Route und zum Höhenprofil Anstieg und Gefälle in Metern.

**Festlegungen (OQ-0075):**
- Grundlage ist die Bewegungsstrecke nach der Vorverarbeitung; Pausen zählen nicht zur Pace. Ein angebrochener letzter Kilometer erscheint mit seiner Länge.
- Liegt das Tempo eines Abschnitts unter der Stillstandsschwelle (PAR-014, 0,5 m/s), steht statt der Pace „–“ (OQ-0076).
- Fehlt der Puls in einem Kilometer, steht dort „–“, nicht 0. Kilometer mit GPS-Lücke sind gekennzeichnet.
- In Meilen gelten Meilen statt Kilometer (NFR-0006).

**Akzeptanzkriterien:**
- [ ] Die Summe der Kilometerzeiten entspricht der Bewegungszeit.
- [ ] Anstieg und Gefälle stimmen mit dem Höhenprofil überein.

### FR-0212 — Zeitraum in der Historie
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0040, FR-0044, OQ-0075

Über der Liste der Läufe wählt der Nutzer Woche, Monat, Jahr oder Alle und sieht dazu Summen von Strecke, Zeit und Anzahl der Läufe. Die Liste ist nach Wochen gruppiert („Diese Woche“, „Letzte Woche“, danach mit Datum).

**Festlegung (OQ-0075):** Die Statistik behält ihre Zeitraumarten nach FR-0044.

**Akzeptanzkriterien:**
- [ ] Die Summen entsprechen der Statistik für denselben Zeitraum.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0039](../migration/open-questions.md#oq-0039--benennung-von-ctl-in-statistik-und-erklärungen) (entschieden): Benennung von CTL in Statistik und Erklärungen
- [OQ-0065](../migration/open-questions.md#oq-0065--lücken-aus-dem-plan-für-phase-1) (entschieden): Lücken aus dem Plan für Phase 1
- [OQ-0074](../migration/open-questions.md#oq-0074--karte-der-route) (entschieden): Karte der Route
- [OQ-0075](../migration/open-questions.md#oq-0075--screen-design-und-marke) (entschieden): Screen-Design und Marke
- [OQ-0076](../migration/open-questions.md#oq-0076--nachschliff-der-lauf-seiten) (entschieden): Nachschliff der Lauf-Seiten
<!-- END OQ -->

## Quellen
- SRC-001: §5, Z. 191–214; §25 Nr. 4
