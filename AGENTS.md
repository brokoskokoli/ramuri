# Anweisungen für Agenten

Dieses Repository enthält das Produkt: den Code der App (`app/`), die Werkzeuge (`tool/`) und die gültige Spezifikation (`docs/`). Es ist öffentlich und so zu behandeln. Umsetzbar sind nur Anforderungen mit Status `Approved` (siehe Register) oder eine Änderung, die der Maintainer mit der Aufgabe ausdrücklich freigibt. Phase 4 und die Strava-Direktanbindung sind nicht freigegeben.

**Code und Spezifikation sind ein Stand.** Wer Verhalten ändert, ändert die Spezifikation im selben Branch mit; nach dem Merge beschreibt `docs/` genau das, was der Code tut.

**Rangfolge bei Widersprüchen:** Entscheidungen des Maintainers (DEC in `product.md`, beantwortete offene Fragen `OQ-nnnn`) vor den Specs und Parameterdokumenten, diese vor dem Ursprungskonzept (`SRC-001`). Offene Fragen, Quelleninventar, Ursprungskonzept und Traceability pflegt der Maintainer außerhalb dieses Repos; wer eine Aufgabe bekommt, bekommt die betroffenen Entscheidungen mit. Bis Commit `5f91aa4` lagen sie unter `docs/migration/`.

## Maßgebliche Dateien

- Einstieg: [docs/index.md](docs/index.md)
- Anforderungen finden: [docs/requirements.md](docs/requirements.md), dann der Link zur Detailstelle
- Sicherheit und Datenschutz: [docs/quality/security.md](docs/quality/security.md)
- Tests und Abnahme: [docs/quality/testing.md](docs/quality/testing.md)
- Startwerte der Berechnungen: [docs/model-parameters.md](docs/model-parameters.md)
- Regeln und Startwerte der Planung: [docs/planning-rules.md](docs/planning-rules.md), [docs/phase-2-3-rules.md](docs/phase-2-3-rules.md)
- Architektur und ADRs: [docs/architecture/overview.md](docs/architecture/overview.md), `docs/architecture/adr/`; wo welcher Code liegt, wohin neuer Code gehört und welche Regeln dafür gelten: [docs/architecture/code-map.md](docs/architecture/code-map.md)

Lade nur die für die Aufgabe nötigen Abschnitte.

## Befehle

Nach jeder Änderung an `docs/`:

```sh
python3 tool/spec_tool.py build
python3 tool/spec_tool.py check
```

