---
id: FEAT-001
title: Nutzerprofil und persönliche Einstellungen
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0001, FR-0002, FR-0003, FR-0004, FR-0005, FR-0006, FR-0214, FR-0217, FR-0220]
---

# Nutzerprofil und persönliche Einstellungen

## Ziel
Der Nutzer hinterlegt persönliche Basiswerte, auf denen Fitnessberechnungen und Trainingspläne aufbauen.

## Scope
- Ersteinrichtung und spätere Korrektur des Profils
- Maximale Herzfrequenz: gemessener Wert oder altersbasierte Näherung
- Nachvollziehbare Neuberechnung nach Änderungen

## Funktionale Anforderungen

### FR-0001 — Profil beim ersten Start einrichten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2, Z. 33
- **Verwandt:** FR-0002, OQ-0010

Beim ersten Start richtet der Nutzer ein persönliches Profil ein.

**Akzeptanzkriterien:**
- [ ] Beim ersten Start wird die Profileinrichtung angeboten.
- [ ] Die Einrichtung lässt sich überspringen, und ein Lauf ist danach möglich (OQ-0010).

### FR-0002 — Profildatenfelder
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 37–47
- **Verwandt:** FR-0001, OQ-0010, OQ-0013, OQ-0038, OQ-0065

Das Profil umfasst die folgenden Felder.

| Datenfeld | Zweck | Erforderlich |
|---|---|---|
| Alter oder Geburtsjahr | Näherung für maximale Herzfrequenz | Optional |
| Körpergewicht | Optionale Energieverbrauchsschätzung | Optional |
| Körpergröße | Erweiterte Analysen | Optional |
| Ruheherzfrequenz | Intensitäts- und VO₂max-Schätzung | Optional |
| Maximale Herzfrequenz | Belastungszonen und Fitnessberechnung | Optional |
| Fitness-/Lauferfahrung | Auswahl des anfänglichen Trainingsplans | Für Trainingspläne |
| Aktuelles Leistungsniveau (im Konzept „Aktuelle Laufleistung“): aktuelle Zeit über eine Distanz oder Selbsteinschätzung | Einschätzung des Trainingsniveaus | Für Trainingspläne |
| Wöchentlicher Laufumfang (Minuten) | Ausgangsanalyse des Plans (OQ-0013) | Für Trainingspläne |
| Verfügbare Trainingstage | Trainingskalender | Für Trainingspläne |
| Übliche Trainingsdauer | Trainingsplanung | Optional |
| Koeffizienten des Banister-Modells (männlich, weiblich) | Nur für das Belastungsprofil Banister (OQ-0053) | Optional, ab Phase 2 |

**Festlegung (OQ-0065):** Lauferfahrung und Selbsteinschätzung sind bis Phase 2 zurückgestellt. Alter, Gewicht und Größe verlangen nur positive Zahlen.

**Akzeptanzkriterien:**
- [ ] Alle als „Optional“ markierten Felder können leer bleiben, ohne dass die Grundfunktionen gesperrt werden.
- [ ] Trainingstage und Trainingsdauer im Profil sind Standardwerte für neue Ziele (OQ-0038).
- [ ] Beim Erstellen eines Plans fragt die App fehlende Angaben ab. Pflicht sind die verfügbaren Trainingstage und die maximale Trainingszeit je Einheit (K53); ohne die übrigen Angaben entsteht ein konservativer Einstiegsplan (OQ-0010).

### FR-0003 — Gemessene maximale Herzfrequenz hat Vorrang
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 49
- **Verwandt:** FR-0004

Eine gemessene maximale Herzfrequenz ist einer altersbasierten Schätzung vorzuziehen.

**Akzeptanzkriterien:**
- [ ] Sind Messwert und Alter hinterlegt, rechnet die App mit dem Messwert.

### FR-0004 — Altersbasierte Näherung der maximalen Herzfrequenz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 51–55
- **Verwandt:** FR-0003, FR-0005, OQ-0012

