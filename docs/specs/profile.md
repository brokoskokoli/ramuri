---
id: FEAT-001
title: Nutzerprofil und persönliche Einstellungen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0001, FR-0002, FR-0003, FR-0004, FR-0005, FR-0006]
---

# Nutzerprofil und persönliche Einstellungen

## Ziel
Der Nutzer hinterlegt persönliche Basiswerte, auf denen Fitnessberechnungen und Trainingspläne aufbauen.

## Scope
- Ersteinrichtung und spätere Korrektur des Profils
- Maximale Herzfrequenz: gemessener Wert oder altersbasierte Näherung
- Nachvollziehbare Neuberechnung nach Änderungen

## Funktionale Anforderungen

### FR-0001 — Profil beim ersten Start einrichten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2, Z. 33
- **Verwandt:** FR-0002, OQ-0010

Beim ersten Start richtet der Nutzer ein persönliches Profil ein.

**Akzeptanzkriterien:**
- [ ] Beim ersten Start wird die Profileinrichtung angeboten.
- [ ] Die Einrichtung lässt sich überspringen, und ein Lauf ist danach möglich (OQ-0010).

### FR-0002 — Profildatenfelder
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 37–47
- **Verwandt:** FR-0001, OQ-0010, OQ-0013, OQ-0038, OQ-0065

Das Profil umfasst die folgenden Felder.

| Datenfeld | Zweck | Erforderlich |
|---|---|---|
| Alter oder Geburtsjahr | Näherung für maximale Herzfrequenz | Optional |
| Körpergewicht | Optionale Energieverbrauchsschätzung | Optional |
| Körpergröße | Erweiterte Analysen | Optional |
| Ruheherzfrequenz | Intensitäts- und VO₂max-Schätzung | Optional |
| Maximale Herzfrequenz | Belastungszonen und Fitnessberechnung | Optional |
| Fitness-/Lauferfahrung | Auswahl des anfänglichen Trainingsplans | Für Trainingspläne |
| Aktuelles Leistungsniveau (im Konzept „Aktuelle Laufleistung“): aktuelle Zeit über eine Distanz oder Selbsteinschätzung | Einschätzung des Trainingsniveaus | Für Trainingspläne |
| Wöchentlicher Laufumfang (Minuten) | Ausgangsanalyse des Plans (OQ-0013) | Für Trainingspläne |
| Verfügbare Trainingstage | Trainingskalender | Für Trainingspläne |
| Übliche Trainingsdauer | Trainingsplanung | Optional |
| Koeffizienten des Banister-Modells (männlich, weiblich) | Nur für das Belastungsprofil Banister (OQ-0053) | Optional, ab Phase 2 |

**Festlegung (OQ-0065):** Lauferfahrung und Selbsteinschätzung sind bis Phase 2 zurückgestellt. Alter, Gewicht und Größe verlangen nur positive Zahlen.

**Akzeptanzkriterien:**
- [ ] Alle als „Optional“ markierten Felder können leer bleiben, ohne dass die Grundfunktionen gesperrt werden.
- [ ] Trainingstage und Trainingsdauer im Profil sind Standardwerte für neue Ziele (OQ-0038).
- [ ] Beim Erstellen eines Plans fragt die App fehlende Angaben ab. Pflicht sind nur die verfügbaren Trainingstage; ohne die übrigen Angaben entsteht ein konservativer Einstiegsplan (OQ-0010).

### FR-0003 — Gemessene maximale Herzfrequenz hat Vorrang
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 49
- **Verwandt:** FR-0004

Eine gemessene maximale Herzfrequenz ist einer altersbasierten Schätzung vorzuziehen.

**Akzeptanzkriterien:**
- [ ] Sind Messwert und Alter hinterlegt, rechnet die App mit dem Messwert.

### FR-0004 — Altersbasierte Näherung der maximalen Herzfrequenz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 51–55
- **Verwandt:** FR-0003, FR-0005, OQ-0012

Ist kein Wert bekannt, kann vorläufig `HFmax = 208 − 0,7 · Alter` verwendet werden.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet aus der Formel): Alter 40 ergibt 180 bpm.
- [ ] Der so ermittelte Wert ist als Schätzung gekennzeichnet (CON-0009).

### FR-0005 — Hinweis auf Streuung und Korrektur der Näherung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 57
- **Verwandt:** FR-0004

Die Näherung besitzt eine erhebliche individuelle Streuung. Der Nutzer kann den Wert jederzeit korrigieren.

**Akzeptanzkriterien:**
- [ ] Der Nutzer kann den Wert jederzeit ändern.
- [ ] Die Näherung wird nicht als individuell genauer Wert dargestellt.

### FR-0006 — Neuberechnung nach Änderung der Basiswerte
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 59
- **Verwandt:** FR-0058, OQ-0031

Änderungen an persönlichen Basiswerten müssen zu einer nachvollziehbaren Neuberechnung der davon abhängigen Fitnesswerte führen können.

**Akzeptanzkriterien:**
- [ ] Nach einer Änderung lassen sich abhängige Fitnesswerte neu berechnen.
- [ ] Ursprünglicher und neu berechneter Wert bleiben unterscheidbar (FR-0058).

## Randfälle und Fehlerverhalten
- Weder Alter noch maximale Herzfrequenz bekannt: Abhängige Funktionen sind nicht verfügbar, die App bittet um die Eingabe (OQ-0012).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0010](../migration/open-questions.md#oq-0010--welche-eingaben-sind-beim-einstieg-nötig) (entschieden): Welche Eingaben sind beim Einstieg nötig?
- [OQ-0012](../migration/open-questions.md#oq-0012--was-gilt-wenn-ruhepuls-oder-hfmax-fehlen) (entschieden): Was gilt, wenn Ruhepuls oder HFmax fehlen?
- [OQ-0013](../migration/open-questions.md#oq-0013--was-bedeutet-laufleistung) (entschieden): Was bedeutet „Laufleistung“?
- [OQ-0031](../migration/open-questions.md#oq-0031--ablauf-der-neuberechnung-historischer-werte) (entschieden): Ablauf der Neuberechnung historischer Werte
- [OQ-0038](../migration/open-questions.md#oq-0038--doppelte-eingaben-in-profil-und-ziel) (entschieden): Doppelte Eingaben in Profil und Ziel
- [OQ-0065](../migration/open-questions.md#oq-0065--lücken-aus-dem-plan-für-phase-1) (entschieden): Lücken aus dem Plan für Phase 1
<!-- END OQ -->

## Quellen
- SRC-001: §2, Z. 31–59
