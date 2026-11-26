# Code-Landkarte

Technische Sicht auf den Code: wo was liegt, wohin neuer Code gehört und welche Regeln dabei gelten. Die fachliche (logische) Sicht steht im [Architekturüberblick](overview.md), die Entscheidungen in den ADRs (`docs/architecture/adr/`). Aufbau und Abhängigkeiten der Pakete legt [ADR-0002](adr/ADR-0002-flutter-mindestversion-projektaufbau.md) fest.

`python3 tool/spec_tool.py check` prüft, dass jeder Pfad in Backticks dieser Datei existiert (ein Teil mit `<…>` ist ein Platzhalter; geprüft wird der Pfad davor) und dass die Suchbegriffe der Tabelle „Große Dateien“ in der genannten Datei vorkommen.

## Pakete und Abhängigkeitsrichtung

```
app  ──►  adapters  ──►  core
 └──────────────────────►  core
```

Abhängigkeiten zeigen nur in diese Richtung: `app` nutzt `adapters` und `core`, `adapters` nutzt `core`, `core` hat keine Laufzeit-Abhängigkeiten (nur `lints` und `test` zur Entwicklung, `app/packages/core/pubspec.yaml`). Alle drei bilden einen Pub-Workspace mit gemeinsamem Lock `app/pubspec.lock`.

### `app` (Flutter-App, `app/`)

| Ordner / Datei | Zweck |
|---|---|
| `app/lib/main.dart` | Einstieg des Release-Builds: startet die App mit `AppDependencies.create()` in `runCountingErrors` (globale Fehlerbehandlung, siehe `app/lib/error_counter.dart`). |
| `app/lib/error_counter.dart` | Globale Fehlerbehandlung: Handler für Flutter-, Plattform- und Zonenfehler und `ErrorCounter`, der unbehandelte und still abgefangene Fehler nur nach Fehlertyp und Ortskennung (erste Datei der App im Stack, ohne Zeile) zählt, nie Nachricht, Werte oder Stack (SEC-0009). Je Eintrag zusätzlich der lokale Tag des ersten und letzten Auftretens. Höchstens 50 Einträge in den Einstellungen der verschlüsselten Datenbank (Schlüssel `diagnostics.error_counts`, nicht im Archiv); keine Ausgabe im Release-Build. Angezeigt nur in den Entwicklereinstellungen (`app/lib/features/settings/error_counts_section.dart`), geteilt nur als Diagnose-Datei ohne Werte (`app/lib/features/export/diagnostics_export_action.dart`, FR-0223); `ErrorCounterScope` reicht den Zähler der App an die Seiten. |
| `app/lib/main_debug.dart` | Einstieg des Debug-Builds; bindet als einzige Datei die Debug-Quellen aus `app/lib/debug/` ein. |
| `app/lib/app_dependencies.dart` | Manueller Zusammenbau (ohne DI-Bibliothek): bindet die Adapter aus `adapters` an die Ports aus `core`; Tests setzen stattdessen Fakes ein. |
| `app/lib/app.dart` | Wurzel-Widget mit Theme, Lokalisierung und Navigation. |
| `app/lib/system_clock.dart` | Echte Uhr (`SystemClock`) als Umsetzung des Ports `Clock`. |
| `app/lib/features/<bereich>/` | Je Bereich die Screens und ihr `ChangeNotifier`-Controller (z. B. `app/lib/features/plan/`, `app/lib/features/run/`); nur Darstellung, Ablauf und Verdrahtung, keine Fachregel. |
| `app/lib/ui/` | Gemeinsame Bausteine der Oberfläche: Theme, Farben, Schrift, Karten, Chips, Zeichner (z. B. `app/lib/ui/sparkline.dart`), Barrel `app/lib/ui/ui.dart`. |
| `app/lib/l10n/` | Texte als ARB (`app/lib/l10n/app_de.arb` ist die Vorlage, dazu `app/lib/l10n/app_en.arb`); `pub get` erzeugt daraus `app_localizations*.dart` (nicht eingecheckt). |
| `app/lib/debug/` | Test-Sensor, Test-Kamera, Test-Health-Connect und Debug-Panel; nur aus `app/lib/main_debug.dart` erreichbar. |
| `app/test/` | Widget- und Verdrahtungstests der App; Hilfen in `app/test/helpers/`, Debug-Quellen in `app/test/debug/`. |
| `app/integration_test/` | E2E-Sammlung (Einstieg `app/integration_test/all_test.dart`, Übersicht `app/integration_test/README.md`, Hilfen in `app/integration_test/support/`). |
| `app/android/` | Android-Projekt; Kotlin unter `app/android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/` (Kanäle, Vordergrunddienst, Kamera, Health Connect), Tests unter `app/android/app/src/test/`. |
| `app/assets/` | Schriften, Logo und weitere gebündelte Dateien. |

