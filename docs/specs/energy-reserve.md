---
id: FEAT-012
title: Energiereserve (Body-Battery-ähnliche Funktion)
status: Draft
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0119, FR-0120, FR-0121, FR-0122, FR-0123, FR-0124, FR-0125, FR-0126, FR-0127]
---

# Energiereserve

**Zurückgestellt auf Phase 4 (DEC-0060).** Nicht Teil der Umsetzung der Phasen 1 bis 3.

## Ziel
Optional stellt die App eine laufend aktualisierte Schätzung der körperlichen Energiereserve dar. Die Funktion setzt zusätzliche Daten voraus.

## Funktionale Anforderungen

### FR-0119 — Optionale Funktion
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12, Z. 739–741
- **Verwandt:** CON-0007, OQ-0007

Optional soll die App eine laufend aktualisierte Schätzung der körperlichen Energiereserve darstellen. Diese Funktion setzt zusätzliche Daten voraus.

**Akzeptanzkriterien:**
- [ ] Alle anderen Funktionen bleiben ohne diese Funktion nutzbar.
- [ ] Die Funktion bleibt ausgeblendet, bis sie an echten Daten kalibriert ist (OQ-0030).

### FR-0120 — Datenvoraussetzungen
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.1, Z. 745–751, 755
- **Verwandt:** ACC-12, OQ-0007

Für eine aussagekräftige Schätzung werden insbesondere benötigt: kontinuierliche oder ausreichend häufige Herzfrequenzmessungen, regelmäßige HRV-Daten, Bewegungs- und Ruhephasen, Schlafinformationen und Trainingshistorie. Eine normale Pulsaufzeichnung nur während des Laufens reicht dafür nicht aus.

**Entschieden (OQ-0007):** Die Funktion gibt es nur mit kontinuierlichen Tages- und Schlafdaten; „ausreichend häufig“ genügt nicht.

**Akzeptanzkriterien:**
- [ ] Mit Pulsdaten nur aus Läufen wird kein zuverlässiger aktueller Wert angezeigt (ACC-12).

### FR-0121 — Deaktiviert oder als unvollständig gekennzeichnet
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.1, Z. 753; §25 Nr. 12, Z. 1407
- **Verwandt:** ACC-12, OQ-0007

Bei fehlenden Daten bleibt die Funktion deaktiviert oder wird ausdrücklich als unvollständig gekennzeichnet.

**Akzeptanzkriterien:**
- [ ] Bei fehlenden kontinuierlichen Daten ist die Funktion deaktiviert und erklärt warum (ACC-12, OQ-0007).

### FR-0122 — Berechnungsmodell
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.2, Z. 759–771
- **Verwandt:** NFR-0002, OQ-0030, OQ-0048

Die Energiereserve wird als modellierter Zustand auf einer Skala von 0 bis 100 dargestellt: `B[t+1] = clamp(B[t] + R[t] − D[t], 0, 100)`, mit bisheriger Energiereserve B, modelliertem Regenerationszuwachs R und modellierter Belastung D. Die Aktualisierung erfolgt in regelmäßigen Zeitintervallen.

**Akzeptanzkriterien:**
- [ ] Testfälle (abgeleitet): B = 95, R = 10, D = 0 ergibt 100; B = 5, R = 0, D = 10 ergibt 0.

### FR-0123 — Regenerations- und Belastungskomponente
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.3–12.4, Z. 775–789
- **Verwandt:** OQ-0030

Die Regeneration steigt beispielsweise bei erholsamem Schlaf, längeren Ruhephasen, günstigen HRV-Werten gegenüber dem persönlichen Referenzbereich und niedriger physiologischer Belastung. Die Energiereserve sinkt beispielsweise bei sportlicher Belastung, erhöhtem physiologischem Stress, schlechter Erholung und längerer Wachzeit.

**Akzeptanzkriterien:**
- [ ] Die Komponenten folgen PAR-094 bis PAR-097 und werden an echten Daten kalibriert (PAR-099).

### FR-0124 — Empirische Kalibrierung, keine physikalische Energie
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.4, Z. 791–793
- **Verwandt:** NFR-0004, OQ-0030

Die konkreten Zuwachs- und Abnahmeraten müssen empirisch kalibriert werden. Die Werte stellen keine physikalisch messbare Energie dar.

**Akzeptanzkriterien:**
- [ ] Die App stellt den Wert nicht als gemessene Energie dar.

### FR-0125 — Darstellung
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.5, Z. 797–803

Die App zeigt: aktuelle Energiereserve, Tagesdiagramm, Veränderungen während des Schlafs, Veränderungen während sportlicher Belastung und optional historische Trends.

**Akzeptanzkriterien:**
- [ ] Die genannten Pflichtansichten sind bei ausreichenden Daten vorhanden.

### FR-0126 — Keine Fortschreibung über Datenlücken
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.5, Z. 805
- **Verwandt:** CON-0009, OQ-0030

Bei längeren Datenlücken soll der Zustand nicht einfach mit einer angenommenen Standardbelastung weitergeführt werden. Stattdessen wird die Schätzung als veraltet beziehungsweise unvollständig gekennzeichnet.

**Akzeptanzkriterien:**
- [ ] Nach einer längeren Lücke ist der Wert als veraltet oder unvollständig markiert.
- [ ] Die Dauer einer längeren Lücke folgt PAR-098.

### FR-0127 — Getrennt von der Training Readiness
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §12.5, Z. 807
- **Verwandt:** FR-0109

Die Energiereserve und die Training Readiness werden getrennt geführt. Sie können ähnliche Eingangssignale verwenden, beschreiben aber unterschiedliche Konzepte.

**Akzeptanzkriterien:**
- [ ] Beide Werte erscheinen als eigene Größen und werden nicht verrechnet.

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0007](../migration/open-questions.md#oq-0007--energiereserve-nur-mit-kontinuierlichen-wearable-daten) (entschieden): Energiereserve nur mit kontinuierlichen Wearable-Daten?
- [OQ-0030](../migration/open-questions.md#oq-0030--parameter-der-energiereserve) (entschieden): Parameter der Energiereserve
- [OQ-0048](../migration/open-questions.md#oq-0048--rechtliche-prüfung) (non-blocking): Rechtliche Prüfung
<!-- END OQ -->

## Quellen
- SRC-001: §12, Z. 737–807; §25 Nr. 12