Ist kein Wert bekannt, kann vorläufig `HFmax = 208 − 0,7 · Alter` verwendet werden.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet aus der Formel): Alter 40 ergibt 180 bpm.
- [ ] Der so ermittelte Wert ist als Schätzung gekennzeichnet (CON-0009).

### FR-0005 — Hinweis auf Streuung und Korrektur der Näherung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 57
- **Verwandt:** FR-0004

Die Näherung besitzt eine erhebliche individuelle Streuung. Der Nutzer kann den Wert jederzeit korrigieren.

**Akzeptanzkriterien:**
- [ ] Der Nutzer kann den Wert jederzeit ändern.
- [ ] Die Näherung wird nicht als individuell genauer Wert dargestellt.

### FR-0006 — Neuberechnung nach Änderung der Basiswerte
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §2.1, Z. 59
- **Verwandt:** FR-0058, OQ-0031

Änderungen an persönlichen Basiswerten müssen zu einer nachvollziehbaren Neuberechnung der davon abhängigen Fitnesswerte führen können.

**Akzeptanzkriterien:**
- [ ] Nach einer Änderung lassen sich abhängige Fitnesswerte neu berechnen.
- [ ] Ursprünglicher und neu berechneter Wert bleiben unterscheidbar (FR-0058).

### FR-0214 — Ruhepuls mit der Handykamera messen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-003 (Maintainer 2026-11-09)
- **Verwandt:** FR-0002, FR-0060, SEC-0001, OQ-0078, DEC-0073, DEC-0074, FR-0220

Im Profil und bei der Einrichtung kann der Nutzer seinen Ruhepuls messen lassen, statt ihn einzutragen: Finger auf Rückkamera und Blitz, die App erkennt die Schläge im Kamerabild (Photoplethysmografie). Vor der Messung empfiehlt sie eine Ruhephase mit beruhigender Anleitung; wer schon entspannt ist, misst sofort. Vor der ersten Messung kann die Kamerasuche nach FR-0220 vorgeschaltet sein.

**Akzeptanzkriterien:**
- [ ] Erreichbar über das Profil (Ruheherzfrequenz) und als Knopf bei der Einrichtung.
- [ ] Ablauf: Erklärung mit Bild, wie der Finger liegt: leicht und gleichmäßig aufgelegt, nicht fest gedrückt; wählbar Ruhephase (Vorgabe 5 min, Länge einstellbar) oder sofort messen; danach 60 s Messung.
- [ ] Haltung sitzend oder liegend wählbar; sie wird mit dem Wert gespeichert, ebenso der Zeitpunkt.
- [ ] Die beruhigende Anleitung gibt kein Atemtempo vor; während der 60 s atmet der Nutzer spontan.
- [ ] Es zählt die erste Messung mit ausreichender Qualität; wiederholt wird nur, wenn die Qualität nicht reicht.
- [ ] Während der Messung zeigt die App die Pulskurve und den laufenden Puls, damit der Nutzer den Finger justieren kann, sowie den Fortschritt.
- [ ] Ergebnis nur bei ausreichender Signalqualität; sonst ein Hinweis mit Grund und „noch einmal“. Der Nutzer übernimmt den Wert ausdrücklich ins Profil. Hat der Kamera-Ruhepuls die Validierung „nicht bestanden“ (Validierungssperre in K-1, FR-0215), trägt der Vorschlag den Hinweis „ungenauer als erwartet“.
- [ ] Ohne Kamera, Blitz oder Berechtigung bleibt die manuelle Eingabe; die App stürzt nicht ab.
- [ ] Kamerabilder werden weder gespeichert noch übertragen; die Auswertung läuft auf dem Gerät.
- [ ] Der Algorithmus folgt der Referenz aus `../puls` (`docs/ALGORITHMUS.md`, Stand `algo-v0.4-frozen`) und ist gegen deren Testvektoren geprüft.

