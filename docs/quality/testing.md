# Tests und Abnahme

**Status:** Draft. Die Abnahmekriterien und Testfälle stammen aus der Quelle. Die Teststrategie ist eine Empfehlung, weil die Quelle dazu nichts festlegt. Es wurden noch keine Tests ausgeführt.

## Funktionale Abnahmekriterien

Aus SRC-001 §25. Das Konzept gilt in seinen jeweiligen Entwicklungsphasen als erfüllt, wenn mindestens diese Anforderungen nachweisbar sind. Die Phase ergibt sich aus den Anforderungen; die Quelle ordnet sie nicht direkt zu.

| ID | Kriterium | Quelle | Anforderungen |
|---|---|---|---|
| ACC-01 | Ein Nutzer kann einen Lauf vollständig ohne Pulssensor aufzeichnen. | Z. 1396 | FR-0035, CON-0004 |
| ACC-02 | Ein kompatibler Bluetooth-Pulssensor kann verbunden und während eines Laufs live ausgelesen werden. | Z. 1397 | FR-0007, FR-0012, FR-0015 |
| ACC-03 | Ein Verbindungsabbruch führt nicht zum Verlust des übrigen Laufs. | Z. 1398 | FR-0036, FR-0017 |
| ACC-04 | Die Trainingshistorie zeigt aufgezeichnete Läufe mit Strecke, Dauer, Pace und vorhandenen Herzfrequenzdaten. | Z. 1399 | FR-0040 |
| ACC-05 | Eine VO₂max-Schätzung wird nur aus dafür geeigneten Daten berechnet und als Schätzung gekennzeichnet. | Z. 1400 | FR-0067, FR-0073 |
| ACC-06 | Der Nutzer kann nachvollziehen, warum ein Fitnesswert berechnet oder nicht berechnet wurde. | Z. 1401 | FR-0059 |
| ACC-07 | Trainingsbelastung und langfristige Belastungstrends verwenden eine konsistente Berechnungsskala. | Z. 1402 | FR-0097 |
| ACC-08 | Ein Trainingsplan kann anhand eines Ziels und verfügbarer Trainingstage erstellt werden. | Z. 1403 | FR-0138 |
| ACC-09 | Der Plan reagiert auf zusätzliche oder ausgefallene Trainingseinheiten. | Z. 1404 | FR-0157, FR-0162 |
| ACC-10 | Größere Planänderungen werden begründet. | Z. 1405 | FR-0170 |
| ACC-11 | Eine Training-Readiness-Bewertung berücksichtigt fehlende Daten und persönliche Referenzwerte. | Z. 1406 | FR-0111, FR-0112 |
| ACC-12 | Eine Energiereserve wird nicht ohne geeignete kontinuierliche Daten als zuverlässiger aktueller Wert dargestellt (ab Phase 4, DEC-0060). | Z. 1407 | FR-0120, FR-0121 |
| ACC-13 | Ein Lauf kann unabhängig von Strava exportiert werden. | Z. 1408 | FR-0182 |
| ACC-14 | Die App bleibt ohne externe Fitnessplattform nutzbar. | Z. 1409 | CON-0010 |
| ACC-15 | Persönliche Daten können vom Nutzer exportiert und gelöscht werden. | Z. 1410 | SEC-0004, FR-0192 |

## Testfälle aus den Rechenbeispielen der Quelle

Die Migration hat diese Beispiele nachgerechnet; sie stimmen mit der Quelle überein. Sie eignen sich als Referenzwerte für künftige Tests.

| Berechnung | Eingabe | Erwartung | Anforderung |
|---|---|---|---|
| Relative Auslastung | HFmax 190, HFRuhe 60, HF 151 | r = 0,70 | FR-0060 |
| Sauerstoffbedarf | 10 km/h, eben | 36,83 ml/kg/min | FR-0069 |
| VO₂max | 10 km/h, HF 150, HFmax 190, HFRuhe 60 | r = 0,6923; ≈ 51,6 ml/kg/min | FR-0071 |
| Aerobe Effizienz | 9,0 auf 9,5 km/h | 5,56 % | FR-0087 |
| TRIMP | 10 min Z1, 30 min Z2, 10 min Z4 | 110 | FR-0092 |
| sRPE | 45 min, RPE 5 | 225 | FR-0095 |
| Riegel | 5 km in 25 min auf 10 km | ≈ 52 min 7 s | FR-0130 |

## Teststrategie (Empfehlung, nicht bindend)

