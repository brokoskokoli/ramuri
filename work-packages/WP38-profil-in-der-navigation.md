# WP38 – Profil in der unteren Navigation (`features/home`)

**Zuordnung:** M3 nebenher (klein, keine Abhängigkeit). Anlass: Wunsch des Maintainers vom 2026-11-14 (K69).

Bezug: FR-0208 (Navigation, mit K69 ergänzt), FR-0205 (Erscheinungsbild), WP14 (Navigation), `app/lib/features/home/app_shell.dart`, `overview_screen.dart`. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md).

## Inhalt
- Fünfter Bereich „Profil“ ganz rechts in der unteren Leiste (Symbol wie das Profil-Symbol oben rechts auf „Heute“, Text de/en). Er zeigt die Übersicht (`OverviewScreen`); das Symbol oben rechts auf „Heute“ bleibt und führt zum selben Ziel.
- Verhalten wie die anderen Bereiche: Zurück führt zu „Heute“; Unterseiten der Übersicht (Einstellungen, Sensoren, Daten, Über …) einheitlich behandeln (entweder mit Leiste oder als Vollbild darüber, die einfachere Lösung, und begründen).
- Kein eigenes Design nötig: Stil der Leiste aus `design/` (Main.dc.html); fünf Einträge müssen bei 360 dp Breite, Schriftfaktor 1,3, hell und dunkel, de und en lesbar bleiben (48 dp).

## Abnahmekriterien
- [ ] Widget-Test: Bereich Profil öffnet die Übersicht; Zurück → Heute (Mutation: falsches Ziel → rot).
- [ ] Bestehende E2E-Tests der Sammlung, die die Leiste per Index oder Anzahl ansprechen, laufen weiter (CI grün auf API 31 und 36).
- [ ] Foto hell/dunkel, de/en, 360 dp mit Schriftfaktor 1,3 ohne abgeschnittene Beschriftung.

## Parallel
- WP34 baut auf „Heute“ die Karte „Erholung“ um; WP37 ändert `features/measure`. WP38 ändert nur `app_shell.dart`, ggf. `overview_screen.dart` (Zurück-Verhalten) und Texte.
