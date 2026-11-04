---
id: FEAT-008
title: VO₂max-Schätzung
status: Teilweise Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0066, FR-0067, FR-0068, FR-0069, FR-0070, FR-0071, FR-0072, FR-0073, FR-0074, FR-0075, FR-0076, FR-0077, FR-0078, FR-0079, FR-0080, FR-0081, FR-0082, FR-0083]
---

# VO₂max-Schätzung

## Ziel
Die App schätzt die maximale Sauerstoffaufnahme anhand gewöhnlicher Laufeinheiten.

**Entschieden:** Die erste Version nutzt den ACSM-/Herzfrequenzreserve-Schätzer (OQ-0001).

## Ablauf der Verarbeitung eines Laufs
Siehe FR-0076.

## Funktionale Anforderungen

### FR-0066 — Schätzung aus gewöhnlichen Läufen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8, Z. 323–325

Die App soll die maximale Sauerstoffaufnahme anhand gewöhnlicher Laufeinheiten schätzen können. Ein standardisierter Maximaltest ist dafür nicht zwingend erforderlich.

**Akzeptanzkriterien:**
- [ ] Aus einem geeigneten gewöhnlichen Lauf entsteht ohne Maximaltest eine Schätzung.

### FR-0067 — Kennzeichnung als indirekte Schätzung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8, Z. 327; §25 Nr. 5, Z. 1400
- **Verwandt:** CON-0009, ACC-05

Der berechnete Wert ist eine indirekte Schätzung und keine tatsächliche Messung der maximalen Sauerstoffaufnahme. Er wird nur aus dafür geeigneten Daten berechnet und als Schätzung gekennzeichnet.

**Akzeptanzkriterien:**
- [ ] Jede Anzeige des Werts weist ihn als Schätzung aus (ACC-05).
- [ ] Ohne geeignete Daten entsteht kein Wert (ACC-05).

### FR-0068 — Eingabedaten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.1, Z. 331–343
- **Verwandt:** OQ-0012, OQ-0059

Benötigt: Laufgeschwindigkeit, Herzfrequenz, maximale Herzfrequenz, Ruheherzfrequenz, Zeitstempel. Optional: Streckensteigung, Umgebungsbedingungen, individuelle Kalibrierungsdaten.

**Akzeptanzkriterien:**
- [ ] Fehlt ein benötigter Wert, entsteht keine Schätzung und der Grund ist sichtbar (OQ-0012).

### FR-0069 — Sauerstoffbedarf nach ACSM-Laufformel
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.2, Z. 347–363
- **Verwandt:** NFR-0002, OQ-0001, OQ-0059

Ein mögliches Basismodell ist `VO2 = 3,5 + 0,2·v + 0,9·v·G` mit VO2 in ml/kg/min, v in m/min und der Steigung G als Dezimalzahl. Bei ebener Strecke gilt vereinfacht `VO2 = 3,5 + 0,2·v`.

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 10 km/h eben (166,67 m/min) ergibt 36,83 ml/kg/min.
- [ ] Die Steigung geht nur nach PAR-027 ein.

### FR-0070 — Grenzen der ACSM-Laufformel beachten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.2, Z. 365
- **Verwandt:** FR-0074

Die Formel beschreibt einen geschätzten Sauerstoffbedarf bei geeigneter, annähernd gleichförmiger Laufbelastung. Sie ist insbesondere bei sehr langsamem Laufen, starkem Gefälle, Geländewechseln und wechselnder Laufökonomie begrenzt.

**Akzeptanzkriterien:**
- [ ] Testdaten mit starkem Gefälle oder sehr langsamem Laufen liefern keine ungekennzeichnete Schätzung.

### FR-0071 — Hochrechnung auf VO2max
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.3, Z. 369–407
- **Verwandt:** FR-0060, NFR-0002, OQ-0001

Als einfaches Anfangsmodell wird angenommen, dass der Anteil der Herzfrequenzreserve ungefähr dem Anteil der genutzten Sauerstoffaufnahme-Reserve entspricht: `VO2max ≈ 3,5 + (VO2 − 3,5) / r`.

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 10 km/h eben, HF 150, HFmax 190, HFRuhe 60 ergibt r = 0,6923 und ungefähr 51,6 ml/kg/min.

