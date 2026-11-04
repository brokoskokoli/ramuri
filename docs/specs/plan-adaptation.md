---
id: FEAT-016
title: Adaptive Anpassung des Trainingsplans
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0156, FR-0157, FR-0158, FR-0159, FR-0160, FR-0161, FR-0162, FR-0163, FR-0164, FR-0165, FR-0166, FR-0167, FR-0168, FR-0169, FR-0170, FR-0203]
---

# Adaptive Anpassung des Trainingsplans

## Ziel
Der Plan folgt den tatsächlich absolvierten Einheiten, statt statisch zu bleiben.

**Entschieden:** Inhalt und Intensität künftiger Einheiten passt die App selbst an und begründet größere Änderungen. Termine ändert sie nur nach Bestätigung (OQ-0011). Sie bleibt dabei innerhalb der Trainingstage und der maximalen Zeit je Einheit (OQ-0005).

## Funktionale Anforderungen

### FR-0156 — Fortlaufende Anpassung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17, Z. 1055
- **Verwandt:** CON-0006, OQ-0005, OQ-0011, OQ-0060

Der Trainingsplan wird fortlaufend an tatsächlich absolvierte Trainingseinheiten angepasst.

**Akzeptanzkriterien:**
- [ ] Nach einem abgeschlossenen Lauf spiegelt der Plan das Ergebnis wider.
- [ ] Inhalt und Intensität künftiger Einheiten ändern sich ohne Bestätigung; Terminänderungen gelten erst nach Bestätigung (OQ-0011).
- [ ] Automatische Änderungen überschreiten nie die Trainingstage und die maximale Zeit pro Einheit des Nutzers (OQ-0005).
- [ ] Die App fragt alle 2 Wochen „zu leicht, passt oder zu schwer?“ und passt die Wochenzeit an (PAR-200).
- [ ] Von selbst nimmt die App nur zurück und steigert nie stärker als PAR-193 (PAR-201).

### FR-0157 — Auslöser einer Neuberechnung
- **Status:** Approved | **Phase:** 2, 3 (Erholung)
- **Quelle:** SRC-001 §17.1, Z. 1059–1069; §25 Nr. 9, Z. 1404
- **Verwandt:** ACC-09, FR-0039, OQ-0022, OQ-0058, OQ-0059

Eine Neuberechnung kann ausgelöst werden durch: abgeschlossenen Lauf, ausgefallenes Training, zusätzliches Training, deutliche Änderung der Trainingsbelastung, Veränderungen der langfristigen Leistungsentwicklung, veränderten Erholungszustand, Änderungen des Trainingsziels, Änderungen der verfügbaren Trainingstage und Nutzerfeedback zu Schmerzen, Krankheit oder Überlastung.

**Akzeptanzkriterien:**
- [ ] Der Plan reagiert auf zusätzliche und auf ausgefallene Einheiten (ACC-09).
- [ ] Jeder genannte Auslöser kann eine Neuberechnung des Plans auslösen.
- [ ] Eine Neuberechnung wegen eines veränderten Erholungszustands ändert nur die intensive Einheit an dessen Tag (PAR-173, OQ-0058).

### FR-0158 — Mindestens wöchentliche Überprüfung
- **Status:** Approved | **Phase:** 2, 3 (Erholung)
- **Quelle:** SRC-001 §17.2, Z. 1073–1084
- **Verwandt:** OQ-0005, OQ-0011

Die App überprüft den Plan mindestens wöchentlich. Ausgewertet werden geplanter und tatsächlicher Umfang, durchgeführte Trainingsarten, Belastungsentwicklung, Leistungsentwicklung, Konsistenz der Teilnahme und verfügbare Erholungsdaten. Daraufhin werden zukünftige Einheiten angepasst.

**Akzeptanzkriterien:**
- [ ] Bei aktivem Plan findet mindestens wöchentlich eine Prüfung statt.
- [ ] Bereits absolvierte Einheiten bleiben unverändert.

### FR-0159 — Kurzfristige Empfehlung vor einer Einheit
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1088–1090
- **Verwandt:** FR-0179

Vor einer geplanten Trainingseinheit kann die App eine erneute Empfehlung ausgeben.