### `adapters` (Flutter-Paket, `app/packages/adapters/`)

Umsetzungen der Ports aus `core` gegen Plattform und Bibliotheken; Barrel `app/packages/adapters/lib/adapters.dart`.

| Ordner | Zweck |
|---|---|
| `app/packages/adapters/lib/src/archive/` | Verschlüsseltes Gesamtarchiv: Schreiben, Lesen und Prüfen gegen die Datenbank (ADR-0008). |
| `app/packages/adapters/lib/src/export/` | Übergabe exportierter Dateien an das System (Teilen, Speichern). |
| `app/packages/adapters/lib/src/health/` | Health Connect über den Plattformkanal (ADR-0007). |
| `app/packages/adapters/lib/src/location/` | GPS über den Plattformkanal. |
| `app/packages/adapters/lib/src/map/` | Kartenadapter: Kacheln aus dem Netz nach Einwilligung, verschlüsselter Kachel-Cache, Karten-Widgets (ADR-0009); einzige Stelle mit Netz. |
| `app/packages/adapters/lib/src/permissions/` | Abfrage von Android-Berechtigungen. |
| `app/packages/adapters/lib/src/reminders/` | Planen der Erinnerungen über den Plattformkanal. |
| `app/packages/adapters/lib/src/sensors/` | Bluetooth-Pulsgurt (ADR-0006), Schrittfrequenz und Kamera-PPG über Plattformkanäle (ADR-0011). |
| `app/packages/adapters/lib/src/storage/` | Verschlüsselte Datenbank mit drift (ADR-0003): Schema `app/packages/adapters/lib/src/storage/schema.drift`, Zugriffe je Bereich (`*_access.dart`), Schlüsselablage. |
| `app/packages/adapters/lib/src/voice/` | Sprachausgabe über den Plattformkanal. |
| `app/packages/adapters/drift_schemas/` | Exportierte Schemastände für die Migrationstests. |
| `app/packages/adapters/test/` | Tests je Bereich, darunter der Speicher-Vertrag gegen die echte Datenbank. |

### `core` (reines Dart, `app/packages/core/`)

Fachlogik ohne Flutter; Barrel `app/packages/core/lib/core.dart`.