### FR-0217 — Entwicklermodus
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-003 (Maintainer 2026-11-13, K61/K62)
- **Verwandt:** FR-0215, FR-0213, FR-0021, FR-0216, SEC-0009, DEC-0074, FR-0220, FR-0223

Unter Einstellungen → Über schaltet 10-maliges Tippen auf die Versionsnummer den Entwicklermodus ein; er lässt sich in den Entwicklereinstellungen wieder ausschalten. Er dient der Validierung der Kamera-Morgenmessung (FR-0215) gegen einen Brustgurt und gilt auch in der Release-Version. Bis die Validierung bestanden ist, ist die Morgenmessung nur im Entwicklermodus nutzbar (K62 Punkt 1). **Abweichung von der Validierungssperre in K-1 (Entscheidung des Maintainers, K61, K62 Punkt 6):** Im Entwicklermodus gelten Ruhepuls und RMSSD der Morgenmessung vollständig als gültige Werte, als wäre die Validierung bestanden. Ohne Entwicklermodus gilt die Sperre unverändert.

**Umsetzung (WP33, K65):** Die Seite „Über“ (Name, Version, Lizenzen) ist ein Eintrag der Übersicht hinter dem Profil-Symbol; ab dem 7. Tipp zählt ein Hinweis die restlichen Tipps herunter. Ist der Modus an, erscheint in der Übersicht der Eintrag „Entwicklereinstellungen“ (Entscheidung Maintainer 2026-11-18). Diese Seite bündelt alles des Entwicklermodus: Schalter zum Ausschalten, Kamerawahl (FR-0220), Export der Messpaare, den Vergleich Kamera/Gurt und die gezählten Fehler mit dem Diagnose-Export (FR-0223). Dazu kommen Diagnose-Schalter „Kamera-Bildverarbeitung“ (Rauschunterdrückung aus, Kantenschärfung aus, Weißabgleich fest ab Start, Tonwertkurve linear, Linsenschattierung fest; Vorgabe jeweils aus), Geräteeinstellung wie die Kamerawahl (Entscheidung des Maintainers 2026-11-21). Er ist eine Einstellung des Geräts, kommt nicht ins Archiv und wird von „Alles löschen“ zurückgesetzt. Nach dem Ausschalten bleiben die Messungen gespeichert, sind aber nicht sichtbar; die Morgen-Erinnerung bleibt eingeschaltet, ihr Wecker ist gestrichen. Gurt-RR speichert die App nur vom ersten Quellgerät der Messung, von Beginn der Ruhephase bis Ende der Messung (bei „Noch einmal messen“ lückenlos bis Ende der Wiederholung); das Format der CSV steht in [morning-pairs-csv.md](../contracts/morning-pairs-csv.md). Für den Vergleich Kamera/Gurt ordnet die App die Kamera-Schlagabstände ohne gemeinsame Uhr über einen Versatz in Schlägen der Gurt-Folge zu: Gewählt wird der Versatz mit den kleinsten mittleren Abweichungen (je Paar höchstens 100 ms, mindestens 10 Paare und 60 % der gültigen Kamera-Abstände); ist er nicht eindeutig (PAR-229), zeigt die Zeile „keine Zuordnung“. Gurt-RMSSD und Gurt-Ruhepuls stammen aus den Gurt-Werten an den Stellen des Kamera-Fensters (gültig 0,27 bis 2,0 s), berechnet beim Anzeigen und nicht gespeichert (Verfahren `morning-belt-compare`).

