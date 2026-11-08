# WP15 – Fortschritt im Design (`app/lib/features/statistics`, `app/lib/features/transparency`)

**Zuordnung:** M1, nachgereicht am 2026-11-08 (OQ-0075). Nach WP14, parallel zu WP13 möglich.

Bezug: FR-0043, FR-0044, FR-0053, FR-0059, FR-0067, FR-0072, FR-0081, FR-0087, FR-0205; OQ-0036, OQ-0075; K33. Vorlage: `design/screens/Fortschritt.dc.html`.

## Inhalt
1. Bereich „Fortschritt“ nach Design, Festlegung in FR-0043: oben Kilometer der letzten 8 Wochen als Balken (ohne Wochenziel), darunter VO₂max mit Trend und Kennzeichnung „geschätzt“ und „Wie wird das berechnet?“, dann aerobe Effizienz.
2. Inhalte nach Spec: VO₂max ohne Genauigkeitsangabe (FR-0072), Datenqualität in den Stufen von FR-0053, Effizienz als Änderung in % nach FR-0087.
3. Darunter alle übrigen Kennzahlen aus FR-0043 und die Zeitraumwahl nach FR-0044 im Stil des Designs (Wertkacheln, Abschnitte aus WP14).
4. Erklärungsseiten (`value_explanation_screen.dart`) im Stil des Designs.

## Umsetzung
- Ein Coder-Auftrag, wenn er passt, sonst Teil A Punkte 1–2, Teil B Punkte 3–4.
- Prognose, Belastung (ATL/CTL/TSB) und Wochenziel aus dem Design gehören zu Phase 2 und kommen nicht.
- **Parallel:** WP13 berührt diese Dateien nicht. Neue Texte mit Präfix `progress`.

## Hinweise aus WP14
- Theme und Bausteine liegen in `app/lib/ui/`. Noch fehlende Tokens und Bausteine legt dieses Paket dort an, nicht in den Seiten: Töne `#E2EAE8`, `#D3EEE9`, `#3A4F4D`, `#FFE6DA`, `#8DBDB4`, Schriftgrößen 48/44/30, Umschalter in voller Breite, Live-Zonenanzeige, Wochenbalken (`../running-app-wt/handoff/hinweise/wp14/wp14-review-1.md`, Zusatzfrage 8; `wp14-a.md` dort für abgeleitete Töne).
- Verlauf und Fortschritt werden bei jedem Tab-Wechsel neu aufgebaut; Zeitraumwahl und Scrollposition gehen dabei verloren. Sie bleiben beim Tab-Wechsel erhalten (Abnahme), die Daten trotzdem frisch.
- Bildschirmfotos je API und Modus; Vorlagen in `../running-app-wt/handoff/e2e-vorlagen/wp14-e2e*`.

## Abnahmekriterien
- [ ] Aufbau und Optik wie `Fortschritt.dc.html`, hell und dunkel; Abweichungen nach FR-0205 benannt.
- [ ] FR-0043/FR-0057: jede Kennzahl berechnet oder als nicht verfügbar erkennbar; alle vorher sichtbaren Kennzahlen weiter da (Test).
- [ ] Wochenbalken stimmen mit der Wochenstatistik überein; Woche ohne Lauf als 0 km, nicht ausgelassen (Test).
- [ ] Kein „±“ an der VO₂max; Datenqualität nur in den Stufen von FR-0053 (Test).
- [ ] Zeitraumwahl und Scrollposition bleiben beim Tab-Wechsel erhalten, die Werte sind danach aktuell (Test).
- [ ] E2E (separater Agent), API 31 und 36, hell und dunkel: Bildschirmfotos neben dem Design. Gate grün.

## Ungeprüft
Lesbarkeit auf echten Geräten im Sonnenlicht.
