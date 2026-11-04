# Nichtfunktionale Anforderungen

**Status:** Draft. Die Quelle nennt keine messbaren Zielwerte für Performance, Akkuverbrauch oder Verfügbarkeit. Sie werden hier nicht erfunden (OQ-0035).

## Modellqualität

### NFR-0001 — Algorithmen versionierbar und nachvollziehbar
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §23, Z. 1270–1272
- **Verwandt:** FR-0053, FR-0058

Alle fitnessbezogenen Algorithmen müssen versionierbar und nachvollziehbar sein.

**Akzeptanzkriterien:**
- [ ] Jeder berechnete Fitnesswert nennt Methode und Berechnungsversion.

### NFR-0002 — Einordnung in drei Verfahrenskategorien
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §23.1, Z. 1276–1305

Es wird zwischen drei Kategorien unterschieden:

| Kategorie | Beispiele |
|---|---|
| A. Etablierte Rechenverfahren | Herzfrequenzreserve; ACSM-Gleichungen zur Sauerstoffbedarfschätzung; TRIMP; exponentiell gewichtete Trainingsbelastung; Riegel-Leistungsprognose |
| B. Eigene, heuristische Verfahren | Gewichtung einzelner VO₂max-Segmente; Qualitätsbewertung; Training-Readiness-Score; Energiereserve; regelbasierte Trainingsanpassung |
| C. Individuell kalibrierte Verfahren | Nutzerabhängige VO₂max-Korrektur; individuelle Trainingszonen; individuelle Belastungsverträglichkeit; Prognosen anhand eigener Leistungshistorie |

**Akzeptanzkriterien:**
- [ ] Jedes Berechnungsverfahren der App ist genau einer Kategorie zugeordnet und dokumentiert.

### NFR-0003 — Heuristiken nicht als validiert darstellen
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §23.1, Z. 1307
- **Verwandt:** FR-0054

Eigene Heuristiken dürfen nicht als wissenschaftlich validiert dargestellt werden, solange keine entsprechende Validierung stattgefunden hat.

**Akzeptanzkriterien:**
- [ ] Texte zu Verfahren der Kategorie B behaupten ohne dokumentierte Validierung keine wissenschaftliche Absicherung.

### NFR-0004 — Validierung vor Genauigkeitsaussagen
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-001 §8.3, Z. 409; §11.2, Z. 695; §12.4, Z. 791
- **Verwandt:** FR-0072, FR-0110, FR-0124, OQ-0020

Modellparameter und Schätzer aus den genannten Stellen sind vor einer Genauigkeitsaussage zu validieren beziehungsweise empirisch zu kalibrieren.

**Akzeptanzkriterien:**
- [ ] Zu jeder Genauigkeitsaussage in der App gibt es einen dokumentierten Validierungsnachweis.
- [ ] Die Validierung erfolgt im Feldtest und ist kein Release-Gate (OQ-0020).

### NFR-0005 — Austauschbare Algorithmen
- **Status:** Approved | **Phase:** 1*
- **Quelle:** SRC-003 (Maintainer 2026-11-03)
- **Verwandt:** NFR-0001, NFR-0002, FR-0197, OQ-0043

Alle verwendeten Algorithmen sind austauschbar. `1*`: Die Funktion zur Auswahl kommt später, die Architektur muss den Austausch aber von Anfang an erlauben.

**Akzeptanzkriterien:**
- [ ] Eine zweite Variante eines Algorithmus lässt sich ergänzen, ohne Aufzeichnung und gespeicherte Rohdaten zu ändern.
- [ ] Jeder berechnete Wert ist der Variante zugeordnet, die ihn erzeugt hat (NFR-0001).
- [ ] Für Nutzer wählbar ist nur das Belastungsmodell; alle übrigen Algorithmen sind technisch austauschbar (OQ-0043).

### NFR-0006 — Sprachen und Einheiten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (OQ-0035)
- **Verwandt:** CON-0001, FR-0031, OQ-0035, OQ-0067

Die App ist auf Deutsch und Englisch verfügbar. Bei jeder anderen Gerätesprache zeigt sie Englisch (OQ-0067). Strecken werden in Kilometern und optional in Meilen angezeigt.

**Akzeptanzkriterien:**
- [ ] Alle Texte der App liegen auf Deutsch und Englisch vor.
- [ ] Bei einer anderen Gerätesprache erscheint die App auf Englisch.
- [ ] Der Nutzer kann Kilometer oder Meilen wählen; die gespeicherten Rohdaten ändern sich dadurch nicht.

## Noch nicht festgelegt

Zielwerte für Akku und Genauigkeit werden nach ersten Feldtests festgelegt (OQ-0035). Die Android-Mindestversion wird per ADR vorgeschlagen und freigegeben. Zu Barrierefreiheit und Antwortzeiten gibt es noch keine Vorgabe.
