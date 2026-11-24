---
id: FEAT-004
title: Aufzeichnung von Laufeinheiten
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0025, FR-0026, FR-0027, FR-0028, FR-0029, FR-0030, FR-0031, FR-0032, FR-0033, FR-0034, FR-0035, FR-0036, FR-0037, FR-0038, FR-0039, FR-0193, FR-0194, FR-0195, FR-0196, FR-0202, FR-0204, FR-0210, FR-0218, FR-0221]
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
- **Verwandt:** FR-0210, OQ-0075

Der Nutzer startet eine freie Laufeinheit oder eine Trainingseinheit aus einem Trainingsplan.

**Festlegung (OQ-0075):** Vor dem Start steht die Seite „Lauf vorbereiten“ nach FR-0210.

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

**Festlegung (K63):** Bei einer geführten Einheit zeigt eine eigene, in beiden Modi dunkle Seite Abschnitt, Restzeit, Soll und Ist als Text und den nächsten Abschnitt; der Pace-Balken des Designs entfällt. Hinweise zum Pulsbereich nach PAR-107.

### FR-0028 — Training starten, pausieren, fortsetzen, beenden
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 152–157
- **Verwandt:** FR-0052, OQ-0075, OQ-0076

Der Nutzer kann ein Training starten, pausieren, fortsetzen und beenden.

**Festlegung (OQ-0075):** Wie im Design gibt es „Beenden“ erst im pausierten Zustand, neben „Weiter“. Beenden fragt kurz nach, damit ein versehentliches Tippen den Lauf nicht abschließt.

**Festlegung (OQ-0076):** Die Zurück-Taste fragt im laufenden Lauf, ob er pausiert werden soll („Pausieren“ / „Weiterlaufen“). Die Aufzeichnung läuft bis zur Antwort unverändert weiter.

**Akzeptanzkriterien:**
- [ ] Pausenzeit zählt nicht zur Bewegungszeit, aber zur Gesamtzeit (FR-0052).
- [ ] Nach dem Beenden ist der Lauf in der Historie vorhanden.

### FR-0029 — Automatisches Pausieren
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.2, Z. 158
- **Verwandt:** FR-0210, OQ-0037, OQ-0065, OQ-0068, OQ-0071, OQ-0075

Optional pausiert die App das Training automatisch.

**Festlegung (OQ-0065, OQ-0075):** Die Autopause ist standardmäßig aus. Sie wird auf der Seite „Lauf vorbereiten“ (FR-0210) ein- oder ausgeschaltet.

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

**Festlegung (K63):** Die Ansagen nutzen die Sprachausgabe des Systems, ohne Netz aus der App. Sie werden als Datei erzeugt und im Prozess der App abgespielt (Entscheidung des Maintainers 2026-11-13, wegen der Härtung von Hintergrund-Audio unter Android 17); die Datei liegt im Cache und wird nach jeder Ansage gelöscht. Hauptschalter „Ansagen“ auf „Lauf vorbereiten“, die Einzelschalter in den Einstellungen; sie gelten ab dem Start des Laufs. Beenden bricht eine laufende Ansage ab, Pause nicht. Fehler der Sprachausgabe stören die Aufzeichnung nicht. Fehlt die Sprachausgabe (keine Engine oder Sprache), zeigt die App bei einer geführten Einheit mit eingeschalteten Ansagen beim Start und nach Wiederaufnahme einmal „Sprachausgabe nicht verfügbar“; bei freien Läufen nicht (K71).

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

**Festlegung (K63):** Abschnitte laufen nur nach Zeit oder bis der Nutzer überspringt (FR-0218), gemessen in Bewegungszeit; Pause und Autopause halten den Abschnitt an. Angesagt werden jeder Wechsel und das Ende der Einheit, dazu 10 s vorher der nächste Abschnitt (nicht bei Abschnitten bis 20 s).

**Akzeptanzkriterien:**
- [ ] Bei einer strukturierten Einheit wird das nächste Intervall angekündigt.

### FR-0218 — Abschnitt einer geführten Einheit überspringen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-003 (Entscheidung des Maintainers 2026-11-15)
- **Verwandt:** FR-0027, FR-0031, FR-0033, K63

