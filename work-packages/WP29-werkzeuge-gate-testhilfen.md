# WP29 – Werkzeuge: Gate in Stufen, Locks, Testhilfen, Mutationsskript, Plan-Dateien teilen

**Zuordnung:** M2, vor WP23 (Aufräumpaket aus der Prozessanalyse vom 2026-11-11, Vorschläge 2, 4, 5, 6). Keine Funktion der App ändert sich.

Bezug: Prozessanalyse `../running-app-wt/handoff/analyse-prozess-2026-11-11.md` (Abschnitte 5, 7, 8); `tool/gate.sh`; `docs/agents/wp-supervisor.md`, `docs/agents/common.md`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Anlass (gemessen)
- Der Gate-Median stieg von 0,5 min (04.11.) auf 6–12 min (11.11.). Rund 25 % der Läufe enden rot, meist schon bei Format oder Analyse; trotzdem laufen Release-APK, Gradle und `build_runner` weiter. Das Gate schreibt keine Zeiten, welcher Schritt dominiert, ist daher unbelegt.
- Agenten warten in Schleifen auf Rechnerlast (879 Warte-Aufrufe). Die Last-Regeln stehen in jedem Auftrag statt im Werkzeug.
- `_pump`, `_tap`, `_settle`, `_app` und `_k` sind 4- bis 7-fach in den Widget-Tests kopiert; `app_harness.dart` nutzen 48 von 94 App-Testdateien.
- `plan_calendar.dart` (1 538 Zeilen) und `plan_screen.dart` (1 086) sind genau die Dateien, an denen WP23 und WP24 weiterbauen.
- 32 % der Muss-Befunde lauteten „Test fehlt oder Mutant überlebt“; Mutationen macht bisher jeder Reviewer von Hand.

## Inhalt
1. **Gate in Stufen (Teil A):**
   - Jede Zeile der Ausgabe zeigt die Dauer des Schritts in Sekunden.
   - **fail-fast:** Nach dem ersten roten Schritt bricht das Gate ab. Ausnahme: Innerhalb der Stufe „schnell“ (Format, Analyse aller Pakete) werden alle Schritte gezeigt, damit ein Lauf alle Format- und Analysefehler meldet.
   - **`--fast`:** spec, privat, Format, Analyse und die Tests der geänderten Pakete (gegen `main` bzw. die Basis des Branches). Ohne Release-APK, Drift, Kotlin und `pub get --enforce-lockfile` nur, wenn sich `pubspec.*` geändert hat. Das ist der Standard für Coder zwischendurch.
   - **Ohne Option (voll):** wie heute, alle Schritte, mit fail-fast. Pflicht vor Review-Abgabe und vor der Fertigmeldung.
   - **`--changed`:** bleibt (für main nach dem Merge). Drift-, Kotlin- und Release-Schritt laufen bei `--changed` nur, wenn sich ihre Eingaben geändert haben (Drift: `schema.drift`, `app_database*.dart`, `drift_schemas/`; Kotlin: `app/android/`; Release: `app/android/`, `pubspec.*`, `app/lib/`, `lib/debug/`). Die Auswahl steht als Liste oben im Skript.
   - Ein Lauf ohne Zeitmessung fehlt in der Fertigmeldung: Nenne die Dauer je Schritt eines vollen Laufs vorher (main) und nachher.
2. **Locks statt Warteschleifen (Teil B):**
   - `tool/gate.sh` (voll und `--changed`) nimmt einen Lock (`/usr/bin/lockf`, auf macOS vorhanden; kein `flock`) in einer Datei unter `$(git rev-parse --git-common-dir)`, damit über alle Worktrees höchstens ein schweres Gate gleichzeitig läuft. `--fast` nimmt keinen Lock. Wartet der Lock, schreibt das Gate einmal „wartet auf Gate von …“.
   - Neues Skript `tool/emu.sh start <avd> | stop <serial> | list`: startet einen AVD mit `-no-audio -no-snapshot-save` auf einem freien Port, nimmt einen Lock je AVD, gibt den Serial aus, wartet auf `sys.boot_completed`, beendet nur den selbst gestarteten Emulator (per Serial bzw. PID). Ist der AVD belegt, wartet es auf den Lock statt einen zweiten Emulator zu starten. Das private Handy des Maintainers (`(entfernt)`) spricht das Skript nie an; es lehnt jeden Serial ohne `emulator-` ab.
   - In `docs/agents/wp-supervisor.md`, `docs/agents/e2e.md` und `docs/agents/common.md` die Absätze zu Rechnerlast, `uptime`, Warten auf andere Gates und Emulator-Belegung durch einen Verweis auf die beiden Skripte ersetzen. Keine neuen Regeln.