**Akzeptanzkriterien:**
- [ ] Eine geänderte Empfehlung nennt die ursprüngliche Einheit und den Grund.

### FR-0160 — Anpassung bei hoher Belastung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1092–1096
- **Verwandt:** OQ-0028

Beispiel: Aus einem intensiven Intervalltraining wird ein lockerer Dauerlauf oder ein Ruhetag.

**Akzeptanzkriterien:**
- [ ] Bei hoher Belastung kann die App statt des Intervalltrainings einen lockeren Dauerlauf oder Ruhetag empfehlen.

### FR-0161 — Anpassung bei deutlich besserer Leistungsentwicklung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1098–1102
- **Verwandt:** FR-0165

Beispiel: Ein Dauerlauf mit älterem Zieltempo erhält einen moderat aktualisierten Zielbereich auf Grundlage mehrerer geeigneter Einheiten.

**Akzeptanzkriterien:**
- [ ] Der Zielbereich ändert sich erst nach mehreren geeigneten Einheiten (PAR-186).

### FR-0162 — Anpassung bei ausgefallenem Training
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1104–1108
- **Verwandt:** FR-0164, OQ-0011

Beispiel: Fällt das Intervalltraining am Dienstag aus, wird die Woche neu verteilt, ohne automatisch sämtliche ausgefallenen Einheiten nachzuholen.

**Akzeptanzkriterien:**
- [ ] Nach einem Ausfall enthält die Woche nicht automatisch alle ausgefallenen Einheiten zusätzlich.
- [ ] Neue Termine gelten erst nach Bestätigung (OQ-0011).

### FR-0163 — Anpassung bei Beschwerden oder Krankheit
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1110–1114
- **Verwandt:** FR-0118, OQ-0026, OQ-0048

Beispiel: Statt eines langen Dauerlaufs schlägt die App keine intensive Einheit vor; bei entsprechenden Warnsignalen empfiehlt sie eine Trainingspause und gegebenenfalls eine medizinische Abklärung.

**Akzeptanzkriterien:**
- [ ] Nach gemeldeten Beschwerden oder Krankheit wird keine intensive Einheit vorgeschlagen; bei einem Warnsignal gilt FR-0203.
- [ ] Warnsignale sind vom Nutzer gemeldete Schmerzen, Krankheit oder Überlastung; die App empfiehlt dann mit festem, neutralem Text Pause und gegebenenfalls ärztliche Abklärung (OQ-0026).
- [ ] Die App leitet aus Messwerten keine medizinische Bewertung ab (OQ-0026).

### FR-0203 — Warnsignal melden und aufheben
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.3, Z. 1110–1114; SRC-003 (OQ-0055)
- **Verwandt:** FR-0163, FR-0118, OQ-0026, OQ-0048, OQ-0055, OQ-0058

Der Nutzer kann Schmerzen, Krankheit oder Überlastung jederzeit im Plan melden und die Meldung wieder aufheben. Solange sie besteht, plant die App nur Ruhetage (OQ-0058). Nach 7 Tagen erinnert sie an die Meldung.

Fester Text, Wortlaut vorbehaltlich der rechtlichen Prüfung (OQ-0048):

- **Deutsch:** „Du hast Beschwerden gemeldet. Wir empfehlen dir, das Training zu pausieren. Wenn die Beschwerden anhalten oder stark sind, lass sie ärztlich abklären. Diese App stellt keine Diagnose.“
- **Englisch:** “You reported symptoms. We recommend pausing your training. If they persist or are severe, please see a doctor. This app does not provide a diagnosis.”

**Akzeptanzkriterien:**
- [ ] Die Meldung ist ohne Bezug zu einem Lauf möglich.
- [ ] Solange sie besteht, enthält der Plan nur Ruhetage, auch nach einer Neuberechnung.
- [ ] Nach 7 Tagen erinnert die App daran; die Meldung endet nur durch den Nutzer.

## Planungsregeln

Die Quelle leitet FR-0164 bis FR-0170 mit „Folgende Regeln gelten grundsätzlich“ ein (Z. 1118). Sie gelten also als Grundsatz; Ausnahmen nennt die Quelle nicht.

### FR-0164 — Kontinuität vor exaktem Nachholen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 1, Z. 1118–1120

