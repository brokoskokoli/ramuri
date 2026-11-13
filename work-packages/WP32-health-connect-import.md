# WP32 – Import aus Health Connect (`adapters`, Android, `core`, `features/settings`, Verlauf, Fortschritt)

**Zuordnung:** M3, Welle 1, nach WP31, WP30 und WP24. Parallel zu WP33.

Bezug: FR-0022, FR-0023, FR-0024, FR-0200, FR-0199, K62 (F2), FR-0108 (nur Datenbereitstellung), PAR-160, PAR-162 (Wertebereich), PAR-164, PAR-166, PAR-189; SEC-0001, SEC-0002, SEC-0005, SEC-0007, SEC-0009; CON-0007; ADR-0007; OQ-0033, OQ-0047. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md). Readiness selbst gehört zu WP34.

## Problem
Die App soll Schlaf, HRV (RMSSD), Ruhepuls, VO₂max-Schätzwerte, Trainingseinheiten und Pulsverlauf aus Health Connect lesen, je Datenart getrennt freigegeben und widerrufbar, mit sichtbarer Quell-App, ohne dass Grundfunktionen daran hängen.

## Inhalt
0. **Screens (Teil 0):** Mit Claude Design im Stil von `design/`: Einwilligung „Gesundheitsdaten aus Health Connect“ mit Liste der Datenarten (je ein Schalter), Zustand „Health Connect nicht verfügbar“, Widerruf mit Löschfrage, Kennzeichnung importierter Werte („aus Health Connect, Quelle: <App>“), Vergleichskarte fremder VO₂max-Werte. Freigabe durch den Maintainer.
1. **ADR-0007 auffrischen und Adapter (Teil A):** Version und Bedingungen von `connect-client` neu abrufen (Nachtrag im ADR). Kotlin-Adapter hinter einem Port in `adapters`: `getSdkStatus`, Rechte prüfen und anfordern, seitenweise lesen, Ratenbegrenzung. Manifest: nur die sechs Leserechte aus ADR-0007, Rationale-Activity mit `activity-alias`, `<queries>`. **Gate:** `release_rechte()` prüft, dass das Release-APK genau diese Leserechte trägt und weder `WRITE_*`-Rechte von Health Connect noch `READ_HEALTH_DATA_IN_BACKGROUND` oder `READ_HEALTH_DATA_HISTORY` (Sicherheitsprüfung, Selbsttest wie `check_release_manifest_test.py`).
2. **Speicher (Teil B):** Tabellen für Schlafsitzungen, Schlafphasen, Einzelwerte (RMSSD, Ruhepuls, VO₂max mit Zeitpunkt, Einheit, Quell-App), Trainingseinheiten (Art, Start, Ende, Quell-App) und deren Pulswerte. Jede Zeile trägt `origin` (Paket aus `metadata.dataOrigin`) und die Health-Connect-ID zum Entdoppeln. Migration, Archivabschnitte, Vertrag `docs/contracts/archive.md`, Vektor, Löschen (auch je Datenart). Schema und Abschnitte nach der Regel im M3-Plan („wer zuerst mergt, nimmt 12“).
3. **Einwilligung und Import (Teil C):** Eigener Einwilligungsdatensatz je Datenart (SEC-0001, SEC-0002) zusammen mit dem Dialog von Health Connect. Import nur im Vordergrund: beim App-Start und beim Öffnen von „Heute“, höchstens einmal je 15 min, zusätzlich „Jetzt abrufen“. Rechte vor jedem Lesen prüfen; fehlt ein Recht, nichts lesen und beim nächsten Öffnen nach dem Löschen der importierten Daten dieser Art fragen (SEC-0007). Ohne Health Connect bleibt alles andere unverändert (CON-0007).
4. **Aufbereitung in `core` (Teil D):** Reine Funktionen, die WP34 nutzt: Hauptschlafphase (PAR-164), Schlafzeit und Effizienz (PAR-166), HRV-Tageswert je Quell-App aus der Hauptschlafphase mit Rückfall „60 min danach“ und Markierung (PAR-160), Ruhepuls-Tageswert je Quell-App mit Bereich PAR-017, Auswahl der Quell-App nach PAR-189. Keine Readiness hier.
5. **Anzeige (Teil E):** Fremde VO₂max-Werte nur als Vergleich auf „Fortschritt“ mit Quelle, nie in der eigenen Reihe (FR-0024). Trainingseinheiten im Verlauf nur als Anzeige mit Quelle und Pulskurve; sie zählen für Belastung, Pause und Plan erst nach „als Training übernehmen“ (Nachtrag nach FR-0199, Dauer vorausgefüllt, RPE fragt die App). **Entscheidung des Maintainers (K62 F2).** Zu jedem importierten Wert ist die Quelle abrufbar (SEC-0005).

