---
id: FEAT-004
title: Aufzeichnung von Laufeinheiten
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0025, FR-0026, FR-0027, FR-0028, FR-0029, FR-0030, FR-0031, FR-0032, FR-0033, FR-0034, FR-0035, FR-0036, FR-0037, FR-0038, FR-0039, FR-0193, FR-0194, FR-0195, FR-0196, FR-0202, FR-0204]
---

# Aufzeichnung von Laufeinheiten

## Ziel
Der Nutzer zeichnet Läufe auf, steuert sie während des Trainings und erhält danach eine Zusammenfassung.

## Scope
- Start, Live-Anzeige, Steuerung und Abschluss einer Einheit
- Subjektive Angaben nach dem Lauf

## Nicht im Scope
- Läufe ohne GPS in Phase 1 (FR-0195)
- Berechnung der Bewegungswerte: siehe [data-quality.md](data-quality.md)

## Ablauf
1. Der Nutzer startet eine freie Einheit oder eine Einheit aus dem Plan.
2. Die App zeigt während des Laufs die Live-Werte.
3. Der Nutzer pausiert, setzt fort und beendet die Einheit.
4. Die App zeigt die Zusammenfassung, der Nutzer ergänzt subjektive Angaben.

## Funktionale Anforderungen

### FR-0025 — Freie oder geplante Einheit starten
- **Status:** Approved | **Phase:** 1 (frei), 2 (aus Plan)
- **Quelle:** SRC-001 §4.1, Z. 130

Der Nutzer startet eine freie Laufeinheit oder eine Trainingseinheit aus einem Trainingsplan.

**Akzeptanzkriterien:**
- [ ] Eine freie Einheit lässt sich ohne Trainingsplan starten.
- [ ] Eine geplante Einheit lässt sich aus dem Plan starten.

### FR-0026 — Pflichtanzeigen während des Trainings
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.1, Z. 132–140
- **Verwandt:** FR-0051, FR-0056, OQ-0012

Während des Trainings zeigt die App mindestens: verstrichene Zeit, aktuelle Geschwindigkeit oder Pace, durchschnittliche Pace, zurückgelegte Strecke, aktuelle Herzfrequenz (sofern verfügbar), Herzfrequenzzone sowie GPS- und Sensorstatus.

**Akzeptanzkriterien:**
- [ ] Alle genannten Werte sind sichtbar, sofern ihre Daten vorliegen.
- [ ] Ohne Herzfrequenz wird „nicht verfügbar“ statt 0 angezeigt.
- [ ] Fehlen Basiswerte für die Zonenberechnung, wird die Zone als nicht verfügbar angezeigt (OQ-0012).

### FR-0027 — Optionale Anzeigen während des Trainings
- **Status:** Approved | **Phase:** 1 (Rundenzeiten, Höhenmeter, Schrittfrequenz, Karte), 2 (Soll-/Ist-Vergleich, Belastungsbereich)
- **Quelle:** SRC-001 §4.1, Z. 142–148
- **Verwandt:** FR-0204, OQ-0041, OQ-0074

Optional zeigt die App Rundenzeiten, Höhenmeter, Schrittfrequenz, einen Soll-/Ist-Vergleich bei strukturierten Trainings und Hinweise zum geplanten Belastungsbereich.

**Festlegung (OQ-0074):** Dazu kommt in Phase 1 eine Karte mit der bisherigen Strecke auf einer eigenen Seite des Lauf-Bildschirms (FR-0204).

### FR-0028 — Training starten, pausieren, fortsetzen, beenden
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 152–157
- **Verwandt:** FR-0052

Der Nutzer kann ein Training starten, pausieren, fortsetzen und beenden.

**Akzeptanzkriterien:**
- [ ] Pausenzeit zählt nicht zur Bewegungszeit, aber zur Gesamtzeit (FR-0052).
- [ ] Nach dem Beenden ist der Lauf in der Historie vorhanden.

