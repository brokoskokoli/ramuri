---
id: FEAT-003
title: Import vorhandener Gesundheitsdaten
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0022, FR-0023, FR-0024, FR-0200]
---

# Import vorhandener Gesundheitsdaten

## Ziel
Fremde VO₂max-Werte bleiben getrennt. Kompatible Gesundheitsplattformen dienen mit Zustimmung des Nutzers als zusätzliche Datenquellen. Sie sind keine Voraussetzung für Grundfunktionen (CON-0007).

## Funktionale Anforderungen

### FR-0022 — Import nur mit Zustimmung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §3 und §3.4, Z. 113
- **Verwandt:** SEC-0001, SEC-0002, OQ-0033

Mit Zustimmung des Nutzers können kompatible Gesundheitsplattformen als zusätzliche Datenquellen dienen.

**Akzeptanzkriterien:**
- [ ] Ohne erteilte Zustimmung werden keine Daten importiert.

### FR-0023 — Importierbare Datenarten
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §3.4, Z. 115–122
- **Verwandt:** FR-0199, OQ-0033

Mögliche Daten sind historische Trainingseinheiten, Herzfrequenzverlauf, Ruheherzfrequenz, HRV, Schlafdauer und Schlafphasen sowie vorhandene VO₂max-Schätzwerte.

Phase 3 nennt nur Schlaf- und HRV-Daten (SRC-001 §24, Z. 1373–1374). Die übrigen Datenarten hat der Maintainer ebenfalls Phase 3 zugeordnet (OQ-0041).

**Entschieden (Maintainer 2026-11-13, K62 Punkt 2):** Trainings und Puls anderer Apps aus Health Connect werden nur angezeigt (im Verlauf mit Quelle und Pulskurve). In Belastung und Pausenregel zählen sie erst, wenn der Nutzer sie „als Training übernehmen“ wählt; das legt einen Nachtrag nach FR-0199 an. So zählt kein Training doppelt.

**Akzeptanzkriterien:**
- [ ] Importierte Daten sind als solche und mit ihrer Quelle erkennbar (SEC-0005).
- [ ] Importierte Trainings und Pulsdaten gehen erst nach „als Training übernehmen“ in Belastung und Pausenregel ein (FR-0199, K62 Punkt 2).

### FR-0024 — Fremde VO2max-Werte nicht ungeprüft zusammenführen
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §3.4, Z. 124
- **Verwandt:** FR-0081, OQ-0033

Importierte VO₂max-Werte anderer Hersteller dürfen zum Vergleich angezeigt werden, sollen aber nicht ungeprüft mit selbst berechneten Werten zu einer Zeitreihe zusammengeführt werden.

**Entschieden (OQ-0033):** Sie werden nie zusammengeführt.

**Akzeptanzkriterien:**
- [ ] Ungeprüft gelangt kein importierter Wert in die Zeitreihe der eigenen VO₂max-Schätzung.
- [ ] Werden importierte Werte zum Vergleich angezeigt, ist ihre Herkunft sichtbar.
- [ ] Fremde Werte werden nie mit eigenen zusammengeführt, sondern nur zum Vergleich gezeigt (OQ-0033).

### FR-0200 — Import über Health Connect
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-001 §3.4, Z. 113; SRC-003 (OQ-0033)
- **Verwandt:** FR-0022, SEC-0002, CON-0003, OQ-0033, OQ-0047, OQ-0059

Die App importiert über Android Health Connect. Die Google Health API ist zurückgestellt, bis der Android-Weg ohne Secret und die jährlichen Prüfkosten geklärt sind. Weitere Hersteller folgen erst, wenn sich ein Weg ohne eigenen Server ergibt (OQ-0047). Jede Quelle wird getrennt freigegeben. Grundfunktionen hängen an keinem Hersteller.

**Akzeptanzkriterien:**
- [ ] Der Zugriff auf Health Connect lässt sich je Datenart freigeben und widerrufen.
- [ ] Die App enthält kein ausgeliefertes Secret eines Anbieters (OQ-0047).
- [ ] Liefern mehrere Quell-Apps HRV oder Ruhepuls, gilt PAR-189.

## Datenschutz und Sicherheit
- Siehe [security.md](../quality/security.md)

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0033](../migration/open-questions.md#oq-0033--welche-gesundheitsplattformen-werden-unterstützt) (entschieden): Welche Gesundheitsplattformen werden unterstützt?
- [OQ-0047](../migration/open-questions.md#oq-0047--welche-hersteller-apis-und-gehen-sie-ohne-eigenen-server) (entschieden): Welche Hersteller-APIs, und gehen sie ohne eigenen Server?
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
<!-- END OQ -->

## Quellen
- SRC-001: §3.4, Z. 111–124