### FR-0072 — Keine Genauigkeit ohne Validierung versprechen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.3, Z. 409
- **Verwandt:** NFR-0004, OQ-0020

Das Modell ist bewusst ein nachvollziehbarer erster Schätzer. Es muss durch Referenzdaten validiert werden, bevor eine bestimmte Messgenauigkeit versprochen werden kann.

**Akzeptanzkriterien:**
- [ ] Die App nennt ohne dokumentierte Validierung keine Genauigkeitsangabe.

### FR-0073 — Auswahl geeigneter Abschnitte
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.4, Z. 413–425
- **Verwandt:** FR-0075, OQ-0019

Nicht jeder Abschnitt ist geeignet; verwendet werden bevorzugt gleichmäßige Belastungsphasen. Vorläufige Auswahlregeln:

1. Mehrere Minuten annähernd konstante Bewegung
2. Keine Pause oder unmittelbar vorausgegangener Tempowechsel
3. Stabiler und plausibler Puls
4. Ausreichende GPS-Qualität
5. Keine starke Steigung oder starkes Gefälle
6. Keine offensichtlichen Messausreißer
7. Ausreichende Belastungsintensität

**Akzeptanzkriterien:**
- [ ] Ein Abschnitt, der eine der vorläufigen Regeln verletzt, wird gegenüber einem gleichmäßigen Abschnitt nicht bevorzugt.

### FR-0074 — Klare Laufgeschwindigkeit, keine unkritische Bewertung des Gehens
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.4, Z. 427
- **Verwandt:** FR-0070, OQ-0001

Für die erste, auf der ACSM-Laufformel basierende Implementierung werden vor allem Abschnitte mit klarer Laufgeschwindigkeit berücksichtigt. Sehr langsames Laufen oder Gehen darf nicht mit derselben Formel unkritisch bewertet werden.

**Akzeptanzkriterien:**
- [ ] Ein reiner Gehabschnitt liefert keine ungekennzeichnete Schätzung nach der Laufformel.

### FR-0075 — Schwellenwerte sind Modellparameter
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.4, Z. 429
- **Verwandt:** NFR-0001, OQ-0019, OQ-0020

Die konkreten Schwellenwerte für Geschwindigkeit, Stabilität und Mindestdauer sind zu validierende Modellparameter.

**Akzeptanzkriterien:**
- [ ] Die Startwerte stehen in [model-parameters.md](../model-parameters.md) und tragen eine Version; validiert wird im Feldtest (OQ-0020).

### FR-0076 — Verarbeitung eines Laufs
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.5, Z. 433–443
- **Verwandt:** FR-0045, FR-0053

Der Ablauf:

1. Relevante Messdaten synchronisieren.
2. Geschwindigkeit und Herzfrequenz vorsichtig glätten.
3. Geeignete gleichmäßige Abschnitte identifizieren.
4. Für jeden Abschnitt Sauerstoffbedarf berechnen.
5. Für jeden Abschnitt eine VO₂max-Schätzung bestimmen.
6. Unplausible Schätzungen verwerfen.
7. Verbleibende Abschnitte nach Datenqualität gewichten.
8. Einen robusten Gesamtwert, beispielsweise einen gewichteten Median, berechnen.
9. Qualitätsbewertung für den Lauf vergeben.

**Akzeptanzkriterien:**
- [ ] Ein einzelner unplausibler Abschnitt verschiebt den Gesamtwert nicht ungefiltert.
- [ ] Jeder Laufwert trägt eine Qualitätsstufe (FR-0053).

### FR-0077 — Abweichende Schätzungen senken die Konfidenz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.5, Z. 445
- **Verwandt:** OQ-0019, OQ-0059

Stark voneinander abweichende Schätzungen sollen die Konfidenz reduzieren.

**Akzeptanzkriterien:**
- [ ] Bei gleichem Mittelwert und gleichem Zeittrend erhält ein Lauf mit stark streuenden Abschnitten keine bessere Qualität als ein Lauf mit eng beieinanderliegenden.