- **Rechenmodelle:** Unit-Tests mit den Referenzwerten oben und Randfällen.
- **Vorverarbeitung und Modelle:** Wiedergabe aufgezeichneter oder synthetischer Läufe mit GPS-Sprüngen, Sensorlücken und Pausen.
- **Gerätefunktionen:** Tests auf echten Android-Geräten mit Sensor, ausgeschaltetem Bildschirm und Verbindungsabbruch.
- **Strava:** Tests gegen eine simulierte Gegenstelle einschließlich Fehlern und Duplikaten.
- **Datenschutz:** Negativtests ohne Einwilligung und nach einem Widerruf.
- **Modellqualität:** Validierung gegen Referenzdaten getrennt von Softwaretests (OQ-0020).

## CI-Gates

Maßgeblich ist `tool/gate.sh` (lokal und in `.github/workflows/gate.yml`). Seit WP31 laufen das volle Gate und die E2E-Sammlung aus `app/integration_test/` (`.github/workflows/e2e.yml`, API 31 und 36) auf GitHub für jeden Push auf `issue-**`, `wp/**` und `main`; gemergt wird nur mit grünem `gate` und `e2e` auf dem Branch-SHA. Das Gate prüft:

- Spezifikation (`spec_tool.py build`/`check`, generierte Abschnitte aktuell) und private Daten. `check` prüft auch die Architektur-Doku: jede ADR in `docs/index.md` verlinkt und mit ihrem Status genannt, Status und Datum in der ADR-Tabelle von `docs/architecture/overview.md` wie in der ADR-Datei, jeder Pfad der Code-Landkarte (`docs/architecture/code-map.md`) vorhanden samt den Suchbegriffen ihrer großen Dateien; der Selbsttest `tool/check_docs_links_test.py` zeigt jede Abweichung auf einem Temp-Baum als rot.
- Netz nur im Kartenadapter (`tool/check_net.py`, fail-closed): Pakete aus `pubspec.lock` und Gradle-Abhängigkeiten nur laut Freigabeliste `tool/net_allowed_packages.txt` (neues Paket ist rot bis zur Netzprüfung und zum Eintrag), Netz-APIs und `src/map` nur im Kartenadapter; ein eigener Schritt (`tool/check_net_test.py`) belegt mit Umgehungsfällen auf einem Temp-Baum, dass die Prüfung nicht aufweicht.
- Keine neuen Zyklen (`tool/check_architecture.py`, fail-closed, auch bei `--fast`): Aus allen `import`-, `export`- und `part`-Direktiven unter `app/packages/core/lib/src/` und `app/lib/features/` (auch `*.g.dart` und bedingte Importe) entsteht je ein Modulgraph (Modul = Ordner unter `src/` bzw. `features/`; Dateien direkt in `src/` werden durchgereicht). Die Zahl der Module in starken Zusammenhangskomponenten mit mehr als einem Knoten wird mit der Grundlinie im Skript (`CORE_CYCLE_MODULES`, `APP_CYCLE_FEATURES`) verglichen: mehr ist rot mit Komponente und je Modul der Kante (Datei:Zeile), die seinen Zyklus schließt; weniger ist rot mit dem Hinweis, die Grundlinie zu senken. Unlesbare Dateien, symbolische Links, unbekannte Importformen und `package:core/core.dart` innerhalb von `core/lib/src` sind rot. Der Selbsttest `tool/check_architecture_test.py` zeigt jeden Fall auf einem Temp-Baum.
- Keine neuen festen Wartezeiten in App-Tests (`tool/check_test_waits.py`, fail-closed, auch bei `--fast`): Jedes `Future.delayed` (auch mit Typargument und über Zeilenumbrüche) in Dart-Dateien unter `app/test/` zählt; die Zahl wird mit der Grundlinie `TEST_WAITS` im Skript verglichen: mehr ist rot mit Datei:Zeile der Fundstellen, weniger ist rot mit dem Hinweis, die Grundlinie zu senken. Widget-Tests warten stattdessen auf das Ereignis, das sie brauchen: `settleStorage` in `app/test/support/settle_storage.dart` pumpt Frames der Test-Uhr bis zur Bedingung bzw. bis kein Frame mehr geplant ist (mit Obergrenze und Meldung), `observeFrames` beobachtet eine feste Zahl Frames der Test-Uhr; beide ohne Echtzeit-Pausen. Für Arbeit, die echte Zeit braucht (Isolates, Bilddekodierung, Fakes mit echten Zeitgebern, etwa beim Öffnen der Kartenquelle), gibt `settleReal` der echten Ereignisschleife je Frame Durchläufe, bis die Bedingung gilt (höchstens eine kurze Scheibe je Frame), ebenfalls mit Obergrenze und Meldung. Die Kartentests warten darüber mit `settleUntilMapIdle` (`app/test/helpers/widget_helpers.dart`) auf das Ende der Kachelarbeit: keine Anfrage an das Fake-Netz offen und keine neue Anfrage seit dem vorigen Frame, in zwei aufeinanderfolgenden Frames (Folgeanfragen nach der Dekodierung). Die Helfer haben eigene Tests (`app/test/support/settle_storage_test.dart`, `app/test/helpers/map_idle_test.dart`). Der Selbsttest `tool/check_test_waits_test.py` zeigt jeden Fall auf einem Temp-Baum.
- Flutter-Version: die laufende Version muss exakt `environment.flutter` aus `app/pubspec.yaml` entsprechen (leere oder unlesbare Vorgabe ist rot). CI liest sie per `flutter-version-file` aus derselben Datei.
- `flutter pub get --enforce-lockfile` in `app`: weicht `pubspec.yaml` vom eingecheckten `pubspec.lock` ab, ist das Gate rot. Ein Schritt am Ende stellt außerdem sicher, dass `pubspec.lock` während des Gates unverändert bleibt (fängt auch den Wechsel von transitiv zu direkt ab, den `--enforce-lockfile` nur meldet). Die generierten Lokalisierungsdateien `app/lib/l10n/app_localizations*.dart` sind nicht eingecheckt (`.gitignore`); `pub get` erzeugt sie aus den ARB-Dateien.
- `core flutterfrei`: Abhängigkeits-Walk (keine direkte oder transitive Abhängigkeit von Flutter, `sky_engine` oder `adapters`) und Auflösung außerhalb des Pub-Workspace. Dazu wird `core` in ein Temp-Verzeichnis kopiert, `resolution: workspace` entfernt, mit dem Workspace-Lock (`app/pubspec.lock`) `dart pub get --offline` ausgeführt und ein Einstieg, der alle Bibliotheken (alle `.dart`-Dateien in `core` außer `.dart_tool` und `build`, auch `bin/`) importiert, mit `dart compile kernel` übersetzt. Jeder Import von `package:flutter*`, `sky_engine`, `adapters` oder `dart:ui` scheitert dort, unabhängig von Lint-Regeln und Schreibweise. Ein bedingter Import oder Export (`if (dart.library.…)`) in `core` ist verboten und macht den Schritt rot (Analyzer und Kompilat prüfen den Zweig nicht, im App-Build wäre er aktiv). Bedingungen über `-D`-Deklarationen und bewusste Schreibtricks erkennt der Schritt nicht; das ist eine bekannte Grenze. Eine `part of`-Datei wird nur ausgelassen, wenn `part of` ihre erste Direktive ist und eine andere Datei sie einbindet.
- Je Paket (`app` und jedes Verzeichnis unter `app/packages/`, neue Pakete werden automatisch erfasst): Format, Analyse (`dart analyze --fatal-infos` in Dart-Paketen, `flutter analyze lib test [integration_test]` in Flutter-Paketen, damit `app/packages/` nicht doppelt analysiert wird; Format und Analyse prüfen `integration_test/`, sobald es existiert) und Tests (`dart test` bzw. `flutter test`). Ein fehlendes `lib/` oder `test/` ist rot.
- Tageszuordnung in mehreren Zeitzonen (nicht bei `--fast`): Die Tests in `app/packages/core/test/` `health/`, `readiness/`, `recording/` und `reminders/` sowie in `app/test/` `system_clock_test.dart`, `readiness_home_test.dart`, `readiness_detail_test.dart`, `manual_training_test.dart` und die Tests von Plan und „Heute“ (`home_today_test.dart`, `plan_page_test.dart`, `guided_start_test.dart`, `plan_controller_test.dart`, `plan_calendar_test.dart`, `plan_started_unit_test.dart`, `plan_warning_page_test.dart`, `home_hints_test.dart`, `plan_change_page_test.dart`, `prediction_card_test.dart`, `plan_goal_form_test.dart`, `reminder_wiring_test.dart`, `measure/resting_measure_screen_test.dart`) sowie das Referenzformular (`reference_form_test.dart`, Datum eines übernommenen Laufs vor dem Sommerzeitende als lokale Mitternacht) laufen zusätzlich unter `TZ=America/Los_Angeles` (westlich, Sommerzeit), `TZ=Pacific/Auckland` (weit östlich, Südhalbkugel) und `TZ=UTC`. Ortstag und Hauptschlafphase (PAR-164) werden dabei an lokaler Mitternacht und an Tagen mit 23 h und 25 h geprüft (`health_time_zone_test.dart`, `readiness_local_day_test.dart`); der Tag eines nachgetragenen Trainings (FR-0199) aus Kalenderwahl, Vorgabe „heute“ und Übernahme aus Health Connect wird um 23:30 und 00:30 Ortszeit geprüft (`manual_training_test.dart`); „Heute“ und Plan zeigen um 00:30 Ortszeit denselben Ortstag, nicht den UTC-Vortag (`home_today_test.dart`); App-Tests setzen dafür Ortszeit (`DateTime(…)`) und die Test-Uhr `LocalFakeClock` (`app/test/helpers/local_clock.dart`), deren Versatz wie bei der Systemuhr der Prozesszone folgt; ein Test prüft, dass `TZ` wirkt (fehlende Zonendaten sind rot statt still UTC). Tests, die eine Zone voraussetzen, prüfen sie ausdrücklich, statt übersprungen zu werden.
- `--changed` lässt Flutter nur aus, wenn `app/` und `tool/gate.sh` gegenüber `main` unverändert ist (getrackt und ungetrackt); ohne `main` oder bei Zweifel läuft die Prüfung.

