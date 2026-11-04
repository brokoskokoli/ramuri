---
id: FEAT-018
title: Erklärbare Trainingsempfehlungen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0179, FR-0180, FR-0181]
---

# Erklärbare Trainingsempfehlungen

## Ziel
Die App zeigt nicht nur Zahlen und Einheiten, sondern erklärt deren Bedeutung.

## Funktionale Anforderungen

### FR-0179 — Bedeutung erklären
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §19, Z. 1165
- **Verwandt:** CON-0005

Die App soll nicht nur Zahlen und Trainingseinheiten anzeigen, sondern deren Bedeutung erklären.

**Akzeptanzkriterien:**
- [ ] Zu Empfehlungen und Fitnesswerten ist eine Erklärung abrufbar.

### FR-0180 — Erklärungsarten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §19, Z. 1167–1183
- **Verwandt:** FR-0170, OQ-0011, OQ-0039

Beispiele je Erklärungsart:

| Art | Beispieltext |
|---|---|
| Fitnessentwicklung | „Deine geschätzte VO₂max ist in den vergangenen sechs Wochen von 43 auf 46 gestiegen. Die Schätzung basiert auf fünf geeigneten Läufen.“ |
| Trainingsempfehlung | „Für morgen ist ein lockerer Dauerlauf vorgesehen. Deine kurzfristige Trainingsbelastung liegt aktuell über deinem langfristigen Durchschnitt.“ |
| Planänderung | „Das intensive Training wurde um einen Tag verschoben, weil sich dadurch ein zusätzlicher Erholungstag ergibt.“ |
| Datenqualität | „Für diesen Lauf konnte keine zuverlässige VO₂max-Schätzung berechnet werden. Die Geschwindigkeit und Herzfrequenz waren über längere Abschnitte nicht stabil genug.“ |

Die Zahlen der Beispiele sind illustrativ. Im Beispiel „Trainingsempfehlung“ heißt es in der App „langfristiges Belastungsniveau“ statt „langfristigen Durchschnitt“ (OQ-0039). Das Beispiel „Planänderung“ ist eine Terminänderung und gilt nach OQ-0011 erst nach Bestätigung.

**Akzeptanzkriterien:**
- [ ] Zu jeder der vier beispielhaften Arten kann eine Erklärung erzeugt werden.

### FR-0181 — Erklärungen beruhen auf tatsächlichen Daten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §19, Z. 1185
- **Verwandt:** FR-0059

Erklärungen müssen auf tatsächlich vorhandenen Daten und den verwendeten Berechnungsregeln beruhen.

**Akzeptanzkriterien:**
- [ ] Alle Zahlen und Gründe einer Erklärung stimmen mit den Metadaten des erklärten Werts überein (FR-0053).
- [ ] Nicht vorhandene Daten werden nicht als Grund genannt.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0011](../migration/open-questions.md#oq-0011--automatische-plananpassung-oder-bestätigung) (entschieden): Automatische Plananpassung oder Bestätigung?
- [OQ-0039](../migration/open-questions.md#oq-0039--benennung-von-ctl-in-statistik-und-erklärungen) (entschieden): Benennung von CTL in Statistik und Erklärungen
<!-- END OQ -->

## Quellen
- SRC-001: §19, Z. 1163–1185