### FR-0078 — Stabiler langfristiger Wert
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.6, Z. 449–451, 469

Der angezeigte langfristige VO₂max-Wert soll nicht bei jedem einzelnen Lauf stark schwanken. Dafür werden mehrere geeignete Läufe berücksichtigt. Eine einzelne gute oder schlechte Einheit soll nicht als deutliche Fitnessveränderung interpretiert werden.

**Akzeptanzkriterien:**
- [ ] Ein einzelner Ausreißerlauf ändert den Langzeitwert weniger als den Laufwert.

### FR-0079 — Mögliche Glättung des langfristigen Werts
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.6, Z. 453–459
- **Verwandt:** OQ-0019

Eine mögliche Glättung ist `V[t] = V[t−1] + α·(V[neu] − V[t−1])`, wobei α ein von Datenqualität und Datenmenge abhängiger Glättungsfaktor ist.

**Akzeptanzkriterien:**
- [ ] α folgt PAR-034 und PAR-035.

### FR-0080 — Keine Aktualisierung bei unzureichender Qualität
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.6, Z. 461

Bei unzureichender Datenqualität wird der Wert nicht aktualisiert.

**Akzeptanzkriterien:**
- [ ] Ein Lauf der Stufe „nicht bestimmbar“ lässt den Langzeitwert unverändert.

### FR-0081 — Drei Sichten auf die VO2max
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §8.6, Z. 463–467

Die App unterscheidet zwischen der Schätzung aus einem einzelnen Lauf, der aktuellen langfristigen VO₂max-Schätzung und dem Verlauf über mehrere Wochen und Monate.

**Akzeptanzkriterien:**
- [ ] Alle drei Sichten sind getrennt verfügbar und eindeutig benannt.

### FR-0082 — Bekannte Leistungsdaten für die Kalibrierung
- **Status:** Draft | **Phase:** 4 (möglich)
- **Quelle:** SRC-001 §8.7, Z. 473–480
- **Verwandt:** OQ-0001, OQ-0017

Optional kann der Nutzer Wettkampfergebnisse, Zeiten aus definierten Laufleistungstests, laborbestimmte VO₂max und ein bekanntes maximales Herzfrequenzniveau eingeben. Diese Werte können zur Bewertung und späteren Kalibrierung des Schätzmodells verwendet werden.

**Akzeptanzkriterien:**
- [ ] Die Eingabe ist optional; ohne sie bleibt die Schätzung verfügbar.

### FR-0083 — Messmethoden getrennt kennzeichnen
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §8.7, Z. 482
- **Verwandt:** FR-0024, OQ-0041

Laborwerte und indirekte Schätzwerte bleiben als unterschiedliche Messmethoden gekennzeichnet.

**Akzeptanzkriterien:**
- [ ] Ein Laborwert und eine Schätzung sind in der Anzeige eindeutig unterscheidbar.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0001](../migration/open-questions.md#oq-0001--welches-vo2max-modell-gilt-für-die-erste-version) (entschieden): Welches VO2max-Modell gilt für die erste Version?
- [OQ-0012](../migration/open-questions.md#oq-0012--was-gilt-wenn-ruhepuls-oder-hfmax-fehlen) (entschieden): Was gilt, wenn Ruhepuls oder HFmax fehlen?
- [OQ-0017](../migration/open-questions.md#oq-0017--verbindlichkeit-der-phasen-und-fehlende-zuordnungen) (entschieden): Verbindlichkeit der Phasen und fehlende Zuordnungen
- [OQ-0019](../migration/open-questions.md#oq-0019--startwerte-der-modellparameter-und-qualitätsregeln) (entschieden): Startwerte der Modellparameter und Qualitätsregeln
- [OQ-0020](../migration/open-questions.md#oq-0020--wie-und-wann-werden-modelle-validiert) (entschieden): Wie und wann werden Modelle validiert?
- [OQ-0041](../migration/open-questions.md#oq-0041--phasen-der-noch-nicht-zugeordneten-anforderungen) (entschieden): Phasen der noch nicht zugeordneten Anforderungen
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
<!-- END OQ -->

## Quellen
- SRC-001: §8, Z. 321–482; §25 Nr. 5
