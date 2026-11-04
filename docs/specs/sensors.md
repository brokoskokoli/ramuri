---
id: FEAT-002
title: Sensoren und Fitnessgeräte
status: Teilweise Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0007, FR-0008, FR-0009, FR-0010, FR-0011, FR-0012, FR-0013, FR-0014, FR-0015, FR-0016, FR-0017, FR-0018, FR-0019, FR-0020, FR-0021]
---

# Sensoren und Fitnessgeräte

## Ziel
Der Nutzer verwendet seine bevorzugten Herzfrequenzquellen ohne Bindung an einen Hersteller (CON-0003).

## Scope
- Direkte Herzfrequenzmessung und Sensorverwaltung
- Erweiterte Sensordaten, sofern das Gerät sie liefert

## Nicht im Scope
- Import aus Gesundheitsplattformen: siehe [health-import.md](health-import.md)

## Funktionale Anforderungen

### FR-0007 — Unterstützte Gerätekategorien
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3 und §3.1, Z. 63–74
- **Verwandt:** CON-0003, OQ-0009, ACC-02

Die App unterstützt verschiedene Quellen für Herzfrequenzdaten: Bluetooth-Brustgurte, Bluetooth-Oberarmsensoren, Fitnessuhren mit Herzfrequenz-Broadcast, Fitnessarmbänder mit geeigneter Schnittstelle, Kopfhörer mit integrierter Herzfrequenzmessung und weitere kompatible Herzfrequenzsensoren.

Phase 1 nennt nur „kompatible Bluetooth-Pulssensoren“ (SRC-001 §24, Z. 1339).

**Akzeptanzkriterien:**
- [ ] Ein kompatibler Bluetooth-Pulssensor lässt sich verbinden und während eines Laufs live auslesen (ACC-02).

### FR-0008 — Automatische Erkennung standardisierter Geräte
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.1, Z. 76
- **Verwandt:** FR-0011

Die App soll standardisierte Bluetooth-Herzfrequenzgeräte automatisch erkennen können.

**Akzeptanzkriterien:**
- [ ] Ein standardisiertes Gerät in Reichweite erscheint ohne herstellerspezifische Einrichtung als verfügbares Gerät.

### FR-0009 — Ergänzende Uhrenanwendung
- **Status:** Draft | **Phase:** 4 (möglich)
- **Quelle:** SRC-001 §3.1, Z. 78
- **Verwandt:** OQ-0009, OQ-0017

Fitnessuhren ohne standardisierte Live-Übertragung sollen gegebenenfalls durch eine ergänzende Uhrenanwendung unterstützt werden können.

### FR-0010 — Herstellerspezifische Anbindungen sind optional
- **Status:** Draft | **Phase:** 4 (möglich)
- **Quelle:** SRC-001 §3.1, Z. 80
- **Verwandt:** CON-0003, OQ-0009, OQ-0017

Herstellerspezifische Anbindungen sind optionale Erweiterungen.

**Akzeptanzkriterien:**
- [ ] Grundfunktionen setzen keine herstellerspezifische Anbindung voraus.

### FR-0011 — Geräte suchen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 84–86
- **Verwandt:** FR-0008

Der Nutzer kann verfügbare Geräte suchen.

**Akzeptanzkriterien:**
- [ ] Die Suche listet verfügbare kompatible Geräte auf.

### FR-0012 — Gerät verbinden und trennen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 87
- **Verwandt:** ACC-02

Der Nutzer kann ein Gerät verbinden und trennen.

**Akzeptanzkriterien:**
- [ ] Nach dem Verbinden liefert das Gerät Werte; nach dem Trennen nicht mehr.

### FR-0013 — Mehrere bekannte Geräte speichern
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 88

Der Nutzer kann mehrere bekannte Geräte speichern.

**Akzeptanzkriterien:**
- [ ] Mindestens zwei Geräte bleiben als bekannt gespeichert.

### FR-0014 — Bevorzugtes Gerät festlegen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 89
- **Verwandt:** FR-0019

Der Nutzer kann ein bevorzugtes Gerät festlegen.

**Akzeptanzkriterien:**
- [ ] Die Festlegung bleibt gespeichert und ist änderbar.

### FR-0015 — Aktuelle Herzfrequenz anzeigen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 90

