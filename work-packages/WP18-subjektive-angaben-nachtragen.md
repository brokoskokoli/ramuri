# WP18 – Subjektive Angaben und Nachtragen (`core`, `app/lib/features/summary`, `history`)

**Zuordnung:** M2, Welle 1. Parallel zu WP20.

Bezug: FR-0038, FR-0095, FR-0096, FR-0199; PAR-086, PAR-087, PAR-105, PAR-169; OQ-0022, OQ-0058, OQ-0059, OQ-0077. Vorlage: `design/screens/Summary.dc.html`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Angaben zum Lauf (Teil A, FR-0038):** Speicherung und Berechnung in `core`: RPE 0–10, Befinden 1–5, Beschwerden, Notiz; freiwillig, dem Lauf zugeordnet, Werte außerhalb des Bereichs nicht speicherbar. Migration, Archiv, Reimport, Löschen.
2. **Eingabe in der Zusammenfassung und im Detail (Teil B):** Bereich aus `Summary.dc.html`, mit dem Wortlaut aus PAR-105 auf Deutsch und Englisch und 5 Stufen beim Befinden. Der Lauf bleibt ohne Angaben gültig, „Fertig“ bleibt der Abschluss. Eine Angabe lässt sich später im Detail ändern. Bei Beschwerden fragt die App, ob sie als Warnsignal gelten sollen; die Antwort wird gespeichert, die Wirkung auf den Plan kommt mit WP23.
3. **sRPE (Teil C, FR-0095, FR-0096):** Dauer · RPE, getrennt von TRIMP geführt und im Detail angezeigt.
4. **Training nachtragen (Teil D, FR-0199):** Datum, Art, Dauer, RPE; „Sonstiges“ für andere Sportarten. Keine GPS- und keine VO₂max-Werte. Im Verlauf gekennzeichnet, änderbar und löschbar. Die Statistik schließt es nach FR-0199 und OQ-0058 korrekt ein oder aus.
5. **Kleine Fehler aus M1 (Teil E):** Der Ersatztext bei der Bestpace bricht in 7 Zeilen; ein flacher Lauf zeigt „0 m 0 m“. Ursachen klären und beheben.

## Umsetzung
- Teile je ein Coder-Auftrag ohne Übergabe. Mutationsbelege für die RPE-Grenzen, die Zuordnung der Stufen, sRPE und den Ausschluss von „Sonstiges“.
- Der Umrechnungsfaktor nach PAR-086 fehlt zunächst: Solange zeigt die App nachgetragene Trainings in der Belastung als „nicht bewertet“ (FR-0199). Der Belastungsverlauf selbst kommt mit WP19.
- **Parallel:** Texte mit Präfix `subjective`/`manual`. Nicht `Fortschritt` (WP20).

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0038, FR-0095, FR-0096 und FR-0199.
- [ ] Angaben und nachgetragene Trainings überstehen Archiv und Reimport und verschwinden beim Löschen (Test).
- [ ] Ältere Archive und Datenbanken bleiben lesbar (Test).
- [ ] Die beiden Fehler aus Teil E sind behoben (Widget-Test bei 360 dp, Schriftfaktor 1,3).
- [ ] E2E auf API 36 und 31, hell und dunkel; Bildschirmfotos neben dem Design. Gate grün.
