# WP31 – Gate und E2E-Tests auf GitHub

**Zuordnung:** Werkzeuge, nach WP30 (das die CI unter Linux wieder grün macht), vor der ersten M3-Welle. Entscheidung des Maintainers vom 2026-11-13: rechenaufwendige Prüfungen laufen auf GitHub, nicht auf dem Mac. Keine Funktion der App ändert sich.

Bezug: `.github/workflows/gate.yml`, `tool/gate.sh`, `tool/hooks/pre-push`, `tool/check_private.sh`, `app/integration_test/`, `docs/agents/` (wp-supervisor, coder, reviewer, e2e, common). Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Anlass
- Das volle Gate (10–18 min) läuft heute je Paket mehrfach lokal; parallele Läufe trieben die Last auf über 200.
- E2E-Tests entstehen je Paket als Wegwerf-Tests des E2E-Agenten und bleiben uncommittet. Committet sind nur `app/integration_test/e2e_recalc_test.dart` und `e2e_storage_test.dart`, und die laufen nirgends automatisch (das Gate prüft dort nur Format und Analyse). Eine Regression aus einem früheren Paket fällt so nicht auf.

## Inhalt
1. **E2E-Job auf GitHub (Teil A):** Workflow (in `gate.yml` oder eigenes `e2e.yml`) mit Android-Emulator auf `ubuntu-latest` (KVM), Matrix API 31 und 36, startet `flutter test integration_test` (bzw. `flutter drive`) gegen die Debug-App mit dem Test-Sensor. Auslöser: Push auf `wp/**` und `main`. AVD-Snapshot wird gecacht. Actions per Commit-SHA gepinnt, Rechte `contents: read`. Bei Rot: Logcat-Auszug und Bildschirmfotos als Artefakt, aber **ohne Gesundheitsdaten** (nur Testdaten, SEC-0001 bis SEC-0010).
2. **Regressionssammlung (Teil B):** Die lohnenden E2E-Tests aus den bisherigen Paketen (Kandidaten in `../running-app-wt/handoff/hinweise/*/` und `handoff/e2e-vorlagen/`, z. B. WP23 `wp23-e2e5/e2e_wp23_test.dart`) sichten, stabil machen und nach `app/integration_test/` übernehmen: je Kernablauf ein Test (Lauf aufzeichnen und speichern, Wiederanlauf, Export/Reimport, Plan anlegen und anpassen, Warnsignal, Laufband, Kamera-Ruhepuls über Fake). Ziel: die ganze Sammlung unter ~15 min je API-Stufe. Was nur mit Sichtprüfung geht, bleibt lokal und wird genannt.
3. **Arbeitsweise (Teil C):**
   - Paket-Sitzungen pushen ihren `wp/`-Branch; das volle Gate und die E2E-Sammlung laufen auf GitHub. Lokal nur `tool/gate.sh --fast` und gezielte Tests. Warten auf das Ergebnis mit `gh run watch` (kein Warten in Schleifen).
   - Der Pre-Push-Hook führt für **jeden** Push `tool/check_private.sh` aus (das Repo ist öffentlich), bevor etwas hinausgeht.
   - Merge nur mit grünem CI auf genau dem Branch-SHA; Gate auf main danach ebenfalls auf GitHub (kein lokaler Lauf mehr nötig).
   - E2E-Agenten liefern neue lohnende Tests committet in `app/integration_test/` (über den Coder), nicht uncommittet in `handoff/`.
   - `docs/agents/*.md` und `~/.claude/agents/wp-supervisor.md`-Verweise anpassen: Verweise statt neuer Regeln.

## Umsetzung
- Teile A, B, C je ein Coder-Auftrag. Review Schwerpunkt: keine Gesundheits- oder Privatdaten in Artefakten und Logs, Pre-Push-Scan nicht umgehbar außer mit `--no-verify`, E2E-Job prüft wirklich (Mutation: eine geprüfte Aussage brechen → Job rot).
- Der Branch darf gepusht werden (das ist der Zweck des Pakets); main pusht nur der Orchestrator.

## Abnahmekriterien
- [ ] E2E-Job grün auf GitHub für API 31 und 36 auf dem Branch (Link zum Lauf), Dauer je Stufe genannt.
- [ ] Ein absichtlich gebrochener Test macht den Job rot (Beleg), Artefakte ohne Gesundheitsdaten.
- [ ] Regressionssammlung mit Liste: welcher Ablauf, welche Datei, was bleibt lokal und warum.
- [ ] Pre-Push lehnt einen Push mit einem verbotenen Begriff ab (Beleg mit einem harmlosen Testbegriff über eine temporäre Liste).
- [ ] `docs/agents/` beschreibt den neuen Ablauf; volles Gate lokal ist nicht mehr Pflicht.