Während einer geführten Einheit kann der Nutzer den laufenden Abschnitt überspringen, auch Auf- und Abwärmen und den letzten. Der nächste Abschnitt beginnt sofort mit seiner vollen Dauer und wird angesagt; die folgenden Abschnitte rücken nach. Nach dem letzten Abschnitt meldet die App „Einheit fertig“, der Lauf läuft frei weiter. Einige Sekunden lang lässt sich der Sprung rückgängig machen; eine Rückfrage gibt es nicht. Die Aufzeichnung bleibt unverändert, die Einheit zählt im Plan als absolviert. Ein Wiederanlauf nach Abbruch setzt am erreichten Abschnitt fort.

**Umsetzung:** Der Knopf „Abschnitt überspringen“ steht auf der Seite „Einheit“ (FR-0027) bis zum Ende der Einheit, im Lauf neben „Pause“, in der Pause vor „Weiter“. Nach dem Sprung erscheint ein Hinweis mit „Rückgängig“; läuft er ab, bleibt der Sprung. „Rückgängig“ nimmt nur den letzten Sprung zurück und sagt nichts an. Die Sprünge (Bewegungszeit) stehen im Schnappschuss der Einheit (`guided.unit_snapshot`), nicht in der Aufzeichnung.

**Akzeptanzkriterien:**
- [ ] Ein Sprung mitten in einem Abschnitt (auch Auf- oder Abwärmen) startet den nächsten Abschnitt sofort mit voller Dauer, die folgenden rücken nach; ein Sprung im letzten Abschnitt beendet die Einheit; ohne Sprung verläuft die Einheit unverändert.
- [ ] Nach einem Sprung kommt genau eine Ansage (Wechsel bzw. „Einheit fertig“), keine doppelte Vorankündigung; der Pulshinweis beginnt neu; Pause hält den Abschnitt auch nach einem Sprung an; „Rückgängig“ sagt nichts an.
- [ ] „Rückgängig“ im Hinweis stellt Abschnitt und Restzeit wie ohne Sprung her und entfernt den Sprung aus dem Schnappschuss; nach Ablauf des Hinweises bleibt der Sprung; bei zwei Sprüngen nimmt „Rückgängig“ nur den letzten zurück; es gibt keine Rückfrage.
- [ ] Sprünge werden im Schnappschuss geschrieben und gelesen; ein Schnappschuss ohne Sprünge liest sich weiter; ein Wiederanlauf nach Abbruch setzt am erreichten Abschnitt fort.
- [ ] Nach dem Sprung im letzten Abschnitt läuft der Lauf weiter, der Knopf ist verschwunden und der Lauf gehört wie ohne Sprung zur Einheit aus dem Plan.

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
- **Quelle:** SRC-003 (OQ-0021); SRC-003 (Maintainer 2026-11-15)
- **Verwandt:** OQ-0021, OQ-0064

Ohne Standortberechtigung startet kein GPS-Lauf. Läufe ohne GPS gibt es in Phase 1 nicht; ein Laufbandmodus folgt in Phase 2 (FR-0196).

**Festlegungen (Maintainer 2026-11-15):**
- Ist der Standort ausgeschaltet, bietet die Seite „Lauf vorbereiten“ an, die Standort-Einstellungen des Systems zu öffnen, und prüft nach der Rückkehr erneut. Die Erklärung des Grunds bleibt stehen; ein neues Recht braucht das nicht.

**Akzeptanzkriterien:**
- [ ] Ohne Berechtigung startet kein Lauf, und die App erklärt den Grund.
- [ ] Bei ausgeschaltetem Standort öffnet ein Knopf die Standort-Einstellungen des Systems; nach der Rückkehr mit eingeschaltetem Standort ist die Sperre aufgehoben.

### FR-0202 — Schrittfrequenz aus dem Smartphone
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.1, Z. 146; SRC-003 (OQ-0052)
- **Verwandt:** FR-0027, FR-0021, OQ-0052

In Phase 1 liefert der Schrittsensor des Smartphones die Schrittfrequenz. Die App fragt dafür eine eigene Berechtigung an; ohne sie funktioniert die Aufzeichnung weiter.

Die Schritte werden als Rohdaten `raw_steps` gespeichert ([Datenmodell](../architecture/data-model.md)) und exportiert (FR-0183).

