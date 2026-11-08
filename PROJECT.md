# Projektregeln: Arbeitsorte und Rollen

Diese Datei sagt den globalen Skills und Agenten (`project-supervisor`, `wp-supervisor`, `research-supervisor`, `researcher`, `research-reviewer`), wo sie in diesem Repository arbeiten. Fehlt ein Eintrag, wird gefragt, nicht geraten.

## Projekt
- **Name:** Adaptive Running & Fitness App (Kurzname `running-app`)
- **Zweck:** Android-App für Laufaufzeichnung, Fitnessanalyse und adaptive Trainingsplanung, ohne Wearable-Zwang und nur mit lokaler Datenhaltung.
- **Repository:** vorerst nur lokal, kein Remote. Geplant ist das öffentliche Repo `brokoskokoli/running-app`, den Push gibt der Maintainer separat frei. Inhalte werden schon jetzt so behandelt, als wären sie öffentlich. Lizenz GPL-3.0. Solange es kein Remote gibt, läuft das volle Gate lokal; der Workflow `gate` greift erst danach.
- **Maintainer:** der Nutzer.
- **Toolchain:** Flutter (Entscheidung des Maintainers, 2026-11-04), App in `app/`. Einzelheiten in den ADRs.

## Arbeitsorte

| Bereich | Pfad | Wer arbeitet dort | Regeln |
| --- | --- | --- | --- |
| Quellcode der App | `app/` | Coder über Arbeitspakete | `AGENTS.md`, `docs/agents/` |
| Konzept (Quelle der Wahrheit) | `docs/index.md`, `docs/specs/`, `docs/quality/`, `docs/requirements.md` (Register generiert) | Project Supervisor, Maintainer | `AGENTS.md` |
| Offene Fragen und Entscheidungen | `docs/migration/open-questions.md`, DEC in `docs/product.md` | Antworten nur durch den Maintainer | `AGENTS.md` |
| Änderungsprotokoll | `docs/changelog.md` | Project Supervisor | dort |
| Architekturentscheidungen | `docs/architecture/adr/` | Project Supervisor | `AGENTS.md` |
| Rollen-Briefings | `docs/agents/` | Project Supervisor | – |
| Arbeitspakete und Umsetzungsstand | `work-packages/` (`STATUS.md`, `REVIEW.md`, `WPnn-<slug>.md`, `M<n>-PLAN.md`) | Project Supervisor, WP-Supervisor | `work-packages/README.md` |
| Research | `research/` (ein Ordner `Rnnn-<slug>/` je Analyse; R001 bis R004 liegen als Berichte in `docs/migration/research-reviews/`, nächste freie Nummer laut `research/README.md`) | Research Supervisor, Researcher | `research/CLAUDE.md` |
| Research-Daten | `research/data/` im Haupt-Checkout, nicht in Git | Researcher | `research/CLAUDE.md` |
| Nicht wiederherstellbare Eingaben | `research/input/<sammlung>/` im Haupt-Checkout, nicht in Git | Maintainer legt ab | `research/CLAUDE.md` |
| Logo und Icon | `branding/` (Quelle `build_brand.py`) | Maintainer | `branding/README.md` |
| Screen-Design (Vorschlag) | `design/` | Maintainer | `design/README.md` |
| Werkzeuge, Git-Hooks | `tool/` (`core.hooksPath=tool/hooks`) | Project Supervisor | `docs/agents/common.md` |
| Worktrees und Übergaben | `../running-app-wt/` (`wpNN`, `rev-wpNN`, `rNNN`, `handoff/`) | alle Agenten | `docs/agents/common.md` |

## Rollen

| Rolle | Wie | Aufgabe |
| --- | --- | --- |
| Project Supervisor | Skill `project-supervisor` in der Hauptsitzung | Überblick, Pakete und Research-Aufträge, Sitzungen starten, mergen, Änderungsprotokoll |
| WP-Supervisor | Agent `wp-supervisor`, eigene Sitzung | genau ein Arbeitspaket bis zum Ziel |
| Research Supervisor | Agent `research-supervisor`, eigene Sitzung | genau einen Research-Auftrag steuern |
| Researcher, Research Reviewer | globale Agenten, Sub-Agenten des Research Supervisors | Analysen durchführen und prüfen |
| Coder | Projekt-Agent `running-app-coder` | Code schreiben |
| Reviewer | Projekt-Agent `running-app-reviewer` | Code prüfen, ändert nichts |
| E2E | Projekt-Agent `running-app-e2e` | Integrationstests im Emulator |

## Branches
- Arbeitspaket: `wp/NN-<slug>` im Worktree `../running-app-wt/wpNN`
- Research: `research/rNNN-<slug>` im Worktree `../running-app-wt/rNNN`
- Gemergt wird nur durch den Project Supervisor nach `main`. Ohne Remote per `git merge --no-ff` nach vollem Gate auf dem Branch. Mit Remote über `tool/merge_wp.sh` (verlangt grünes CI), Push mit `RUNNING_APP_PUSH_MAIN=1`.

## Rahmen vom Maintainer (2026-11-04)
- **Testumgebung:** vorerst nur Emulator, keine Feldtests. Echte Hintergrundaufzeichnung, Akku und echter Pulsgurt (ACC-02) bleiben dadurch unbelegt; Anforderungen, die nur im Feld prüfbar sind, werden in `STATUS.md` als offen geführt und nicht als erfüllt gemeldet.
- **Ablauf:** Nach Freigabe der ADRs laufen die Pakete von Phase 1 ohne weitere Plan-Freigabe, höchstens 2 Sitzungen gleichzeitig. Phase 2 und 3 starten erst nach seinem Go.
- **Öffentliches Repo:** Keine echten Gesundheitsdaten, keine privaten Daten, auch nicht in Testdaten und Logs (SEC-0001 bis SEC-0010). Verbotene Begriffe stehen lokal in `~/.config/running-app/forbidden-terms`.