**Akzeptanzkriterien:**
- [ ] 10 Tipps auf die Versionsnummer schalten den Modus ein, weniger nicht; ausschalten lässt er sich in den Entwicklereinstellungen.
- [ ] Ohne Entwicklermodus ist die Morgenmessung vor bestandener Validierung nirgends erreichbar (K62 Punkt 1).
- [ ] Im Entwicklermodus erscheinen Ruhepuls und RMSSD der Morgenmessung in Trends, Kurven, Readiness und bei „adaptiv“ (FR-0216) im Plan wie nach bestandener Validierung, ohne Opt-in und ohne Kennzeichnung „experimentell“ oder „noch nicht geprüft“; höchstens ein unauffälliger Hinweis „Entwicklermodus aktiv“ (K62 Punkt 6, ersetzt die Kennzeichnung aus K61).
- [ ] Jede Messung trägt intern dauerhaft das Merkmal „vor der Validierung gemessen“, wenn sie vor bestandener Validierung entsteht; es ändert weder Anzeige noch Rechnung.
- [ ] Die Qualitätsgrenze je Messung (PAR-160K) gilt auch im Entwicklermodus: unbrauchbare Messungen, auch mit einem Ruhepuls außerhalb PAR-017, zählen nirgends; ohne Entwicklermodus werden sie verworfen, im Entwicklermodus mit Stufe „unbrauchbar“ und Grund, aber ohne Puls gespeichert.
- [ ] Ist bei der Morgenmessung ein Brustgurt mit RR-Intervallen verbunden, speichert die App im Entwicklermodus dessen RR parallel zur Messung (K61 Punkt 3); ohne Entwicklermodus nicht.
- [ ] Die Messpaare Kamera/Gurt lassen sich nur im Entwicklermodus als unverschlüsselte CSV teilen, mit Warnhinweis vor dem Teilen wie bei der Zusatzmetriken-CSV (K62 Punkt 4, K57).
- [ ] Die Entwicklereinstellungen zeigen je Morgenmessung mit Gurt-RR RMSSD und Ruhepuls von Kamera und Gurt, die Differenz und eine Kurve der Schlagabstände (Entscheidung Maintainer 2026-11-18, hebt K62 Punkt 4 in diesem Teil auf). Die Werte gehen in keine Auswertung ein.
- [ ] Im Entwicklermodus speichert die Morgenmessung mit dem Rohsignal je Bild die von der Kamera gemeldeten Werte der Bildverarbeitung und Belichtung (Farbverstärkungen, Weißabgleich-Zustand und -Modus, Modus der Farbkorrektur, Rauschunterdrückung, Kanten, Tonwertkurve, Linsenschattierung, Belichtungszeit, Empfindlichkeit, AE-Zustand, Bilddauer) sowie den gemeldeten Zustand von Fokus und Bildstabilisierung (AF-Modus, Fokusdistanz, OIS-Modus, Linsenzustand). Die Diagnose-Schalter wirken nur auf die Morgenmessung im Entwicklermodus und nur, soweit die Kamera sie anbietet; die gesetzten Schalter werden mit der Messung gespeichert. Auswertung und Zählen bleiben unverändert; eine solche Messung trägt intern das Merkmal „mit Diagnose-Einstellung gemessen“, das Anzeige und Rechnung nicht ändert (Entscheidung des Maintainers 2026-11-21).
- [ ] Im Entwicklermodus zeigen die Entwicklereinstellungen die gezählten Fehler (FR-0223).

### FR-0220 — Kamera für die Kamera-Messung
- **Status:** Approved | **Phase:** 3
- **Quelle:** SRC-003 (Maintainer 2026-11-18, 2026-11-20, 2026-11-22)
- **Verwandt:** FR-0214, FR-0215, FR-0217, ADR-0011, PAR-219, PAR-227, PAR-228

Die Kamera-Messung (FR-0214, FR-0215) nutzt eine Rückkamera mit Blitz. Hat das Handy mehrere Rückkameras (auch als einzelne Objektive einer Mehrfachkamera), gilt: Im Entwicklermodus (FR-0217) lässt sich in den Entwicklereinstellungen eine Kamera wählen; sie gilt für Ruhepuls- und Morgenmessung. Sonst gilt das Ergebnis der Kamerasuche, wenn eine stattgefunden hat, sonst die Standardkamera (die erste Rückkamera mit Blitz). Ohne Entwicklermodus gilt die Wahl von Hand nicht, bleibt aber gespeichert. Ist die gewählte Kamera nicht mehr vorhanden oder nicht nutzbar, gilt die nächste Stufe; startet die Kamera nicht, endet die Messung mit Grund wie bisher, ohne Wechsel der Kamera. Wahl und Suchergebnis sind Einstellungen des Geräts: nicht im Archiv, „Alles löschen“ setzt sie zurück. Bei gespeichertem Rohsignal (Entwicklermodus) trägt die Messung die verwendete Kamera (Kamera-ID, physische Kamera, Brennweite); sie steht im Archiv und in der Messpaare-CSV.