| Ordner | Zweck |
|---|---|
| `app/packages/core/lib/ports/` | Schnittstellen zu Uhr, Geräten, Plattform und Speicher (z. B. `app/packages/core/lib/ports/clock.dart`, `app/packages/core/lib/ports/storage.dart`). |
| `app/packages/core/lib/fakes/` | Fakes zu den Ports für Tests und Debug-Build. |
| `app/packages/core/lib/testing/` | Speicher-Vertrag (`app/packages/core/lib/testing/storage_contract.dart`): dieselben Tests laufen gegen den Fake und gegen die drift-Umsetzung. |
| `app/packages/core/lib/src/algorithms/` | Algorithmen-Registry (`app/packages/core/lib/src/algorithms/algorithm_registry.dart`, ADR-0004, NFR-0005): Familien, Varianten und Standardbestückung `AlgorithmRegistry.standard()`. Oberes Modul: darf `fitness`, `plan` und `prediction` importieren, kein anderes Modul unter `src/` importiert es (`CORE_TOP_MODULES` in `tool/check_architecture.py`). Die App baut die Registry einmal (`AppDependencies.algorithms`); die Wertberechnung bekommt sie als `AlgorithmLookup` (`app/packages/core/lib/src/fitness/algorithm_lookup.dart`), Laufanalyse und Versionsprüfung nehmen ihre Verfahren daraus. |
| `app/packages/core/lib/src/archive/` | Format, Export und Import des Gesamtarchivs. |
| `app/packages/core/lib/src/calendar/` | Tageszuordnung (Blattmodul, importiert kein anderes Modul unter `src/`): ISO-Tag `isoDay` und Tag eines Laufs `dayOfRun` (Ortstag seines Starts, PAR-237) mit den zugehörigen Tagesfunktionen in `app/packages/core/lib/src/calendar/run_day.dart`. |
| `app/packages/core/lib/src/consent/` | Einwilligungen, Widerruf und eingewilligte Quellen. |
| `app/packages/core/lib/src/export/` | Dateiexporte GPX, TCX, FIT und CSV. |
| `app/packages/core/lib/src/fitness/` | Zonen, VO₂max, aerobe Effizienz, TRIMP und die Lesesicht `AlgorithmLookup` auf die Registry (die Registry selbst liegt in `algorithms/`). |
| `app/packages/core/lib/src/goals/` | Trainingsziele. |
| `app/packages/core/lib/src/guidance/` | Geführte Einheit: Position im Ablauf, Ansagen, Gehpausen. |
| `app/packages/core/lib/src/health/` | Verarbeitung importierter Gesundheitsdaten (Tageswerte, Schlaf). |
| `app/packages/core/lib/src/hints/` | Hinweise, Erklärungen und Erholungskarte. |
| `app/packages/core/lib/src/load/` | Trainingsbelastung und Pausentage. |
| `app/packages/core/lib/src/morning/` | Morgenmessung und Gurtvergleich. |
| `app/packages/core/lib/src/plan/` | Planerstellung, Anpassung, Verschieben, Warnungen und Geh-Lauf-Programm; die Schreibreihe des Plans je Sitzung (`app/packages/core/lib/src/plan/plan_write_queue.dart`). |
| `app/packages/core/lib/src/ppg/` | Kamera-PPG-Auswertung (Beschreibung in `app/packages/core/lib/src/ppg/ALGORITHMUS.md`). |
| `app/packages/core/lib/src/prediction/` | Leistungsprognosen. |
| `app/packages/core/lib/src/preprocessing/` | Vorverarbeitung der Messwerte: Lücken, Bewegung, Höhe, Puls. |
| `app/packages/core/lib/src/profile/` | Profil, Prüfung der Eingaben und Herkunft des Ruhepulses. |
| `app/packages/core/lib/src/readiness/` | Readiness-Modell und Erklärung. |
| `app/packages/core/lib/src/recalculation/` | Analyse eines Laufs und Neuberechnung abgeleiteter Werte; gespeicherte Kurzfassung eines Laufs (`overviewOf`, `runOverviewMethod`) mit Bestpace (`bestPace`) und deren Parametern (`StatisticsParameters`). |
| `app/packages/core/lib/src/recording/` | Aufzeichnung, Startprüfung, Wiederanlauf und Laufband. |
| `app/packages/core/lib/src/reminders/` | Regeln der Erinnerungen. |
| `app/packages/core/lib/src/sensors/` | Auswertung der Pulsdaten und Wahl der Pulsquelle. |
| `app/packages/core/lib/src/settings/` | Einstellungen als Werte. |
| `app/packages/core/lib/src/statistics/` | Historie, Perioden, Laufübersicht (`RunOverviewService`) und Kilometer-Splits; liest Analyseergebnisse aus `recalculation/`, nicht umgekehrt. |
| `app/packages/core/lib/src/storage/` | Schlüsseldienst der Datenbank. |
| `app/packages/core/lib/src/subjective/` | Subjektive Angaben und nachgetragene Trainings. |
| `app/packages/core/test/` | Unit-Tests, je Modul ein Ordner wie unter `app/packages/core/lib/src/`. |

## Wohin kommt …

