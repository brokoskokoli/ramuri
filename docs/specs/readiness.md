---
id: FEAT-011
title: Erholungszustand und Training Readiness
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0105, FR-0106, FR-0107, FR-0108, FR-0109, FR-0110, FR-0111, FR-0112, FR-0113, FR-0114, FR-0115, FR-0116, FR-0117, FR-0118, FR-0215]
---

# Erholungszustand und Training Readiness

## Ziel
Die App schätzt den aktuellen Trainingsbereitschaftszustand in zwei Stufen ein: einer Basis-Einschätzung ohne Fitnessuhr und einer erweiterten mit Gesundheitsdaten.

## Nicht im Scope
- Medizinische Diagnosen (FR-0118)
- Energiereserve: siehe [energy-reserve.md](energy-reserve.md), zurückgestellt auf Phase 4 (DEC-0060)

## Funktionale Anforderungen

### FR-0105 — Zwei Stufen der Einschätzung
- **Status:** Approved | **Phase:** 2 (Basis), 3 (erweitert)
- **Quelle:** SRC-001 §11, Z. 650–652
- **Verwandt:** FR-0106, FR-0108

Die App soll den aktuellen Trainingsbereitschaftszustand einschätzen können. Dabei werden zwei Stufen unterschieden.

**Akzeptanzkriterien:**
- [ ] Die Anzeige macht erkennbar, welche Stufe gerade vorliegt.

### FR-0106 — Basis-Erholungseinschätzung ohne Fitnessuhr
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §11.1, Z. 656–668
- **Verwandt:** CON-0004, OQ-0029, OQ-0057

Auch ohne Fitnessuhr sind verfügbar: kurzfristige und langfristige Trainingsbelastung, Tage seit dem letzten Training, subjektive Anstrengung vorheriger Trainings und optional selbst eingegebenes Wohlbefinden. Daraus kann die App Hinweise zur Trainingssteuerung ableiten.

Beispiel: „Deine Trainingsbelastung lag in den letzten sieben Tagen deutlich über deinem bisherigen Niveau. Für heute wird ein lockerer Lauf empfohlen.“

**Akzeptanzkriterien:**
- [ ] Ohne Wearable und ohne Gesundheitsdaten kann ein Hinweis erzeugt werden, sofern die Trainingsdaten dafür ausreichen. Auslöser und Texte folgen PAR-174 bis PAR-183.

### FR-0107 — Kein Anspruch auf vollständige Bestimmung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §11.1, Z. 670
- **Verwandt:** OQ-0029, OQ-0077

Es wird nicht behauptet, dass daraus der tatsächliche körperliche Erholungszustand vollständig bestimmbar sei.

**Akzeptanzkriterien:**
- [ ] Hinweise der Basisstufe formulieren keinen festgestellten Erholungszustand.
- [ ] Die Basisstufe gibt nur Texthinweise und zeigt keine Zustände (OQ-0029).
- [ ] Die Karte „Erholung“ auf „Heute“ hat in der Basisstufe die Optik des Designs, zeigt aber nur den Texthinweis, ohne Zahl und ohne Zustand (OQ-0077).

### FR-0108 — Faktoren der erweiterten Training Readiness
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.2, Z. 674–681
- **Verwandt:** FR-0022, SEC-0001

Wenn zusätzliche Gesundheitsdaten vorhanden sind, kann die App weitere Faktoren verwenden: nächtliche HRV, Ruheherzfrequenz, Schlafdauer, Schlafqualität (soweit verfügbar), Trainingsbelastung und subjektives Wohlbefinden.

**Akzeptanzkriterien:**
- [ ] Nur freigegebene Datenquellen fließen ein (SEC-0002).

### FR-0109 — Wert von 0 bis 100 mit Einordnung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.2, Z. 683
- **Verwandt:** OQ-0006, OQ-0059, DEC-0074

Der erweiterte Zustand wird mit einem Wert zwischen 0 und 100 und einer erklärenden Einordnung dargestellt.

