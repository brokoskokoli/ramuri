# Prüfprotokoll für Reviews

1. Abnahmekriterien des Pakets einzeln prüfen (erfüllt / teilweise / fehlt).
2. Diff lesen: Logik, Fehlerwege, Rennen, Grenzfälle, fail-closed bei Sicherheitslogik.
3. Tests: Decken sie die Kriterien ab? Mutationstests an 3–10 kritischen Stellen.
4. Datenschutz und Secrets: keine Inhalte in Logs/Exporten, keine Keys, keine privaten Daten im (öffentlichen) Repo.
5. Konsistenz: Spezifikation, ADRs, `docs/architecture/overview.md`, Abhängigkeitsregeln, Dateigrößen.
6. Identität aller Commits.
7. Urteil: FREIGABE oder NACHBESSERN; Befunde Blocker/Muss/Soll mit Datei:Zeile und Fix.

Zusätzlich hier: Abgleich mit den betroffenen FR/NFR/SEC und PAR-Startwerten; keine Gesundheitsdaten in Logs und Testdaten (SEC-0001 bis SEC-0010); Modelle und Grenzwerte nur aus `docs/model-parameters.md`, `docs/planning-rules.md`, `docs/phase-2-3-rules.md`, nicht frei erfunden.