### FR-0029 — Automatisches Pausieren
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 158
- **Verwandt:** OQ-0037, OQ-0065, OQ-0068, OQ-0071

Optional pausiert die App das Training automatisch.

**Festlegung (OQ-0065):** Die Autopause ist standardmäßig aus.

**Akzeptanzkriterien:**
- [ ] Nach rund 10 s ohne Bewegung pausiert die Aufzeichnung, wenn die Funktion eingeschaltet ist (OQ-0037; Schwellen: PAR-014, PAR-015).

### FR-0030 — Manuelle Rundenmarkierung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 159

Der Nutzer kann Runden manuell markieren.

**Akzeptanzkriterien:**
- [ ] Eine markierte Runde erscheint in der Zusammenfassung mit ihrer Rundenzeit.

### FR-0031 — Akustische Trainingshinweise
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §4.2, Z. 160
- **Verwandt:** OQ-0044

Die App gibt akustische Trainingshinweise.

**Akzeptanzkriterien:**
- [ ] Einzeln schaltbare Sprachansagen: je Kilometer mit Zeit und Pace, Überschreitung des Pulsbereichs und Intervallwechsel (OQ-0044).

### FR-0032 — Warnung bei Überschreitung des Herzfrequenzbereichs
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §4.2, Z. 161

Die App warnt bei Überschreitung festgelegter Herzfrequenzbereiche.

**Akzeptanzkriterien:**
- [ ] Liegt die Herzfrequenz über dem festgelegten Bereich, erfolgt eine Warnung.
- [ ] Ohne Herzfrequenzwert erfolgt keine solche Warnung.

### FR-0033 — Hinweise zum nächsten Trainingsintervall
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §4.2, Z. 162

Die App gibt Hinweise zum nächsten Trainingsintervall.

**Akzeptanzkriterien:**
- [ ] Bei einer strukturierten Einheit wird das nächste Intervall angekündigt.

### FR-0034 — Aufzeichnung bei ausgeschaltetem Bildschirm
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 164
- **Verwandt:** OQ-0021

Ein Training muss auch bei ausgeschaltetem Smartphone-Bildschirm weiter aufgezeichnet werden können.

**Akzeptanzkriterien:**
- [ ] Ein Lauf mit ausgeschaltetem Bildschirm enthält durchgehende Daten über den gesamten Zeitraum.

### FR-0035 — Aufzeichnung ohne Pulssensor
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §25 Nr. 1, Z. 1396
- **Verwandt:** CON-0004, ACC-01, OQ-0021

Ein Nutzer kann einen Lauf vollständig ohne Pulssensor aufzeichnen.

**Akzeptanzkriterien:**
- [ ] Ein Lauf ohne Sensor wird vollständig aufgezeichnet und gespeichert (ACC-01).

### FR-0036 — Verbindungsabbruch verliert den übrigen Lauf nicht
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §25 Nr. 3, Z. 1398
- **Verwandt:** FR-0017, ACC-03

Ein Verbindungsabbruch führt nicht zum Verlust des übrigen Laufs.

**Akzeptanzkriterien:**
- [ ] Bricht der Sensor während des Laufs ab, bleiben GPS-Daten und Herzfrequenzwerte vor und nach dem Abbruch erhalten (ACC-03).

### FR-0037 — Zusammenfassung nach dem Lauf
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.3, Z. 168–180
- **Verwandt:** FR-0052, FR-0092, FR-0204, OQ-0037, OQ-0065, OQ-0074

Nach dem Lauf erscheint eine Zusammenfassung mit: Strecke, Bewegungszeit und Gesamtzeit, Durchschnitts- und Bestpace, Durchschnitts- und Maximalpuls, Herzfrequenzzonen, Höhenprofil, GPS-Karte, Rundenzeiten, Trainingsbelastung, Einordnung gegenüber vorherigen Einheiten und optional aktualisierter VO₂max-Schätzung.

