---
id: FEAT-001
title: Nutzerprofil und persönliche Einstellungen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0001, FR-0002, FR-0003, FR-0004, FR-0005, FR-0006, FR-0214, FR-0217]
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
- [ ] Beim Erstellen eines Plans fragt die App fehlende Angaben ab. Pflicht sind die verfügbaren Trainingstage und die maximale Trainingszeit je Einheit (K53); ohne die übrigen Angaben entsteht ein konservativer Einstiegsplan (OQ-0010).

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

### FR-0214 — Ruhepuls mit der Handykamera messen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-003 (Maintainer 2026-11-09)
- **Verwandt:** FR-0002, FR-0060, SEC-0001, OQ-0078, DEC-0073, DEC-0074

Im Profil und bei der Einrichtung kann der Nutzer seinen Ruhepuls messen lassen, statt ihn einzutragen: Finger auf Rückkamera und Blitz, die App erkennt die Schläge im Kamerabild (Photoplethysmografie). Vor der Messung empfiehlt sie eine Ruhephase mit beruhigender Anleitung; wer schon entspannt ist, misst sofort.

**Akzeptanzkriterien:**
- [ ] Erreichbar über das Profil (Ruheherzfrequenz) und als Knopf bei der Einrichtung.
- [ ] Ablauf: Erklärung mit Bild, wie der Finger liegt; wählbar Ruhephase (Vorgabe 5 min, Länge einstellbar) oder sofort messen; danach 60 s Messung.
- [ ] Haltung sitzend oder liegend wählbar; sie wird mit dem Wert gespeichert, ebenso der Zeitpunkt.
- [ ] Die beruhigende Anleitung gibt kein Atemtempo vor; während der 60 s atmet der Nutzer spontan.
- [ ] Es zählt die erste Messung mit ausreichender Qualität; wiederholt wird nur, wenn die Qualität nicht reicht.
- [ ] Während der Messung zeigt die App die Pulskurve und den laufenden Puls, damit der Nutzer den Finger justieren kann, sowie den Fortschritt.
- [ ] Ergebnis nur bei ausreichender Signalqualität; sonst ein Hinweis mit Grund und „noch einmal“. Der Nutzer übernimmt den Wert ausdrücklich ins Profil. Hat der Kamera-Ruhepuls die Validierung „nicht bestanden“ (Validierungssperre in K-1, FR-0215), trägt der Vorschlag den Hinweis „ungenauer als erwartet“.
- [ ] Ohne Kamera, Blitz oder Berechtigung bleibt die manuelle Eingabe; die App stürzt nicht ab.
- [ ] Kamerabilder werden weder gespeichert noch übertragen; die Auswertung läuft auf dem Gerät.
- [ ] Der Algorithmus folgt der Referenz aus `../puls` (`docs/ALGORITHMUS.md`, Stand `algo-v0.4-frozen`) und ist gegen deren Testvektoren geprüft.

### FR-0217 — Entwicklermodus
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-003 (Maintainer 2026-11-13, K61/K62)
- **Verwandt:** FR-0215, FR-0213, FR-0021, FR-0216, SEC-0009, DEC-0074

Unter Einstellungen → Über schaltet 10-maliges Tippen auf die Versionsnummer den Entwicklermodus ein; er lässt sich dort wieder ausschalten. Er dient der Validierung der Kamera-Morgenmessung (FR-0215) gegen einen Brustgurt und gilt auch in der Release-Version. Bis die Validierung bestanden ist, ist die Morgenmessung nur im Entwicklermodus nutzbar (K62 Punkt 1). **Abweichung von der Validierungssperre in K-1 (Entscheidung des Maintainers, K61, K62 Punkt 6):** Im Entwicklermodus gelten Ruhepuls und RMSSD der Morgenmessung vollständig als gültige Werte, als wäre die Validierung bestanden. Ohne Entwicklermodus gilt die Sperre unverändert.

**Umsetzung (WP33, K65):** Die Seite „Über“ (Name, Version, Lizenzen) ist ein Eintrag der Übersicht hinter dem Profil-Symbol; ab dem 7. Tipp zählt ein Hinweis die restlichen Tipps herunter. Ausgeschaltet wird der Modus mit dem Schalter im Abschnitt „Entwickler“ derselben Seite. Er ist eine Einstellung des Geräts, kommt nicht ins Archiv und wird von „Alles löschen“ zurückgesetzt. Nach dem Ausschalten bleiben die Messungen gespeichert, sind aber nicht sichtbar; die Morgen-Erinnerung bleibt eingeschaltet, ihr Wecker ist gestrichen. Gurt-RR speichert die App nur vom ersten Quellgerät der Messung, von Beginn der Ruhephase bis Ende der Messung (bei „Noch einmal messen“ lückenlos bis Ende der Wiederholung); das Format der CSV steht in [morning-pairs-csv.md](../contracts/morning-pairs-csv.md).

**Akzeptanzkriterien:**
- [ ] 10 Tipps auf die Versionsnummer schalten den Modus ein, weniger nicht; ausschalten lässt er sich in den Einstellungen.
- [ ] Ohne Entwicklermodus ist die Morgenmessung vor bestandener Validierung nirgends erreichbar (K62 Punkt 1).
- [ ] Im Entwicklermodus erscheinen Ruhepuls und RMSSD der Morgenmessung in Trends, Kurven, Readiness und bei „adaptiv“ (FR-0216) im Plan wie nach bestandener Validierung, ohne Opt-in und ohne Kennzeichnung „experimentell“ oder „noch nicht geprüft“; höchstens ein unauffälliger Hinweis „Entwicklermodus aktiv“ (K62 Punkt 6, ersetzt die Kennzeichnung aus K61).
- [ ] Jede Messung trägt intern dauerhaft das Merkmal „vor der Validierung gemessen“, wenn sie vor bestandener Validierung entsteht; es ändert weder Anzeige noch Rechnung.
- [ ] Die Qualitätsgrenze je Messung (PAR-160K) gilt auch im Entwicklermodus; unbrauchbare Messungen werden verworfen.
- [ ] Ist bei der Morgenmessung ein Brustgurt mit RR-Intervallen verbunden, speichert die App im Entwicklermodus dessen RR parallel zur Messung (K61 Punkt 3); ohne Entwicklermodus nicht.
- [ ] Die Messpaare Kamera/Gurt lassen sich nur im Entwicklermodus als unverschlüsselte CSV teilen, mit Warnhinweis vor dem Teilen wie bei der Zusatzmetriken-CSV (K62 Punkt 4, K57). Die App zeigt keine Gurt-RMSSD und keine Differenzen.

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
- [OQ-0078](../migration/open-questions.md#oq-0078--puls-und-hrv-mit-der-handykamera) (entschieden): Puls und HRV mit der Handykamera
<!-- END OQ -->

## Quellen
- SRC-001: §2, Z. 31–59