**Akzeptanzkriterien:**
- [ ] Mit Berechtigung wird die Schrittfrequenz live angezeigt.
- [ ] Ohne Berechtigung ist sie als nicht verfügbar ausgewiesen, und der Lauf wird normal aufgezeichnet.

### FR-0204 — Karte der Route
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §4.3, Z. 168–180; §5.1, Z. 197; SRC-003 (OQ-0074)
- **Verwandt:** FR-0027, FR-0037, FR-0040, FR-0041, FR-0056, FR-0193, SEC-0002, SEC-0007, SEC-0008, SEC-0009, OQ-0074, OQ-0075, ADR-0009

Die App zeigt die gelaufene Route auf einer Karte: während des Laufs auf einer eigenen Seite des Lauf-Bildschirms, in der Zusammenfassung und in der Detailansicht eines Laufs sowie als Miniatur je Lauf in der Trainingshistorie. Kartenmaterial kommt aus dem Netz vom Anbieter nach ADR-0009, nur nach ausdrücklicher Einwilligung, die der Nutzer jederzeit widerrufen kann. Ohne Einwilligung, ohne Netz oder bei Fehlern zeigt die App dieselbe Route ohne Kartenhintergrund.

**Festlegungen (OQ-0074):**
- Lauf-Bildschirm: Die Werte bleiben die erste Seite, die Karte ist per Wischen erreichbar. Sie folgt der aktuellen Position und zeigt die bisherige Strecke. Gezeichnet wird nur, solange die Seite sichtbar und der Bildschirm an ist. Die Aufzeichnung hängt nicht von der Karte ab.
- Einheitliche Darstellung in allen Ansichten: Strecke als Linie, Start und Ende markiert, Pausen, Ausfälle nach Absturz und GPS-Lücken als Unterbrechung der Linie, nie als gerade Verbindung (FR-0056). Gezeichnet werden die gespeicherten Positionen, die die Vorverarbeitung akzeptiert hat.
- Miniatur: kleine, nicht bedienbare Karte mit der Route, mit Einwilligung auf Kartenhintergrund, sonst nur die Linie.
- Anfragen an den Anbieter enthalten nur die Koordinaten der Kacheln, keine Kennung, keine Lauf- oder Gesundheitsdaten und keine Cookies.
- Geladene Kacheln und Miniaturen werden nur verschlüsselt gespeichert (SEC-0009), mit fester Größengrenze. Sie gehören nicht in Archiv und Dateiexport. Nach dem Widerruf fragt die App, ob sie gelöscht werden sollen (SEC-0007); „Alles löschen“ löscht sie.
- Jede Karte mit Kartenhintergrund nennt die Quelle des Kartenmaterials, wie dessen Lizenz es verlangt.
- Kartenseite im Lauf (OQ-0075, nach Design `LiveKarte`): unten ein Blatt mit den wichtigsten Werten und Pause; nach Verschieben der Karte zentriert ein Knopf wieder auf die Position, bis dahin folgt sie nicht.
- Detailansicht (OQ-0075): Mit Einwilligung schaltet der Nutzer zwischen Karte und Linie um; ohne Einwilligung gibt es nur die Linie.

**Akzeptanzkriterien:**
- [ ] Lauf-Bildschirm, Zusammenfassung, Detailansicht und Historie zeigen die Route, mit Einwilligung auf Kartenmaterial, ohne Einwilligung als Linie.
- [ ] SEC-0008: Ohne Einwilligung zeigt ein Netzwerkmitschnitt keine Verbindung; nach dem Widerruf keine neue.
- [ ] Pausen, Ausfälle nach Absturz und GPS-Lücken erscheinen nicht als gerade Verbindung.
- [ ] Kacheln und Miniaturen liegen nicht im Klartext auf dem Datenträger.
- [ ] Die Aufzeichnung läuft unverändert, wenn die Karte nicht lädt oder die Seite gewechselt wird.
- [ ] Die Quellenangabe ist auf jeder Karte mit Kartenhintergrund sichtbar.

### FR-0210 — Lauf vorbereiten
- **Status:** Approved | **Phase:** 1 (freier Lauf), 2 (geplante Einheit)
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0011, FR-0025, FR-0029, FR-0195, FR-0202, OQ-0075