| Neues … | Ort | Hinweis |
|---|---|---|
| Fachlogik (Modell, Regel, Berechnung) | `app/packages/core/lib/src/<modul>/` | Export über `app/packages/core/lib/core.dart`; jede Berechnung trägt Methode und Version (NFR-0001, NFR-0005). |
| Port (Gerät, Plattform, Speicher, Uhr) | `app/packages/core/lib/ports/` | Nur Schnittstelle und Werttypen, keine Umsetzung. |
| Fake zu einem Port | `app/packages/core/lib/fakes/` | Test in `app/packages/core/test/fakes/`. |
| Adapter (Umsetzung eines Ports) | `app/packages/adapters/lib/src/<bereich>/` | Export über `app/packages/adapters/lib/adapters.dart`, Verdrahtung in `app/lib/app_dependencies.dart`. |
| Controller | `app/lib/features/<bereich>/` | `ChangeNotifier`, bekommt Ports und Dienste von außen; Fachregeln ruft er aus `core` auf. |
| Screen | `app/lib/features/<bereich>/` | Neben seinem Controller. |
| Gemeinsamer Formatierer oder Zeichner | `app/lib/ui/` | Für Bausteine, die mehr als ein Bereich nutzt; Export über `app/lib/ui/ui.dart`. |
| Unit-Test der Fachlogik | `app/packages/core/test/<modul>/` | `dart test`, Uhr über `FakeClock`. |
| Test eines Adapters | `app/packages/adapters/test/<bereich>/` | Speicher zusätzlich über den Vertrag in `app/packages/core/lib/testing/`. |
| Widget- oder Verdrahtungstest | `app/test/` | Fakes statt Geräte; Hilfen in `app/test/helpers/`. |
| Kotlin-Test | `app/android/app/src/test/kotlin/io/github/brokoskokoli/ramuri/` | JUnit, läuft im vollen Gate. |
| E2E-Fall | `app/integration_test/` | `e2e_<name>_test.dart`, in `app/integration_test/all_test.dart` oder als Stufe in `tool/ci_e2e.sh` eintragen und in der Tabelle von `app/integration_test/README.md`. |
| Plattformkanal (Kotlin) | `app/android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/` | Registrierung in `app/android/app/src/main/kotlin/io/github/brokoskokoli/ramuri/MainActivity.kt`. |
| Plattformkanal (Dart) | `app/packages/adapters/lib/src/<bereich>/` | Als `method_channel_<name>.dart`, Kanalnamen geprüft in `app/test/channel_names_test.dart`. |
| Parameter (PAR) | `docs/model-parameters.md`, `docs/planning-rules.md` oder `docs/phase-2-3-rules.md` | Im Code als Konstante in der Parameterdatei des Moduls (z. B. `app/packages/core/lib/src/plan/plan_parameters.dart`). |
| Text (ARB) | `app/lib/l10n/app_de.arb` und `app/lib/l10n/app_en.arb` | Beide Sprachen; geprüft in `app/test/arb_test.dart`. |

## Regeln

Heute geltende Regeln und wo sie geprüft werden. Weitere Regeln ergänzt die Änderung, die sie einführt, hier und in `AGENTS.md`.

| Regel | Prüfung |
|---|---|
| `core` ist frei von Flutter, `dart:ui` und `adapters`. | Schritt „core flutterfrei“ in `tool/gate.sh` (Abhängigkeits-Walk und Übersetzung außerhalb des Workspace). |
| Netz nur im Kartenadapter (`app/packages/adapters/lib/src/map/`), Pakete nur laut `tool/net_allowed_packages.txt`. | `tool/check_net.py` mit Selbsttest `tool/check_net_test.py`, beide in `tool/gate.sh`. |
| Keine neuen Zyklen zwischen Modulen in `core` (Ordner unter `app/packages/core/lib/src/`) bzw. zwischen Features der App (Ordner unter `app/lib/features/`); Kante ist jedes `import`, `export` oder `part` einer Datei des anderen Moduls. Die Zahl der Module in Zyklen darf nur sinken (Grundlinie `CORE_CYCLE_MODULES`, `APP_CYCLE_FEATURES` im Skript). | `tool/check_architecture.py` mit Selbsttest `tool/check_architecture_test.py`, beide in `tool/gate.sh` (auch `--fast`). |
| Blattmodule in `core` importieren kein anderes Modul unter `app/packages/core/lib/src/` (auch nicht über Dateien direkt in `src/`): `calendar/` (Tageszuordnung). | `tool/check_architecture.py` (Liste `CORE_LEAF_MODULES`) mit Selbsttest `tool/check_architecture_test.py`. |
| Zeit nur über den Port `Clock` (`app/packages/core/lib/ports/clock.dart`); kein `DateTime.now()` in Fachlogik. | Keine maschinelle Prüfung; Tests setzen `FakeClock` bzw. `LocalFakeClock` (`app/test/helpers/local_clock.dart`). |
| Jede Planänderung (Fassung, Zuordnung, Verschieben) aus der App läuft über die eine Schreibreihe der Sitzung (`PlanWriteQueue.of`), gemeinsam für alle Plan-Controller, den Erholungs-Auslöser und das Warnsignal aus der Zusammenfassung (`warningEntry`); die Zuordnung beim Öffnen von „Heute“ und der Plan-Seite läuft zudem hinter der Sperre der Wertberechnung. Wer zusätzlich die Wertberechnung sperrt (`exclusive`), nimmt diese Sperre zuerst. `assignRun` schreibt nur, wenn die Einheit noch den erwarteten Lauf trägt (sonst „veraltet“). | `app/test/plan_write_queue_test.dart`, `app/test/plan_open_assign_lock_test.dart`; Vertragsfall der Zuordnung im Speicher-Vertrag (`app/packages/core/lib/testing/storage_contract_plan.dart`) gegen Fake und drift. |
| Debug-Quellen (`app/lib/debug/`) nur aus `app/lib/main_debug.dart`, nie im Release-Build. | `tool/check_release_apk.sh` (Marker der Debug-Quellen fehlen im Release-APK), aus `tool/gate.sh`. |

