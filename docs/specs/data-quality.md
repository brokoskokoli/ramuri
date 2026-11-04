---
id: FEAT-006
title: Datenqualität und gemeinsame Berechnungsgrundlagen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0045, FR-0046, FR-0047, FR-0048, FR-0049, FR-0050, FR-0051, FR-0052, FR-0053, FR-0054, FR-0055, FR-0056, FR-0057, FR-0058, FR-0059]
---

# Datenqualität und gemeinsame Berechnungsgrundlagen

## Ziel
Querschnittsregeln für alle Berechnungen: Vorverarbeitung, Bewegungswerte, Qualitätsangaben, Umgang mit fehlenden Daten und Neubewertung. Andere Specs verweisen hierher, statt die Regeln zu wiederholen.

**Phase `1*`:** §24 nennt diese Punkte nicht, die Fitnessberechnungen aus Phase 1 setzen sie aber voraus.

## Funktionale Anforderungen

### FR-0045 — Keine Fitnessberechnung auf ungefilterten Daten
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6, Z. 218–220

Fitnessberechnungen sollen nicht unmittelbar auf ungefilterten Sensordaten stattfinden. Vor der eigentlichen Berechnung wird eine gemeinsame Qualitätsbewertung durchgeführt.

**Akzeptanzkriterien:**
- [ ] Ein offensichtlicher Sensorausreißer verändert das Berechnungsergebnis nicht ungefiltert.

### FR-0046 — Synchronisation über Zeitstempel
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6.1, Z. 224

Die Aufzeichnungen werden anhand ihrer Zeitstempel synchronisiert.

**Akzeptanzkriterien:**
- [ ] Werte verschiedener Quellen werden über ihre Zeitstempel einander zugeordnet.

### FR-0047 — Zu berücksichtigende Datenprobleme
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6.1, Z. 226–235
- **Verwandt:** OQ-0019

Zu berücksichtigen sind: GPS-Ungenauigkeiten, unplausible Positionssprünge, fehlende Herzfrequenzwerte, offensichtliche Sensorausreißer, zeitliche Verzögerung der Herzfrequenz, Trainingspausen, Messunterbrechungen und Höhenmessungsfehler.

**Akzeptanzkriterien:**
- [ ] Für jedes genannte Problem existiert ein Testfall mit definiertem Ergebnis.
- [ ] Es gelten die Schwellenwerte PAR-001 bis PAR-015 aus [model-parameters.md](../model-parameters.md).

### FR-0048 — Qualitätsbewertung je Abschnitt
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6.1, Z. 237
- **Verwandt:** OQ-0019

Jeder für eine Fitnessberechnung verwendete Abschnitt erhält eine Qualitätsbewertung.

**Akzeptanzkriterien:**
- [ ] Zu jedem verwendeten Abschnitt ist eine Bewertung gespeichert.

### FR-0049 — Strecke aus plausiblen Positionsdistanzen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.2, Z. 241

Die zurückgelegte Strecke ergibt sich aus der Summe plausibler Positionsdistanzen.

**Akzeptanzkriterien:**
- [ ] Ein unplausibler Positionssprung erhöht die Strecke nicht.

### FR-0050 — Geschwindigkeit und Pace
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.2, Z. 243–253
- **Verwandt:** OQ-0037

Für die momentane Geschwindigkeit gilt `v = Δs / Δt`. Die Pace wird in Minuten beziehungsweise Sekunden pro Kilometer dargestellt: `Pace[s/km] = 1000 / v[m/s]`.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet aus der Formel): 4 m/s ergibt 250 s/km.
- [ ] Im Stillstand wird die Pace als „–“ angezeigt (OQ-0037).

### FR-0051 — Geglättete Tempoanzeige
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.2, Z. 255
- **Verwandt:** OQ-0019

Für kurzfristige Tempoanzeigen werden geeignete gleitende Zeit- oder Distanzfenster verwendet, damit GPS-Schwankungen nicht zu ständig springenden Werten führen.

