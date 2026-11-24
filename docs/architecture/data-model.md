# Fachliches Datenmodell

**Status:** Draft, nicht bindend. Dies ist ein aus den Anforderungen abgeleitetes **Begriffsmodell** und kein Persistenzmodell. Die Daten liegen lokal (ADR-0001). Rohdaten bleiben erhalten, solange der Lauf existiert (OQ-0031). Identitäten, Lebenszyklen und Migrationen sind TBD.

| Fachobjekt | Wesentliche Inhalte laut Quelle | Anforderungen |
|---|---|---|
| Profil | Basiswerte aus der Felderliste | FR-0002 |
| Bekanntes Gerät | Gerät, Bevorzugung | FR-0013, FR-0014 |
| Lauf | Art (GPS, Laufband, andere Sportart mit Sportart), Zeiten (Bewegung, gesamt), Strecke, Runden, Zusammenfassung, subjektive Angaben | FR-0037, FR-0038, FR-0052, FR-0196, FR-0221 |
| Messreihe | Zeitstempel, Wert, Quellgerät, Zustand des Werts | FR-0020, FR-0046, FR-0057 |
| Bewerteter Abschnitt | Teil eines Laufs mit Qualitätsbewertung | FR-0048, FR-0073 |
| Fitnesswert | Wert plus Zeitpunkt, Datenzeitraum, Anzahl Messungen, Quellen, Methode, Version, Qualitätsstufe; an Laufwerten die Kettenversion der Vorverarbeitung; ursprünglicher und neu berechneter Wert | FR-0053, FR-0058 |
| Belastung | TRIMP und sRPE getrennt; Tageswerte; ATL, CTL, TSB | FR-0092, FR-0095, FR-0096, FR-0098 bis FR-0101 |
| Gesundheitsdatensatz | Importierte Daten mit Quelle und Messmethode | FR-0023, FR-0115 |
| Readiness-Bewertung | Stufe, Wert, Zustand, Ursachen | FR-0105, FR-0109, FR-0116, FR-0117 |
| Energiereserve (ab Phase 4, DEC-0060) | Zeitverlauf 0–100, Vollständigkeit | FR-0122, FR-0126 |
| Prognose | Distanz, Referenzleistung, Art | FR-0129, FR-0133 |
| Ziel | Typ, optionale Zusatzangaben | FR-0135, FR-0136 |
| Plan und geplante Einheit | Phase, Wochenbudget; Einheit mit Tag, Ziel, Dauer oder Distanz, Intensität, Zustand | FR-0141, FR-0143, FR-0148, FR-0172 |
| Einwilligung | Datenquelle oder Empfänger, Zustand | SEC-0001, SEC-0002, SEC-0007 |
| Externe Verknüpfung | Strava-Verbindung, Upload-Status je Lauf | FR-0185, FR-0188, FR-0190 |

## Art eines Laufs (`runs.mode`, `runs.sport`)

Seit Schema 18 (`schema.drift`, Archivabschnitt 1, [Archivvertrag](../contracts/archive.md)):

- **`mode`:** `gps` (GPS-Lauf), `treadmill` (Laufband, FR-0196) oder `sport` (andere Sportart, FR-0221). Läufe aus älteren Schemata behalten ihren Wert.
- **`sport`:** die Sportart bei `mode` = `sport`: `rope` (Seilspringen), `cycling` (Radfahren), `rowing` (Rudern/Ergometer) oder `other` (Sonstiges); bei `gps` und `treadmill` immer `null`. Ein CHECK über beide Spalten lehnt jede andere Kombination ab; die Migration auf Schema 18 ändert keine Daten (`sport` = `null`).
- **Verwendung:** Eine Einheit mit `sport` hat keine Positionen, Schritte, Strecke und Laufwerte; ihr Puls, ihre Pausen und ihre Belastung stehen wie beim Lauf in den übrigen Tabellen (FR-0221, PAR-232).

## Kettenversion der Vorverarbeitung (`computed_values.preprocessing_version`)

Seit Schema 19 (`schema.drift`, Archivabschnitt 12, [Archivvertrag](../contracts/archive.md), [ADR-0004](adr/ADR-0004-algorithmen-rohdaten-versionierung.md)):

- **Inhalt:** Text aus den Versionen aller Stufen der Vorverarbeitung, aus denen ein Laufwert entstand, in fester Reihenfolge (Puls, Pace, Bewegungszeit, Position, Höhe, Einschwingen, Abschnittsqualität, Schritte), z. B. `hr1.pace1.mov2.pos2.alt1.set1.sq2.st1` (`preprocessingChainVersion` im Kern). Jede Stufe mit eigener Methodenversion gehört dazu.
- **Wo:** an jedem Laufwert, an `original` und `current` je eigener Wert; das Original behält die Kette, mit der es entstand. Tageswerte tragen `null`.
- **Migration auf Schema 19:** Alle bestehenden Laufwerte bekommen die Kette, mit der sie damals gerechnet wurden (`legacyPreprocessingChainVersion`, fest), Tageswerte bleiben `null`. Ein Archiv mit Schema 18 oder früher liest sich ebenso.
- **Verwendung:** Die Prüfung auf neue Versionen (`RecalculationService.checkVersions`) vergleicht die Kette des aktuellen Laufwerts (VO2max, TRIMP, Zeit über der Intensitätsschwelle) mit der aktuellen Kette, gemeinsam mit Methoden- und Parameterversion. Weicht sie ab, bietet die App eine Neuberechnung an; dabei bleibt das Original unverändert, `current` bekommt die neue Kette.

## Schritte eines Laufs (`raw_steps`)

Speicherung der Schrittfrequenz des Smartphones (FR-0202, FR-0183); Tabelle `raw_steps` (`schema.drift`), Archivabschnitt 7 ([Archivvertrag](../contracts/archive.md)).

- **`step_count`:** kumulierter Schrittzähler des Laufs, gezählt ab Laufbeginn aus den Schritten, die der Schrittdetektor des Telefons meldet; Schritte während einer manuellen Pause zählen nicht (in der automatischen Pause schon). Nach dem Fortsetzen eines unterbrochenen Laufs (FR-0193) zählt der Zähler vom höchsten gespeicherten Wert weiter, nie doppelt und nie von 0. Der Zähler fällt innerhalb eines Laufs nicht.
- **`time_us`:** Zeitpunkt des Empfangs in derselben Zeitbasis wie die Anzeige und die übrigen Rohdaten des Laufs (Sitzungszeit, UTC).
- **`source`:** `phone`. **`state`:** `present`.
- **Dichte:** höchstens ein Wert je Anzeigetakt; kommen mehrere Meldungen vor dem nächsten Schreiben, bleibt nur der neueste Zählerstand (verlustfrei, weil kumuliert).
- **Laufband:** gilt genauso für Läufe im Laufbandmodus (FR-0196).
- **Andere Sportart:** eine Einheit mit `mode` = `sport` (FR-0221) speichert keine Schritte; sie hat keine Kadenz.
- **Verwendung:** Die Schrittfrequenz im Export rechnet der Dateiexport aus dem Zuwachs des Zählers ([Dateiexport-Vertrag](../contracts/file-export.md), Regel 11). Löschen eines Laufs und „Alles löschen“ entfernen die Werte (SEC-0004); Archiv und Reimport enthalten sie.

## Datenhoheit

Läufe und Fitnessdaten müssen unabhängig von externen Plattformen nutzbar und exportierbar bleiben (CON-0008). Fremde und eigene VO₂max-Werte werden nicht ungeprüft zusammengeführt (FR-0024). TRIMP und sRPE werden zunächst getrennt geführt (FR-0096).
