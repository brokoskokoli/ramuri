# WP03 – Vorverarbeitung und Bewegungswerte (`app/packages/core`)

**Zuordnung:** M1.

Bezug: FR-0045 bis FR-0052, FR-0056, FR-0057; PAR-001 bis PAR-015 in `docs/model-parameters.md`; ADR-0004 Punkte 1 und 2; OQ-0019, OQ-0037.

## Inhalt
1. **Eingangsmodell:** Zeitgestempelte Reihen für Position, Herzfrequenz, Höhe und Schritte mit Quelle und den vier Zuständen aus FR-0057. Zuordnung verschiedener Quellen über Zeitstempel (FR-0046).
2. **Position und Strecke:** Filter nach PAR-001 bis PAR-004; Strecke nur aus plausiblen Distanzen (FR-0049), Lücken erhöhen sie nicht.
3. **Tempo:** Momentanwert und Pace (FR-0050), Stillstandsanzeige nach OQ-0037, Live-Fenster nach PAR-005 (FR-0051), Glättung für die Abschnittsauswahl nach PAR-006.
4. **Herzfrequenz:** Plausibilität, Kontaktbit und Ausreißer nach PAR-007 bis PAR-009, Lücken nach PAR-010 ohne Interpolation, Einschwingzeit nach PAR-011. Fehlend ist nie null (FR-0056).
5. **Höhe:** Filter nach PAR-012 und PAR-013, Aufstieg als Ergebnis.
6. **Bewegungszeit:** Getrennt von der Gesamtzeit nach PAR-014 und PAR-015 (FR-0052). Automatische Pause wird hier nur als Zustand berechnet, die Steuerung liegt in WP06.
7. **Qualitätsbewertung je Abschnitt (FR-0048):** Bewertungsobjekt, das WP04 und WP09 weiterverwenden.

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkte 3 und 6 / Teil C: Punkte 4 und 7 / Teil D: Punkt 5 und die Tabelle der Testfälle zu FR-0047, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Reine Funktionen ohne Zeit, Zufall und Plattform (ADR-0004 Punkt 2); dieselbe Logik muss für den Live-Betrieb (WP06) schrittweise aufrufbar sein.
- Alle Startwerte kommen aus einem Parametersatz mit `parameterVersion`, keine Zahl im Code außerhalb dieses Satzes.
- Nicht dazu: Oberfläche, Speicherung, Abschnittsauswahl für VO₂max (WP09).
- Parallel: läuft mit WP02. Berührt nur `app/packages/core/lib/src/preprocessing/` und seine Tests; gemeinsam nur der Export in `app/packages/core/lib/core.dart`.

## Abnahmekriterien
- [ ] Für jedes Problem aus FR-0047 ein Testfall mit festem erwartetem Ergebnis, aus synthetischen Läufen: GPS-Ungenauigkeit, Sprung, fehlende Herzfrequenz, Ausreißer, Verzögerung, Pause, Unterbrechung, Höhenfehler.
- [ ] Grenzwerte jeder PAR-ID aus PAR-001 bis PAR-015 knapp innerhalb und knapp außerhalb getestet, einschließlich beider Schwellen von PAR-014 und der Grenze aus PAR-004.
- [ ] FR-0049: Ein Sprung erhöht die Strecke nicht. FR-0050: Testfall aus der Spec, Stillstand ergibt die Anzeige nach OQ-0037 und keine Division durch null.
- [ ] FR-0051: Die Anzeige folgt dem Fenster; vor der Mindestdatenmenge aus PAR-005 gibt es keinen Wert.
- [ ] FR-0052: Bei einem Lauf mit Pause ist die Bewegungszeit kleiner als die Gesamtzeit; auch bei ausgeschalteter Autopause (PAR-015).
- [ ] FR-0056: Eine Pulslücke senkt den Durchschnitt nicht. FR-0057: Alle vier Zustände sind unterscheidbar und kommen im Ergebnis an.
- [ ] FR-0045: Ein Ausreißer verändert kein Ergebnis ungefiltert; Mutationsbeleg an mindestens drei Filtern.
- [ ] Rohreihen bleiben unverändert: Eingabe und Eingabe nach der Verarbeitung sind gleich.
- [ ] E2E: entfällt (reine Fachlogik); die Prüfung im Emulator erfolgt in WP06.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Die Güte der Startwerte mit echtem GPS-Rauschen (siehe „Validierungsbedarf“ in `docs/model-parameters.md`, OQ-0020).