**Akzeptanzkriterien:**
- [ ] Die Anzeige verwendet ein gleitendes Fenster statt des rohen Einzelwerts.
- [ ] Fensterart und -größe folgen PAR-005.

### FR-0052 — Bewegungszeit und Gesamtzeit getrennt
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.2, Z. 257
- **Verwandt:** OQ-0068

Die Bewegungszeit wird von der gesamten verstrichenen Zeit getrennt.

**Akzeptanzkriterien:**
- [ ] Bei einem Lauf mit Pause ist die Bewegungszeit kleiner als die Gesamtzeit.

### FR-0053 — Metadaten jedes fortgeschrittenen Fitnesswerts
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6.3, Z. 261–269
- **Verwandt:** CON-0005, CON-0009, NFR-0001, OQ-0019, OQ-0040, OQ-0059

Jeder fortgeschrittene Fitnesswert besitzt zusätzlich: Berechnungszeitpunkt, zugrunde liegenden Datenzeitraum, Anzahl verwertbarer Messungen, Datenquellen, verwendete Berechnungsmethode, Versionsstand der Berechnung und eine Qualitätsstufe (vorläufig, ausreichend, gut oder nicht bestimmbar).

**Akzeptanzkriterien:**
- [ ] Zu VO₂max, aerober Effizienz, Drift, Readiness, Energiereserve (ab Phase 4, DEC-0060) und Prognosen sind alle sieben Angaben abrufbar; TRIMP, ATL und CTL tragen Methode und Version (OQ-0040).
- [ ] Die Qualitätsstufen werden nach PAR-036 bis PAR-043 und PAR-047 vergeben, für spätere Werte nach [phase-2-3-rules.md](../phase-2-3-rules.md).

### FR-0054 — Qualitätsstufen sind keine Genauigkeitsangaben
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §6.3, Z. 271
- **Verwandt:** NFR-0003

Die Qualitätsstufen sind zunächst produktinterne Regeln. Sie dürfen nicht als statistisch validierte Genauigkeitsangaben dargestellt werden.

**Akzeptanzkriterien:**
- [ ] Keine Anzeige setzt eine Qualitätsstufe mit einer statistischen Genauigkeit gleich.

### FR-0055 — Funktionen je Datenverfügbarkeitsstufe
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §22, Z. 1248–1257
- **Verwandt:** CON-0004, CON-0007, OQ-0012, OQ-0034

Die App arbeitet mit unterschiedlichen Datenverfügbarkeitsstufen.

| Datenbasis | Verfügbare Funktionen |
|---|---|
| Nur Smartphone/GPS | Laufaufzeichnung, Pace, Strecke, Grundstatistik, einfache Trainingsplanung |
| GPS + Herzfrequenz | Herzfrequenzzonen, TRIMP, erste VO₂max-Schätzungen, aerobe Effizienz |
| Mehrwöchige Trainingshistorie | ATL/CTL, Fitness-Trends, verbesserte adaptive Trainingsplanung |
| Zusätzlich valide HRV-/Schlafdaten | Erweiterte Training Readiness |
| Kontinuierliche Tages- und Schlafdaten | Optionaler Energiereserve-Verlauf |
| Geeignete Wettkampfdaten | Leistungsprognosen und verbesserte Zielplanung |

**Entschieden (OQ-0012):** Die Funktionen der zweiten Zeile brauchen zusätzlich Profilwerte. Fehlen sie, ist die Funktion nicht verfügbar und die App bittet um die Eingabe. TRIMP braucht HFmax; Reservezonen und VO₂max brauchen zusätzlich den Ruhepuls. Die HFmax-Altersnäherung ist erlaubt und als Schätzung markiert.

**Akzeptanzkriterien:**
- [ ] Mit nur Smartphone und GPS funktionieren alle in der ersten Zeile genannten Funktionen, jeweils ab ihrer Phase.
- [ ] Fehlt ein nötiger Profilwert, zeigt die betroffene Funktion „nicht verfügbar“ und einen Hinweis zur Eingabe.

### FR-0056 — Fehlender Sensorwert ist keine Nullmessung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §22, Z. 1259