**Festlegung (OQ-0065, OQ-0074):** Die Einordnung vergleicht die Pace. Die GPS-Karte zeigt die Route nach FR-0204: mit Einwilligung auf Kartenmaterial, sonst ohne.

**Akzeptanzkriterien:**
- [ ] Die Zusammenfassung erscheint nach dem Beenden.
- [ ] Nicht verfügbare Werte sind als nicht verfügbar ausgewiesen.
- [ ] Bestpace ist der schnellste zusammenhängende Kilometer; die Einordnung vergleicht mit dem Schnitt der letzten 5 Läufe (OQ-0037).

### FR-0038 — Subjektive Angaben erfassen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §4.3, Z. 182–187
- **Verwandt:** FR-0095, OQ-0059

Der Nutzer kann zusätzlich erfassen: subjektive Anstrengung (RPE, 0–10), allgemeines Befinden, Schmerzen oder Beschwerden und eine Freitextnotiz.

**Akzeptanzkriterien:**
- [ ] RPE-Werte außerhalb von 0–10 sind nicht speicherbar.
- [ ] Bei einer Angabe zu Schmerzen oder Beschwerden fragt die App, ob sie als Warnsignal gemeldet werden soll (FR-0203).
- [ ] Die Angaben sind freiwillig und bleiben dem Lauf zugeordnet. Das Befinden hat die Stufen 1–5 (PAR-169).
- [ ] Die RPE-Skala erklärt jede Stufe von 0 bis 10 mit dem Wortlaut aus PAR-105, auf Deutsch und Englisch, nicht mit den Borg-Ankern.

### FR-0039 — Subjektive Angaben in der Planung berücksichtigen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §4.3, Z. 189
- **Verwandt:** FR-0148, FR-0157

Diese Eingaben können bei der künftigen Trainingsplanung berücksichtigt werden.

**Akzeptanzkriterien:**
- [ ] Gemeldete Beschwerden können eine Plananpassung auslösen (FR-0157).

### FR-0193 — Laufende Sicherung und Wiederaufnahme
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.1, Z. 234; SRC-003 (OQ-0021, OQ-0061)
- **Verwandt:** FR-0034, FR-0036, OQ-0021, OQ-0061, OQ-0065

Die App sichert die Aufzeichnung laufend. Nach einem Abbruch, etwa durch Absturz, Neustart oder leeren Akku, bietet sie die Wiederaufnahme an. Der Nutzer wählt beim nächsten Start: denselben Lauf fortsetzen oder ihn als beendeten Lauf speichern. Eine Frist gibt es nicht.

**Festlegung (OQ-0065):** Die Ausfallzeit zählt zur Gesamtzeit, nicht zur Bewegungszeit.

**Akzeptanzkriterien:**
- [ ] Nach einem erzwungenen App-Abbruch sind die bis dahin gesicherten Daten vorhanden.
- [ ] Beim nächsten Start wird die Wiederaufnahme des Laufs angeboten.
- [ ] Beim Fortsetzen wird die Lücke markiert und die Strecke für sie nicht geschätzt.
- [ ] Beim Speichern entsteht ein beendeter Lauf aus den gesicherten Daten.

### FR-0194 — Verhalten bei GPS-Verlust
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §6.1, Z. 234; SRC-003 (OQ-0021)
- **Verwandt:** FR-0049, FR-0057, OQ-0021

Bei GPS-Verlust laufen Zeit und Puls weiter. Die Lücke wird markiert, und die Strecke wird für sie nicht geschätzt.

**Akzeptanzkriterien:**
- [ ] Während eines simulierten GPS-Ausfalls laufen Zeit und Puls weiter.
- [ ] Die Lücke ist markiert und erhöht die Strecke nicht.

### FR-0195 — Start nur mit Standortberechtigung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (OQ-0021)
- **Verwandt:** OQ-0021, OQ-0064