**Akzeptanzkriterien:**
- [ ] Ein angezeigter Wert liegt zwischen 0 und 100 und erscheint immer mit Einordnung.
- [ ] Eine Zahl erscheint nur mit aktueller HRV (nächtlich aus Health Connect oder gültiger Kamera-Morgenwert nach bestandener Validierung und Opt-in, PAR-160K), einem rollenden Mittel nach PAR-161 bzw. PAR-161K, einer Schlafdauer der letzten Nacht (aus Health Connect oder als Selbstangabe in Stufen, PAR-164K/165K) sowie einer Referenz derselben Reihe aus mindestens 14 gültigen Werten in 28 Tagen; sonst eine eingeschränkte Einschätzung ohne Zahl (OQ-0006).

### FR-0110 — Vorläufige Gewichtung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.2, Z. 685–695
- **Verwandt:** NFR-0002, NFR-0003, NFR-0004, OQ-0020, OQ-0029, OQ-0057, OQ-0059

Beispielhafte Faktoren. Diese Gewichtungen sind Produktannahmen für einen später zu validierenden Algorithmus, keine wissenschaftlich gesicherten Koeffizienten.

| Faktor | Vorläufige Gewichtung |
|---|---:|
| HRV-Abweichung vom persönlichen Normalbereich | 25 % |
| Ruhepuls-Abweichung | 20 % |
| Schlaf | 30 % |
| Trainingsbelastung | 15 % |
| Subjektives Befinden | 10 % |

**Akzeptanzkriterien:**
- [ ] Die Gewichte sind Teil des versionierten Modells (NFR-0001).
- [ ] Teilskalen und Gesamtwert folgen PAR-163 bis PAR-170; die Wirkung auf den Plan folgt PAR-173.
- [ ] Die App stellt sie nicht als wissenschaftlich gesichert dar.
- [ ] Für die Wirkung auf den Plan zählt nur der Wert am Tag der intensiven Einheit (PAR-173).

### FR-0111 — Fehlende Faktoren gelten nicht als normal
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.2, Z. 697; §25 Nr. 11, Z. 1406
- **Verwandt:** ACC-11, OQ-0029, OQ-0059

Fehlende Faktoren werden nicht automatisch als „normal“ bewertet. Die App zeigt gegebenenfalls nur eine eingeschränkte Einschätzung.

**Akzeptanzkriterien:**
- [ ] Fehlt ein Faktor, ist die Einschätzung als eingeschränkt erkennbar (ACC-11).
- [ ] Fehlende optionale Faktoren werden herausgerechnet und ausgewiesen (OQ-0029). Fehlt der Belastungsfaktor, gilt die Obergrenze aus PAR-170.

### FR-0112 — Persönlicher Referenzzeitraum
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.3, Z. 701–703
- **Verwandt:** ACC-11, OQ-0006

Bei HRV und Ruhepuls sind individuelle Veränderungen aussagekräftiger als ein Vergleich mit pauschalen Bevölkerungswerten. Deshalb verwendet die App einen persönlichen Referenzzeitraum, beispielsweise 28 Tage mit ausreichenden gültigen Messungen.

**Akzeptanzkriterien:**
- [ ] Die Bewertung nutzt persönliche Referenzwerte und keine Bevölkerungswerte (ACC-11).

### FR-0113 — Robuste Abweichungsbewertung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.3, Z. 705–711
- **Verwandt:** OQ-0059, DEC-0074

Eine robuste Abweichungsbewertung kann auf Median und Median Absolute Deviation basieren: `z = (x − Median(X)) / (1,4826 · MAD(X))`. Für HRV kann eine logarithmische Transformation vor der Berechnung sinnvoll sein. Bei HRV und Ruhepuls ist `x` das rollende Mittel aus `k` gültigen Werten der letzten 7 Nächte, bei der Kamerareihe der letzten 7 Tage, und `X` die Reihe der Tageswerte. Im Nenner steht dann `1,4826 · MAD(X) / √k` (PAR-161, PAR-162, PAR-161K, PAR-162K).

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): X = {48, 50, 52}, x = 50 ergibt z = 0.
- [ ] Testfall (abgeleitet): X = {48, 50, 52}, k = 4, x = 51 ergibt z = 0,67.

