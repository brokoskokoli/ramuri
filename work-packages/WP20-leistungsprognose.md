# WP20 – Leistungsprognose (`core`, `app/lib/features/statistics`, `profile`)

**Zuordnung:** M2, Welle 1. Parallel zu WP18.

Bezug: FR-0128 bis FR-0134, FR-0053, FR-0054; PAR-143 bis PAR-146; OQ-0008, OQ-0034. Vorlage: `design/screens/Fortschritt.dc.html`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Berechnung (Teil A):** Riegel-Modell in `core`, Prognosen für 5 km, 10 km, Halbmarathon und Marathon (FR-0128). Stufen je Zieldistanz nach PAR-143 bis PAR-146. Die Zielprognose aus PAR-146 wird mit dem Plan aus WP21 angeschlossen; hier nur die Schnittstelle dafür.
2. **Referenzleistung (Teil B, FR-0129, FR-0131):** Eintragen einer Wettkampf- oder Testzeit, Vorschlag und Bestätigung eines schnellen Laufs; Speichern, Archiv, Reimport, Löschen.
3. **Anzeige (Teil C, FR-0132 bis FR-0134):** Karte auf der Seite Fortschritt im Stil des Designs. Ohne Referenz keine Zeit, sondern der Grund und der Hinweis aus PAR-143; VO₂max allein ergibt keine Prognose. Grundlage und Stufe sichtbar, nie als statistische Sicherheit.

## Umsetzung
- Teile je ein Coder-Auftrag. Mutationsbelege für die Stufengrenzen, die Altersgrenzen und die Pausenregel.
- **Parallel:** Texte mit Präfix `prediction`. Nicht `summary` und `history` (WP18).

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0128 bis FR-0134.
- [ ] Beispielrechnungen gegen die Riegel-Formel und je ein Test je Stufe (Grenzen beidseitig).
- [ ] Marathon höchstens „vorläufig“ (PAR-144); keine Prognose nur aus der VO₂max (Test).
- [ ] E2E auf API 36 und 31, hell und dunkel, mit Bildschirmfotos. Gate grün.
