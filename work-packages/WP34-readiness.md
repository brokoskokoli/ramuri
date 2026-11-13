# WP34 – Erweiterte Training Readiness (`core/src/readiness`, `features/readiness`, `home`)

**Zuordnung:** M3, Welle 2, nach WP32 und WP33.

Bezug: FR-0105, FR-0107 bis FR-0118, FR-0215 (Bewertung), FR-0209, FR-0181; PAR-147 bis PAR-150, PAR-159 bis PAR-172, PAR-189, K-1 (PAR-160K bis PAR-171K, Vorrang, Validierungssperre); OQ-0006 (neue Fassung), OQ-0029, OQ-0059; DEC-0042, DEC-0074, K46, K47, K61 Punkt 2, K62 (F1, Punkt 6); ACC-11; NFR-0001, NFR-0003. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md). Die Wirkung auf den Plan (PAR-173) gehört zu WP35.

## Problem
Aus Health-Connect-Reihen, Kamerareihen, Schlaf, Belastung und Befinden soll die App einen Wert 0–100 mit Zustand oder, wo die Daten nicht reichen, eine eingeschränkte Einschätzung bzw. „Unzureichende Daten“ zeigen, mit den wichtigsten Ursachen, ohne Diagnose und ohne fehlende Daten als normal zu werten.

## Inhalt
0. **Screens (Teil 0):** Die Karte „Erholung“ auf „Heute“ folgt `Main.dc.html` (Ring mit Zahl); neu mit Claude Design: Detailseite (Zahl oder eingeschränkte Einschätzung, Zustand, Stufe mit Grund, bis zu zwei Ursachen, Faktoren mit Quelle und Gewicht, fehlende Faktoren, markierte Tatsachen, Verlauf der Reihen über 28 Tage ohne Bevölkerungswerte). Freigabe durch den Maintainer.
1. **Reihen und Abweichung (Teil A, `core`):** Reihen je Quelle getrennt (FR-0115): Health Connect je Quell-App nach PAR-189 (Tageswerte aus WP32), Kamera je Haltung und Gerät (aus WP33). Robuste Abweichung nach FR-0113 mit PAR-161/162 bzw. PAR-161K/162K, keine Scheinpräzision (FR-0114), Hinweis „wenige Messungen“. Vorrangregel K-1 je Faktor.
2. **Validierungssperre und Entwicklermodus (Teil B, `core`):** Freigabe je Faktor aus Validierungsstand (Konstante aus WP33), Opt-in und Entwicklermodus: ohne Entwicklermodus genau K-1 (alle Stände; vor der Freischaltung gibt es ohne Entwicklermodus keine Kamerawerte, K62 F1); im Entwicklermodus gelten Kamera-Ruhepuls und Kamera-RMSSD unabhängig vom Stand wie nach bestandener Validierung mit eingeschaltetem Opt-in, ohne Kennzeichnung (K62 Punkt 6, ersetzt K61). Die Qualitätsgrenze je Messung gilt weiter. Markierte Tatsachen (K-1, ohne Entwicklermodus) gehen in keine Zahl und keinen Faktor ein.
3. **Wert, Zustand, Stufe, Erklärung (Teil C, `core`):** Teilskalen PAR-163, PAR-165 bis PAR-169 (Schlaf aus Health Connect oder Selbstangabe nach PAR-164K/165K), Gesamtwert PAR-170 mit Kappung 74, Zahl nur nach OQ-0006 (neue Fassung), sonst PAR-171 bzw. PAR-171K, Bänder nach FR-0116, Stufe PAR-147 bis PAR-150 mit Darstellung PAR-159, Erklärung PAR-172 als Textbausteine (wie die Erklärungen aus WP23). Versioniertes Modell `readiness v1` mit Gewichten.
4. **Anzeige (Teil D):** Karte „Erholung“ auf „Heute“: erweiterte Stufe mit Ring und Zahl oder eingeschränkte Einschätzung bzw. „Unzureichende Daten“; die Basisstufe aus WP23 bleibt, wenn keine Gesundheitsdaten freigegeben sind, und die Anzeige macht die Stufe erkennbar (FR-0105). Warnsignal vor jeder Einschätzung (PAR-173, Satz aus FR-0203). Detailseite nach Teil 0. Einstieg „Woher kommt das?“ wie bei den Erklärungen.

