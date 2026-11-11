# Anweisungen für Agenten

Stand: Spezifikation fertig, Umsetzung läuft (M1, Projektgerüst und Gate stehen); der aktuelle Stand steht in [work-packages/STATUS.md](work-packages/STATUS.md). Arbeitsorte, Rollen und Branches stehen in [PROJECT.md](PROJECT.md). Das Repository wird öffentlich und ist schon jetzt so zu behandeln. Umsetzbar sind nur Anforderungen mit Status `Approved` (siehe Register). Das sind derzeit die Phasen 1 bis 3, in dieser Reihenfolge. Phase 4 und die Strava-Direktanbindung sind nicht freigegeben.

**Rangfolge bei Widersprüchen:** Entscheidungen des Maintainers (`open-questions.md`, DEC in `product.md`) vor den Specs und Parameterdokumenten, diese vor dem Ursprungskonzept in `sources/`.

**Erster Schritt der Umsetzung:** Die in `docs/architecture/overview.md` genannten ADRs als `Proposed` vorlegen. Erst freigegebene ADRs gelten.

## Maßgebliche Dateien

- Einstieg: [docs/index.md](docs/index.md)
- Anforderungen finden: [docs/requirements.md](docs/requirements.md), dann der Link zur Detailstelle
- Offene Punkte: [docs/migration/open-questions.md](docs/migration/open-questions.md)
- Sicherheit und Datenschutz: [docs/quality/security.md](docs/quality/security.md)
- Startwerte der Berechnungen: [docs/model-parameters.md](docs/model-parameters.md)
- Regeln und Startwerte der Planung: [docs/planning-rules.md](docs/planning-rules.md), [docs/phase-2-3-rules.md](docs/phase-2-3-rules.md)

Lade nur die für die Aufgabe nötigen Abschnitte. Die Dateien in `docs/migration/sources/` sind Belege, keine Arbeitsgrundlage, und werden nie verändert.

## Befehle

Nach jeder Dokumentationsänderung:

```sh
python3 docs/migration/tools/spec_tool.py build
python3 docs/migration/tools/spec_tool.py check
```

Gate (Spec-Prüfung, private Daten, Netz nur im Kartenadapter (`tool/check_net.py`, Freigabeliste `tool/net_allowed_packages.txt`), Flutter-Version, Lockfile, `core` flutterfrei (Auflösung außerhalb des Workspace), je Paket in `app/` und `app/packages/*` Format, Analyse und Tests), volle Fassung in CI. Details: [docs/quality/testing.md](docs/quality/testing.md#ci-gates).

```sh
sh tool/gate.sh            # alles (Pflicht vor Review-Abgabe und Fertigmeldung)
sh tool/gate.sh --fast     # Zwischenstand: Format, Analyse, Tests der geänderten Pakete; ersetzt nie das volle Gate
sh tool/gate.sh --changed  # Flutter nur auslassen, wenn app/ und tool/gate.sh gegenüber main unverändert sind
```

Weitere Befehle ergänzt du erst, wenn sie funktionieren.

## Regeln

- Erfinde keine Anforderungen, Grenzwerte, Endpunkte oder Technologien. Vorschläge kennzeichnest du als `Vorschläge` beziehungsweise ADR-Status `Proposed`.
- Bei Widersprüchen oder fehlenden Angaben: nicht im Code entscheiden, sondern eine `OQ` anlegen oder melden.
- IDs nie umnummerieren. Jede Regel hat genau eine maßgebliche Stelle; sonst nur darauf verweisen.
- Generierte Abschnitte (Register, Traceability Teil A, Marker `BEGIN`/`END`) nicht von Hand bearbeiten.
- Abweichungen vom Spec trägst du nicht still ein: Du meldest sie im Abschlussbericht; der Orchestrator führt sie in [docs/changelog.md](docs/changelog.md).
- Sicherheitsanforderungen nicht abschwächen. Keine Geheimnisse ins Repository. Gesundheitsdaten nur gemäß `SEC-0001` bis `SEC-0010` behandeln, auch in Logs und Testdaten.
- Der Status `Approved` und die Beantwortung einer `OQ` sind dem Maintainer vorbehalten.

## Freigabe nötig für

Änderungen am Produktverhalten, Architekturentscheidungen (ADR), neue Technologien, Datenschutzregeln und jede Änderung an bestätigten Entscheidungen.

## Definition of Ready

Eine Aufgabe ist bereit, wenn sie auf freigegebene Anforderungen verweist, Scope und Akzeptanzkriterien klar sind, Schnittstellen und Abhängigkeiten benannt sind, keine `blocking`-Frage sie betrifft, nötige ADRs freigegeben sind und Sicherheits- und Testanforderungen feststehen. Andernfalls: Klärungsaufgabe vorschlagen statt eines scheinbar fertigen Issues.

## Definition of Done

Das Verhalten entspricht der freigegebenen Spec. Tests der Akzeptanzkriterien und Negativfälle bestehen. Definierte Prüfungen laufen durch, die vorgesehene unabhängige Prüfung ist erfolgt, und Code, Verträge und Dokumentation sind konsistent. Es bleiben keine sicherheitskritischen Abweichungen offen.
