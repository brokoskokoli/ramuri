# ADR-0001 — Nur lokale Datenhaltung

- **Status:** Accepted
- **Datum:** 2026-11-03
- **Quellen:** SRC-003 (Entscheidung zu OQ-0023), SRC-001 §1.1 Nr. 6 (Z. 28), §21 (Z. 1242)
- **Betroffene Anforderungen:** CON-0008, SEC-0006, FR-0192

## Kontext
Das Konzept fordert Datenhoheit und Berechnungen ohne zwingende externe Übertragung, sagt aber nichts zu Konto, Server oder Gerätewechsel.

## Entscheidung
Alle Daten bleiben auf dem Gerät. Es gibt kein Benutzerkonto und keinen eigenen Server. Eine direkte Strava-Anbindung ist deshalb zurückgestellt (OQ-0049).

## Erwogene Alternativen
- Lokal mit optionalem Cloud-Backup
- Konto mit eigenem Server

## Konsequenzen
- Kein Serverbetrieb und weniger Datenschutzaufwand.
- Keine Nutzung auf mehreren Geräten zugleich.
- Geht das Gerät verloren, sind nicht exportierte Daten verloren, weil System-Backups immer aus sind (SEC-0010).
- Ein Gerätewechsel läuft über den Gesamtexport und den Reimport (FR-0198).

## Offene Punkte
Keine. Dienste, die einen eigenen Server oder ein ausgeliefertes Secret verlangen, werden nicht angebunden (OQ-0047, OQ-0049).