## Vorentscheidungen (selbst entschieden, einfachste Lösung)
- **Keine Speicherung des Werts:** Readiness wird bei Bedarf aus den gespeicherten Rohwerten berechnet (rein, deterministisch, mit Modellversion), kein neues Schema. Für die Planwirkung hält WP35 fest, was am Tag galt.
- **Entwicklermodus (Entscheidung des Maintainers, K62 Punkt 6):** Keine Kennzeichnung an Wert, Zahl, Trend oder Kurve; nur der unauffällige Hinweis „Entwicklermodus aktiv“ aus WP33. Das Merkmal „vor der Validierung gemessen“ geht nicht in die Rechnung ein. Auch die sitzende Reihe ohne „liegend verglichen“. Ohne Entwicklermodus gelten die Markierungen aus PAR-171K.
- **Schlafangabe:** Nur bei der Morgenmessung (PAR-164K), nicht zusätzlich auf der Karte.
- **„Heute“ für die Kamera:** Der Ortstag der Messung im Morgenfenster; für Health Connect der Tag, an dem die Hauptschlafphase endet (PAR-164).
- **Belastungsfaktor:** TSB% aus dem Belastungsdienst von WP19; fehlt er (PAR-073, PAR-090), gilt die Kappung aus PAR-170.
- **Fix oder adaptiv** ändert an der Anzeige nichts (K61 Punkt 1: erheben und anzeigen gilt immer).

## Umsetzung
- Teile je ein Coder-Auftrag; A und B zuerst (rein `core`), dann C, dann 0 und D.
- **Testfälle:** FR-0113 (z = 0 und z = 0,67), MAD = 0 → kein z, alle Rechenbeispiele aus Abschnitt 5 der Regeln als Test, Kappung 74, Vorrang Health Connect vor Kamera, Quellwechsel ohne Mischen, alle Stände der Sperre mit und ohne Opt-in und Entwicklermodus, sitzend mit „liegend verglichen“.
- **Eigenschaftstests:** Fehlende Faktoren heben den Wert nie über 74 ohne Belastungsfaktor; RMSSD und andere Reihen werden nie gemischt; eine markierte Tatsache ändert die Zahl nie.
- Mutationsbelege für jede PAR-Regel aus 160 bis 172 und für die Sperre.
- Sprachprüfung der Texte (PAR-172, PAR-174, FR-0118).
- **Parallel:** `home` nur hier (Welle 2 hat kein weiteres Paket). Texte mit Präfix `readiness`.

## Abnahmekriterien
- [ ] Screens freigegeben, im Repo unter `design/`.
- [ ] Akzeptanzkriterien von FR-0105, FR-0108 bis FR-0118 und die bewertenden Kriterien von FR-0215; ACC-11.
- [ ] Ohne Entwicklermodus und mit Stand „nicht geprüft“ entsteht ohne Uhr nie eine Zahl (E1, Test); im Entwicklermodus mit Kamera-RMSSD, Schlafangabe und Referenz entsteht dieselbe Zahl wie bei Stand „bestanden“ mit Opt-in, ohne Kennzeichnung (Test: gleiche Eingaben, gleiche Ausgabe; das Merkmal „vor der Validierung gemessen“ ändert nichts).
- [ ] Jede Erklärung im Test wird aus den Eingangsdaten belegt; keine Zahl ohne Einordnung.
- [ ] E2E auf API 36 und 31 mit synthetischen Reihen (Debug-Quelle aus WP32, Messungen aus WP33): Zahl mit Uhrdaten, eingeschränkte Einschätzung nur mit Kamera, „Unzureichende Daten“, Warnsignal vor der Einschätzung, Entwicklermodus an und aus. Hell und dunkel, Bildschirmfotos. Tests, die sich lohnen, committet in `app/integration_test/`. Gate grün auf GitHub.

## Ungeprüft
Verhalten der Zahl mit echten Nachtwerten verschiedener Quell-Apps und echter Kamera; R8 ist nur eine Rechnung. Feldtest.
