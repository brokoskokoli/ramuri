# WP37 – Morgenmessung nach dem ersten Feldtest (`core/src/ppg`, `features/measure`, `features/sensors`)

**Zuordnung:** M3, nach WP33, vor dem Start der Validierungsmessung (Welle 2b). Anlass: erste echte Morgenmessung des Maintainers am 2026-11-14 (Rückmeldung, K66). Parallel zu WP34 und WP35 möglich.

Bezug: K66, K67, K68, K70, R010, FR-0215, FR-0115, FR-0217, PAR-160K, K62 (F1, F4, Punkt 6), K65; R009 Abschnitte 1, 2, 5, 6; `core/src/ppg/ALGORITHMUS.md` Abschnitte 2 und 10; WP07/WP26 (Pulssensoren, RR); SEC-0001 bis SEC-0010. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md).

## Problem
Beim ersten Feldtest zeigten sich drei Hürden, die die Validierungsmessung (28 Morgen) unnötig schwer machen:
1. **Gurt:** Die Morgenmessung zeigt nicht, ob ein Brustgurt verbunden ist. Der Maintainer musste vorher in die Einstellungen und den Gurt dort verbinden. Ohne Gurt fehlen die Referenz-RR für die Validierung.
2. **Ruhephase:** Die feste Ruhephase von 2 min passt nicht, wenn man gerade aufgewacht ist und ohnehin liegt.
3. **Qualität:** Das Messfenster ist fest 5–65 s ab Aufnahmebeginn. Wer am Anfang den Finger noch zurechtlegt, verliert die Messung: Die zweite Hälfte lief eine halbe Minute mit gutem Signal, trotzdem kam „nicht gut“ heraus (gültige Intervalle unter 70 % über das ganze Fenster), also kein RMSSD.

Auswertung der exportierten Messpaare (Orchestrator, nur lokal, Werte nicht im Repo): Bei der Messung mit Gurt war das erste Drittel des Fensters fast ohne gültige Intervalle, die übrigen zwei Drittel vollständig gültig; der Gesamtanteil lag knapp unter der Grenze für „gut“. In den gültigen Abschnitten stimmten die Kamera-Schlagabstände Schlag für Schlag eng mit den Gurt-RR überein, ebenso die daraus gerechnete RMSSD. Das stützt das wandernde Fenster; es ist eine Einzelmessung und ersetzt die Validierung nicht.

## Entscheidungen (Maintainer und Orchestrator, 2026-11-14, K66)
- **Gurt im Ablauf:** Die Morgenmessung zeigt oben den Gurtzustand: „verbunden: <Name>“, „verbinde …“ oder „kein Gurt“. Beim Öffnen sucht die App kurz nach einem bekannten Gurt (zuletzt genutztes Gerät aus WP07) und verbindet ihn ohne Rückfrage. Findet sie keinen, gibt es direkt dort „Gurt verbinden“ mit der Geräteauswahl aus WP07 (kein Umweg über die Einstellungen). Die Messung geht auch ohne Gurt, dann mit dem Hinweis, dass für die Validierung die Gurtwerte fehlen.
- **Ruhephase überspringbar:** Knopf „Überspringen“ in der Ruhephase. Die Vorgabe bleibt 2 min (R009). An der Messung wird intern vermerkt, ob und nach wie vielen Sekunden übersprungen wurde (Anzeige und Rechnung ändern sich nicht; für die Auswertung der Validierung).
- **Einschwingen nicht zählen (Orchestrator, einfachste Lösung nach dem Vorschlag des Maintainers):** Die Aufnahme läuft bis zu 120 s. Ausgewertet wird das beste zusammenhängende 60-s-Fenster (nach den bestehenden Kriterien aus Abschnitt 10, Fenster frühestens ab 5 s). Die Aufnahme endet früher, sobald ein 60-s-Fenster die Stufe „gut“ erreicht. Die Grenzen selbst (Q, Anteil gültiger Intervalle, Zeitrauschen) bleiben unverändert; nur das Fenster wandert. Gespeichert werden die Schlagabstände der ganzen Aufnahme (wie K65 Punkt 15) und Anfang und Ende des gewählten Fensters, damit die Validierung genau dieses Fenster mit den Gurt-RR vergleicht.
- **Haltung (Maintainer, K67):** Die Messung fragt liegend/sitzend (Vorgabe liegend) und speichert die Antwort, aber beide zählen in einer gemeinsamen Reihe je Gerät; es zählt die erste gültige Messung des Morgens. Punkte in Kurven und Listen sind nach Haltung markiert (z. B. gefüllt = liegend, hohl = sitzend, dazu Text für Screenreader). Die Sonderregeln für sitzend entfallen: keine eigene Reihe, kein Opt-in „liegend verglichen“, ein Freigabestand für das Verfahren. Bestehende sitzende Messungen werden in die gemeinsame Reihe übernommen (Migration).
- **Alle Messungen speichern (Maintainer, K68):** Im Entwicklermodus wird jede Messung gespeichert, auch unbrauchbare, mit Stufe, Grund, Kamera-Schlagabständen und Gurt-RR. Unbrauchbare zählen nirgends und sind in der Liste markiert; Archiv und CSV der Messpaare enthalten sie.
- **Rohsignal (Maintainer, K70):** Im Entwicklermodus wird je Messung das Kamera-Rohsignal gespeichert (je Bild Zeitstempel und die Farbmittel, die der Algorithmus nutzt), verschlüsselt in der Datenbank, mit Migration, Archiv, Löschen, und mit den Messpaaren exportiert (eigene Zeilenart oder eigene Datei, Vertrag nachziehen). Größe je Messung nennen. Mit dem Rohsignal werden die Kamera-Angaben je Messung gespeichert (Empfehlung R010): Belichtungszeit, ISO, Zeitstempelquelle, Rolling-Shutter-Versatz, Torch-Stärke, Bildlücken (Anzahl/Dauer), Anteil gesättigter Pixel. Ohne Entwicklermodus wird nichts davon gespeichert.
- **Hinweis zur Durchführung (R010):** Der Einstiegstext sagt zusätzlich: Finger nur leicht auflegen, Hand abstützen, nicht bewegen.
- **Noch nicht in WP37 (R010 in Nachbesserung):** Fensterwahl nach kleinstem Zeitrauschen, eine eigene RMSSD-Grenze für das Zeitrauschen und ein neuer Bezugspunkt im Pulsschlag. Das Fenster wird nach den bestehenden Kriterien gewählt; das Zeitrauschen jedes Kandidatenfensters wird nicht gespeichert, nur das des gewählten.
- Die Qualitätsanzeige während der Messung sagt, ob schon genug gutes Signal am Stück vorliegt (z. B. Fortschritt „gutes Signal 0:42 von 1:00“), statt nur die Gesamtzeit herunterzuzählen.

