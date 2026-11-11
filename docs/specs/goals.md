---
id: FEAT-014
title: Individuelle Trainingsziele
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0135, FR-0136, FR-0137]
---

# Individuelle Trainingsziele

## Ziel
Der Nutzer definiert ein persönliches Trainingsziel als Grundlage der Planung.

## Nicht im Scope
- Marathonpläne in Phase 2 (OQ-0004)
- Mehrere gleichzeitige Ziele: nur als mögliche Zusatzfunktion der Phase 4 genannt (SRC-001 §24, Z. 1386).

## Funktionale Anforderungen

### FR-0135 — Zieltypen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §14 und §14.1, Z. 860–887
- **Verwandt:** OQ-0004, OQ-0059, OQ-0060

Der Nutzer kann ein persönliches Trainingsziel definieren.

| Zieltyp | Beispiele |
|---|---|
| Distanzziele | Erstmals 5 km durchlaufen; 10 km ohne Pause laufen; Halbmarathon absolvieren |
| Zeitziele | 5 km unter 25 Minuten; 10 km unter 60 Minuten; Halbmarathon unter zwei Stunden |
| Allgemeine Fitnessziele | Regelmäßig dreimal pro Woche laufen; Ausdauer verbessern; Laufumfang vorsichtig steigern; Wieder mit dem Laufen beginnen |

**Akzeptanzkriterien:**
- [ ] Je Zieltyp lässt sich ein Ziel anlegen.
- [ ] In Phase 2 sind Ziele für 5 km, 10 km und Halbmarathon sowie offene Fitnessziele möglich (OQ-0004).
- [ ] Die Zielspitze eines Strecken- oder Zeitziels folgt PAR-205. Ohne Tempodaten nennt der Text die Zeit, etwa „35 min Laufen“, nicht die Strecke.

### FR-0136 — Zusätzliche Angaben für die Planung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §14.2, Z. 891–900
- **Verwandt:** FR-0002, OQ-0013, OQ-0027, OQ-0038, OQ-0060

Für die Planung kann der Nutzer festlegen: gewünschtes Zieldatum, die Lauftage (Wochentage; ihre Anzahl ist die Zahl der Trainingstage), maximale Trainingszeit pro Einheit und seinen aktuellen Stand (PAR-192). Bisherige Wettkampfzeiten gehen als Referenzleistung ein (FR-0129). Bevorzugte Tage neben den Lauftagen und bekannte Einschränkungen werden nicht abgefragt (K52).

**Akzeptanzkriterien:**
- [ ] Der erzeugte Plan hält die verfügbaren Wochentage und die maximale Trainingszeit pro Einheit ein.
- [ ] Die Werte aus dem Profil sind vorausgefüllt; für den Plan gilt der Wert am Ziel (OQ-0038).
- [ ] Ein Regler legt die höchste Wochenzeit fest, von entspannt bis anspruchsvoll (PAR-196).
- [ ] Ziel, Datum, Tage und Regler lassen sich jederzeit ändern; der Plan rechnet dann ab heute neu (PAR-203).

### FR-0137 — Keine feste Zielzeit erforderlich
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §14.2, Z. 902
- **Verwandt:** OQ-0027, OQ-0059, OQ-0060

Die App darf keine feste Zielzeit voraussetzen. Auch offene Ziele wie „allgemein fitter werden“ sind zulässig.

**Akzeptanzkriterien:**
- [ ] Ein Ziel ohne Zielzeit lässt sich anlegen und führt zu einem Plan.
- [ ] Ein offenes Ziel läuft ohne Datum und ohne Reduktion fort (OQ-0027, PAR-196).
- [ ] Ein offenes Ziel steigert die Wochenzeit bis zum Regler und hält sie dann (PAR-196).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0004](../migration/open-questions.md#oq-0004--welche-ziele-und-trainingsarten-zuerst) (entschieden): Welche Ziele und Trainingsarten zuerst?
- [OQ-0013](../migration/open-questions.md#oq-0013--was-bedeutet-laufleistung) (entschieden): Was bedeutet „Laufleistung“?
- [OQ-0027](../migration/open-questions.md#oq-0027--pläne-ohne-zieldatum-und-bei-offenen-zielen) (entschieden): Pläne ohne Zieldatum und bei offenen Zielen
- [OQ-0038](../migration/open-questions.md#oq-0038--doppelte-eingaben-in-profil-und-ziel) (entschieden): Doppelte Eingaben in Profil und Ziel
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0060](../migration/open-questions.md#oq-0060--einfacher-trainingsplan) (entschieden): Einfacher Trainingsplan
<!-- END OQ -->

## Quellen
- SRC-001: §14, Z. 858–902