Ohne Standortberechtigung startet kein GPS-Lauf. Läufe ohne GPS gibt es in Phase 1 nicht; ein Laufbandmodus folgt in Phase 2 (FR-0196).

**Akzeptanzkriterien:**
- [ ] Ohne Berechtigung startet kein Lauf, und die App erklärt den Grund.

### FR-0202 — Schrittfrequenz aus dem Smartphone
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.1, Z. 146; SRC-003 (OQ-0052)
- **Verwandt:** FR-0027, FR-0021, OQ-0052

In Phase 1 liefert der Schrittsensor des Smartphones die Schrittfrequenz. Die App fragt dafür eine eigene Berechtigung an; ohne sie funktioniert die Aufzeichnung weiter.

**Akzeptanzkriterien:**
- [ ] Mit Berechtigung wird die Schrittfrequenz live angezeigt.
- [ ] Ohne Berechtigung ist sie als nicht verfügbar ausgewiesen, und der Lauf wird normal aufgezeichnet.

### FR-0204 — Karte der Route
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.3, Z. 168–180; §5.1, Z. 197; SRC-003 (OQ-0074)
- **Verwandt:** FR-0027, FR-0037, FR-0040, FR-0041, FR-0056, SEC-0002, SEC-0007, SEC-0008, SEC-0009, OQ-0074, ADR-0009

Die App zeigt die gelaufene Route auf einer Karte: während des Laufs auf einer eigenen Seite des Lauf-Bildschirms, in der Zusammenfassung und in der Detailansicht eines Laufs sowie als Miniatur je Lauf in der Trainingshistorie. Kartenmaterial kommt aus dem Netz vom Anbieter nach ADR-0009, nur nach ausdrücklicher Einwilligung, die der Nutzer jederzeit widerrufen kann. Ohne Einwilligung, ohne Netz oder bei Fehlern zeigt die App dieselbe Route ohne Kartenhintergrund.

**Festlegungen (OQ-0074):**
- Lauf-Bildschirm: Die Werte bleiben die erste Seite, die Karte ist per Wischen erreichbar. Sie folgt der aktuellen Position und zeigt die bisherige Strecke. Gezeichnet wird nur, solange die Seite sichtbar und der Bildschirm an ist. Die Aufzeichnung hängt nicht von der Karte ab.
- Einheitliche Darstellung in allen Ansichten: Strecke als Linie, Start und Ende markiert, Pausen und GPS-Lücken als Unterbrechung der Linie, nie als gerade Verbindung (FR-0056). Gezeichnet werden die gespeicherten Positionen, die die Vorverarbeitung akzeptiert hat.
- Miniatur: kleine, nicht bedienbare Karte mit der Route, mit Einwilligung auf Kartenhintergrund, sonst nur die Linie.
- Anfragen an den Anbieter enthalten nur die Koordinaten der Kacheln, keine Kennung, keine Lauf- oder Gesundheitsdaten und keine Cookies.
- Geladene Kacheln und Miniaturen werden nur verschlüsselt gespeichert (SEC-0009), mit fester Größengrenze. Sie gehören nicht in Archiv und Dateiexport. Nach dem Widerruf fragt die App, ob sie gelöscht werden sollen (SEC-0007); „Alles löschen“ löscht sie.
- Jede Karte mit Kartenhintergrund nennt die Quelle des Kartenmaterials, wie dessen Lizenz es verlangt.

**Akzeptanzkriterien:**
- [ ] Lauf-Bildschirm, Zusammenfassung, Detailansicht und Historie zeigen die Route, mit Einwilligung auf Kartenmaterial, ohne Einwilligung als Linie.
- [ ] SEC-0008: Ohne Einwilligung zeigt ein Netzwerkmitschnitt keine Verbindung; nach dem Widerruf keine neue.
- [ ] Pausen und GPS-Lücken erscheinen nicht als gerade Verbindung.
- [ ] Kacheln und Miniaturen liegen nicht im Klartext auf dem Datenträger.
- [ ] Die Aufzeichnung läuft unverändert, wenn die Karte nicht lädt oder die Seite gewechselt wird.
- [ ] Die Quellenangabe ist auf jeder Karte mit Kartenhintergrund sichtbar.

