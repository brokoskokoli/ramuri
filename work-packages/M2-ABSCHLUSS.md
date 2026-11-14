# Abschlussprüfung M2

Stand: 2026-11-14, Branch `wp/m2-abschluss` (Basis main ab8efb0, main mit WP32 und WP33 nachgemergt). Umfang laut [M2-PLAN.md](M2-PLAN.md#abschlussprüfung-m2). Alle Daten in Tests und E2E sind synthetisch; dieser Bericht nennt keine Gesundheitswerte, nur Zähler, Dauern und Planminuten synthetischer Pläne. Rohbelege (Logs, Mitschnitte, Bilder, Review-Akten) liegen lokal im Übergabeordner der Sitzung, nicht im Repository.

## Ergebnis je Kriterium

| Kriterium | Ergebnis | Beleg | Nur im Feld prüfbar / offen |
|---|---|---|---|
| Ein Jahr Plan im Schnelldurchlauf über die Kernlogik | erfüllt, nach Behebung von 3 Fehlern (F1, F2, sRPE) | `app/packages/core/test/plan/plan_year_simulation_test.dart`: Szenario A 365 Tage (10 km, dann 5 km, Warnsignal, Pausen lang und kurz, Ausfall- und Ermüdungswochen, Rückmeldungen, 8 verschobene und gelaufene Termine, manuelles Neuberechnen), Szenario B Geh-Lauf-Einsteiger 150 Tage. Invarianten je Tag/Woche: Vergangenes unverändert (PAR-203), Wochenzeit ≤ Regler und Steigerung in den PAR-Grenzen, keine harte Einheit unter Warnsignal/`noHardUntil`, Lauftage, Termine nur nach Bestätigung, Wochensumme und Tage bleiben nach Verschiebung und manuellem Neuberechnen, Prüftag nie in der Zukunft und nie rückwärts, zweiter Durchlauf identisch; Laufzeit < 1 s | Plangüte mit echten Läufen; Wochenzeit nach langer Pause und Ausfall sinkt in Szenario A auf 15 bis 60 min (folgt aus PAR-202: 50 % der gelaufenen Basiswoche) – wirkt niedrig, Hinweis an den Maintainer |
| E2E vom Anlegen eines Ziels über eine geführte Einheit (WP24) bis zur Anpassung (WP23) | erfüllt auf API 36 und 31 (Emulator) | neuer Test `app/integration_test/e2e_m2_flow_test.dart` (Stufe `m2-flow` in `tool/ci_e2e.sh`): Profil → Ziel → Plan → „Einheit starten“ → Abschnittswechsel in Echtzeit → Beenden → Zusammenfassung „Aus dem Plan“ → Rückmeldung → Zieländerung mit Änderungskarte und Erklärung → Neu berechnen → Verlauf der Fassungen. Lokal 4× grün (2× API 36, 2× API 31) | einmal rot auf API 31 lokal und einmal in der CI; Ursache nicht belegt (Hypothese: Tipp ohne Treffer unter Last, dann `plan_form_error`), belegt war nur der Abbaufehler im Profil (Fehler 10). Test jetzt mit Trefferprüfung und sichtbarer Fehlerzeile ohne Werte; danach CI auf API 31 und 36 grün. Hörbarkeit der Ansagen, gesperrter Bildschirm, Akku, echter Puls, Android 17: Feld |
| Netzprüfung wie in M1 (keine neuen Hosts) | erfüllt auf API 36 | Mitschnitt über eth0 (WLAN aus): ohne Karten-Einwilligung Rundgang durch Plan, Kalender, Planverlauf, geführte Einheit, Zusammenfassung, Verlauf, Detail, Fortschritt, Lauf vorbereiten → kein DNS/SNI der App, App-UID rx/tx 0; mit Einwilligung nur `tiles.openfreemap.org` | API 31 nicht wiederholt (dort ohne WLAN kein Netz, und der Mitschnitt sieht den WLAN-Weg nicht); Mitschnitte über WLAN sind ungültig und zählen nicht |
| Archiv mit allen M2-Daten hin und zurück | erfüllt | `app/packages/adapters/test/archive/archive_m2_roundtrip_test.dart`: Ziele, Planfassungen und -einheiten (fest, verschoben, Ruhetag), Läufe mit RPE/sRPE, Nachtrag, aktives Warnsignal, Laufband, RR-Pakete, Prognose-Referenzen, Plan-Merker; Export → Reimport in leere App → jede Tabelle zeilengleich, Plan und Warnsignal auch über die Ports | bewusst nicht im Archiv: Einwilligungen, Speicher-Metadaten, Schlüssel, technische Merker (`plan.started_unit`, `guided.unit_snapshot`, `values.*Pending`); `health.last_import_ms` (WP32) ebenfalls ausgeschlossen und im Vertrag genannt. Echter Gerätewechsel und große Archive: Feld |
| Abgleich mit `Plan`, `Intervall`, `Main`, `Summary`, `Start` (`design/screens/*.dc.html`) | erfüllt mit Abweichungen | Bilder hell und dunkel auf API 36, Vergleich gegen Text und Aufbau der Design-Dateien (nicht pixelgenau); Beispielwerte und die in `design/README.md` dokumentierten Abweichungen nicht gezählt. Behoben: Startseite fasst wiederholte Abschnitte zusammen („8× 1 min Laufen · 2 min Gehen“ statt 17 Zeilen) | siehe „Abweichungen vom Design“ |

## Gefundene und behobene Fehler

Jeder Fix hat einen Test und einen Mutationsbeleg (`tool/mutate.sh`, Mutant erkannt).

1. **Manuelles Neuberechnen setzte den Prüftag ohne Wochenbewertung** (gegen ADR-0010, Nachtrag WP24, K63). Ebenso „Geh-Lauf wiederholen“ und die Antwort auf die Nachfrage alle 2 Wochen (PAR-200). Jetzt setzen nur Rechnungen mit Wochenbewertung den Prüftag.
2. **Fehlende Sprachausgabe blieb still.** Neue Kanalmethode `available` (Sprache der Engine verfügbar); beim Start und beim Fortsetzen einer geführten Einheit mit eingeschalteten Ansagen einmal der Hinweis „Sprachausgabe nicht verfügbar“ auf der Seite „Einheit“ und „Werte“. Auf dem Emulator belegt: mit Engine kein Hinweis, Engine deaktiviert → Hinweis auf „Werte“; die Anzeige auf „Einheit“ kam danach dazu und ist per Widget-Test belegt.
3. **Ø-Pace außerhalb der Diagrammwerte nach Absturzlücke.** Ursache: Die Wartezeit vom Abschnittsbeginn (Start, Fortsetzen) bis zum ersten Punkt zählte bis 10 s (PAR-004) als Bewegungszeit ohne Strecke; trat auch ohne Absturz auf. Jetzt zählt sie wie Lückenzeit nicht in die Durchschnittspace (K20); die Kilometertabelle zeigt „GPS-Lücke“ weiter nur für echte Lücken. Methodenversionen Positionsfilter 2, Kurzfassung 4 (alte Kurzfassungen werden neu gerechnet).
4. **Karten-Einwilligungsfrage über dem Beenden-Dialog.** Die Frage erscheint nicht mehr während eines Laufs (auch pausiert) und nicht, solange eine andere Route oder ein Dialog oben liegt; sie kommt beim nächsten Öffnen einer Karte außerhalb des Laufs. Bleibt fail-closed (ohne Einwilligung keine Kacheln). E2E: nie im Lauf, nicht über „Lauf beenden?“, danach in der Zusammenfassung.
5. **Werkzeuge:** Kommentar `tool/hooks/pre-push` vollständig; neuer Test `tool/merge_wp_test.sh` (10 Fälle der CI-Entscheidung) im Gate.
6. **F1 – Verschobener, gelaufener Termin kostete eine Einheit der Woche** (gefunden in der Jahressimulation): Die gehaltenen Tage gingen nicht in die Erzeugung ein, die neu erzeugte Einheit wurde verworfen. Jetzt deckt der Lauf genau eine Einheit gleicher Rolle ab (die früheste ab heute; eine ersetzte harte zählt als hart), künftige verschobene Termine bleiben reserviert, im Rückfall entfällt zuerst die lockere, dann die harte, zuletzt die lange Einheit. Planregelversion 5.
7. **F2 – Kein Neustart nach langer Pause, wenn eine Rückmeldung den Anker schon verschoben hatte** (PAR-202 entfiel). Jetzt gilt nach langer Pause der Neustart auch dann, wenn eine Rückmeldung oder Wochenbewertung den Anker gesetzt hat (ein in dieser Woche neu angelegter Plan startet weiterhin nicht neu); Obergrenze ist das Minimum aus der Woche vor und nach der Anpassung. Solange die Pausenfrage offen ist, wird die Nachfrage nach PAR-200 nicht angeboten.
8. **sRPE blieb nach fehlgeschlagener Neuberechnung veraltet** (offen seit WP18). Jetzt wird sRPE vor der Kurzfassung geschrieben; scheitert es, holt der nächste Lauf beides nach. Bei Bewegungszeit 0 wird der Wert gelöscht.
9. **„Zu schwer“ meldete „Plan geändert“, ohne dass eine Fassung entstand.** Jetzt „Der Plan bleibt, wie er ist“.
10. **`ProfileScreen` rief beim Abbau `clearSnackBars` auf** (Fehler „setState() called when widget tree was locked“, ohne Animationen z. B. mit Bedienungshilfen). Jetzt nach dem Frame.

## Abweichungen vom Design (nicht behoben, Folgepunkte)

- Heute: „Einheit starten“ bricht auf zwei Zeilen um.
- Geführte Einheit: keine Soll/Ist-Skala (bewusst, K63 Punkt 13), keine Pulswarnung auf der Seite „Einheit“, kein Knopf „Intervall überspringen“, keine Meter-Restanzeige.
- Zusammenfassung: Die feste Knopfleiste verdeckt anfangs die Kennzahlen bis zum Scrollen; Kopf „Lauf beendet“ statt Datum·Typ.
- Plan: Start-Knopf in fester Leiste statt in der Tageszeile, Tageszeilen ohne Zweck, Phasenbalken 3 statt 4 Abschnitte.
- Start: Laufart Draußen/Laufband zusätzlich; Los-Knopf rund statt Pille.

## Offene Punkte aus STATUS (WP18 bis WP31), gesichtet

87 Punkte eingeordnet: 16 inzwischen erledigt, 25 per Unit-/Widget-Test prüfbar, 8 per Emulator, 12 nur im Feld, 26 Produktfragen oder anderes Thema. In dieser Prüfung behoben bzw. belegt: sRPE veraltet (WP18), Ø-Pace nach Absturzlücke und Prüftag (WP24), Kartenfrage, `pre-push`-Kommentar und Test für `merge_wp.sh` (WP31); E2E von WP23 liegt inzwischen in `e2e_plan_test.dart`. Nicht in dieser Prüfung: die übrigen per Test prüfbaren Folge-Soll aus WP22 (Wochenschritt und +18-h-Grenze der Erinnerungen, Meilenrundung, Prognosekarte mit gemischten Referenzen), WP25 Fehlerwege beim Fortsetzen, Laufband-Führung (WP24) und Erinnerungen nach Neustart des Geräts (WP22) auf dem Emulator.

## Nur im Feld prüfbar

Ansagen hörbar bei gesperrtem Bildschirm und mit Musik, echter Pulsgurt (Pulsansagen, Gehpausen-Hinweis), Akku und Hintergrundbetrieb, Android 17, echte Laufband-Führung, Autopause am Gerät, Verhalten der echten Sprach-Engine bei fehlender Sprache auf anderen Herstellern.

## Wie belastbar

- Simulation und Archiv: deterministische Host-Tests mit synthetischen Daten; die Invarianten prüfen Regeln, nicht die Güte des Plans.
- E2E und Netz: zwei Emulatoren (API 36 und 31), je wenige Läufe; Netz nur API 36. Der Mitschnitt deckt TLS-Inhalte nicht ab, nur Hosts.
- Design: Sichtvergleich, keine Pixelvergleiche.