### FR-0114 — Keine künstlich präzise Abweichung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.3, Z. 713
- **Verwandt:** OQ-0006

Bei nicht ausreichender Streuung oder Datenmenge darf keine künstlich präzise standardisierte Abweichung erzeugt werden.

**Akzeptanzkriterien:**
- [ ] Bei MAD = 0 oder zu wenigen Messungen entsteht kein z-Wert.

### FR-0115 — Messmethoden nur konsistent vergleichen
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.3, Z. 715–717
- **Verwandt:** OQ-0059, DEC-0074

Messungen sollen nur dann direkt verglichen werden, wenn Messmethode und Messbedingungen ausreichend konsistent sind. Insbesondere RMSSD und SDNN dürfen nicht als identische HRV-Werte behandelt werden.

**Akzeptanzkriterien:**
- [ ] RMSSD- und SDNN-Werte gehen nicht in dieselbe Referenzreihe ein.
- [ ] Jede Reihe stammt aus genau einer Quell-App; mehrere Quell-Apps werden nicht gemischt (PAR-160, PAR-189).
- [ ] Die Kamera ist eine eigene Quelle mit eigener Reihe je Haltung (liegend als Vorgabe, sitzend getrennt) und Gerät; sie wird nie mit Health Connect gemischt. Am selben Tag gilt die Vorrangregel aus K-1 (PAR-160K).

### FR-0116 — Mögliche Zustände
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.4, Z. 721–727
- **Verwandt:** OQ-0029, OQ-0058, OQ-0059, DEC-0074

Mögliche Zustände: Gut erholt, Normal belastbar, Erhöhte Belastung, Erholung empfohlen, Unzureichende Daten.

**Akzeptanzkriterien:**
- [ ] Ohne Zahl gilt PAR-171 bzw. PAR-171K: eingeschränkte Einschätzung, wenn Schlaf der letzten Nacht (auch als Selbstangabe) oder eine frische Messung (Kamera oder Health Connect) vorliegt, sonst „Unzureichende Daten“.
- [ ] 75–100 gut erholt, 50–74 normal belastbar, 25–49 erhöhte Belastung, 0–24 Erholung empfohlen; vorläufig und versioniert (OQ-0029).
- [ ] Für die Bremsung des Plans zählt der Zustand am Tag der intensiven Einheit; er wird nicht vorgezogen oder übertragen (PAR-173, OQ-0058).

### FR-0117 — Wichtigste Ursachen erklären
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.4, Z. 729–733
- **Verwandt:** FR-0181, OQ-0059

Die App erklärt die wichtigsten Ursachen einer Bewertung.

Beispiel: „Deine nächtliche HRV liegt unter deinem üblichen Bereich. Gleichzeitig ist dein Ruhepuls erhöht. Deshalb wird heute ein weniger intensives Training vorgeschlagen.“

**Akzeptanzkriterien:**
- [ ] Jede Bewertung nennt die Faktoren, die sie am stärksten beeinflusst haben.
- [ ] Liegt nur der Schlaf unter seinem Bezug, nennt die Erklärung die kurze Schlafdauer als Grund (PAR-172).

### FR-0118 — Keine medizinische Diagnose
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §11.4, Z. 735
- **Verwandt:** OQ-0026

Die App stellt daraus keine medizinische Diagnose.

**Akzeptanzkriterien:**
- [ ] Texte der App stellen keine medizinische Diagnose.

### FR-0215 — Morgenmessung mit der Handykamera
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-003 (Maintainer 2026-11-09)
- **Verwandt:** FR-0109, FR-0112, FR-0115, FR-0214, OQ-0006, OQ-0078, DEC-0073, DEC-0074