**Umsetzung:** Die Karte „Kamera für die Pulsmessung“ auf der Seite „Entwicklereinstellungen“ zeigt „Standard“ (löscht die Wahl von Hand) und jede Rückkamera als „Kamera <Kennung>“ bzw. „Kamera <Kennung>/<physische Kennung>“ mit Brennweite und der Bildrate, mit der die Messung auf ihr liefe (höchste feste Bildrate 30–60 Bilder/s, 60 vor 30, ADR-0011); die Standardkamera ist als „Standard“ markiert. Nicht nutzbare Kameras (ohne Blitz, ohne feste Bildrate) sind sichtbar, aber nicht wählbar, mit Grund. Ist die gespeicherte Wahl nicht mehr in der Liste, steht dort ein Hinweis, dass die Standardkamera gilt; ohne Rückkamera „Keine Rückkamera“. Die Liste braucht kein Kamera-Recht. Kennungen, Brennweiten, Bildraten und die Liste stehen in keinem Log. Technik der Kamerawahl: ADR-0011, Nachtrag 2026-11-18.

**Kamerasuche:** Die Kamerasuche zeigt Live-Bilder aller nutzbaren Rückkameras bei eingeschaltetem Blitz (gleichzeitig, wo das Gerät es kann, sonst im Wechsel, PAR-227) mit ihrer Bildrate und empfiehlt eine Kamera nach PAR-228 (60 Bilder/s bevorzugt); der Nutzer übernimmt die Empfehlung oder tippt eine andere an. Vorschaubilder werden nur angezeigt, nie gespeichert, übertragen oder protokolliert. Im Entwicklermodus ist sie in den Entwicklereinstellungen aufrufbar („Kamera suchen“ in der Karte „Kamera für die Pulsmessung“) und zeigt die Zahlen je Kamera.

**Umsetzung der Kamerasuche:** Die Seite „Kamera finden“ zeigt oben „Lege den Finger über Blitz und Kamera, wie bei der Messung.“, im Wechselbetrieb zusätzlich „Kameras werden nacheinander gezeigt“. Darunter in zwei Spalten je nutzbarer Kamera das Vorschaubild mit der Bezeichnung wie in der Liste, im Entwicklermodus der Bildrate („60 Bilder/s“), einem Balken „Licht“ (Lichtmenge relativ zur hellsten Kamera), einem Haken „Finger erkannt“ und bei der Empfehlung „Empfohlen“; im Entwicklermodus zusätzlich je Bild R/G, Belichtungszeit, ISO und Lichtmenge. Liefert eine Kamera keine Vorschau, steht ihr Grund im Bild. Ein Tipp auf ein Bild wählt die Kamera (hervorgehoben). „Übernehmen“ speichert die gewählte Kamera, ohne Tipp die Empfehlung, als Ergebnis der Kamerasuche; ohne Empfehlung und ohne Tipp ist „Übernehmen“ gesperrt. In den Entwicklereinstellungen setzt „Als feste Wahl setzen“ dieselbe Kamera als Wahl von Hand. Zurück speichert nichts. Zurück, Übernehmen und die App im Hintergrund beenden die Vorschau und schalten die Taschenlampe aus; nach der Rückkehr in den Vordergrund läuft sie neu an. Gibt es nur eine nutzbare Kamera, zeigt die Seite „Nur eine Kamera, keine Auswahl nötig“ ohne Vorschau. Gibt es keine nutzbare Kamera, zeigt sie „Keine nutzbare Rückkamera mit Blitz gefunden.“; lässt sich die Kameraliste nicht lesen, „Die Kameras ließen sich nicht abfragen. Versuche es später erneut.“; beides ohne Vorschau und ohne Speichern. Ohne Kamera-Recht steht dort ein Hinweis, ohne Vorschau. Technik: ADR-0011, Nachtrag 2026-11-24.