Langfristige Kontinuität ist wichtiger als das exakte Nachholen einzelner Einheiten.

**Akzeptanzkriterien:**
- [ ] Siehe FR-0162.

### FR-0165 — Keine starke Erhöhung nach einer einzelnen Messung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 2, Z. 1121

Die Trainingsbelastung soll nicht aufgrund einer einzelnen positiven Messung stark erhöht werden.

**Akzeptanzkriterien:**
- [ ] Ein einzelner sehr guter Lauf führt nicht zu einer starken Belastungserhöhung.

### FR-0166 — Konservative Anpassung bei Überlastungssignalen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 3, Z. 1122
- **Verwandt:** OQ-0026, OQ-0028

Deutliche Überlastungssignale sollen konservative Anpassungen auslösen.

**Akzeptanzkriterien:**
- [ ] Ein Überlastungssignal erhöht die geplante Belastung nicht.

### FR-0167 — Pausen und Wiedereinstiege berücksichtigen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 4, Z. 1123
- **Verwandt:** OQ-0028, OQ-0059, OQ-0060

Pausen und Wiedereinstiege werden berücksichtigt.

**Akzeptanzkriterien:**
- [ ] Nach einer längeren Pause setzt der Plan nicht unverändert auf dem vorherigen Belastungsniveau fort.
- [ ] Der Neustart folgt PAR-202.

### FR-0168 — Ziel nur mit Zustimmung ändern
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 5, Z. 1124

Ein Trainingsziel wird nicht ohne Zustimmung des Nutzers verändert.

**Akzeptanzkriterien:**
- [ ] Ohne Zustimmung bleibt das Ziel nach jeder Neuberechnung unverändert.

### FR-0169 — Nutzer behält die Kontrolle über Termine
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 6, Z. 1125
- **Verwandt:** FR-0176, OQ-0011

Der Nutzer behält die Kontrolle über die Trainingstermine.

**Akzeptanzkriterien:**
- [ ] Der Nutzer kann jeden geplanten Termin selbst ändern.

### FR-0170 — Größere Änderungen begründen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.4 Nr. 7, Z. 1126; §25 Nr. 10, Z. 1405
- **Verwandt:** FR-0180, ACC-10, OQ-0028, OQ-0060

Größere Änderungen werden begründet.

**Akzeptanzkriterien:**
- [ ] Jede größere Planänderung zeigt eine Begründung (ACC-10).
- [ ] Als größere Änderung gilt, was PAR-204 nennt.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0005](../migration/open-questions.md#oq-0005--welche-parameter-darf-das-modell-automatisch-ändern) (entschieden): Welche Parameter darf das Modell automatisch ändern?
- [OQ-0011](../migration/open-questions.md#oq-0011--automatische-plananpassung-oder-bestätigung) (entschieden): Automatische Plananpassung oder Bestätigung?
- [OQ-0022](../migration/open-questions.md#oq-0022--wie-gelangen-trainings-außerhalb-der-app-in-die-daten) (entschieden): Wie gelangen Trainings außerhalb der App in die Daten?
- [OQ-0026](../migration/open-questions.md#oq-0026--warnsignale-medizinische-hinweise-und-einordnung-als-medizinprodukt) (entschieden): Warnsignale, medizinische Hinweise und Einordnung als Medizinprodukt
- [OQ-0028](../migration/open-questions.md#oq-0028--konkrete-regeln-der-trainingsplanung) (entschieden): Konkrete Regeln der Trainingsplanung
- [OQ-0048](../migration/open-questions.md#oq-0048--rechtliche-prüfung) (non-blocking): Rechtliche Prüfung
- [OQ-0055](../migration/open-questions.md#oq-0055--eingabeweg-und-dauer-von-warnsignalen) (entschieden): Eingabeweg und Dauer von Warnsignalen
- [OQ-0058](../migration/open-questions.md#oq-0058--entscheidungen-aus-der-prüfung-von-phase-2-und-3) (entschieden): Entscheidungen aus der Prüfung von Phase 2 und 3
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0060](../migration/open-questions.md#oq-0060--einfacher-trainingsplan) (entschieden): Einfacher Trainingsplan
<!-- END OQ -->

## Quellen
- SRC-001: §17, Z. 1053–1126; §25 Nr. 9 und 10
