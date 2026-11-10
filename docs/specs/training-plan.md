---
id: FEAT-015
title: Erstellung des Trainingsplans
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0138, FR-0139, FR-0140, FR-0141, FR-0142, FR-0143, FR-0144, FR-0145, FR-0146, FR-0147, FR-0148, FR-0149, FR-0150, FR-0151, FR-0152, FR-0153, FR-0154, FR-0155]
---

# Erstellung des Trainingsplans

## Ziel
Die App erzeugt regelbasiert einen individuellen Trainingsplan auf Basis des Nutzerziels und der vorhandenen Daten.

## Nicht im Scope
- Laufende Anpassung: siehe [plan-adaptation.md](plan-adaptation.md)
- Kalender: siehe [calendar.md](calendar.md)

## Funktionale Anforderungen

### FR-0138 — Individuellen Plan erzeugen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15, Z. 906; §25 Nr. 8, Z. 1403
- **Verwandt:** ACC-08

Die App erzeugt auf Basis des Nutzerziels einen individuellen Trainingsplan.

**Akzeptanzkriterien:**
- [ ] Aus einem Ziel und verfügbaren Trainingstagen entsteht ein Plan (ACC-08).

### FR-0139 — Ausgangsanalyse
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.1, Z. 910–919
- **Verwandt:** OQ-0013, OQ-0027, OQ-0059, OQ-0060

Zunächst werden ausgewertet: gewünschtes Trainingsziel, Zeit bis zum Zieldatum, aktuelles Leistungsniveau, bisherige Trainingshäufigkeit, wöchentlicher Laufumfang, Belastungshistorie, aktueller Fitness- und Erholungszustand und verfügbare Trainingstage.

**Akzeptanzkriterien:**
- [ ] Unterschiedliche Trainingshistorien führen bei gleichem Ziel zu nachvollziehbar unterschiedlichen Startwerten.
- [ ] Die Ausgangsanalyse nutzt vorhandene Läufe oder die Angabe zum heutigen Stand (PAR-192).
- [ ] Das lockere Tempo entsteht aus vorhandenen Daten, ohne neue Eingabe (PAR-205).

### FR-0140 — Konservativer Einstiegsplan bei unzureichenden Daten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.1, Z. 921–923
- **Verwandt:** FR-0104, OQ-0010, OQ-0028, OQ-0048, OQ-0059, OQ-0060, OQ-0077

Wenn keine ausreichenden Daten vorliegen, wird ein konservativer Einstiegsplan erstellt. Der erste Trainingsabschnitt dient dann zugleich dem Aufbau einer individuellen Datenbasis.

**Akzeptanzkriterien:**
- [ ] Ohne Historie entsteht ein Plan, und der Einstiegscharakter ist erkennbar.
- [ ] Der Start folgt PAR-192, bei Bedarf mit der Geh-Lauf-Abfolge (PAR-065).
- [ ] Die Geh-Lauf-Abfolge läuft ohne leichtere Wochen (PAR-065), und jede Woche lässt sich wiederholen (PAR-140).
- [ ] Vor dem Geh-Lauf-Plan steht der Hinweis aus PAR-115.

### FR-0141 — Trainingsphasen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.2, Z. 927–938
- **Verwandt:** OQ-0027, OQ-0028, OQ-0059, OQ-0060, OQ-0077

Ein längerer Plan kann in Phasen unterteilt werden. Die Dauer hängt vom Ziel, Trainingsstand und verfügbaren Zeitraum ab.

| Phase | Hauptziel |
|---|---|
| Einstieg | Belastbarkeit und Ausgangsniveau bestimmen |
| Grundlagentraining | Aerobe Ausdauer und Trainingskontinuität |
| Aufbau | Trainingsumfang und spezifische Leistung entwickeln |
| Spezifisches Training | Vorbereitung auf das konkrete Laufziel |
| Reduktion vor Wettkampf | Belastung senken und Erholung ermöglichen |
| Zieltermin | Wettkampf oder Leistungstest |

