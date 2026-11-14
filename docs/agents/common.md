# Gemeinsame Regeln

- **Identität:** `brokoskokoli` mit der Noreply-Adresse (kommt automatisch aus `~/ai/`). Einziger Trailer `Co-Authored-By: Claude <Modell> <noreply@anthropic.com>`. Nie `--no-verify`.
- **Als öffentlich behandeln:** keine Geheimnisse, keine privaten Daten, keine lokalen Pfade. Testdaten sind synthetisch, auch Gesundheitsdaten in Logs und Fixtures nur nach SEC-0001 bis SEC-0010.
- **Spezifikation:** Finde die Anforderung über `docs/requirements.md`, lies nur die Detailstelle. Grenzwerte und Formeln nur aus den PAR-Dokumenten. Bei Lücken oder Widersprüchen nicht im Code entscheiden, sondern melden.
- **Prüfen und CI:** lokal nur `sh tool/gate.sh --fast` und gezielte Tests (kein volles Gate, keine Emulatoren außer E2E-Agent). Paket-Sitzungen pushen ihren `wp/`-Branch; das volle Gate (Workflow `gate`) und die E2E-Sammlung (Workflow `e2e`) laufen auf GitHub. Warten mit `gh run watch <id> --exit-status`, danach den Status mit `gh run view <id>` bestätigen (watch kann vorzeitig enden); kein Warten in Schleifen. Der Pre-Push-Hook scannt jeden Push mit `tool/check_private.sh`. Gemergt wird nur mit grünem CI auf genau dem Branch-SHA, das Gate auf main läuft danach ebenfalls auf GitHub (Ablauf: [PROJECT.md](../../PROJECT.md#branches)). Nach Doku-Änderungen `spec_tool.py build` und `check`.
- **Arbeitsort:** nur im eigenen Worktree unter `../running-app-wt/`. Löschen nur per `trash`, kein `pkill`.
- **Kontext:** gezielt lesen. Nach etwa 60 Werkzeugaufrufen oder 120k Tokens Übergabe nach `../running-app-wt/handoff/<wp>.md`.
