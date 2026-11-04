---
id: FEAT-013
title: Leistungsprognosen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0128, FR-0129, FR-0130, FR-0131, FR-0132, FR-0133, FR-0134]
---

# Leistungsprognosen

## Ziel
Die App schätzt, welche Laufzeiten ein Nutzer über bestimmte Distanzen erreichen könnte.

## Funktionale Anforderungen

### FR-0128 — Prognose für mögliche Distanzen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13, Z. 811–818

Die App soll abschätzen können, welche Laufzeiten ein Nutzer über bestimmte Distanzen erreichen könnte. Mögliche Distanzen: 5 km, 10 km, Halbmarathon, Marathon.

**Akzeptanzkriterien:**
- [ ] Bei geeigneter Referenzleistung liegt für die unterstützten Distanzen eine Prognose vor.

### FR-0129 — Bevorzugt tatsächliche Leistungen als Grundlage
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13, Z. 820
- **Verwandt:** FR-0055, OQ-0034, OQ-0058, OQ-0059

Die Prognose soll bevorzugt auf geeigneten tatsächlichen Leistungen basieren.

**Akzeptanzkriterien:**
- [ ] Die Prognose nennt die verwendete Referenzleistung.
- [ ] Referenz ist eine eingetragene Wettkampf- oder Testzeit oder ein bestätigter schneller Lauf (OQ-0034).
- [ ] Ohne Referenz gibt es keine Prognose, sondern den Grund und einen Hinweis auf einen 5-km-Test, sobald der Plan ihn nach PAR-117 enthalten dürfte (OQ-0034, OQ-0057, DEC-0059).
- [ ] Ein schneller Lauf wird nach PAR-185 vorgeschlagen und zählt erst nach Bestätigung.

### FR-0130 — Riegel-Modell
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13.1, Z. 824–838
- **Verwandt:** NFR-0002, OQ-0008

Ausgehend von einer bekannten Wettkampf- oder vergleichbaren maximalen Leistung (Referenzleistung) gilt: `T2 = T1 · (D2 / D1)^1,06`.

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 5 km in 25 min ergibt für 10 km ungefähr 52 min 7 s.

### FR-0131 — Voraussetzungen der Referenzleistung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13.1, Z. 840–842
- **Verwandt:** OQ-0034

Das Modell setzt voraus, dass die Referenzleistung ausreichend repräsentativ und der Nutzer für die neue Distanz entsprechend trainiert ist. Ein normaler lockerer Lauf darf nicht ohne Weiteres als maximale Referenzleistung verwendet werden.

**Akzeptanzkriterien:**
- [ ] Ein normaler lockerer Lauf wird nicht automatisch als Referenz übernommen.

### FR-0132 — Einflussgrößen der Prognosequalität
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13.2, Z. 846–852
- **Verwandt:** FR-0059

Die Zuverlässigkeit hängt ab von: Aktualität des Referenzlaufs, Ähnlichkeit der Distanzen, Trainingsumfang, Regelmäßigkeit des Trainings und Vorhandensein geeigneter Wettkampfergebnisse.

**Akzeptanzkriterien:**
- [ ] Ein älterer Referenzlauf führt bei sonst gleichen Daten nicht zu einer höheren Zuverlässigkeit.

### FR-0133 — Allgemeine Schätzung und Zielprognose unterscheiden
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13.2, Z. 854

Die App unterscheidet zwischen einer allgemeinen Leistungsschätzung und der Prognose für das konkret geplante Wettkampfziel.

**Akzeptanzkriterien:**
- [ ] Beide Angaben sind getrennt benannt.

### FR-0134 — VO2max allein ist keine verbindliche Prognosegrundlage
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §13.2, Z. 856
- **Verwandt:** OQ-0034

Die VO₂max allein soll nicht zur verbindlichen Vorhersage einer Wettkampfzeit verwendet werden.

**Akzeptanzkriterien:**
- [ ] Mit nur einer VO₂max-Schätzung erscheint keine verbindliche Wettkampfzeit.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0008](../migration/open-questions.md#oq-0008--reicht-die-riegel-methode) (entschieden): Reicht die Riegel-Methode?
- [OQ-0034](../migration/open-questions.md#oq-0034--datengrundlage-von-leistungsprognosen) (entschieden): Datengrundlage von Leistungsprognosen
- [OQ-0058](../migration/open-questions.md#oq-0058--entscheidungen-aus-der-prüfung-von-phase-2-und-3) (entschieden): Entscheidungen aus der Prüfung von Phase 2 und 3
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
<!-- END OQ -->

## Quellen
- SRC-001: §13, Z. 809–856
