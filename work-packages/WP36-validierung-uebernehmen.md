# WP36 – Ergebnis der Kamera-Validierung übernehmen (`core/src/ppg`, `core/src/readiness`, Einstellungen)

**Zuordnung:** M3, Welle 5. Status `wartet` bis zum Ergebnis der Validierungsmessung (Folgeanalyse zu R009 mit den Messpaaren aus WP33).

Bezug: FR-0215, PAR-160K, PAR-162K, Validierungssperre (K-1), DEC-0074 (E2, E6, E7a bis E7c), K61; R009 Abschnitt 6 und Offene Punkte 2, 4b. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md).

## Problem
Nach der Validierung steht fest, ob Kamera-RMSSD und Kamera-Ruhepuls „bestanden“, „eingeschränkt“ oder „nicht bestanden“ sind und welche RMSSD-Qualitätsgrenze gilt. Das muss in die App, ohne die Logik neu zu bauen (WP33 und WP34 haben alle Zweige schon).

## Inhalt
1. **Teil A:** Validierungsstand je Größe (lnRMSSD liegend, sitzend nach E6 vorläufig wie liegend mit „liegend verglichen“; Ruhepuls) in der Konstante aus WP33 setzen; RMSSD-Qualitätsgrenze aus der Validierung als PAR mit Nummer eintragen; bei geänderter MAD-Grenze für den Ruhepuls (R009, Offene Punkte 4b) PAR-162K nach Entscheidung des Maintainers ändern. Neue Regelversion bzw. Methodenversion nach NFR-0001.
2. **Teil B:** Bei „bestanden“ erscheint der Opt-in-Schalter mit Wortlaut „experimentell, mit einem Brustgurt verglichen (ein Handy)“; bei „nicht bestanden“ für den Ruhepuls der Hinweis „ungenauer als erwartet“ am Profilvorschlag aus WP27 (E7b, Festlegung des Research Supervisors). Texte prüfen.

3. **Teil C:** Freischaltung der Morgenmessung für alle bei lnRMSSD liegend „bestanden“ (K62 F1, Vorentscheidung in WP33); bei gemischtem Ergebnis legt der Orchestrator dem Maintainer vor, ob sie im Entwicklermodus bleibt. Messungen mit dem Merkmal „vor der Validierung gemessen“ (K62 Punkt 6) lassen sich in der Auswertung getrennt halten.

## Abweichung vom Validierungsplan (R009, Abschnitt 6)
- **Referenz aus der App statt aus einer Logger-App:** R009 sieht vor, dass der Polar H9 die RR-Intervalle über eine eigene Logger-App mit RR-Export aufzeichnet. Nach K61 Punkt 3 speichert stattdessen die App selbst im Entwicklermodus die Gurt-RR parallel zur Kamera (WP33), und die Folgeanalyse liest sie aus dem CSV-Export (K62 F4). Vorteil: dieselbe Uhr und dasselbe 60-s-Fenster ohne Abgleich zweier Geräte. Risiko: Fehler im BLE-Weg der App (Paketlänge, verlorene Pakete, K55) wirken auf die Referenz; die Folgeanalyse prüft deshalb Lücken und Artefakte der Gurt-RR nach fester Regel und berichtet sie. Muss als Nachtrag in R009 bzw. im Auftrag der Folgeanalyse stehen und vom Maintainer bestätigt sein, bevor gemessen wird.

## Vorentscheidungen
- Schon gespeicherte Morgenmessungen werden mit der neuen Grenze neu bewertet (aus den gespeicherten Kamera-Schlagabständen, WP33), nicht neu gemessen.
- Der Entwicklermodus bleibt unverändert (K61).

## Abnahmekriterien
- [ ] Ergebnis der Validierung und Konzeptänderung vom Maintainer bestätigt (Änderungsprotokoll).
- [ ] Tests für den eingetragenen Stand; die Tests aller anderen Stände aus WP34 bleiben grün.
- [ ] E2E auf API 36 und 31: Opt-in bzw. Sperre wie im Ergebnis, Hinweis am Profilvorschlag falls „nicht bestanden“. Tests, die sich lohnen, committet in `app/integration_test/`. Gate grün auf GitHub.
- [ ] Teilwiederholung der Abschlussprüfung M3 für die Kamera-Zweige.