Vor dem Start zeigt die Seite „Lauf vorbereiten“ (Design `Start`): den Zustand des GPS-Signals, den Pulssensor mit „Koppeln“, die Quelle der Schrittfrequenz, den Schalter für die Autopause und den Knopf „Los“ mit dem Hinweis, dass der Bildschirm aus sein darf.

**Festlegungen (OQ-0075):**
- Der GPS-Zustand ist eine Anzeige, keine Sperre; gesperrt wird nur nach FR-0195.
- „Koppeln“ führt zur Sensorsuche (FR-0011); nach dem Koppeln kehrt die App auf diese Seite zurück.
- Die Autopause ist vorgewählt wie zuletzt eingestellt, beim ersten Mal aus (FR-0029).
- Umschalter „Geplante Einheit“ und Abschnittsliste kommen mit Phase 2; Ansagen mit FR-0031.
- Die geplante Einheit ist auch auf dem Laufband wählbar. Unter einem Warnsignal (FR-0203) ist nur „Freier Lauf“ wählbar, mit einem Satz dazu (K63).

**Akzeptanzkriterien:**
- [ ] Ohne Standortrecht zeigt die Seite den Grund und startet nicht (FR-0195).
- [ ] Die gewählte Autopause gilt für den gestarteten Lauf.

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

### FR-0221 — Andere Sportart mit Puls aufzeichnen
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-003 (Maintainer 2026-11-20)
- **Verwandt:** FR-0092, FR-0095, FR-0193, FR-0196, FR-0197, FR-0199, PAR-232, DEC-0056

Neben GPS-Lauf und Laufband kann der Nutzer eine andere Sportart aufzeichnen: Seilspringen, Radfahren, Rudern/Ergometer oder Sonstiges. Aufgezeichnet wird nur der Puls eines verbundenen Sensors, ohne Standort und ohne Strecke. Die Belastung wird wie beim Lauf aus dem Puls gerechnet, mit derselben Herzfrequenzbasis und demselben Belastungsprofil, ohne Korrektur je Sportart.

Gespeichert wird eine solche Einheit als Lauf mit der Art `sport` und der Sportart (`runs.sport`: `rope`, `cycling`, `rowing`, `other`; Datenmodell und Archiv: `docs/architecture/data-model.md`, `docs/contracts/archive.md`).

**Akzeptanzkriterien:**
- [ ] Der Start geht nur mit verbundenem Pulssensor; sonst erklärt die App den Grund und bietet den Nachtrag an (FR-0199).
- [ ] Die Aufzeichnung braucht keine Standortberechtigung und nimmt weder Positionen noch Schritte an.
- [ ] Die Bewegungszeit folgt PAR-232; TRIMP, Zonenzeit und Pulsabdeckung entstehen wie beim Lauf (FR-0092, FR-0197).
- [ ] Es gibt keine Strecke, Pace, Splits, Kadenz, VO₂max, aerobe Effizienz, Bestwerte, Prognose und Referenzvorschläge.
- [ ] Die Einheit zählt nicht für Trainingsstand (PAR-192), längste Einheit, lockeres Tempo (PAR-205), Wochenstrecke und Wochenminuten des Plans.
- [ ] Die Einheit zählt für Tageswert, ATL/CTL/TSB (FR-0095) und das Pausenende; der sRPE-Faktor (PAR-087) bleibt aus Läufen.
- [ ] Nach einem Prozessende setzt der Wiederanlauf die Einheit mit derselben Sportart fort (FR-0193).
- [ ] RPE wird wie nach einem Lauf abgefragt.
- [ ] Exportiert wird ohne Strecke als TCX und FIT; GPX ist nicht verfügbar.
- [ ] Hinweise zur Sportart (ersetzt nicht das Laufen, Belastung von Wade und Achillessehne, Brustgurt empfohlen, Unterschätzung bei Rad und Rudern) zeigt die App; wo und wann, legt die Oberfläche der Sportart fest.

## Offene Fragen
<!-- BEGIN OQ -->
- OQ-0012
- OQ-0021
- OQ-0037
- OQ-0041
- OQ-0042
- OQ-0044
- OQ-0052
- OQ-0059
- OQ-0061
- OQ-0064
- OQ-0065
- OQ-0068
- OQ-0071
- OQ-0074
- OQ-0075
- OQ-0076
<!-- END OQ -->

## Quellen
- SRC-001: §4, Z. 126–189; §25 Nr. 1 und 3