## Vorentscheidungen (selbst entschieden, einfachste Lösung)
- **Kanal statt `pigeon`:** Anbindung über einen einfachen `MethodChannel` wie die übrigen Android-Teile (`ramuri/…`), also ohne `pigeon`. Neue Abhängigkeit ist nur `androidx.health.connect:connect-client` (in ADR-0007 schon angenommen); Version beim Orchestrator anmelden.
- **Zeitraum:** Kein `READ_HEALTH_DATA_HISTORY`; der erste Import holt, was Health Connect ohne dieses Recht liefert (30 Tage vor der ersten Freigabe). Die 28-Tage-Referenz (PAR-161) passt in dieses Fenster.
- **Entdoppeln:** Gleiche Health-Connect-ID wird überschrieben, nicht doppelt gespeichert; in Health Connect gelöschte Einträge bleiben in der App, bis der Nutzer sie löscht (kein Abgleich von Löschungen).
- **Archiv:** Importierte Daten gehören ins Archiv (wie alle Tabellen). Die Einwilligungen nicht (K30).
- **Pulsverlauf:** Nur zu importierten Trainingseinheiten, nicht als Dauerpuls. Er geht in keine Berechnung ein, auch nach „als Training übernehmen“ nicht (der Nachtrag nach FR-0199 trägt Dauer und RPE, keinen Puls).
- **Übernommene Trainings:** Der Nachtrag merkt sich die Health-Connect-ID, damit dieselbe Einheit nicht zweimal übernommen wird; das Löschen der importierten Daten löscht den Nachtrag nicht.
- **Profil:** Der Ruhepuls aus dem Profil bleibt vorrangig (K16); Health-Connect-Werte ändern das Profil nie.
- **Kein Schreiben** nach Health Connect, keine Routen.

## Umsetzung
- Teile je ein Coder-Auftrag; Reihenfolge 0 und A, dann B, dann C und D, zuletzt E.
- **Debug-Quelle:** Ein Fake des Ports mit synthetischen Datensätzen (mehrere Quell-Apps, Schlaf mit und ohne Phasen, HRV außerhalb der Schlafphase, Werte außerhalb des Bereichs), nur über `main_debug.dart`; Marker im Gate wie Test-Sensor und Fake-Kamera. Kotlin-Tests mit `FakeHealthConnectClient` aus `connect-testing`, wenn ohne weitere Laufzeitabhängigkeit möglich.
- Mutationsbelege: Rechteprüfung vor dem Lesen, Hauptschlafphase, Rückfall nach PAR-160, Auswahl nach PAR-189, Trennung fremder VO₂max-Werte.
- **Parallel:** `release_rechte()` und Manifest nur hier; Übersicht (`overview_screen.dart`) nur WP33. Texte mit Präfix `health`.

## Abnahmekriterien
- [ ] Screens freigegeben, im Repo unter `design/`. ADR-0007 mit Nachtrag (Version, Kanal statt `pigeon`).
- [ ] Akzeptanzkriterien von FR-0022, FR-0023, FR-0024, FR-0200 sowie SEC-0001, SEC-0002, SEC-0005 und SEC-0007 für Health Connect.
- [ ] Ohne Einwilligung kein Lesezugriff (Test am Port: kein Aufruf); Freigabe einer Datenart gibt keine andere frei (Test).
- [ ] Gate prüft die Rechteliste des Release-APK; ein zusätzliches Schreib- oder Hintergrundrecht macht es rot (Selbsttest).
- [ ] Archiv mit allen neuen Tabellen hin und zurück, Vektor erzeugt; „Alles löschen“ und Löschen je Datenart leeren sie.
- [ ] E2E auf API 36 und 31 mit Debug-Quelle: einwilligen, importieren, Quelle sehen, Training übernehmen (danach in der Belastung, vorher nicht), Datenart widerrufen mit Löschfrage; auf API 36 zusätzlich der echte Berechtigungsdialog ohne Daten; auf API 31 „nicht verfügbar“, Rest der App normal. Hell und dunkel, Bildschirmfotos. Tests, die sich lohnen, committet in `app/integration_test/`. Gate grün auf GitHub.

## Ungeprüft
Echte Quell-Apps (wer schreibt RMSSD, Schlafphasen, wann), Ratenlimits auf dem Gerät, Prüfung durch Google Play. Gerätetest übernimmt der Maintainer.