Für die erweiterte Einschätzung ohne Uhr misst der Nutzer morgens 60 s mit der Kamera wie in FR-0214. Daraus entstehen Ruhepuls und RMSSD als eigene Reihe (nicht gemischt mit Werten aus Health Connect, FR-0115). Eine morgendliche Erinnerung ist freiwillig. Protokoll und Regeln stammen aus R009 (`research/R009-kamera-ppg-morgenmessung/RESULTS.md`, Abschnitte 1, 5 und 5a); es gilt die Regelversion K-1 in [phase-2-3-rules.md](../phase-2-3-rules.md#7-regelversion-k-1-kamera-morgenmessung-phase-3). Freigegeben mit Auflage: RMSSD zählt erst nach bestandener Validierung gegen Polar H9 (R009, Abschnitt 6) und Opt-in des Nutzers.

**Akzeptanzkriterien:**
- [ ] Protokoll: morgens nach dem Aufwachen, erst Toilette, dann messen, vor Kaffee und Frühstück; Haltung liegend als Vorgabe, sitzend wählbar, nie stehend; wechselt die Haltung, beginnt eine neue Reihe. Vorgabe 2 min Ruhe, jeden Tag gleich; 60 s Messung mit spontaner Atmung, Anleitung ohne vorgegebenes Atemtempo.
- [ ] Es zählt die erste Messung des Tages mit ausreichender Qualität; wiederholt wird nur, wenn die Qualität nicht reicht.
- [ ] Gültige Werte, Reihen und Morgenfenster nach PAR-160K; Ruhepuls bei Qualität „gut“ oder „eingeschränkt“, RMSSD nur bei „gut“ und unter der RMSSD-Qualitätsgrenze aus der Validierung.
- [ ] Abweichungen nach PAR-161K und PAR-162K, Hinweis „wenige Messungen“ bei weniger als 5 gültigen Werten in 7 Tagen.
- [ ] Schlafdauer ohne Uhr als freiwillige Selbstangabe in Stufen nach PAR-164K/165K; kein Schlafgefühl am Morgen (PAR-169 bleibt).
- [ ] Zahl, eingeschränkte Einschätzung und „Unzureichende Daten“ nach PAR-171K; Health Connect hat Vorrang vor der Kamera (Vorrangregel K-1).
- [ ] Validierungssperre: Vor der Validierung erscheint Kamera-RMSSD nur als markierte Tatsache „noch nicht geprüft“. Die Folgen von „bestanden“, „eingeschränkt“ und „nicht bestanden“ für RMSSD und Ruhepuls, das Opt-in „experimentell, mit einem Brustgurt verglichen (ein Handy)“ und der Zusatz „liegend verglichen“ für die sitzende Reihe folgen der Validierungssperre in K-1. Die App nennt die Messung nie „validiert“.
- [ ] Kamerabilder werden weder gespeichert noch übertragen; die Auswertung läuft auf dem Gerät mit demselben Algorithmus wie FR-0214.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0006](../migration/open-questions.md#oq-0006--mindestdatenqualität-für-einen-numerischen-readiness-wert) (entschieden): Mindestdatenqualität für einen numerischen Readiness-Wert
- [OQ-0020](../migration/open-questions.md#oq-0020--wie-und-wann-werden-modelle-validiert) (entschieden): Wie und wann werden Modelle validiert?
- [OQ-0026](../migration/open-questions.md#oq-0026--warnsignale-medizinische-hinweise-und-einordnung-als-medizinprodukt) (entschieden): Warnsignale, medizinische Hinweise und Einordnung als Medizinprodukt
- [OQ-0029](../migration/open-questions.md#oq-0029--berechnung-der-readiness-zustände) (entschieden): Berechnung der Readiness-Zustände
- [OQ-0057](../migration/open-questions.md#oq-0057--fehlende-regeln-für-phase-2-und-3) (entschieden): Fehlende Regeln für Phase 2 und 3
- [OQ-0058](../migration/open-questions.md#oq-0058--entscheidungen-aus-der-prüfung-von-phase-2-und-3) (entschieden): Entscheidungen aus der Prüfung von Phase 2 und 3
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0077](../migration/open-questions.md#oq-0077--vorgaben-zum-start-von-phase-2) (entschieden): Vorgaben zum Start von Phase 2
- [OQ-0078](../migration/open-questions.md#oq-0078--puls-und-hrv-mit-der-handykamera) (entschieden): Puls und HRV mit der Handykamera
<!-- END OQ -->

## Quellen
- SRC-001: §11, Z. 648–735; §25 Nr. 11
