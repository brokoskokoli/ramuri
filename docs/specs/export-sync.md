---
id: FEAT-019
title: Export und externe Fitnessplattformen
status: Teilweise Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0182, FR-0183, FR-0184, FR-0185, FR-0186, FR-0187, FR-0188, FR-0189, FR-0190, FR-0191, FR-0192, FR-0198, FR-0201]
---

# Export und externe Fitnessplattformen

## Ziel
Aufgezeichnete Läufe und Fitnessdaten bleiben unabhängig von externen Plattformen nutzbar und exportierbar (CON-0008). Eine Strava-Verbindung ist vollständig optional (CON-0010). **Die Direktanbindung ist zurückgestellt (OQ-0049);** Phase 1 bietet Export und Teilen (FR-0201).

## Funktionale Anforderungen

### FR-0182 — Dateiexport als GPX, TCX und FIT
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §20.1, Z. 1191–1197; §25 Nr. 13, Z. 1408
- **Verwandt:** CON-0010, ACC-13, OQ-0032, OQ-0066

Die App soll aufgezeichnete Laufeinheiten in den standardisierten Formaten GPX, TCX und FIT exportieren können.

**Festlegung (OQ-0066):** FIT entsteht über einen eigenen Kodierer ohne Garmin-Code.

**Akzeptanzkriterien:**
- [ ] Ein GPS-Lauf lässt sich ohne Strava in jedem der drei Formate exportieren (ACC-13). Laufbandläufe: siehe FR-0196.
- [ ] Eine exportierte Datei entspricht dem jeweiligen Standardformat.

### FR-0183 — Exportinhalte
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §20.1, Z. 1199–1205

Exportiert werden je nach Format: GPS-Strecke, Zeitstempel, Herzfrequenz, Höhenwerte und gegebenenfalls Kadenz und weitere vorhandene Trainingsdaten.

**Akzeptanzkriterien:**
- [ ] Vom Format unterstützte, vorhandene Werte stimmen nach dem Export mit dem gespeicherten Lauf überein.
- [ ] Fehlende Herzfrequenz wird nicht als 0 exportiert.

### FR-0184 — Zusatzmetriken separat exportierbar
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §20.1, Z. 1207
- **Verwandt:** OQ-0032

Nicht unterstützte Zusatzmetriken, beispielsweise eine selbst berechnete VO₂max, müssen bei Bedarf separat exportierbar sein.

**Akzeptanzkriterien:**
- [ ] Eine selbst berechnete VO₂max lässt sich exportieren.
- [ ] TBD: Format (OQ-0032).

### FR-0185 — Strava-Konto einmalig verknüpfen
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1211–1215
- **Verwandt:** SEC-0003, SEC-0008, OQ-0024, OQ-0049

Optional kann der Nutzer sein Strava-Konto einmalig verknüpfen.

**Akzeptanzkriterien:**
- [ ] Die App ist ohne Verknüpfung voll nutzbar (CON-0010).
- [ ] Die Verknüpfung muss nicht vor jedem Upload wiederholt werden (Deutung von „einmalig“, OQ-0024).

### FR-0186 — Manueller Upload einzelner Läufe
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1216
- **Verwandt:** SEC-0008, OQ-0049

Der Nutzer kann einzelne Läufe manuell hochladen.

**Akzeptanzkriterien:**
- [ ] Hochgeladen wird nur der gewählte Lauf.

### FR-0187 — Optionale automatische Synchronisierung
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1217
- **Verwandt:** SEC-0003, SEC-0008, OQ-0025, OQ-0032, OQ-0049

Die automatische Synchronisierung ist optional.

**Akzeptanzkriterien:**
- [ ] Sie ist standardmäßig aus, bis der Nutzer eingewilligt hat (SEC-0008).
- [ ] Nach Laufende wird synchronisiert, sobald eine Verbindung besteht (OQ-0032).

### FR-0188 — Upload-Status anzeigen
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1218
- **Verwandt:** OQ-0049

Die App zeigt den Upload-Status an.

**Akzeptanzkriterien:**
- [ ] Zu einem Lauf ist erkennbar, ob er hochgeladen wurde oder der Upload fehlgeschlagen ist.

### FR-0189 — Uploadfehler behandeln
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1219
- **Verwandt:** CON-0010, OQ-0032, OQ-0049

Die App behandelt Uploadfehler.

**Akzeptanzkriterien:**
- [ ] Ein Uploadfehler verändert den lokalen Lauf nicht und ist für den Nutzer sichtbar.
- [ ] Bei einem Fehler wird der Upload wiederholt (OQ-0032).

### FR-0190 — Doppelte Uploads vermeiden
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1220
- **Verwandt:** OQ-0032, OQ-0049