3. **Widget-Testhilfen (Teil C):** `app/test/helpers/` mit `pump`, `tap`, `settle` und dem Einstieg über `app_harness.dart`, ein Name je Bedeutung. Umgestellt werden die Testdateien, die heute eigene Kopien haben, soweit es ohne Änderung der Prüfungen geht. Dateien aus WP27 (`features/measure`, `ppg`) bleiben unberührt. Anzahl der Testfälle vorher und nachher gleich (Zahl nennen).
4. **Plan-Dateien teilen (Teil D):** `app/lib/features/plan/plan_calendar.dart` und `plan_screen.dart` in Teil-Widgets in eigenen Dateien zerlegen (Ziel je Datei unter ~500 Zeilen), ohne Verhaltens- oder Layoutänderung. Die bestehenden Tests bleiben unverändert grün. Wo Tests private Namen brauchen, nur Importe anpassen.
5. **Mutationsskript (Teil E):** `tool/mutate.sh <datei> <zeile> <ersetzung> -- <testbefehl>`: ändert genau diese Zeile, führt den Test aus, stellt die Datei immer wieder her (auch bei Abbruch, per `trap`), meldet „erkannt“ (Test rot) oder „überlebt“ (Test grün). Prüft vorher, dass die Datei keine uncommitteten Änderungen hat. Kurzanleitung in `docs/agents/coder.md` und `docs/agents/reviewer.md` (je 2–3 Zeilen): Der Coder belegt die Kernregel seines Teils damit selbst.

## Umsetzung
- Teile A+B, C, D, E je ein Coder-Auftrag; Review in zwei Schnitten: (A+B+E) und (C+D).
- Keine neue Abhängigkeit, keine Änderung an `pubspec.*`, keine Änderung am Verhalten der App.
- Prüfungen des Gates werden nicht abgeschwächt: Kein Schritt entfällt im vollen Lauf; `--fast` ersetzt nie das volle Gate vor der Fertigmeldung.
- Der Lock darf bei Absturz nicht hängen bleiben (`lockf` löst ihn mit dem Prozess). Test: zwei Gates gleichzeitig, das zweite wartet; Abbruch des ersten per Signal gibt den Lock frei.
- **Parallel:** WP27 (Ruhepuls per Kamera) läuft. Es berührt `features/measure`, `core/src/ppg`, Profil, Einrichtung, Archiv- und Löschtests. WP29 fasst diese Dateien nicht an. **WP27 ändert auch `tool/gate.sh`:** den Rumpf von `release_rechte()` (CAMERA, VIBRATE, uses-feature, zweiter Debug-Marker) und die Beschriftung des Release-Schritts. WP29 lässt alle Prüffunktionen (`release_rechte`, `drift_aktuell`, `kotlin_tests` usw.) im Rumpf unverändert und ändert nur den Ablauf unten im Skript, `step()` und die Optionen. Die Beschriftung des Release-Schritts bleibt Wort für Wort; den Konflikt in dieser einen Zeile löse ich beim Merge.

## Abnahmekriterien
- [ ] Ein Format- oder Analysefehler beendet das volle Gate nach der schnellen Stufe, ohne Release-APK, Gradle oder `build_runner` (Beleg: Ausgabe mit Zeiten).
- [ ] Volles Gate auf dem Branch grün, Dauer je Schritt vorher/nachher in der Fertigmeldung.
- [ ] Zwei gleichzeitige volle Gates laufen nacheinander (Beleg: Ausgabe beider); `--fast` läuft parallel.
- [ ] `tool/emu.sh` startet und beendet `running_app_api36` und `running_app_api31`; ein zweiter Start desselben AVD wartet; ein Nicht-Emulator-Serial wird abgelehnt.
- [ ] Zahl der App-Testfälle vor und nach Teil C gleich; `plan_calendar.dart` und `plan_screen.dart` je unter ~500 Zeilen; Plan-Seite auf dem Emulator (API 36) per Screenshot vorher/nachher gleich.
- [ ] `tool/mutate.sh` erkennt einen gezielten Mutanten und stellt die Datei auch nach Ctrl-C wieder her (Beleg).
- [ ] Last- und Warteabsätze in `docs/agents/` durch Verweise ersetzt.