Stufen des Gates: Jeder Schritt gehört zu genau einer Stufe; `sh tool/gate.sh --stage <stufe>` führt nur diese aus (damit die CI Stufen parallel laufen lassen kann), `--list-stages` nennt alle, ohne Option laufen alle Stufen nacheinander wie bisher. Grün ist das Gate nur, wenn alle Stufen grün sind; die Pflicht, das Gate vor jedem Merge grün zu haben, bleibt. Die Stufen:

- `tools`: Spezifikation, private Daten, Netz, Architektur und die Selbsttests der Werkzeuge (Doku-, Netz-, Architektur- und Release-Manifest-Prüfung, Versionsrechnung, Pre-Push-Regeln, `ci_e2e`, `ci_ndk`, Gate-Stufen).
- `analyze`: Flutter-Version, `pub get`, `core flutterfrei`, Format und Analyse aller Pakete und am Ende „Lock unverändert“.
- `app` und je Paket unter `app/packages/` sein Verzeichnisname (heute `adapters`, `core`): die Tests des Pakets.
- `zones`: Tageszuordnung in Zeitzonen; `drift`: Drift-Schema; `android`: Kotlin-Tests; `release`: Release-APK und seine Rechte.

Stufen außer `tools` und `analyze` holen die Pakete vorher (`pub get --enforce-lockfile`), falls sie noch nicht aufgelöst sind. Der Selbsttest `tool/gate_stages_test.sh` (Stufe `tools`) vergleicht per `--dry-run` die Schritte des vollen Laufs mit denen aller Stufen (jeder genau einmal, keine Stufe führt fremde Schritte aus) und zeigt an Kopien von `tool/gate.sh` mit eingebautem Fehler, dass eine Lücke rot wird. `flutter test` läuft ohne `--coverage`.

