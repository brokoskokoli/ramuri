---
id: FEAT-009
title: Aerobe Effizienz und Fitnessentwicklung
status: Teilweise Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0084, FR-0085, FR-0086, FR-0087, FR-0088, FR-0089, FR-0090]
---

# Aerobe Effizienz und Fitnessentwicklung

## Ziel
Eine Kennzahl dafür, wie schnell der Nutzer bei vergleichbarer relativer Herzbelastung laufen kann.

## Funktionale Anforderungen

### FR-0084 — Kennzahl für aerobe Laufeffizienz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §9, Z. 486–488
- **Verwandt:** OQ-0036

Zusätzlich zur VO₂max soll die App eine Kennzahl für die aerobe Laufeffizienz bieten. Die Idee lautet: Wie schnell kann der Nutzer bei vergleichbarer relativer Herzbelastung laufen?

**Akzeptanzkriterien:**
- [ ] Die Kennzahl ist in der Statistik verfügbar, sofern geeignete Daten vorliegen. Sie ist der „Aerobe Fitness-Trend“ aus Phase 1 (OQ-0036).

### FR-0085 — Referenzgeschwindigkeit
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §9.1, Z. 492–494
- **Verwandt:** OQ-0036

Die App sammelt geeignete Abschnitte in einem definierten Belastungsbereich, beispielsweise zwischen 65 und 75 % der Herzfrequenzreserve, und berechnet für sie die mittlere oder mediane Geschwindigkeit.

**Akzeptanzkriterien:**
- [ ] Abschnitte außerhalb des definierten Bereichs fließen nicht ein.
- [ ] Es gilt der Bereich 65–75 % der Herzfrequenzreserve und der Median (OQ-0036).

### FR-0086 — Vergleichbare Bedingungen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §9.1, Z. 496–501
- **Verwandt:** OQ-0036, OQ-0073

Die Auswertung erfolgt bevorzugt unter vergleichbaren Bedingungen: ähnlicher Herzfrequenzbereich, gleichmäßiges Tempo, vergleichbare Steigung, ausreichende Messqualität.

**Akzeptanzkriterien:**
- [ ] Ein Abschnitt mit unzureichender Messqualität wird nicht bevorzugt verwendet.

### FR-0087 — Veränderung der aeroben Effizienz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §9.2, Z. 505–518
- **Verwandt:** OQ-0036

`ΔE = (v_aktuell / v_referenz − 1) · 100`

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 9,0 km/h auf 9,5 km/h ergibt 5,56 %, angezeigt als ungefähr 5,6 %.
- [ ] Verglichen werden die letzten 4 Wochen mit den 4 Wochen davor (OQ-0036).

### FR-0088 — Abgrenzung zur VO2max
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §9.2, Z. 520

Diese Kennzahl ist keine direkte Messung der VO₂max. Sie wird unter anderem von Laufökonomie, Temperatur, Untergrund, Wind und Tagesform beeinflusst.

**Akzeptanzkriterien:**
- [ ] Die App stellt eine Effizienzänderung nicht als VO₂max-Änderung dar.

### FR-0089 — Herzfrequenzdrift
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §9.3, Z. 524–534

Optional kann die aerobe Entkopplung bei längeren gleichmäßigen Läufen untersucht werden: geprüft wird, ob die Herzfrequenz im Verhältnis zur Geschwindigkeit ansteigt. Ein mögliches Modell ist `D = ((HF2/v2) / (HF1/v1) − 1) · 100`, wobei die Indizes die erste und zweite vergleichbare Hälfte eines geeigneten Laufabschnitts bezeichnen.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): gleiche Geschwindigkeit, HF 140 auf 147 ergibt D = 5 %.

### FR-0090 — Drift nur bei geeigneten Läufen und vorsichtig deuten
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §9.3, Z. 536–538
- **Verwandt:** OQ-0019

Der Wert wird nur für geeignete, ausreichend lange, weitgehend gleichmäßige Läufe berechnet. Eine positive Drift kann unter anderem durch Ermüdung, Hitze oder Flüssigkeitsverlust entstehen.

**Akzeptanzkriterien:**
- [ ] Ein Intervalllauf liefert keinen Driftwert.
- [ ] Die Mindestdauer folgt PAR-048.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0019](../migration/open-questions.md#oq-0019--startwerte-der-modellparameter-und-qualitätsregeln) (entschieden): Startwerte der Modellparameter und Qualitätsregeln
- [OQ-0036](../migration/open-questions.md#oq-0036--parameter-der-aeroben-effizienz) (entschieden): Parameter der aeroben Effizienz
- [OQ-0073](../migration/open-questions.md#oq-0073--aerobe-effizienz-ohne-höhe) (non-blocking): Aerobe Effizienz ohne Höhe
<!-- END OQ -->

## Quellen
- SRC-001: §9, Z. 484–538
