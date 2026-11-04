---
id: FEAT-005
title: Trainingshistorie und Statistiken
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0040, FR-0041, FR-0042, FR-0043, FR-0044]
---

# Trainingshistorie und Statistiken

## Ziel
Der Nutzer sieht alle Läufe und wertet sie über verschiedene Zeiträume aus.

## Funktionale Anforderungen

### FR-0040 — Trainingshistorie
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5, Z. 193; §25 Nr. 4, Z. 1399
- **Verwandt:** ACC-04

Alle Laufeinheiten werden in einer Trainingshistorie dargestellt, mit Strecke, Dauer, Pace und vorhandenen Herzfrequenzdaten.

**Akzeptanzkriterien:**
- [ ] Jeder aufgezeichnete Lauf erscheint mit Strecke, Dauer und Pace (ACC-04).
- [ ] Vorhandene Herzfrequenzdaten werden angezeigt; fehlende nicht als 0.

### FR-0041 — Detailansicht eines Laufs
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5.1, Z. 197

Jeder Lauf verfügt über eine Detailansicht mit GPS-Route, Zeitverlauf und Messwertdiagrammen.

**Festlegung (OQ-0065):** Die Route wird ohne Kartenmaterial gezeichnet.

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
- **Verwandt:** FR-0055, OQ-0039, OQ-0065

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

**Akzeptanzkriterien:**
- [ ] Jede Kennzahl ist entweder berechnet oder als nicht verfügbar erkennbar (FR-0057).

### FR-0044 — Auswertungszeiträume
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §5.2, Z. 214

Die App soll Statistiken nach einzelnen Läufen, Kalenderwochen, Monaten und frei wählbaren Zeiträumen anbieten.

**Akzeptanzkriterien:**
- [ ] Alle vier Zeitraumarten sind wählbar.
- [ ] Die Summe der Läufe einer Woche entspricht der Wochenstatistik.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0039](../migration/open-questions.md#oq-0039--benennung-von-ctl-in-statistik-und-erklärungen) (entschieden): Benennung von CTL in Statistik und Erklärungen
- [OQ-0065](../migration/open-questions.md#oq-0065--lücken-aus-dem-plan-für-phase-1) (entschieden): Lücken aus dem Plan für Phase 1
<!-- END OQ -->

## Quellen
- SRC-001: §5, Z. 191–214; §25 Nr. 4