Die aktuelle Herzfrequenz eines verbundenen Geräts wird angezeigt.

**Akzeptanzkriterien:**
- [ ] Bei einem verbundenen Sensor ist der aktuelle Wert sichtbar.

### FR-0016 — Batteriestand anzeigen, sofern bereitgestellt
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 91

Der Batteriestand wird angezeigt, sofern das Gerät ihn bereitstellt.

**Akzeptanzkriterien:**
- [ ] Liefert das Gerät keinen Batteriestand, wird kein erfundener Wert angezeigt.

### FR-0017 — Verbindungsabbrüche erkennen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 92
- **Verwandt:** FR-0036, FR-0056, ACC-03

Verbindungsabbrüche werden erkannt.

**Akzeptanzkriterien:**
- [ ] Ein Abbruch ist im Sensorstatus sichtbar.
- [ ] Die Zeit ohne Werte wird nicht als Nullmessung gespeichert (FR-0056).

### FR-0018 — Datenquelle während des Trainings wechseln
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 93
- **Verwandt:** FR-0019, FR-0020, OQ-0018

Der Nutzer kann während eines Trainings die Datenquelle wechseln.

**Akzeptanzkriterien:**
- [ ] Ein Wechsel unterbricht die laufende Aufzeichnung nicht.
- [ ] Während eines Laufs wechselt die App nicht automatisch zum bevorzugten Gerät zurück (OQ-0037).
- [ ] Nach dem Wechsel ist die Herkunft der Werte je Zeitabschnitt erkennbar.

### FR-0019 — Eindeutige Priorisierung ohne Vermischung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 95
- **Verwandt:** FR-0014, OQ-0018

Bei mehreren aktiven Herzfrequenzquellen muss eine eindeutige Priorisierung erfolgen. Unterschiedliche Messwerte dürfen nicht unkontrolliert vermischt werden.

**Akzeptanzkriterien:**
- [ ] Bei zwei aktiven Quellen ist für jeden verwendeten Wert eindeutig, aus welcher Quelle er stammt; Werte werden nicht unkontrolliert vermischt.
- [ ] Das bevorzugte Gerät hat Vorrang; ein Wechsel erfolgt nur manuell oder nach einem Verbindungsabbruch (OQ-0018).

### FR-0020 — Herkunft der Messwerte dokumentieren
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §3.2, Z. 97
- **Verwandt:** SEC-0005

Die App dokumentiert, von welchem Gerät die Messwerte stammen.

**Akzeptanzkriterien:**
- [ ] Für einen gespeicherten Lauf ist das Quellgerät der Herzfrequenz abrufbar.

### FR-0021 — Erweiterte Sensordaten aufzeichnen
- **Status:** Draft | **Phase:** 4
- **Quelle:** SRC-001 §3.3, Z. 101–109
- **Verwandt:** OQ-0013

Falls vorhanden, können zusätzlich RR-Intervalle, Herzfrequenzvariabilität (HRV), Laufkadenz, Laufleistung (Watt) und zusätzliche Bewegungsdaten aufgezeichnet werden. Die Verfügbarkeit ist geräteabhängig.

**Akzeptanzkriterien:**
- [ ] Ein Gerät ohne diese Daten führt zu keinem Fehler und zu keinen Ersatzwerten.

## Abhängigkeiten
- Geräteschnittstelle: siehe [Verträge](../contracts/README.md)

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0009](../migration/open-questions.md#oq-0009--rolle-der-smartwatch) (entschieden): Rolle der Smartwatch
- [OQ-0013](../migration/open-questions.md#oq-0013--was-bedeutet-laufleistung) (entschieden): Was bedeutet „Laufleistung“?
- [OQ-0017](../migration/open-questions.md#oq-0017--verbindlichkeit-der-phasen-und-fehlende-zuordnungen) (entschieden): Verbindlichkeit der Phasen und fehlende Zuordnungen
- [OQ-0018](../migration/open-questions.md#oq-0018--regel-für-die-priorisierung-von-herzfrequenzquellen) (entschieden): Regel für die Priorisierung von Herzfrequenzquellen
<!-- END OQ -->

## Quellen
- SRC-001: §3 bis §3.3, Z. 61–109
