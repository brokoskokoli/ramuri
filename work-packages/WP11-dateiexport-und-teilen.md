# WP11 – Dateiexport und Teilen (`app/packages/core/lib/src/export`, `app/packages/adapters`, `app/android`, `app/lib/features/export`)

**Zuordnung:** M1.

Bezug: FR-0182, FR-0183, FR-0201, SEC-0003, CON-0008, CON-0010, ACC-13, ACC-14; ADR-0001; OQ-0032 (Formatversionen offen, non-blocking), OQ-0049; `docs/contracts/README.md`.

## Inhalt
1. **Abbildung:** Gespeicherter Lauf auf die Inhalte aus FR-0183, je Format nur, was es abbildet. Fehlender Puls erscheint nicht als 0. Exportiert werden gemessene Rohwerte mit ihrem Zeitstempel, Abbildung und Formatversionen stehen als Vertrag in `docs/contracts/`.
2. **GPX und TCX:** Eigene Erzeugung in `core`, ohne Paket.
3. **FIT:** Eigener kleiner Kodierer in `core` mit Prüfsummen, ohne Garmin-Code. Wartet in diesem Punkt auf die Entscheidung L1 (`M1-PLAN.md`); GPX und TCX laufen unabhängig davon.
4. **Teilen und Ablegen:** Teilen-Menü über eigenen Plattformaufruf mit `ACTION_SEND` und `FileProvider` (FR-0201), Speichern über das System-Dokumentenziel, hinter einem Port, den WP12 weiterverwendet. Temporäre Dateien liegen außerhalb der Backups und werden aufgeräumt.
5. **Oberfläche:** Export aus dem Lauf-Detail, Formatwahl, Fehlermeldung.

## Umsetzung
- Aus WP10: Zonenzeiten und `trimp_run` sind Laufwerte in `computed_values` (K26). Zonenwerte sind nicht aus den Rohdaten rekonstruierbar, weil die Zonengrenzen nicht gespeichert sind. Export führt alle Laufwerte mit (`zone_*`, `trimp_run`, `original` und `current`, mit `unavailable_reason` und Basis), reicht unbekannte `value_key`s durch und nimmt nicht „genau ein Laufwert“ an. Gelöschte Pulssensoren haben nur ihre Kennung.
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkt 3 / Teil C: Punkte 4 und 5, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Formatversionen sind ein Vorschlag des Pakets (OQ-0032), Kennzeichnung `Vorschläge`. Schemas nicht ohne Lizenzprüfung ins Repository kopieren.
- Keine Netzwerkberechtigung, keine Strava-Anbindung (OQ-0049). Der Nutzer entscheidet über das Teilen.
- Nicht dazu: FR-0184 (Phase 2), Gesamtexport (WP12).
- Parallel: läuft mit WP08. Dateien siehe WP08.

## Abnahmekriterien
- [ ] FR-0182, ACC-13: Ein synthetischer GPS-Lauf lässt sich ohne Strava in jedem umgesetzten Format exportieren.
- [ ] GPX und TCX bestehen die Validierung gegen das jeweilige veröffentlichte Schema; FIT besteht einen unabhängigen Decoder außerhalb des Repos (Werkzeug und Lizenz im Abschluss genannt, nicht im Gate).
- [ ] FR-0183: Hin- und Rücklesen: Unterstützte, vorhandene Werte stimmen mit dem Lauf überein (Golden-Tests je Format).
- [ ] Negativfälle: Lauf ohne Puls ohne Pulswert und nie 0; Lauf mit GPS-Lücke ohne erfundene Punkte; Lauf mit Pause; sehr kurzer und leerer Lauf; ungültige Zeichen in Namen; FIT-Prüfsumme bei Mutationsbeleg nicht mehr gültig.
- [ ] FR-0201: FIT oder GPX geht in das Teilen-Menü; ohne Aktion des Nutzers wird nichts übertragen; die temporäre Datei ist danach entfernt oder wird beim nächsten Start aufgeräumt.
- [ ] Der Export enthält nichts über die Formatinhalte hinaus (keine Profilwerte, keine berechneten Eigenwerte, keine Kennungen des Geräts außer der Quelle, soweit das Format sie vorsieht).
- [ ] SEC-0003, CON-0008, CON-0010, ACC-14: Ansehen und Export laufen ohne Konto und ohne Netz; die Berechtigungsliste des Release-APK enthält weiter kein `INTERNET`.
- [ ] E2E (separater Agent): Lauf aus der Wiedergabe exportieren, über das Teilen-Menü an ein Testziel geben, Datei auslesen und gegen den Lauf prüfen; Flugmodus; Abbruch im Teilen-Menü.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Import der Dateien bei Strava und anderen Plattformen (nur mit Konto und außerhalb der Testumgebung prüfbar). Die Rechtsfrage zum FIT-Protokoll (L1, OQ-0048) entscheidet nicht dieses Paket.