**Kamerasuche vor der ersten Messung (Entscheidung des Maintainers 2026-11-18):** Hat das Handy mehr als eine nutzbare Rückkamera und gibt es kein gültiges Suchergebnis, erscheint vor der ersten Kamera-Messung (Ruhepuls oder Morgenmessung) die Kamerasuche, nach dem Kamera-Recht und vor der Ruhephase. „Weiter“ übernimmt die angetippte oder empfohlene Kamera; ohne Empfehlung wählt der Nutzer die Standardkamera; Zurück startet keine Messung. In den Einstellungen (Abschnitt „Kamera-Messung“) lässt sie sich jederzeit öffnen. Ohne Entwicklermodus zeigt sie keine Zahlen je Kamera.

**Umsetzung vor der Messung:** Ein gültiges Suchergebnis ist eine Kamera, die in der Kameraliste steht und nutzbar ist; im Entwicklermodus mit gültiger Wahl von Hand entfällt die Seite. Lässt sich die Kameraliste oder die Einstellung nicht lesen, entfällt die Seite und die Messung beginnt wie bisher. Die Seite erscheint nach dem Tipp auf den Start (Ruhephase oder sofort messen bzw. Start der Morgenmessung) und fragt das Kamera-Recht selbst an; die Ruhephase (bei der Morgenmessung 2 min) beginnt erst nach der Seite, deren Zeit zählt nicht dazu. Für alle Nutzer zeigt die Seite oben „Dein Handy hat mehrere Kameras. Lege den Finger über Blitz und Kamera – die beleuchtete Kamera ist markiert.“; Bildrate und Zahlen je Kamera nur im Entwicklermodus, „Als feste Wahl setzen“ nur in den Entwicklereinstellungen. Vor der Messung heißt der Knopf „Weiter“ (speichert das Suchergebnis und startet die Messung mit dieser Kamera), in den Einstellungen „Übernehmen“. Ohne Empfehlung und ohne Tipp steht dort „Standardkamera verwenden“: setzt das Suchergebnis auf die Standardkamera (danach erscheint die Seite nicht mehr von selbst) und geht weiter; endet die Vorschau mit Fehler, wird er ebenfalls angeboten, sofern die Standardkamera nutzbar ist. Zurück speichert nichts und startet keine Messung; beim nächsten Start erscheint die Seite wieder. Im Hintergrund endet die Vorschau (Taschenlampe aus), nichts wird gespeichert und keine Messung beginnt; zurück im Vordergrund läuft die Seite wieder an. Der Abschnitt „Kamera-Messung“ der Einstellungen erscheint nur bei mehr als einer nutzbaren Kamera, zeigt die geltende Kamera („Standardkamera“ bzw. „Kamera <Kennung>“ / „Kamera <Kennung>/<physische Kennung>“, je mit Brennweite) und „Kamera suchen“; die Suche dort startet keine Messung, danach zeigt der Abschnitt die neue Kamera.

