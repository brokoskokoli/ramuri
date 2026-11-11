# WP24 – Geführte Einheit und Ansagen (`core`, `adapters`, `app/lib/features/run`)

**Zuordnung:** M2, Welle 4, nach WP22 und WP25. Parallel zu WP23.

Bezug: FR-0025, FR-0027, FR-0031 bis FR-0033, FR-0146, FR-0210; PAR-107, PAR-119 bis PAR-121; ADR-0005, ADR-0009; OQ-0044, OQ-0077. Vorlagen: `design/screens/Start.dc.html`, `Intervall.dc.html`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Lauf vorbereiten (Teil A):** Umschalter „Geplante Einheit“ und „Freier Lauf“ nach `Start.dc.html`, mit den Abschnitten der Einheit und dem Schalter „Ansagen“. Lockere Einheiten ohne eigene Auf- und Abwärm-Abschnitte (PAR-119), das Beispiel des Designs ist keine Vorgabe.
2. **Abschnittsfolge (Teil B, FR-0033):** Reine Logik in `core`: aktueller und nächster Abschnitt, Rest in Zeit oder Strecke, Verhalten bei Pause, Autopause und Wiederanlauf nach einem Absturz.
3. **Intervall-Seite (Teil C, FR-0027, FR-0146):** Nach `Intervall.dc.html`, in beiden Modi dunkel (FR-0205): Abschnitt, Rest, Soll- und Ist-Wert, nächster Abschnitt. Pulshinweise nur nach PAR-107, also nie in Blöcken unter 4 min. Pflichtanzeigen aus WP16 bleiben erreichbar.
4. **Warnung und Ansagen (Teil D, FR-0031, FR-0032):** Einzeln schaltbare Sprachansagen: je Kilometer mit Zeit und Pace, Überschreitung des Pulsbereichs, Intervallwechsel. Über die Sprachausgabe des Systems, auch bei ausgeschaltetem Bildschirm. Texte auf Deutsch und Englisch.
5. **Zuordnung (Teil E):** Der fertige Lauf gehört zur Einheit („Aus dem Plan“ in der Zusammenfassung), zählt aber wie jeder andere Lauf.
6. **Aus WP22:** Ein Neustart nach PAR-202 senkt die Start-Wochenzeit; bei „nein“ fallen die harten Einheiten weg. Nach „Einheit starten“ zeigt „Lauf vorbereiten“ noch „Ohne Vorgabe“ (Teil A).

## Umsetzung
- **Vorab klären und in die Fertigmeldung:** Kommt die Sprachausgabe ohne neue Abhängigkeit aus, und sendet sie aus der App heraus nichts ins Netz (ADR-0009)? Die App darf für Ansagen kein Netz nutzen; ob eine vom Nutzer gewählte Stimme des Systems online arbeitet, liegt außerhalb der App und wird dokumentiert. Neue Abhängigkeit vorher beim Orchestrator anmelden.
- **Aufzeichnung ist unantastbar:** Der Aufzeichnungsdienst aus ADR-0005 bleibt in seinem Kern unverändert; ein Fehler in Führung oder Sprachausgabe darf die Aufzeichnung nie stören (Test). Muss der Dienst geändert werden, vorher beim Orchestrator melden.
- Teile je ein Coder-Auftrag. Mutationsbelege für Abschnittswechsel, die Regeln aus PAR-107 und die Schalter der Ansagen.
- **Parallel:** `run` nur hier, `home` nur WP23. Texte mit Präfix `guided`/`voice`.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0031, FR-0032, FR-0033 und FR-0146.
- [ ] Eine Intervalleinheit lässt sich im Emulator mit eingespielter GPS-Wiedergabe durchlaufen, inklusive Pause und Wiederanlauf.
- [ ] Ohne Sprachausgabe oder Pulssensor läuft die Einheit normal weiter.
- [ ] Netzprüfung wie in M1: keine neuen Hosts durch Ansagen in der App.
- [ ] E2E auf API 36 und 31, hell und dunkel; Bildschirmfotos neben dem Design. Gate grün.

## Ungeprüft
Hörbarkeit und Bedienung im Laufen auf echtem Gerät.