Die App vermeidet doppelte Uploads.

**Akzeptanzkriterien:**
- [ ] Ein bereits hochgeladener Lauf erzeugt keine zweite Aktivität; dazu dient eine Upload-Kennung (OQ-0032).

### FR-0191 — Verbindung trennen
- **Status:** Draft | **Phase:** Zurückgestellt (OQ-0049)
- **Quelle:** SRC-001 §20.2, Z. 1221
- **Verwandt:** SEC-0007, OQ-0025, OQ-0049

Der Nutzer kann die Verbindung trennen.

**Akzeptanzkriterien:**
- [ ] Nach dem Trennen erfolgt kein Upload mehr, und die Zugangsdaten sind gelöscht.
- [ ] Lokale Läufe bleiben erhalten.

### FR-0192 — Gesamtexport der Nutzerdaten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §20.3, Z. 1229–1231; §25 Nr. 15, Z. 1410
- **Verwandt:** SEC-0004, CON-0008, ACC-15, OQ-0041, OQ-0032, SEC-0011, OQ-0050

Neben einzelnen Aktivitäten soll ein Gesamtexport der Nutzerdaten möglich sein. Dazu gehören Trainingshistorie, persönliche Einstellungen und verfügbare berechnete Fitnesswerte.

**Akzeptanzkriterien:**
- [ ] Der Export enthält alle drei genannten Bereiche (ACC-15), dazu Ziele, Pläne und eine aktive Warnmeldung.
- [ ] Der Export ist ein dokumentiertes Archiv und enthält auch die Rohdaten (OQ-0032).
- [ ] Das Archiv ist immer mit einem Passwort des Nutzers verschlüsselt und enthält keine Zugangsdaten und Einwilligungen (SEC-0011).

### FR-0198 — Reimport des Gesamtexports
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (OQ-0032)
- **Verwandt:** FR-0192, OQ-0032

Ein Gesamtexport lässt sich wieder importieren, damit ein Gerätewechsel möglich ist (ADR-0001).

**Akzeptanzkriterien:**
- [ ] Nach Export und Reimport auf einem anderen Gerät sind Läufe, Einstellungen und berechnete Werte vorhanden.
- [ ] Der Reimport prüft die Datei; eine beschädigte oder falsche Datei ändert keine Daten (OQ-0050).
- [ ] Er geht nur auf einer leeren App oder nach ausdrücklichem Zurücksetzen und weist darauf hin, dass ein älteres Archiv gelöschte Daten zurückbringen kann (OQ-0050).
- [ ] Einwilligungen werden danach neu eingeholt (OQ-0050).

### FR-0201 — Export teilen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §20.1, Z. 1191; SRC-003 (OQ-0049)
- **Verwandt:** FR-0182, CON-0010, OQ-0049

Der Nutzer kann die Exportdatei eines Laufs über das Teilen-Menü des Systems weitergeben, etwa um sie selbst bei Strava hochzuladen.

**Akzeptanzkriterien:**
- [ ] Eine FIT- oder GPX-Datei lässt sich über das Teilen-Menü weitergeben.
- [ ] Die App überträgt dabei nichts ohne Aktion des Nutzers.

## Abhängigkeiten
- Formate und externe Schnittstellen: siehe [Verträge](../contracts/README.md)

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0024](../migration/open-questions.md#oq-0024--schutz-gespeicherter-daten-und-zugangsdaten) (entschieden): Schutz gespeicherter Daten und Zugangsdaten
- [OQ-0025](../migration/open-questions.md#oq-0025--reichweite-von-einwilligung-widerruf-und-löschung) (entschieden): Reichweite von Einwilligung, Widerruf und Löschung
- [OQ-0032](../migration/open-questions.md#oq-0032--details-von-export-und-strava-synchronisierung) (non-blocking): Details von Export und Strava-Synchronisierung
- [OQ-0041](../migration/open-questions.md#oq-0041--phasen-der-noch-nicht-zugeordneten-anforderungen) (entschieden): Phasen der noch nicht zugeordneten Anforderungen
- [OQ-0049](../migration/open-questions.md#oq-0049--strava-ohne-server-und-ausgeliefertes-secret) (entschieden): Strava ohne Server und ausgeliefertes Secret
- [OQ-0050](../migration/open-questions.md#oq-0050--schutz-des-gesamtexports-und-regeln-für-den-reimport) (entschieden): Schutz des Gesamtexports und Regeln für den Reimport
- [OQ-0066](../migration/open-questions.md#oq-0066--weg-zum-fit-export) (entschieden): Weg zum FIT-Export
<!-- END OQ -->

## Quellen
- SRC-001: §20, Z. 1187–1231