**Festlegung (OQ-0077):** Im Phasenbalken des Plans stehen die Kurzformen Einstieg, Grundlage, Aufbau, Spezifisch, Reduktion, Ziel. Die Erklärung der Phase nennt den vollen Namen.

**Akzeptanzkriterien:**
- [ ] Der Plan zeigt Einstieg, Aufbau und bei einem Datum die Reduktion (PAR-192, PAR-199). Weitere Phasen sind zunächst nicht vorgesehen.

### FR-0142 — Trainingstypen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.3, Z. 942–953
- **Verwandt:** OQ-0004, OQ-0057

Der Plan kann enthalten: lockere Dauerläufe, längere Dauerläufe, Regenerationsläufe, Intervalle, Tempodauerläufe, progressive Läufe, optional Geh-/Laufintervalle für Anfänger und Ruhetage. Jede Einheit besitzt eine klare Zielsetzung.

**Akzeptanzkriterien:**
- [ ] Jede geplante Einheit nennt ihre Zielsetzung und ist nach [phase-2-3-rules.md](../phase-2-3-rules.md) aufgebaut.

### FR-0143 — Beschreibung einer Trainingseinheit
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.4, Z. 957–966
- **Verwandt:** OQ-0057

Eine Einheit enthält mindestens Bezeichnung, geplanten Tag, Trainingsziel, Dauer oder Distanz und Zielintensität sowie optional Aufwärmphase, Hauptabschnitte und Abwärmphase.

**Akzeptanzkriterien:**
- [ ] Jede geplante Einheit enthält alle Pflichtangaben.

### FR-0144 — Arten der Zielintensität
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.4, Z. 968–972
- **Verwandt:** OQ-0003

Die Zielintensität kann durch einen Herzfrequenzbereich, einen Pace-Bereich oder die subjektive Anstrengung definiert werden.

**Akzeptanzkriterien:**
- [ ] Alle drei Arten sind in einer Einheit darstellbar.

### FR-0145 — Keine genaue Pace aus unzureichender VO2max
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.4, Z. 974
- **Verwandt:** OQ-0028

Eine genaue Pace-Vorgabe darf nicht aus einer unzureichenden VO₂max-Schätzung abgeleitet werden.

**Akzeptanzkriterien:**
- [ ] Aus einer als unzureichend bewerteten Schätzung entsteht keine genaue Pace-Vorgabe.
- [ ] „Vorläufig“ und „nicht bestimmbar“ gelten als unzureichend (PAR-081).

### FR-0146 — Intervalle bevorzugt nach Pace oder RPE
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §15.4, Z. 976

Bei Intervallen können Pace oder RPE geeigneter sein als eine unmittelbare Herzfrequenzsteuerung, da der Puls verzögert reagiert.

**Akzeptanzkriterien:**
- [ ] Intervalleinheiten lassen sich über Pace oder RPE vorgeben.

### FR-0147 — Regelbasierte Planung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16, Z. 980
- **Verwandt:** NFR-0002, OQ-0028

Die Trainingsplanung erfolgt regelbasiert und berücksichtigt die vorhandenen Leistungsdaten.

**Akzeptanzkriterien:**
- [ ] Der Plan folgt den Regeln in [planning-rules.md](../planning-rules.md) in der benannten Version.

### FR-0148 — Wöchentliches Belastungsbudget
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.1, Z. 984–997
- **Verwandt:** FR-0039, OQ-0028, OQ-0059, OQ-0060

Für jede Woche wird ein geplanter Umfang und eine geplante Intensitätsverteilung bestimmt. Die Ausgangswerte ergeben sich aus dem bisherigen Training und den persönlichen Voraussetzungen. Die geplante Belastung wird bei ausreichender Erholung und guter Verträglichkeit schrittweise erhöht. Berücksichtigt werden: Belastungsniveau der vergangenen Wochen, bisherige Kontinuität, Anzahl der Trainingstage, Intensitätsverteilung, subjektive Beschwerden und Ermüdung sowie der Zeitpunkt des Zielwettkampfs.