Die E2E-Sammlung (`app/integration_test/`) läuft nicht in `tool/gate.sh` (lokal und im Workflow `gate`), sondern im eigenen Workflow `e2e` (`.github/workflows/e2e.yml`, Emulator API 31 und 36) für jeden Push auf die Arbeits-Branches und `main`; gemergt wird nur mit grünem `gate` und `e2e`. Zusätzlich läuft `e2e` einmal in der Woche geplant auf `main` (Start Sonntag 23:37 UTC, `schedule`), damit die Tests über den Tageswechsel um Mitternacht UTC laufen und Fehler, die nur dort auftreten, regelmäßig sichtbar werden – nicht nur, wenn zufällig ein Push in dieses Fenster fällt; ein roter geplanter Lauf zählt wie ein roter Lauf auf `main`. Über `workflow_dispatch` startet der Maintainer `e2e` von Hand auf einem beliebigen Branch. Geplante, von Hand gestartete und Push-Läufe stehen in getrennten Concurrency-Gruppen und brechen sich nicht gegenseitig ab. Stufen mit geführter Einheit (`m2-flow`, `treadmill-plan`) warten kurz vor Mitternacht (23:45–23:59 Ortszeit des Emulators) den Tageswechsel ab, und dieses Warten zählt nicht gegen ihr Zeitlimit in `tool/ci_e2e.sh` (Selbsttest `tool/ci_e2e_test.sh`). Tests am echten Gerät (Pulsgurt, Kamera, Hintergrund, GPS im Freien) laufen in keinem der beiden.
