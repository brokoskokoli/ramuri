# ADR-0004 — Austauschbare Algorithmen, Rohdaten und Versionierung der Modelle

- **Status:** Accepted (Maintainer, 2026-11-04)
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0031, OQ-0043, OQ-0045, OQ-0053)
- **Betroffene Anforderungen:** NFR-0001, NFR-0002, NFR-0005, FR-0006, FR-0020, FR-0053, FR-0057, FR-0058, FR-0075, FR-0097, FR-0192, FR-0197, SEC-0004, OQ-0031, OQ-0043

## Kontext
Alle Algorithmen sind austauschbar, wählbar ist nur das Belastungsmodell (OQ-0043). Eine zweite Variante darf Aufzeichnung und Rohdaten nicht berühren (NFR-0005). Rohdaten bleiben, solange der Lauf existiert, und ursprüngliche Werte bleiben neben neu berechneten erhalten (OQ-0031, FR-0058). Beim Wechsel des Belastungsmodells wird nach Bestätigung alles neu gerechnet, sodass ein Verlauf nur ein Modell nutzt (OQ-0045).

## Entscheidung
**1. Drei getrennte Datenebenen:**
- **Rohdaten:** Nur anhängen, nie ändern. Je Wert Zeitstempel, Quellgerät und Zustand (FR-0020, FR-0057). Gelöscht wird nur mit dem Lauf (SEC-0004).
- **Vorverarbeitung:** Abgeleitet und jederzeit neu berechenbar; Rohdaten bleiben dabei unberührt (FR-0045).
- **Berechnete Werte:** Je Wert Methode, Version, Parameterstand und die übrigen Angaben aus FR-0053.

**2. Algorithmen in `core`** (ADR-0002): Je Familie ein Interface, etwa Belastungsmodell oder VO₂max-Schätzer, als reine Funktion aus Eingabe und Parametersatz auf Ergebnis. Keine Zeit, kein Zufall und keine Plattform im Inneren. Eine Registry im Zusammenbau der App ordnet Familie und aktive Variante zu. Der Nutzer wählt nur beim Belastungsmodell (FR-0197), alle anderen Varianten sind Konfiguration im Code.

**3. Versionen:**
- Kennung `method` (etwa `edwards-trimp`), `methodVersion` (Ganzzahl) und `parameterVersion` (Stand der PAR-Tabellen) werden am Wert gespeichert (NFR-0001, FR-0075).
- Jede Änderung, die ein Ergebnis ändern kann, erhöht die Version.
- Alte Implementierungen bleiben nicht im Code. Ursprüngliche Werte werden gelesen, nie nachgerechnet.
- Die Referenzwerte aus [testing.md](../../quality/testing.md) sind feste Tests je Variante. Die Zuordnung zur Kategorie aus NFR-0002 steht an der Variante.

**4. Ursprung und aktueller Stand:** Je Wert höchstens zwei Zeilen: unveränderlich `original` mit ursprünglicher Qualität und `current`. Das reicht für die drei Angaben aus FR-0058. Zwischenstände mehrerer Neuberechnungen entfallen.

**5. Neuberechnung:** Ein Dienst in `core` rechnet nach Bestätigung (FR-0058, FR-0197) in einen Zwischenstand und tauscht ihn in einer Transaktion gegen `current`. So bleibt ein Verlauf auch bei einem Abbruch einheitlich (FR-0097). Lehnt der Nutzer ab, ändert sich nichts an den Daten (OQ-0053).

**6. Schema:** Versionierte drift-Migrationen mit Test je Schritt. Das Archiv (FR-0192) enthält alle drei Ebenen mit ihren Kennungen.

## Erwogene Alternativen
- **Nur berechnete Werte speichern:** Widerspricht OQ-0031.
- **Jeden Rechenlauf aufheben:** Volle Historie, aber die Spec verlangt sie nicht, und sie wächst mit jeder Änderung der Basiswerte.
- **Alte Algorithmen mitführen und ursprüngliche Werte nachrechnen:** Mehr Code und Pflege, ohne Anforderung.
- **Regel-DSL oder Laden zur Laufzeit:** Kein Bedarf, Varianten kommen mit der App.
- **Event Sourcing für alles:** Für eine lokale Einzelnutzer-App übertrieben. Nur die Rohdaten folgen dem Muster.

## Konsequenzen
- Ein Test kann NFR-0005 direkt prüfen: Eine zusätzliche Fake-Variante läuft, ohne dass sich Aufzeichnung oder Rohdatenschema ändern.
- Vorverarbeitung und Modelle lassen sich ohne Gerät mit synthetischen Läufen testen.
- Der Speicher wächst unbegrenzt mit den Läufen, weil Rohdaten bleiben. Die Spec setzt keine Grenze, und ohne Felddaten ist die Größe nicht bekannt.
- Das Archivformat bleibt offen (OQ-0032). Wie ein älterer Stand ein Archiv einer neueren Version behandelt, ist nicht festgelegt.

## Im Emulator nicht belegbar
Diese Entscheidung hängt kaum am Gerät und ist in Unit-Tests prüfbar. Nicht belegbar sind die Modellgüte (NFR-0004, OQ-0020), die Dauer einer Neuberechnung über viele echte Läufe auf einem schwachen Telefon und die tatsächliche Datenmenge.

## Offene Punkte
Keine; es sind keine externen Abhängigkeiten und deshalb keine Belege von außen nötig.
