# ADR-0007 — Anbindung von Health Connect

- **Status:** Accepted (Maintainer, 2026-11-04)
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0033, OQ-0047)
- **Betroffene Anforderungen:** FR-0022, FR-0023, FR-0024, FR-0108, FR-0115, FR-0200, SEC-0001, SEC-0002, SEC-0005, SEC-0007, CON-0007, OQ-0047

## Kontext
Phase 3 importiert nur über Health Connect (OQ-0047), jede Datenart lässt sich getrennt freigeben und widerrufen (FR-0200), ohne ausgeliefertes Secret. Grundfunktionen hängen nicht daran (CON-0007). Jede Reihe stammt aus genau einer Quell-App (FR-0115, PAR-189), die Herkunft muss also am Datensatz erhalten bleiben. Phase 3 startet erst nach dem Go des Maintainers; vorher wird hier nichts gebaut.

## Entscheidung
**1. Eigener dünner Adapter:** Kotlin auf `androidx.health.connect:connect-client` 1.1.0 (stabil, Apache-2.0) [1][2], typisiert angebunden über `pigeon` 29.1.0 (BSD-3-Clause) [3], hinter dem Port aus ADR-0002. Vor Phase 3 sind Version und Bedingungen neu abzurufen (Validierungsbedarf in [planning-rules.md](../../planning-rules.md)).

**2. Nur Lesen, nur was FR-0023 nennt:**

| Datenart | Berechtigung [4] |
|---|---|
| Trainingseinheiten | `READ_EXERCISE` |
| Herzfrequenzverlauf | `READ_HEART_RATE` |
| Ruheherzfrequenz | `READ_RESTING_HEART_RATE` |
| HRV (nur RMSSD) | `READ_HEART_RATE_VARIABILITY` |
| Schlaf mit Phasen | `READ_SLEEP` |
| VO₂max-Schätzwerte | `READ_VO2_MAX` |

Keine Schreibrechte, keine Routen. `READ_HEALTH_DATA_HISTORY` nur, wenn der Maintainer den Import älterer Einheiten will, sonst gilt die Grenze von 30 Tagen vor der ersten Freigabe [5]. Kein Hintergrundlesen: Der Import läuft im Vordergrund, solange keine Anforderung etwas anderes verlangt [5].

**3. Einwilligung:** Der eigene Einwilligungsdatensatz (SEC-0001, SEC-0002) und der Berechtigungsdialog von Health Connect gelten zusammen. Die App prüft erteilte Rechte vor jedem Lesen, weil sie jederzeit entzogen werden können [6]. Beim Entzug fragt sie nach dem Löschen importierter Daten (SEC-0007).

**4. Herkunft:** Jeder Datensatz speichert das Paket aus `metadata.dataOrigin`; Auswahl der Quell-App und PAR-189 liegen in `core`. Fremde VO₂max-Werte landen getrennt und nie in der eigenen Reihe (FR-0024).

**5. Verfügbarkeit:** `getSdkStatus` vor jeder Nutzung. Ab Android 14 gehört Health Connect zum System, auf API 31 bis 33 braucht es die App aus dem Play Store [6]. Fehlt es, bleibt die Funktion aus und der Rest läuft normal. Pflicht im Manifest sind die Rationale-Activity samt `activity-alias` und `<queries>` [6].

## Erwogene Alternativen
- **`health` 13.3.2 (MIT, CARP, Stand 2026-08-14):** Weit verbreitet, liefert Quell-App-Angaben und Rechte für alte Daten. Aber `HealthDataType` im aktuellen Archiv kennt kein VO₂max, FR-0023 ließe sich also nicht ganz erfüllen, und es bindet `connect-client` 1.2.0-alpha02 fest ein [7]. Bleibt Option, falls der Maintainer die VO₂max-Werte streicht oder das Plugin sie ergänzt.
- **Google Health API und Hersteller-APIs:** Durch OQ-0047 ausgeschlossen, nicht neu diskutiert.
- **Direkt `android.health.connect` statt Jetpack:** Nur ab Android 14, wäre für API 31 bis 33 nicht nutzbar.
- **Import per Hintergrundarbeit:** Zusätzliche Berechtigung und Begründung ohne Anforderung.

## Konsequenzen
- Eigener Kotlin-Code, aber klein und auf reine Lesezugriffe begrenzt. Ein Adapter für HealthKit wäre eine eigene Entscheidung.
- Bei Vertrieb über Google Play sind Health-Apps-Erklärung, Data-Safety-Angaben und eine Datenschutzerklärung nötig; dieselbe Erklärung muss die Rationale-Activity zeigen [8]. Die Datenschutzerklärung hängt an OQ-0048.
- Ratenbegrenzung und Seitenweise lesen gehören in den Adapter [5].

## Im Emulator nicht belegbar
Welche Quell-Apps wirklich RMSSD schreiben (schon in R004 als offen vermerkt) und wie gut ihre Daten sind; ohne RMSSD gibt es laut OQ-0006 keine Readiness-Zahl. Auch die Prüfung durch Google und das Verhalten außerhalb von Play sind nicht prüfbar und nicht belegt. Prüfbar sind Berechtigungsablauf und Import mit Testdaten aus der Health Connect Toolbox [9] sowie `FakeHealthConnectClient` aus `connect-testing` [1], beides mit synthetischen Daten.

## Offene Punkte
Kein Research-Auftrag vorgeschlagen, weil der offene Punkt ein echtes Gerät mit Quell-Apps verlangt. Vor Phase 3 als Prüfung am Gerät einplanen.

## Belege (Abruf 2026-11-04)
[1] https://developer.android.com/jetpack/androidx/releases/health-connect ·
[2] https://dl.google.com/android/maven2/androidx/health/connect/connect-client/1.1.0/connect-client-1.1.0.pom ·
[3] https://pub.dev/packages/pigeon ·
[4] https://developer.android.com/health-and-fitness/guides/health-connect/plan/data-types ·
[5] https://developer.android.com/health-and-fitness/guides/health-connect/develop/read-data ·
[6] https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started ·
[7] https://pub.dev/packages/health (`lib/src/heath_data_types.dart` und `android/build.gradle` im Archiv 13.3.2) ·
[8] https://developer.android.com/health-and-fitness/guides/health-connect/publish/declare-access ·
[9] https://developer.android.com/health-and-fitness/guides/health-connect/test/health-connect-toolbox
