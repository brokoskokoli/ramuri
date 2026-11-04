# Fachliches Datenmodell

**Status:** Draft, nicht bindend. Dies ist ein aus den Anforderungen abgeleitetes **Begriffsmodell** und kein Persistenzmodell. Die Daten liegen lokal (ADR-0001). Rohdaten bleiben erhalten, solange der Lauf existiert (OQ-0031). Identitäten, Lebenszyklen und Migrationen sind TBD.

| Fachobjekt | Wesentliche Inhalte laut Quelle | Anforderungen |
|---|---|---|
| Profil | Basiswerte aus der Felderliste | FR-0002 |
| Bekanntes Gerät | Gerät, Bevorzugung | FR-0013, FR-0014 |
| Lauf | Zeiten (Bewegung, gesamt), Strecke, Runden, Zusammenfassung, subjektive Angaben | FR-0037, FR-0038, FR-0052 |
| Messreihe | Zeitstempel, Wert, Quellgerät, Zustand des Werts | FR-0020, FR-0046, FR-0057 |
| Bewerteter Abschnitt | Teil eines Laufs mit Qualitätsbewertung | FR-0048, FR-0073 |
| Fitnesswert | Wert plus Zeitpunkt, Datenzeitraum, Anzahl Messungen, Quellen, Methode, Version, Qualitätsstufe; ursprünglicher und neu berechneter Wert | FR-0053, FR-0058 |
| Belastung | TRIMP und sRPE getrennt; Tageswerte; ATL, CTL, TSB | FR-0092, FR-0095, FR-0096, FR-0098 bis FR-0101 |
| Gesundheitsdatensatz | Importierte Daten mit Quelle und Messmethode | FR-0023, FR-0115 |
| Readiness-Bewertung | Stufe, Wert, Zustand, Ursachen | FR-0105, FR-0109, FR-0116, FR-0117 |
| Energiereserve (ab Phase 4, DEC-0060) | Zeitverlauf 0–100, Vollständigkeit | FR-0122, FR-0126 |
| Prognose | Distanz, Referenzleistung, Art | FR-0129, FR-0133 |
| Ziel | Typ, optionale Zusatzangaben | FR-0135, FR-0136 |
| Plan und geplante Einheit | Phase, Wochenbudget; Einheit mit Tag, Ziel, Dauer oder Distanz, Intensität, Zustand | FR-0141, FR-0143, FR-0148, FR-0172 |
| Einwilligung | Datenquelle oder Empfänger, Zustand | SEC-0001, SEC-0002, SEC-0007 |
| Externe Verknüpfung | Strava-Verbindung, Upload-Status je Lauf | FR-0185, FR-0188, FR-0190 |

## Datenhoheit

Läufe und Fitnessdaten müssen unabhängig von externen Plattformen nutzbar und exportierbar bleiben (CON-0008). Fremde und eigene VO₂max-Werte werden nicht ungeprüft zusammengeführt (FR-0024). TRIMP und sRPE werden zunächst getrennt geführt (FR-0096).