**Akzeptanzkriterien:**
- [ ] Jede Planwoche enthält Umfang und Intensitätsverteilung.
- [ ] Gemeldete Beschwerden und Ermüdung fließen in das Wochenbudget ein.
- [ ] Die Wochenzeit folgt PAR-193, PAR-194 und PAR-199 und bleibt unter dem Regler (PAR-196).
- [ ] Ist der Regler oder die Zielspitze erreicht, bleibt die Wochenzeit gleich (PAR-196); die leichtere Woche nach PAR-194 gilt auch dann (K52).

### FR-0149 — Keine pauschale Steigerung als garantiert sicher
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.1, Z. 999
- **Verwandt:** OQ-0028

Es wird keine pauschale prozentuale Steigerung für alle Nutzer als garantiert sicher angenommen.

**Akzeptanzkriterien:**
- [ ] Die App bezeichnet keine Steigerungsrate als garantiert sicher.

### FR-0150 — Wochen mit reduziertem Umfang
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.1, Z. 1001
- **Verwandt:** OQ-0028

Regelmäßige Wochen mit reduziertem Trainingsumfang können vorgesehen werden.

**Akzeptanzkriterien:**
- [ ] Ein Plan kann Wochen mit reduziertem Umfang enthalten.

### FR-0151 — Verteilung der Einheiten
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.2, Z. 1005–1013
- **Verwandt:** OQ-0028, OQ-0059, OQ-0060

Bei drei Trainingstagen pro Woche wäre beispielsweise möglich: ein lockerer Dauerlauf, eine zielgerichtete intensivere Einheit und ein längerer, überwiegend lockerer Lauf. Für Einsteiger kann der Plan zunächst ausschließlich lockere beziehungsweise kombinierte Geh- und Lauftrainings enthalten. Der Anteil intensiver Einheiten richtet sich nach Leistungsstand, Belastbarkeit und Ziel.

**Akzeptanzkriterien:**
- [ ] Ein Einsteigerplan kann ohne intensive Einheiten erzeugt werden.
- [ ] Eine harte Einheit erscheint nur nach dem Schalter und den Bedingungen aus PAR-198, höchstens 1 je Woche.
- [ ] Der Schalter steht bei Zeitzielen auf an, sonst auf aus, und lässt sich jederzeit umstellen (PAR-198).

### FR-0152 — Intensive Einheiten nicht ohne Erholung hintereinander
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.2, Z. 1015
- **Verwandt:** FR-0177, OQ-0028

Intensive Trainingseinheiten sollen normalerweise nicht ohne ausreichende Erholung direkt aufeinanderfolgen.

**Akzeptanzkriterien:**
- [ ] Ein erzeugter Plan enthält im Normalfall keine zwei intensiven Einheiten ohne ausreichende Erholung direkt hintereinander.

### FR-0153 — Rangfolge für die Ableitung der Zielintensität
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.3, Z. 1019–1029
- **Verwandt:** FR-0145, OQ-0003, OQ-0057, OQ-0059

Die Intensitäten werden aus den verfügbaren Daten abgeleitet. Bevorzugt:

1. Individuell bestimmte Schwellenwerte oder geeignete Leistungstests
2. Aktuelle aussagekräftige Wettkampfleistungen
3. Ausreichend belastbare Pace-/Puls-Beziehungen
4. Allgemeine Herzfrequenzzonen
5. Subjektive Anstrengung, falls andere Daten fehlen

Die Unsicherheit der Intensitätsvorgaben muss bei fehlenden Daten berücksichtigt werden.

**Akzeptanzkriterien:**
- [ ] Liegen Daten mehrerer Stufen vor, wird die höchste verfügbare Stufe genutzt, mit der Ausnahme für Pace bei lockeren Läufen und Intervallen (OQ-0057, PAR-102, PAR-103).
- [ ] Die Zielintensität folgt der Zuordnung in [phase-2-3-rules.md](../phase-2-3-rules.md).
- [ ] Fehlen Daten, ist die Unsicherheit der Intensitätsvorgabe berücksichtigt.
- [ ] Die Bandbreite weitet nur das langsame Ende der Pace, die Grenze für lockere Läufe wird nicht geweitet (PAR-082, PAR-190).