**Akzeptanzkriterien:**
- [ ] Die Kameraliste nennt jede Rückkamera und bei einer logischen Mehrfachkamera ihre physischen Kameras, sortiert (Standardkamera zuerst), mit „nutzbar“ nach Blitz und fester Bildrate; ohne Rückkamera ist sie leer.
- [ ] Der Start mit einer angegebenen Kamera öffnet genau diese und meldet sie; ohne Angabe die Standardkamera wie bisher; eine unbekannte oder unbrauchbare Kamera endet mit Grund, ohne andere Kamera und ohne Absturz.
- [ ] Welche Kamera gilt: Entwicklermodus an mit gültiger Wahl von Hand → diese; Entwicklermodus aus mit gespeicherter Wahl → Ergebnis der Suche bzw. Standard; Wahl von Hand nicht mehr vorhanden oder nicht nutzbar → Suche bzw. Standard; Ergebnis der Suche vorhanden → dieses; nichts gespeichert → Standard.
- [ ] Ruhepuls- und Morgenmessung starten die geltende Kamera; nach Ausschalten des Entwicklermodus wieder die Standardkamera.
- [ ] Seite „Entwicklereinstellungen“ im Entwicklermodus: Liste der Kameras, nicht wählbare mit Grund, die Wahl bleibt nach Neustart der App, „Standard“ löscht sie, Hinweis bei verschwundener Kamera; ohne Entwicklermodus keine Karte.
- [ ] Die Liste nennt je nutzbarer Kamera die Bildrate, mit der die Messung auf ihr liefe.
- [ ] Wahl und Suchergebnis kommen nicht ins Archiv und werden von „Alles löschen“ zurückgesetzt.
- [ ] Ohne Entwicklermodus und ohne Suchergebnis misst die Messung mit der Standardkamera wie vor dieser Anforderung; bei mehr als einer nutzbaren Kamera erscheint davor die Kamerasuche (siehe unten).
- [ ] Kamerasuche: Empfehlung nach PAR-228 (Finger nach PAR-219, 60 Bilder/s vor 30, größte Lichtmenge, unter 10 % Abstand die frühere, ohne Finger keine); im Wechsel erst nach einem vollen Durchgang (PAR-227).
- [ ] Kamerasuche: je Kamera Bild, Bildrate, Licht, „Finger erkannt“ und „Empfohlen“; Tipp überstimmt die Empfehlung; „Übernehmen“ setzt das Suchergebnis, „Als feste Wahl setzen“ die Wahl von Hand; danach startet die Messung diese Kamera.
- [ ] Kamerasuche: Zurück und Hintergrund beenden die Vorschau und schalten die Taschenlampe aus, Zurück speichert nichts; nur eine nutzbare Kamera → Hinweis ohne Vorschau; keine nutzbare Kamera bzw. Liste nicht lesbar → eigener Hinweis ohne Vorschau.
- [ ] Vor der ersten Ruhepuls- oder Morgenmessung erscheint die Kamerasuche nur bei mehr als einer nutzbaren Kamera, ohne gültiges Suchergebnis und (im Entwicklermodus) ohne gültige Wahl von Hand, auch wieder bei einem Suchergebnis auf eine verschwundene Kamera; „Weiter“ startet die Messung mit der übernommenen Kamera, die nächste Messung ohne Seite; bei der Morgenmessung liegt sie vor der Ruhephase, die danach die volle Dauer hat.
- [ ] Ohne Empfehlung setzt „Standardkamera verwenden“ die Standardkamera als Suchergebnis und startet die Messung; Zurück bzw. Hintergrund: keine Messung, nichts gespeichert, Taschenlampe aus, beim nächsten Start wieder die Seite.
- [ ] Einstellungen: Abschnitt „Kamera-Messung“ nur bei mehr als einer nutzbaren Kamera, mit der geltenden Kamera; „Kamera suchen“ ändert sie ohne Messung. Ohne Entwicklermodus zeigt die Kamerasuche keine Zahlen und keine Bildrate je Kamera.
- [ ] Vorschaubilder gehen nicht als Pixel nach Dart und werden nie gespeichert, übertragen oder protokolliert; die Zahlen je Bild stehen in keinem Log.

## Randfälle und Fehlerverhalten
- Weder Alter noch maximale Herzfrequenz bekannt: Abhängige Funktionen sind nicht verfügbar, die App bittet um die Eingabe (OQ-0012).

## Offene Fragen
<!-- BEGIN OQ -->
- OQ-0010
- OQ-0012
- OQ-0013
- OQ-0031
- OQ-0038
- OQ-0065
- OQ-0078
<!-- END OQ -->

## Quellen
- SRC-001: §2, Z. 31–59