## Inhalt
0. **Screens (Teil 0):** Haltungsfrage und Markierung der Punkte nach Haltung; Gurtzeile mit den drei Zuständen und „Gurt verbinden“ in der Morgenmessung; Knopf „Überspringen“ in der Ruhephase; Fortschritt „gutes Signal“ in der Messung. Im Stil von `design/screens/morgen/`, Freigabe durch den Maintainer.
1. **Fenster (Teil A, core):** `ppg_evaluator`/`ppg_analyzer` werten ein wählbares Fenster aus; Suche des besten 60-s-Fensters (Schritt z. B. 1 s) über bis zu 120 s; Abbruchkriterium „gut erreicht“. Neue Parameter mit PAR-Nummer (PAR-160K-Auslegung, Höchstdauer 120 s, Schritt). `ALGORITHMUS.md` Abschnitt 2 nachziehen. Der Kamera-Ruhepuls aus WP27 (Abendmessung) bleibt unverändert, außer er nutzt dieselbe Stelle ohne Nachteil.
2. **Speicherung (Teil B):** Fensteranfang/-ende und „Ruhephase übersprungen nach s“ an der Morgenmessung (Schema-Migration, Archivabschnitt, Vektor, Vertrag `docs/contracts/archive.md` und `morning-pairs-csv.md`, CSV-Spalten bzw. Zeilen ergänzen, `format_version` erhöhen).
3. **Haltung (Teil D, core + app):** Reihenbildung ohne Haltung (`core`), Validierungsstand ohne sitzend-Zweig, Markierung in Kurven/Listen, Spec und `phase-2-3-rules.md` nach K67 nachziehen (Orchestrator prüft). Muss vor WP34-Merge mit WP34 abgestimmt sein, falls WP34 die Reihen je Haltung schon liest.
4. **Ablauf (Teil C, app):** Gurtzeile und automatisches Verbinden mit dem bekannten Gerät; Geräteauswahl direkt aus der Morgenmessung; Überspringen; Fortschrittsanzeige.

## Abnahmekriterien
- [ ] Synthetische Aufnahme: 30 s schlechtes Signal, danach 60 s gutes → Stufe „gut“, RMSSD vorhanden, Fenster = die 60 guten Sekunden (Test, Mutation: Fenster fest auf 5–65 s → rot).
- [ ] Gutes Signal von Anfang an → Aufnahme endet nach etwa 65 s (Test).
- [ ] Nie 60 s gut am Stück in 120 s → bestes Fenster mit seiner Stufe wie bisher (Test).
- [ ] Bekannter Gurt im Test-Sensor wird beim Öffnen ohne Rückfrage verbunden und als „verbunden“ gezeigt; ohne bekannten Gurt führt „Gurt verbinden“ zur Auswahl und zurück (E2E API 36 und 31).
- [ ] Überspringen der Ruhephase startet die Messung sofort; Vermerk gespeichert, im Archiv hin und zurück und in der CSV (Test).
- [ ] Gurt-RR decken die ganze Aufnahme ab; CSV enthält das gewählte Fenster (Test, Vertrag).
- [ ] Liegende und sitzende Messungen bilden eine Reihe; an einem Morgen zählt nur die erste gültige (Test, Mutation: Reihe je Haltung → rot); Markierung nach Haltung sichtbar in hell und dunkel (E2E-Foto).
- [ ] Validierungsstand ohne Unterscheidung nach Haltung (Test über alle Stände).
- [ ] Eine unbrauchbare Messung im Entwicklermodus ist gespeichert, markiert, in der CSV und im Archiv, zählt aber in keiner Reihe (Test, Mutation: unbrauchbar zählt → rot).
- [ ] Rohsignal einer Messung im Entwicklermodus gespeichert und exportiert; Algorithmus auf dem exportierten Rohsignal ergibt dieselben Schlagabstände wie in der App (Test mit synthetischem Signal); ohne Entwicklermodus nichts gespeichert (Test).
- [ ] Ohne Entwicklermodus weiter nirgends erreichbar (K62 F1).

## Nicht Teil des Pakets
- Änderung der Qualitätsgrenzen selbst (erst nach der Validierung, WP36).
- Readiness und Plan (WP34, WP35).
