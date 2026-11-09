# WP27 – Ruhepuls mit der Handykamera (`core/src/ppg`, `adapters`, `app/lib/features/measure`, Profil, Einrichtung)

**Zuordnung:** M2, Welle 2c, nachgereicht am 2026-11-09 (OQ-0078, DEC-0073).

Bezug: FR-0214, FR-0002, FR-0060, FR-0205, SEC-0001 bis SEC-0010; ADR-0002, ADR-0009; K45, K46, K47; R009. Referenz: `../puls` (eigenes Repo des Maintainers): `docs/ALGORITHMUS.md`, `docs/METHODIK.md`, `app/src/main/java/de/puls/test/PpgAnalyzer.kt`, Tag `algo-v0.4-frozen`, Testdaten in `messungen/`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
0. **Screens (Teil 0, vor allem anderen):** Mit Claude Design (Artifact-Typ „Design“) im Stil von `design/` (Farben, Schrift, Bausteine aus `branding/` und `design/screens/*.dc.html`) entwerfen und dem Maintainer vorlegen:
   - Einstieg mit Erklärbild: Finger deckt Rückkamera und Blitz leicht ab, nicht drücken; Wahl der Haltung (sitzend oder liegend); Wahl „erst entspannen (5 min)“ mit einstellbarer Dauer oder „ich bin entspannt, sofort messen“.
   - Ruhephase: beruhigende Anleitung (kurze Sätze, ohne vorgegebenes Atemtempo), Restzeit, Abbrechen. Kein Ton, wenn nicht gewünscht.
   - Messung: Pulskurve live, laufender Puls, Signalqualität mit Hinweis zum Justieren (zu fest gedrückt, Finger verrutscht, zu dunkel), Fortschritt 60 s.
   - Ergebnis: Ruhepuls, Qualität, „übernehmen“ oder „noch einmal“; bei schlechtem Signal der Grund.
   Hell und dunkel. Nach Freigabe als `design/screens/Ruhepuls*.dc.html` (oder Export) mit Eintrag in `design/README.md`.
1. **ADR-0011 (Teil A):** Vorschlag Kamera-PPG: Bildstatistik (Mittelwerte R/G, 4×4-Teilbereiche, Sensor-Zeitstempel) nativ in Kotlin im Android-Teil hinter einem Port in `adapters` (wie die Schrittfrequenz), Torch an, Belichtung und Weißabgleich nach 2,5 s gesperrt, feste Bildrate; Auswertung als reines Dart in `core`. Keine neue Abhängigkeit, wenn möglich (CameraX ist eine; vorher beim Orchestrator anmelden). Kamera-Berechtigung erst beim Start der Messung. Keine Bilder gespeichert oder übertragen. Dem Orchestrator vorlegen, bevor Teil C beginnt.
2. **Algorithmus (Teil B):** Port von `PpgAnalyzer.kt` nach `core/src/ppg` gemäß `ALGORITHMUS.md`. Er wird so gebaut, dass die Morgenmessung (FR-0215, WP28, M3) ihn unverändert wiederverwendet, und gibt Ruhepuls, RMSSD und die Qualitätsstufe „gut“ oder „eingeschränkt“ aus (PAR-160K). Abgleich gegen die Referenz: dieselben Ergebnisse auf den synthetischen Tests der Referenz und auf Bildreihen, die aus `../puls/messungen/` **lokal** gelesen werden. Echte Messdaten des Maintainers sind Gesundheitsdaten und kommen nicht ins Repo: Im Repo nur synthetische Vektoren; der Abgleich mit den echten Dateien läuft als lokaler Test, der ohne die Dateien übersprungen wird, und nur Abweichungen (keine Werte) werden berichtet.
3. **Kamera-Adapter (Teil C):** Android-Seite und Port, ebenfalls für die Morgenmessung (WP28) wiederverwendbar, Fehlerfälle (keine Kamera, kein Blitz, Berechtigung verweigert, Kamera belegt, Bildrate nicht erreichbar), Lebenszyklus (App im Hintergrund bricht die Messung sauber ab, Torch aus).
4. **Oberfläche (Teil D):** Seiten nach den freigegebenen Screens, Einstieg im Profil bei der Ruheherzfrequenz und als Knopf in der Einrichtung. Übernahme ins Profil nur auf Bestätigung; danach greifen Zonen und Neuberechnung wie bei manueller Eingabe.

## Umsetzung
- Messprotokoll der Profilmessung nach R009 (`research/R009-kamera-ppg-morgenmessung/RESULTS.md`, Abschnitt 1) und FR-0214: Ruhephase vorgegeben 5 min, Länge einstellbar oder sofort messen; Haltung sitzend oder liegend wählbar und mit dem Wert gespeichert; beruhigende Anleitung ohne vorgegebenes Atemtempo, immer gleich lang; während der 60 s spontan atmen; es zählt die erste Messung mit ausreichender Qualität, wiederholt wird nur bei zu schlechter Qualität.
- Notiz für WP28 (aus R009, Abschnitt 3): Die Grenze „Zeitrauschen > 25 ms → eingeschränkt“ aus `../puls` (ALGORITHMUS 5.5b) ist für RMSSD zu lasch; RMSSD braucht eine eigene, strengere Qualitätsgrenze aus der Validierung. Für WP27 (nur Puls) nicht blockierend; die Grenze bleibt hier wie in der Referenz.
- Teile je ein Coder-Auftrag. Mutationsbelege für Qualitätsschwelle, Ausreißerprüfung, Störabschnitte und „kein Ergebnis bei schlechtem Signal“.
- Gate: Netzprüfung unverändert grün; Kamera-Berechtigung in die Prüfung der Release-Rechte aufnehmen.
- Emulator hat keine echte Kamera: Adapter mit eingespielten Bildreihen (Fake-Quelle) testen; der echte Kamera-Weg bleibt **ungeprüft**, bis der Maintainer misst.
- Keine Ruhepuls- oder PPG-Werte in Logs.

## Abnahmekriterien
- [ ] Screens vom Maintainer freigegeben, im Repo unter `design/`.
- [ ] ADR-0011 vorgelegt und entschieden.
- [ ] Akzeptanzkriterien von FR-0214.
- [ ] Port stimmt mit der Referenz überein: Puls auf 0,1/min, RMSSD auf 0,5 ms bei den synthetischen Vektoren; lokale Abweichungen gegen die echten Messungen berichtet.
- [ ] E2E auf API 36 und 31 mit Fake-Kameraquelle: kompletter Ablauf mit und ohne Ruhephase, schlechtes Signal, Abbruch, Berechtigung verweigert; hell und dunkel, Bildschirmfotos neben den Screens. Gate grün.
- [ ] Debug-APK für den Maintainer zum Test am echten Gerät.

## Ungeprüft
Echte Kamera auf verschiedenen Geräten (Bildrate, AE-Sperre, Torch); nur der Maintainer kann das prüfen.