## Große Dateien

Diese Dateien muss man nicht ganz lesen. Die Suchbegriffe markieren, wo ihre Abschnitte beginnen (`grep -n '<Suchbegriff>' <datei>`). Zeilenzahlen sind ungefähr.

| Datei | Zeilen | Abschnitte (Suchbegriffe) |
|---|---|---|
| `app/lib/features/plan/plan_controller.dart` | 1500 | `class PlanViewState`, `class PlanController`, `Future<void> open`, `Future<GoalDraftCheck> checkGoal`, `Future<PlanActionResult> saveGoal`, `Future<PlanActionResult> recalculate`, `Future<PlanActionResult> confirmMove`, `Future<PlanActionResult> replaceUnit`, `Future<PlanActionResult> reportWarning`, `Future<PlanFeedbackOutcome> answerFeedback`, `Future<PlanActionResult> answerPause`, `Future<PlanActionResult> setAdaptation`, `Future<bool> recheckRecovery` |
| `app/lib/features/run/run_flow_screen.dart` | 1200 | `class RunFlowScreen`, `void initState`, `void _startGps`, `Future<void> _check(`, `Widget build`, `Widget _modeCard`, `Widget _plannedCard` |
| `app/lib/features/home/home_screen.dart` | 1200 | `class HomeScreen`, `class _HomeScreenState`, `Widget _cards`, `Widget build`, `Widget _content`, `class _LastRun` |
| `app/lib/features/statistics/load_card.dart` | 1100 | `class LoadCard`, `class LoadCardBody` |
| `app/lib/features/history/history_screen.dart` | 1000 | `class HistoryScreen`, `class _HistoryScreenState`, `Widget build` |
| `app/lib/features/measure/resting_measure_controller.dart` | 1000 | `class RestingMeasureResult`, `class RestingMeasureController`, `Future<void> startRest`, `void tick`, `void checkFrameGap` |
| `app/lib/features/plan/plan_goal_form.dart` | 1000 | `class PlanGoalFormScreen`, `class _PlanGoalFormScreenState` |
| `app/lib/features/run/run_controller.dart` | 900 | `class LiveZone`, `class RunController`, `Future<void> start`, `bool skipSegment` |
| `app/packages/core/lib/src/plan/generate_plan.dart` | 1000 | `class GeneratedPlan`, `GeneratedPlan generatePlan(`, `planDroppedWithoutRestDays(`, `List<PinnedConflict> planSpacingConflicts(` |
| `app/packages/core/lib/src/ppg/ppg_analyzer.dart` | 900 | `class PpgMethodResult`, `class PpgChannelResult`, `class PpgAnalysisSet` |
| `app/packages/core/lib/testing/storage_contract_plan.dart` | 1100 | `planContractCases` (Liste der Fälle), danach je Fall eine Funktion, z. B. `Future<void> _moveEasyForHard`, `Future<void> _unitMethods` |
| `app/lib/app_dependencies.dart` | 350 | `class AppDependencies`, `storageWiringFor(`, `class _NoHealthConnect` |