### FR-0154 — Machbarkeit des Ziels beurteilen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §16.4, Z. 1033–1051
- **Verwandt:** FR-0137, OQ-0027, OQ-0059, OQ-0060

Die App soll beurteilen, ob das Ziel mit dem vorhandenen Zeitraum und Umfang plausibel erreichbar erscheint. Sie berücksichtigt aktuelles Leistungsniveau, Differenz zum Zielniveau, verfügbare Trainingswochen, Trainingshäufigkeit, bisherige Fortschrittsrate und den notwendigen Aufbau der Ausdauer.

Darstellung beispielsweise als: Ziel erscheint realistisch; Ziel ist ambitioniert; Ziel erscheint mit dem vorgesehenen Umfang eher unrealistisch; noch nicht ausreichend Daten vorhanden. Dies ist eine modellbasierte Einschätzung und keine Erfolgsgarantie.

**Akzeptanzkriterien:**
- [ ] Bei unzureichenden Daten weist die Einschätzung dies aus.
- [ ] Die Einschätzung wird nicht als Erfolgsgarantie dargestellt.
- [ ] Sie erfolgt nur bei Zielen mit Datum; ein offenes Ziel zeigt die Regelmäßigkeit (OQ-0027).
- [ ] Die Einschätzung folgt PAR-206.
- [ ] Bei einem zu knappen Datum nennt die App ein passendes Datum. Bleibt der Nutzer dabei, plant sie so weit wie möglich, ohne schneller zu steigern (PAR-206).
- [ ] Ein späteres Datum ergibt nie eine schlechtere Einschätzung.

### FR-0155 — Einfache Trainingsplanung nur mit dem Smartphone
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §1.1 Nr. 2, Z. 24; §22, Z. 1252
- **Verwandt:** CON-0004, OQ-0028

Einfache Trainingsplanung muss allein mit dem Smartphone funktionieren.

**Akzeptanzkriterien:**
- [ ] Ohne Wearable und ohne Gesundheitsdaten lässt sich ein Plan erzeugen.
- [ ] Der Plan braucht nur die Angaben aus PAR-192.

## Regeln und Startwerte

Die konkreten Werte stehen in [planning-rules.md](../planning-rules.md) und [phase-2-3-rules.md](../phase-2-3-rules.md).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0003](../migration/open-questions.md#oq-0003--herzfrequenzzonen-allein-oder-schwellenmodell) (entschieden): Herzfrequenzzonen allein oder Schwellenmodell?
- [OQ-0004](../migration/open-questions.md#oq-0004--welche-ziele-und-trainingsarten-zuerst) (entschieden): Welche Ziele und Trainingsarten zuerst?
- [OQ-0010](../migration/open-questions.md#oq-0010--welche-eingaben-sind-beim-einstieg-nötig) (entschieden): Welche Eingaben sind beim Einstieg nötig?
- [OQ-0013](../migration/open-questions.md#oq-0013--was-bedeutet-laufleistung) (entschieden): Was bedeutet „Laufleistung“?
- [OQ-0027](../migration/open-questions.md#oq-0027--pläne-ohne-zieldatum-und-bei-offenen-zielen) (entschieden): Pläne ohne Zieldatum und bei offenen Zielen
- [OQ-0028](../migration/open-questions.md#oq-0028--konkrete-regeln-der-trainingsplanung) (entschieden): Konkrete Regeln der Trainingsplanung
- [OQ-0048](../migration/open-questions.md#oq-0048--rechtliche-prüfung) (non-blocking): Rechtliche Prüfung
- [OQ-0057](../migration/open-questions.md#oq-0057--fehlende-regeln-für-phase-2-und-3) (entschieden): Fehlende Regeln für Phase 2 und 3
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0060](../migration/open-questions.md#oq-0060--einfacher-trainingsplan) (entschieden): Einfacher Trainingsplan
- [OQ-0077](../migration/open-questions.md#oq-0077--vorgaben-zum-start-von-phase-2) (entschieden): Vorgaben zum Start von Phase 2
<!-- END OQ -->

## Quellen
- SRC-001: §15, Z. 904–976; §16, Z. 978–1051