### FR-0196 — Laufbandmodus
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-003 (Maintainer 2026-11-03)
- **Verwandt:** FR-0195, OQ-0042

In Phase 2 gibt es einen Laufbandmodus, in dem der Nutzer die aktuelle Geschwindigkeit des Bands einstellen kann.

**Akzeptanzkriterien:**
- [ ] Der Nutzer kann die aktuelle Bandgeschwindigkeit während des Laufs einstellen.
- [ ] Die Strecke ergibt sich aus Geschwindigkeit mal Zeit; die Steigung ist optional einstellbar (OQ-0042).
- [ ] Die VO₂max entsteht höchstens als „vorläufig“; Belastung und Statistik zählen normal (OQ-0042).
- [ ] Der Modus braucht keine Standortberechtigung (FR-0195 gilt nur für GPS-Läufe).
- [ ] Die Bewegungszeit läuft, solange die eingestellte Geschwindigkeit über 0 liegt; die Autopause entfällt.
- [ ] Exportiert wird ohne GPS-Strecke als TCX und FIT, GPX ist nicht verfügbar (OQ-0042).
- [ ] Für die aerobe Effizienz gilt die GPS-Regel PAR-025; Laufbandläufe fließen deshalb derzeit nicht ein.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0012](../migration/open-questions.md#oq-0012--was-gilt-wenn-ruhepuls-oder-hfmax-fehlen) (entschieden): Was gilt, wenn Ruhepuls oder HFmax fehlen?
- [OQ-0021](../migration/open-questions.md#oq-0021--verhalten-bei-gps-problemen-und-abbrüchen-der-aufzeichnung) (entschieden): Verhalten bei GPS-Problemen und Abbrüchen der Aufzeichnung
- [OQ-0037](../migration/open-questions.md#oq-0037--details-von-aufzeichnung-und-zusammenfassung) (entschieden): Details von Aufzeichnung und Zusammenfassung
- [OQ-0041](../migration/open-questions.md#oq-0041--phasen-der-noch-nicht-zugeordneten-anforderungen) (entschieden): Phasen der noch nicht zugeordneten Anforderungen
- [OQ-0042](../migration/open-questions.md#oq-0042--details-des-laufbandmodus) (entschieden): Details des Laufbandmodus
- [OQ-0044](../migration/open-questions.md#oq-0044--inhalte-akustischer-hinweise) (entschieden): Inhalte akustischer Hinweise
- [OQ-0052](../migration/open-questions.md#oq-0052--quelle-der-schrittfrequenz-in-phase-1) (entschieden): Quelle der Schrittfrequenz in Phase 1
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0061](../migration/open-questions.md#oq-0061--bedeutung-der-wiederaufnahme) (entschieden): Bedeutung der Wiederaufnahme
- [OQ-0064](../migration/open-questions.md#oq-0064--technische-vorgaben-der-aufzeichnung) (non-blocking): Technische Vorgaben der Aufzeichnung
- [OQ-0065](../migration/open-questions.md#oq-0065--lücken-aus-dem-plan-für-phase-1) (entschieden): Lücken aus dem Plan für Phase 1
- [OQ-0068](../migration/open-questions.md#oq-0068--gps-rauschen-im-stand) (entschieden): GPS-Rauschen im Stand
- [OQ-0071](../migration/open-questions.md#oq-0071--strecke-während-der-erkannten-pause) (non-blocking): Strecke während der erkannten Pause
- [OQ-0074](../migration/open-questions.md#oq-0074--karte-der-route) (entschieden): Karte der Route
<!-- END OQ -->

## Quellen
- SRC-001: §4, Z. 126–189; §25 Nr. 1 und 3
