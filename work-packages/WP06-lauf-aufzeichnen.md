# WP06 – Lauf aufzeichnen im Vordergrund (`app/packages/core/lib/src/recording`, `app/packages/adapters`, `app/android`, `app/lib/features/run`)

**Zuordnung:** M1.

Bezug: FR-0025 (frei; aus dem Plan ist Phase 2), FR-0026, FR-0027 (Rundenzeiten, Höhenmeter, Schrittfrequenz als Anzeige), FR-0028, FR-0029, FR-0030, FR-0035, FR-0194, FR-0195, CON-0004; ADR-0005 Punkte 4 und 5; OQ-0012, OQ-0021, OQ-0037, OQ-0064 (geltender Vorschlag zu GPS-Takt und genauem Standort); PAR-004, PAR-005, PAR-014, PAR-015 (über WP03).

Wartet nicht auf R005: Dieses Paket zeichnet nur mit sichtbarer App auf. Hintergrunddienst, Wake Lock, Wiederanlauf und die endgültige Transaktionsgröße liegen in WP08.

## Inhalt
1. **Aufzeichnungssitzung in `core`:** Zustandsmaschine Start, Pause, Fortsetzen, Beenden, Autopause, unabhängig von Widgets und vom Host, damit WP08 sie unverändert in den Dienst übernehmen kann (ADR-0005 Punkt 3).
2. **Standort-Adapter:** Eigener Kotlin-Code auf `LocationManager` mit `GPS_PROVIDER`, Takt nach OQ-0064, hinter dem Port (ADR-0005 Punkt 4). Keine Play-Dienste.
3. **Berechtigung:** Genauer Standort nach OQ-0064 vor dem Start verlangt; ohne ihn startet kein Lauf, und die App erklärt den Grund (FR-0195).
4. **Laufende Speicherung:** Rohwerte in kurzen Transaktionen (ADR-0005 Punkt 5), Lauf-Zustand `aktiv`, Transaktionsgröße als eine Konstante.
5. **Live-Bildschirm:** Pflichtanzeigen aus FR-0026, optionale aus FR-0027, Steuerung, Runden (FR-0030), Autopause als Einstellung (FR-0029). Herzfrequenz über den Port mit Fake; echte Sensoren kommen mit WP07, Schritte mit WP08.
6. **GPS-Verlust:** Zeit und Puls laufen weiter, Lücke markiert, Strecke nicht geschätzt (FR-0194, PAR-004).

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkt 1 mit Uhr-Fake / Teil B: Punkte 2 und 3 / Teil C: Punkte 4 und 6 / Teil D: Punkt 5, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Schrittfrequenz und Herzfrequenz erscheinen als „nicht verfügbar“, solange keine Quelle liefert. Zone nach OQ-0012.
- Nach dem Beenden: einfache Abschlussansicht und Speicherung; die Zusammenfassung baut WP10. Der Bezug „in der Historie vorhanden“ (FR-0028) wird hier am Speicherzugriff, in WP10 an der Oberfläche geprüft.
- Standardwert der Autopause: siehe `M1-PLAN.md`, L12, nicht im Code festlegen ohne Antwort; bis dahin muss die Einstellung ausdrücklich gesetzt werden können.
- Nicht dazu: Hintergrund, Dienst, Sensorverwaltung, Schrittsensor, Wiederaufnahme.
- Parallel: läuft mit WP09. WP09 berührt `core/lib/src/fitness/vo2max`, `core/lib/src/fitness/efficiency`, `core/lib/src/recalculation`, `app/lib/features/settings` (Dialog). Gemeinsam nur ARB-Dateien und der Zusammenbau in `app/lib`; wer später mergt, gleicht ab.

## Abnahmekriterien
- [ ] FR-0028: Alle Zustandswechsel und ungültigen Übergänge getestet (etwa Pause vor Start, zweites Beenden). Pausenzeit zählt zur Gesamt-, nicht zur Bewegungszeit. Der beendete Lauf ist über den Speicherzugriff vorhanden.
- [ ] FR-0029: Mit eingeschalteter Funktion pausiert die Aufzeichnung nach PAR-014, PAR-015 und setzt nach PAR-015 fort; ausgeschaltet nicht. Negativfall: Eine GPS-Lücke löst keine Autopause aus (PAR-004).
- [ ] FR-0030: Eine Runde ist mit Zeit gespeichert; Runde bei pausiertem Lauf nach Testfall definiert oder gemeldet.
- [ ] FR-0026: Jede Anzeige mit und ohne Daten; ohne Puls „nicht verfügbar“ statt 0; ohne Basiswerte Zone nicht verfügbar (OQ-0012); Pace im Stand nach OQ-0037.
- [ ] FR-0027: Rundenzeiten und Höhenmeter sichtbar, Schrittfrequenz ohne Quelle als nicht verfügbar. Soll-/Ist-Anzeigen fehlen (Phase 2).
- [ ] FR-0195: Ohne Berechtigung und mit nur ungefährem Standort startet kein Lauf; Grund sichtbar; nach Erteilung startet er.
- [ ] FR-0194: Beim simulierten Ausfall laufen Zeit und Puls-Fake weiter, Lücke markiert, Strecke unverändert, Mutationsbeleg.
- [ ] FR-0025, FR-0035, CON-0004: Freie Einheit ohne Plan und ohne Sensor wird vollständig gespeichert. Es gibt noch keinen Einstieg aus einem Plan.
- [ ] Rohwerte tragen Zeitstempel, Quelle und Zustand; keine Messwerte in Logs.
- [ ] E2E (separater Agent), API 31 und 36, `adb emu geo`, synthetische Route: Lauf ohne Sensor mit Pause, Runde und Ende (ACC-01); GPS-Ausfall und Rückkehr; Sprung in den Daten; Stand mit Autopause; Start ohne Berechtigung; nur ungefährer Standort.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Echte GPS-Qualität und echtes Rauschen im Stand. Die Emulator-Wiedergabe liefert nicht zwingend realistische Genauigkeitswerte; die davon abhängige Filterung prüfen die Unit-Tests aus WP03.