Ein fehlender Sensorwert darf nicht als Nullmessung interpretiert werden.

**Akzeptanzkriterien:**
- [ ] Eine Lücke in der Herzfrequenz senkt den Durchschnittspuls nicht.

### FR-0057 — Vier Zustände eines Messwerts
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §22, Z. 1261–1266
- **Verwandt:** CON-0009

Die App unterscheidet ausdrücklich zwischen: Messwert vorhanden, Messwert geschätzt, Messwert nicht verfügbar, Messwert wegen schlechter Qualität verworfen.

**Akzeptanzkriterien:**
- [ ] Für jeden der vier Zustände existiert ein unterscheidbarer gespeicherter und angezeigter Zustand.

### FR-0058 — Ursprüngliche und neu berechnete Werte unterscheiden
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §23.2, Z. 1311–1317
- **Verwandt:** FR-0006, NFR-0001, OQ-0031

Eine Änderung des Algorithmus oder persönlicher Basiswerte kann dazu führen, dass historische Fitnesswerte neu berechnet werden müssen. Die App soll dann unterscheiden können zwischen ursprünglich berechnetem Wert, aktuell neu berechnetem Wert und ursprünglicher Datenqualität.

**Akzeptanzkriterien:**
- [ ] Nach einer Neuberechnung sind alle drei Angaben abrufbar.
- [ ] Rohdaten bleiben erhalten, solange der Lauf existiert (OQ-0031).
- [ ] Nach einer Änderung bietet die App die Neuberechnung an und startet sie erst nach Bestätigung (OQ-0031).
- [ ] Danach werden die neuen Werte angezeigt, gekennzeichnet mit Methode und Version (OQ-0031).

### FR-0059 — Nachvollziehbarkeit eines geschätzten Werts
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §23.3, Z. 1321–1328; §25 Nr. 6, Z. 1401
- **Verwandt:** CON-0005, FR-0181, ACC-06

Ein geschätzter Fitnesswert soll mindestens beantworten: Aus welchen Daten wurde er berechnet? Wie alt sind diese Daten? Wie viele geeignete Messungen wurden verwendet? Welche Methode wurde verwendet? Ist das Ergebnis ausreichend zuverlässig? Wurde der Wert direkt gemessen oder geschätzt?

Der Nutzer kann nachvollziehen, warum ein Fitnesswert berechnet oder nicht berechnet wurde.

**Akzeptanzkriterien:**
- [ ] Alle sechs Fragen lassen sich für einen berechneten Wert in der App beantworten.
- [ ] Bei einem nicht berechneten Wert ist der Grund sichtbar (ACC-06).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0012](../migration/open-questions.md#oq-0012--was-gilt-wenn-ruhepuls-oder-hfmax-fehlen) (entschieden): Was gilt, wenn Ruhepuls oder HFmax fehlen?
- [OQ-0019](../migration/open-questions.md#oq-0019--startwerte-der-modellparameter-und-qualitätsregeln) (entschieden): Startwerte der Modellparameter und Qualitätsregeln
- [OQ-0031](../migration/open-questions.md#oq-0031--ablauf-der-neuberechnung-historischer-werte) (entschieden): Ablauf der Neuberechnung historischer Werte
- [OQ-0034](../migration/open-questions.md#oq-0034--datengrundlage-von-leistungsprognosen) (entschieden): Datengrundlage von Leistungsprognosen
- [OQ-0037](../migration/open-questions.md#oq-0037--details-von-aufzeichnung-und-zusammenfassung) (entschieden): Details von Aufzeichnung und Zusammenfassung
- [OQ-0040](../migration/open-questions.md#oq-0040--was-ist-ein-fortgeschrittener-fitnesswert) (entschieden): Was ist ein „fortgeschrittener Fitnesswert“?
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0068](../migration/open-questions.md#oq-0068--gps-rauschen-im-stand) (non-blocking): GPS-Rauschen im Stand
<!-- END OQ -->

## Quellen
- SRC-001: §6, Z. 216–271; §22, Z. 1246–1266; §23.2–23.3, Z. 1309–1328
