# Gemeinsame Regeln

- **Identität:** `brokoskokoli` mit der Noreply-Adresse (kommt automatisch aus `~/ai/`). Einziger Trailer `Co-Authored-By: Claude <Modell> <noreply@anthropic.com>`. Nie `--no-verify`.
- **Als öffentlich behandeln:** keine Geheimnisse, keine privaten Daten, keine lokalen Pfade. Testdaten sind synthetisch, auch Gesundheitsdaten in Logs und Fixtures nur nach SEC-0001 bis SEC-0010.
- **Spezifikation:** Finde die Anforderung über `docs/requirements.md`, lies nur die Detailstelle. Grenzwerte und Formeln nur aus den PAR-Dokumenten. Bei Lücken oder Widersprüchen nicht im Code entscheiden, sondern melden.
- **Prüfen:** zwischendurch `sh tool/gate.sh --fast`, für main nach dem Merge `--changed`, volles Gate ohne Remote lokal per `sh tool/gate.sh`, sonst in CI (Workflow `gate`). Das Gate zeigt die Dauer je Schritt, bricht nach der schnellen Stufe und danach beim ersten roten Schritt ab und wartet selbst auf andere laufende Gates (Lock, siehe Kopf von `tool/gate.sh`). Nach Doku-Änderungen `spec_tool.py build` und `check`.
- **Arbeitsort:** nur im eigenen Worktree unter `../running-app-wt/`. Löschen nur per `trash`, kein `pkill`.
- **Kontext:** gezielt lesen. Nach etwa 60 Werkzeugaufrufen oder 120k Tokens Übergabe nach `../running-app-wt/handoff/<wp>.md`.
