---
id: FEAT-007
title: Herzfrequenz und Trainingszonen
status: Teilweise Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0060, FR-0061, FR-0062, FR-0063, FR-0064, FR-0065]
---

# Herzfrequenz und Trainingszonen

## Ziel
Individualisierte Belastungsbewertung über die Herzfrequenzreserve und konfigurierbare Zonen.

**Wichtige Abgrenzung:** Die Zonen dieser Spec beziehen sich auf die Herzfrequenzreserve. Die TRIMP-Zonen beziehen sich auf die maximale Herzfrequenz: siehe [training-load.md](training-load.md).

## Funktionale Anforderungen

### FR-0060 — Herzfrequenzreserve und relative Auslastung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §7.1, Z. 277–299
- **Verwandt:** OQ-0012, OQ-0019, OQ-0059

Die Herzfrequenzreserve bildet eine Grundlage für die individualisierte Belastungsbewertung: `HFR = HFmax − HFRuhe`. Die relative Auslastung ist `r = (HFaktuell − HFRuhe) / (HFmax − HFRuhe)`.

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: HFmax 190, HFRuhe 60, HFaktuell 151 ergibt r = 0,70.
- [ ] Fehlt Ruhepuls oder HFmax, ist r nicht verfügbar und nicht 0 (OQ-0012).
- [ ] Bei HFmax ≤ HFRuhe gilt PAR-018, bei 0 < HFR < 50 bpm PAR-019.

### FR-0061 — Fünf konfigurierbare Zonen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §7.2, Z. 303

Die App bietet fünf konfigurierbare Trainingszonen.

**Akzeptanzkriterien:**
- [ ] Der Nutzer kann die fünf Zonen anpassen; neue Berechnungen verwenden die angepasste Einteilung.

### FR-0062 — Vorläufiges Zonenmodell auf Basis der Herzfrequenzreserve
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §7.2, Z. 305–313
- **Verwandt:** OQ-0003, OQ-0014

Als vorläufiges Modell können Zonen auf Grundlage der Herzfrequenzreserve verwendet werden.

| Zone | Anteil der Herzfrequenzreserve | Bezeichnung |
|---|---|---|
| 1 | 50–60 % | Sehr leicht |
| 2 | 60–70 % | Leicht |
| 3 | 70–80 % | Moderat |
| 4 | 80–90 % | Hoch |
| 5 | 90–100 % | Sehr hoch |

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): r = 0,65 liegt in Zone 2.
- [ ] Die Untergrenze zählt zur Zone: r = 0,60 liegt in Zone 2 (OQ-0014).
- [ ] Werte über 100 % zählen zur Zone 5 und lösen einen Hinweis auf eine zu niedrige HFmax oder einen Messfehler aus (OQ-0014).

### FR-0063 — Bereiche unter Zone 1 separat ausweisen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §7.2, Z. 315

Bereiche unterhalb von Zone 1 werden separat ausgewiesen.

**Akzeptanzkriterien:**
- [ ] Zeit unter 50 % der Reserve erscheint nicht in Zone 1, sondern gesondert.

### FR-0064 — Zonen als Näherung kennzeichnen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §7.2, Z. 317
- **Verwandt:** CON-0009

Diese Einteilung ist eine konfigurierbare Näherung. Sie ersetzt keine individuell bestimmten ventilatorischen oder Laktatschwellen.

**Akzeptanzkriterien:**
- [ ] Die App stellt die Zonen nicht als gemessene physiologische Schwellen dar.

### FR-0065 — Zonen aus Tests oder gemessenen Schwellen
- **Status:** Draft | **Phase:** 4 (möglich)
- **Quelle:** SRC-001 §7.2, Z. 319
- **Verwandt:** OQ-0003, OQ-0017

Später können Herzfrequenzzonen auch aus individuellen Leistungstests oder gemessenen Schwellen abgeleitet werden.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0003](../migration/open-questions.md#oq-0003--herzfrequenzzonen-allein-oder-schwellenmodell) (entschieden): Herzfrequenzzonen allein oder Schwellenmodell?
- [OQ-0012](../migration/open-questions.md#oq-0012--was-gilt-wenn-ruhepuls-oder-hfmax-fehlen) (entschieden): Was gilt, wenn Ruhepuls oder HFmax fehlen?
- [OQ-0014](../migration/open-questions.md#oq-0014--zuordnung-an-zonengrenzen-und-außerhalb-der-zonen) (entschieden): Zuordnung an Zonengrenzen und außerhalb der Zonen
- [OQ-0017](../migration/open-questions.md#oq-0017--verbindlichkeit-der-phasen-und-fehlende-zuordnungen) (entschieden): Verbindlichkeit der Phasen und fehlende Zuordnungen
- [OQ-0019](../migration/open-questions.md#oq-0019--startwerte-der-modellparameter-und-qualitätsregeln) (entschieden): Startwerte der Modellparameter und Qualitätsregeln
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
<!-- END OQ -->

## Quellen
- SRC-001: §7, Z. 273–319
