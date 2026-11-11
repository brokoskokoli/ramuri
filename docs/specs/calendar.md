---
id: FEAT-017
title: Trainingskalender
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0171, FR-0172, FR-0173, FR-0174, FR-0175, FR-0176, FR-0177, FR-0178]
---

# Trainingskalender

## Ziel
Die App stellt alle geplanten und absolvierten Einheiten in einem Kalender dar.

## Funktionale Anforderungen

### FR-0171 — Kalender mit geplanten und absolvierten Einheiten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18, Z. 1130

Die App stellt alle geplanten und absolvierten Trainingseinheiten in einem Kalender dar.

**Akzeptanzkriterien:**
- [ ] Geplante und absolvierte Einheiten erscheinen im Kalender.

### FR-0172 — Ansichten und Kennzeichnungen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.1, Z. 1134–1137

Der Kalender bietet eine Wochen- und Monatsübersicht und zeigt geplante Trainings, abgeschlossene Trainings und gekennzeichnete ausgefallene Einheiten.

**Akzeptanzkriterien:**
- [ ] Beide Übersichten sind verfügbar.
- [ ] Die drei Zustände einer Einheit sind unterscheidbar.

### FR-0173 — Training verschieben, ersetzen, Ruhetage festlegen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.1, Z. 1138–1140
- **Verwandt:** OQ-0011, ADR-0010

Der Nutzer kann Trainings verschieben und ersetzen sowie Ruhetage festlegen.

**Festlegung (K53):** Ersetzen setzt die gewählte Art fest; sie bleibt bei jeder Neuberechnung, Dauer, Struktur und Intensität rechnet die App (ADR-0010, Nachtrag WP22). Liegt auf dem neuen Ruhetag eine Einheit, bietet die App das Verschieben auf einen Alternativtag derselben Woche an oder lässt die Einheit nach Bestätigung entfallen.

**Akzeptanzkriterien:**
- [ ] Jede der drei Aktionen ist im Kalender ausführbar und bleibt gespeichert.
- [ ] Auf einem festgelegten Ruhetag plant die App nur nach Bestätigung ein Training (OQ-0011).
- [ ] Eine ersetzte Einheit behält ihre Art nach einer Neuberechnung (K53).

### FR-0174 — Trainingszeiten und Erinnerungen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.1, Z. 1141–1142

Optional lassen sich Trainingszeiten definieren. Vor geplanten Trainings gibt es Erinnerungen.

**Akzeptanzkriterien:**
- [ ] Vor einem geplanten Training erfolgt eine Erinnerung.

### FR-0175 — Termine empfehlen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.1, Z. 1144–1148
- **Verwandt:** FR-0176

Die App kann neue Termine empfehlen.

Beispiel: „Der lange Dauerlauf passt besser auf Sonntag, da zwischen dem Tempotraining und dem langen Lauf mehr Erholungszeit liegt.“

**Akzeptanzkriterien:**
- [ ] Eine Empfehlung nennt ihren Grund.

### FR-0176 — Bestätigung vor Kalenderänderungen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.1, Z. 1150
- **Verwandt:** FR-0156, FR-0169, OQ-0011, OQ-0005

Der Nutzer bestätigt Änderungen, bevor bestehende Kalendereinträge verändert werden.

**Akzeptanzkriterien:**
- [ ] Ohne Bestätigung bleibt der Termin eines bestehenden Eintrags unverändert (OQ-0011).
- [ ] Art, Dauer, Distanz und Intensität künftiger Einheiten, auch die Umwandlung in einen Ruhetag, ändern sich ohne Bestätigung (OQ-0005, OQ-0011).
- [ ] Ein festgelegter Ruhetag wird nur nach Bestätigung aufgehoben (K53).

### FR-0177 — Prüfung beim Verschieben
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.2, Z. 1154–1159
- **Verwandt:** FR-0152, OQ-0079, OQ-0080

Wenn der Nutzer einen Termin verschiebt, prüft die App: Abstand zu intensiven Einheiten, verbleibende Trainingszeit, Belastung der betreffenden Woche und verfügbare Alternativtage.

**Akzeptanzkriterien:**
- [ ] Das Verschieben einer intensiven Einheit direkt neben eine andere wird als Konflikt erkannt.

### FR-0178 — Alternativen bei Konflikten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §18.2, Z. 1161

Bei Konflikten werden Alternativen vorgeschlagen.

**Akzeptanzkriterien:**
- [ ] Bei einem Konflikt erscheint mindestens eine Alternative, sofern ein Alternativtag verfügbar ist.
- [ ] Wird ein Ruhetag auf einen Tag mit Einheit gelegt, bietet die App einen Alternativtag derselben Woche zum Verschieben an, sofern einer verfügbar ist (K53).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0005](../migration/open-questions.md#oq-0005--welche-parameter-darf-das-modell-automatisch-ändern) (entschieden): Welche Parameter darf das Modell automatisch ändern?
- [OQ-0011](../migration/open-questions.md#oq-0011--automatische-plananpassung-oder-bestätigung) (entschieden): Automatische Plananpassung oder Bestätigung?
- [OQ-0079](../migration/open-questions.md#oq-0079--pulskriterium-für-absolvierte-intensive-einheiten) (non-blocking): Pulskriterium für absolvierte intensive Einheiten
- [OQ-0080](../migration/open-questions.md#oq-0080--bedeutung-von-verbleibende-trainingszeit-beim-verschieben) (non-blocking): Bedeutung von „verbleibende Trainingszeit“ beim Verschieben
<!-- END OQ -->

## Quellen
- SRC-001: §18, Z. 1128–1161
