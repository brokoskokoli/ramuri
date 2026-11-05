# Migrationsbericht

Stand: 2026-11-04. Durchgeführt nach SRC-002. Die Anforderungen der Phasen 1 bis 3 sind `Approved`; Phase 4 mit der Energiereserve und die zurückgestellte Strava-Anbindung bleiben `Draft`.

## Verarbeitete Quellen

- SRC-001: Funktionales Konzept, Version 0.1 – Entwurf (ursprüngliche Produktquelle)
- SRC-002: Transformationskonzept, Version 1.0 (Arbeitsanweisung)
- SRC-003: Entscheidungen des Maintainers (Vorrang vor SRC-001)

Details stehen im [Quelleninventar](source-inventory.md). Die Originale blieben unverändert.

## Erstellte Dateien

- `README.md`, `AGENTS.md`
- `docs/index.md`, `docs/product.md`, `docs/requirements.md`, `docs/references.md`, `docs/model-parameters.md`, `docs/planning-rules.md`, `docs/phase-2-3-rules.md`
- `docs/specs/`: 19 Feature-Spezifikationen
- `docs/architecture/overview.md`, `docs/architecture/data-model.md`, `docs/architecture/adr/ADR-0001-nur-lokale-datenhaltung.md`
- `docs/contracts/README.md`
- `docs/quality/testing.md`, `docs/quality/security.md`, `docs/quality/non-functional.md`
- `docs/migration/`: Inventar, Traceability, offene Fragen, dieser Bericht, Quellkopien, `tools/spec_tool.py`

**Bewusst nicht erstellt:** `deployment.md`, weil es keinen Serverbetrieb gibt (ADR-0001). ADRs entstehen nur aus Entscheidungen des Maintainers. Ebenso kein Anwendungscode, keine Issues und kein Git-Repository.

## Abdeckung

Die Zahlen werden aus den Dateien erzeugt.

<!-- BEGIN STATS -->
| Kennzahl | Wert |
|---|---|
| Quellen im Inventar | 3 |
| Feature-Spezifikationen | 19 |
| Anforderungen gesamt | 230 |
| davon FR / NFR / SEC / CON | 203 / 6 / 11 / 10 |
| davon Status Blocked | 0 |
| Akzeptanzkriterien in Anforderungen | 385 |
| Fragen gesamt (offen blocking / offen non-blocking / entschieden) | 71 (0 / 6 / 65) |
| Traceability-Zeilen (Teil A / Teil B) | 271 (257 / 14) |
| davon Duplikat zusammengefasst | 5 |
| davon begründet nicht übernommen | 1 |
<!-- END STATS -->

Eine Traceability-Zeile entspricht einer Fundstelle und nicht zwingend genau einer atomaren Aussage.

## Offene Entscheidungen und Risiken

Alle Fragen stehen in [open-questions.md](open-questions.md). Vor der Umsetzung sind besonders wichtig:

**Blockierend:** Keine offene Frage mehr. Startwerte und Planungsregeln sind freigegeben, aber nicht validiert (OQ-0020). Die Phasen 1 bis 3 sind abgenommen.

**Nicht blockierend:** OQ-0032 (Formatversionen, Format für Zusatzmetriken), OQ-0048 (rechtliche Prüfung, Voraussetzung für ein Release).

**Bereits entschieden (SRC-003):** Alle übrigen Fragen; Einzelheiten stehen je Frage in open-questions.md.

**Risiken:**

- Gesundheitsbezogene Hinweise (OQ-0026) und Datenschutz (OQ-0025) sind fachlich entschieden, aber nicht rechtlich geprüft.
- Die Quelle ist ein Entwurf. Die Modelle sind nicht validiert (OQ-0020).
- Die Akzeptanzkriterien auf Anforderungsebene hat der Migrationsagent aus den Quellaussagen abgeleitet. Sie sind Teil der fachlichen Abnahme; nur ACC-01 bis ACC-15 stehen wörtlich in der Quelle.

## Validierungen

Automatische Prüfung mit `spec_tool.py check`:

| Prüfung | Ergebnis |
|---|---|
| Eindeutigkeit der IDs und gültige Referenzen | PASS |
| Interne Markdown-Links und Anker | PASS |
| Quellenabdeckung auf Zeilenebene | PASS |
| Prüfsummen der Quellkopien | PASS |
| Rechenbeispiele der Quelle, von Hand nachgerechnet (nicht Teil von `check`) | PASS |
| Unabhängige inhaltliche Prüfungen (Konzept; Abschlussprüfung; Phase 2 und 3) | DURCHGEFÜHRT, Befunde eingearbeitet; drei Prüfungen; die Korrekturen der letzten nicht erneut unabhängig geprüft |
| Externe Links in `references.md` | NICHT GEPRÜFT |
| Research-Prüfungen R001 bis R004 | Jeweils NACHBESSERN, Korrekturen eingetragen (OQ-0059, DEC-0058); gezielte Prüfung der R004-Korrekturen durchgeführt, Befunde eingetragen (DEC-0059), nicht erneut unabhängig geprüft |

Die Zeilenabdeckung zeigt nur, dass jede Quellzeile zugeordnet ist, nicht dass ihr Sinn korrekt übernommen wurde. Die Gegenprüfung fand die meisten Fehler in abgeleiteten Akzeptanzkriterien: vorweggenommene offene Fragen und aus „kann“ gemachte Pflichten. Sie führte auch zu OQ-0038 bis OQ-0040. Laut Prüfer sind besonders die kleineren Befunde wahrscheinlich nicht vollständig; die fachliche Abnahme bleibt daher nötig.

## Prüfstand der Regeldokumente

Die Research-Prüfungen urteilten dreimal **NACHBESSERN**: [R001](research-reviews/R001-model-parameters.md) zu den Modellparametern, [R002](research-reviews/R002-planning-rules.md) zu den Planungsregeln, [R003](research-reviews/R003-phase-2-3-rules.md) zu Phase 2 und 3. Die Korrekturlisten stehen in [R001-fixes](research-reviews/R001-fixes.md), [R002-fixes](research-reviews/R002-fixes.md) und [R003-fixes](research-reviews/R003-fixes.md), die Wertänderungen in [values-applied](research-reviews/values-applied.md) und OQ-0059. Das Re-Review [R004](research-reviews/R004-final-review.md) urteilte ebenfalls **NACHBESSERN**. Die letzte Korrekturrunde steht in [R004-fixes](research-reviews/R004-fixes.md), mit reproduzierbarer Rechnung und Prüfsummen. Version 2 war danach eingefroren (DEC-0058). Die [gezielte Prüfung](research-reviews/R004-check.md) fand einen Verstoß gegen FR-0154 in PAR-083 und einen Widerspruch beim Hinweis auf den 5-km-Test. Beides ist korrigiert; Planungsregeln und Regeln für Phase 2 und 3 sind deshalb Version 3 (DEC-0059). Die Energiereserve ist danach auf Phase 4 verschoben, ihre Werte sind unverändert (DEC-0060). Danach hat der Maintainer alle präzisen Planregeln annulliert und einfache Regeln zum Testen festgelegt (OQ-0060, DEC-0061, Version 4). Die Prüfberichte R001 bis R004 gelten für den Trainingsplan deshalb nur noch als Hintergrund. Version 3 liegt in `archive/`.

## Nächste empfohlene Schritte

1. Rechtliche Prüfung beauftragen (OQ-0048).
2. Implementierungsagent starten.
3. Die benötigten ADRs als `Proposed` vorlegen ([Überblick](../architecture/overview.md)).
4. Erst dann freigegebene Specs in Epics und Issues zerlegen.