Gate (Spec-Prüfung, private Daten, Netz nur im Kartenadapter (`tool/check_net.py`, Freigabeliste `tool/net_allowed_packages.txt`), keine neuen Zyklen zwischen `core`-Modulen bzw. App-Features (`tool/check_architecture.py`), Flutter-Version, Lockfile, `core` flutterfrei (Auflösung außerhalb des Workspace), je Paket in `app/` und `app/packages/*` Format, Analyse und Tests), volle Fassung auf GitHub (Workflow `gate`). Details: [docs/quality/testing.md](docs/quality/testing.md#ci-gates).

```sh
sh tool/gate.sh            # alles (läuft auf GitHub bei jedem Push eines Arbeitsbranchs und für Pull Requests)
sh tool/gate.sh --fast     # Zwischenstand: Format, Analyse, Tests der geänderten und der von ihnen abhängigen Pakete; ersetzt nie das volle Gate
sh tool/gate.sh --changed  # Flutter nur auslassen, wenn app/, tool/gate.sh und von Tests gelesene Dokumente gegenüber main unverändert sind; drift/kotlin/release nur bei geänderten Eingaben
sh tool/gate.sh --stage app  # nur eine Stufe (Liste: --list-stages); alle Stufen zusammen = voller Lauf
```

Die E2E-Sammlung (`app/integration_test/`, Übersicht dort in `README.md`) läuft im Workflow `e2e` auf GitHub (Emulator, API 31 und 36). Lokal nur mit eigenem Emulator (`tool/emu.sh`, `tool/ci_e2e.sh`), nie auf einem echten Gerät.

Kernregeln mit einer Mutation belegen: `sh tool/mutate.sh <datei> <zeile> '<ersetzung>' -- <testbefehl>` (stellt die Datei immer wieder her; „überlebt“ = Prüfung fehlt).

## Git

- **Identität:** `brokoskokoli` mit der Noreply-Adresse. Einziger Trailer `Co-Authored-By: Claude <Modell> <noreply@anthropic.com>`, keine Sitzungs-Links. Hooks: `git config core.hooksPath tool/hooks` (Identität, Privat-Scan, Trailer, `main`-Schutz); nie `--no-verify`.
- **Branches:** Arbeit auf einem eigenen Branch (`issue-<nr>-<slug>` bzw. `wp/<nr>-<slug>`), Pull Request gegen `main`. Gemergt wird nur nach unabhängigem Review und grünem `gate` und `e2e` auf genau dem Kopf des Branchs, als Merge-Commit mit der Noreply-Identität; Push auf `main` nur mit `RUNNING_APP_PUSH_MAIN=1`.
- **Generierte Abschnitte** (Register, Frontmatter der Specs, Marker `BEGIN`/`END`) nie von Hand bearbeiten oder Konflikte darin von Hand lösen: `python3 tool/spec_tool.py build`.

## Regeln

- Erfinde keine Anforderungen, Grenzwerte, Endpunkte oder Technologien. Vorschläge kennzeichnest du als `Vorschläge` beziehungsweise ADR-Status `Proposed`.
- Bei Widersprüchen, fehlenden Angaben oder einer offenen Frage, die die Aufgabe berührt: nicht im Code entscheiden, sondern dem Maintainer melden.
- IDs nie umnummerieren. Jede Regel hat genau eine maßgebliche Stelle; sonst nur darauf verweisen. Neue Anforderungen bekommen die nächste freie Nummer, veraltete den Status `Deprecated`.
- Abweichungen von der Spezifikation trägst du nicht still ein: Eine freigegebene Änderung setzt du im selben Branch in `docs/` um, jede andere meldest du dem Maintainer mit einem genauen Vorschlag.
- Sicherheitsanforderungen nicht abschwächen. Keine Geheimnisse ins Repository. Gesundheitsdaten nur gemäß `SEC-0001` bis `SEC-0010` behandeln, auch in Logs, Testdaten und CI-Artefakten; Testdaten sind synthetisch.
- Öffentlich: keine Namen, Kontaktdaten, Orte oder Geräte von Personen („Maintainer“ schreiben), keine absoluten lokalen Pfade, keine echten Messwerte.
- Der Status `Approved` und die Beantwortung einer offenen Frage sind dem Maintainer vorbehalten.
- Architektur: Fachlogik (Modelle, Planung) in `app/packages/core` ohne Flutter und einzeln testbar; Geräte, GPS, Bluetooth, Health Connect, Kamera und Speicher über Ports mit Fakes (`app/packages/adapters`). Jede Berechnung trägt Methode und Version (NFR-0001, NFR-0005). Keine neuen Abhängigkeitszyklen zwischen Modulen unter `app/packages/core/lib/src/` bzw. Features unter `app/lib/features/` (Prüfung `tool/check_architecture.py`). Ordner, Ablageorte und geprüfte Regeln stehen in der [Code-Landkarte](docs/architecture/code-map.md).

## Freigabe nötig für

Änderungen am Produktverhalten, Architekturentscheidungen (ADR), neue Technologien, Datenschutzregeln und jede Änderung an bestätigten Entscheidungen.

## Definition of Ready

Eine Aufgabe ist bereit, wenn sie auf freigegebene Anforderungen verweist (oder die Spezifikationsänderung selbst freigibt), Scope und Akzeptanzkriterien klar sind, Schnittstellen und Abhängigkeiten benannt sind, keine `blocking`-Frage sie betrifft, nötige ADRs freigegeben sind und Sicherheits- und Testanforderungen feststehen.

## Definition of Done

Das Verhalten entspricht der freigegebenen Spec, und die Spec beschreibt das Verhalten. Tests der Akzeptanzkriterien und Negativfälle bestehen. `gate` und `e2e` laufen auf GitHub durch, die unabhängige Prüfung ist erfolgt, und Code, Verträge und Dokumentation sind konsistent (`tool/spec_tool.py check`). Es bleiben keine sicherheitskritischen Abweichungen offen.
