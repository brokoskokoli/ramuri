# Offene Fragen, Konflikte und Blocker

`blocking` heißt: Der betroffene Bereich kann erst nach einer Entscheidung umgesetzt werden. Die Phase steht bei der Auswirkung. Optionen sind Vorschläge des Migrationsagenten und keine Beschlüsse. Die Zeile „Betroffene Anforderungen“ wird generiert.

OQ-0001 bis OQ-0010 entsprechen den zehn offenen Punkten aus SRC-001 §26. Alle weiteren Fragen hat die Migration aufgedeckt.

## Widersprüche in der Quelle

Hier stehen die Aussagen im Wortlaut, weil keine Seite stillschweigend bevorzugt werden darf: OQ-0001, OQ-0002, OQ-0007, OQ-0010, OQ-0011, OQ-0012, OQ-0013, OQ-0034, OQ-0038 und OQ-0039.

## Aus SRC-001 §26 übernommen

Die Quelle sagt: „Vor der technischen Spezifikation sollten insbesondere folgende Punkte fachlich entschieden werden“ (Z. 1414). Das gilt für alle zehn Punkte. Die Einstufung `non-blocking` bei OQ-0003, OQ-0008 und OQ-0009 bezieht sich nur auf den Umsetzungsstart von Phase 1 und ist eine Einschätzung der Migration.

### OQ-0001 — Welches VO2max-Modell gilt für die erste Version?
- **Frage:** Reicht der transparente ACSM-/Herzfrequenzreserve-Schätzer als erste Version, oder soll von Anfang an ein auf Leistungsdaten kalibriertes Modell vorgesehen werden?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 1 (Z. 1416). Konflikt: §8.3 „Als einfaches Anfangsmodell wird angenommen …“ (Z. 369) und §8.4 „Für die erste, auf der ACSM-Laufformel basierende Implementierung …“ (Z. 427) gegenüber der in §26 als offen benannten Frage.
- **Betroffene Anforderungen:** FR-0069, FR-0071, FR-0074, FR-0082
- **Auswirkung:** blocking — Phase 1, VO₂max-Schätzung.
- **Optionen (Vorschläge):** ACSM-Schätzer zuerst und Kalibrierung später, oder Kalibrierung von Beginn an.
- **Status:** Resolved
- **Entscheidung:** ACSM-/Herzfrequenzreserve-Schätzer für die erste Version; Kalibrierung auf Leistungsdaten bleibt für Phase 4 vorgesehen. 2026-11-03, SRC-003. Ziel: FR-0069, FR-0071, DEC-0008.

### OQ-0002 — Welches Belastungsmodell ist Standard?
- **Frage:** Edwards-TRIMP als Standard oder ein kontinuierliches Modell wie Banister-TRIMP?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 2 (Z. 1417). Konflikt: §10.1 „Als erste Variante wird der Edwards-TRIMP verwendet.“ (Z. 546).
- **Betroffene Anforderungen:** FR-0092
- **Auswirkung:** blocking — Phase 1, TRIMP.
- **Optionen (Vorschläge):** Edwards als erste Variante bestätigen und Banister offenhalten, oder sofort Banister.
- **Status:** Resolved
- **Entscheidung:** Edwards-TRIMP für die erste Version; ein späterer Wechsel, etwa auf Banister, bleibt möglich. 2026-11-03, SRC-003. Ziel: FR-0092, DEC-0007. Ergänzung 2026-11-03: Algorithmen werden austauschbar, Edwards ist die Startvariante (NFR-0005, OQ-0043).

### OQ-0003 — Herzfrequenzzonen allein oder Schwellenmodell?
- **Frage:** Werden Herzfrequenzzonen allein genutzt, oder wird möglichst früh ein individuelles Schwellenmodell ergänzt?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 3 (Z. 1418); §7.2 (Z. 319); §16.3 (Z. 1023).
- **Betroffene Anforderungen:** FR-0062, FR-0065, FR-0144, FR-0153
- **Auswirkung:** non-blocking für Phase 1, weil die Reservezonen als vorläufiges Modell beschrieben sind; vor Phase 2 zu klären.
- **Status:** Resolved
- **Entscheidung:** Bis Phase 3 gelten die konfigurierbaren Reservezonen. Individuelle Tests und Schwellen kommen mit den kalibrierten Modellen in Phase 4. Ziel: FR-0062, FR-0065, DEC-0046. 2026-11-03, SRC-003.

### OQ-0004 — Welche Ziele und Trainingsarten zuerst?
- **Frage:** Welche konkreten Trainingsziele und Trainingsarten sollen zunächst abgedeckt werden?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 4 (Z. 1419); §14.1; §15.3.
- **Betroffene Anforderungen:** FR-0135, FR-0142
- **Auswirkung:** blocking — Phase 2, Umfang der Planung.
- **Status:** Resolved
- **Entscheidung:** Phase 2 deckt alle drei Zieltypen für 5 km, 10 km und Halbmarathon sowie offene Fitnessziele ab, mit allen Trainingsarten aus §15.3. Marathonpläne folgen später. Ziel: FR-0135, FR-0142, DEC-0034. 2026-11-03, SRC-003.

### OQ-0005 — Welche Parameter darf das Modell automatisch ändern?
- **Frage:** Welche Trainingsparameter darf das Modell automatisch verändern?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 5 (Z. 1420). Zusammenhang mit OQ-0011. Durch die Entscheidung zu OQ-0011 eingegrenzt: Inhalt und Intensität künftiger Einheiten ja, Termine nur nach Bestätigung, das Ziel nur mit Zustimmung. Offen sind die Grenzen dieser Anpassung.
- **Betroffene Anforderungen:** FR-0156, FR-0158, FR-0176
- **Auswirkung:** blocking — Phase 2, Plananpassung.
- **Status:** Resolved
- **Entscheidung:** Die App ändert Art, Dauer, Distanz und Zielintensität künftiger Einheiten sowie den Wochenumfang nach den Planungsregeln. Sie überschreitet nie die Trainingstage und die maximale Zeit pro Einheit des Nutzers. Größere Änderungen begründet sie. Ziel: FR-0156, FR-0158, DEC-0035. 2026-11-03, SRC-003.

### OQ-0006 — Mindestdatenqualität für einen numerischen Readiness-Wert
- **Frage:** Welche Mindestdatenqualität wird für einen numerischen Readiness-Wert vorausgesetzt?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 6 (Z. 1421); §11.2 (Z. 683, 697); §11.3 (Z. 703, 713).
- **Betroffene Anforderungen:** FR-0109, FR-0112, FR-0114, FR-0215
- **Auswirkung:** blocking — Phase 3, erweiterte Readiness.
- **Status:** Resolved
- **Entscheidung:** Eine Zahl erscheint nur mit aktueller HRV und Schlaf sowie einer persönlichen Referenz aus mindestens 14 gültigen Messungen in 28 Tagen; sonst eine eingeschränkte Einschätzung ohne Zahl. Die Mengen sind vorläufige Heuristiken. Ziel: FR-0109, FR-0112, DEC-0042. 2026-11-03, SRC-003.

### OQ-0007 — Energiereserve nur mit kontinuierlichen Wearable-Daten?
- **Frage:** Soll die Energiereserve ausschließlich mit kontinuierlicher Wearable-Datenerfassung angeboten werden?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 7 (Z. 1422). Konflikt: §12.1 „Kontinuierliche oder ausreichend häufige Herzfrequenzmessungen“ (Z. 747) gegenüber §22 „Kontinuierliche Tages- und Schlafdaten“ (Z. 1256) und §25 Nr. 12 „ohne geeignete kontinuierliche Daten“ (Z. 1407). §12.1 lässt zudem Deaktivieren oder Kennzeichnen zu (Z. 753).
- **Betroffene Anforderungen:** FR-0119, FR-0120, FR-0121
- **Auswirkung:** blocking — Phase 3, Energiereserve.
- **Status:** Resolved
- **Entscheidung:** Die Energiereserve gibt es nur mit kontinuierlichen Tages- und Schlafdaten; sonst ist sie deaktiviert und erklärt warum. Ziel: FR-0119, FR-0120, FR-0121, DEC-0044. 2026-11-03, SRC-003.

### OQ-0008 — Reicht die Riegel-Methode?
- **Frage:** Reicht zunächst die Riegel-Methode, oder sollen mehrere Prognoseverfahren angeboten werden?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 8 (Z. 1423); §13.1.
- **Betroffene Anforderungen:** FR-0130
- **Auswirkung:** non-blocking, weil Riegel beschrieben ist; weitere Verfahren wären eine Ergänzung.
- **Status:** Resolved
- **Entscheidung:** Phase 2 nutzt nur das Riegel-Modell. Weitere Verfahren kommen mit den erweiterten Prognosen in Phase 4. Ziel: FR-0130, DEC-0046. 2026-11-03, SRC-003.

### OQ-0009 — Rolle der Smartwatch
- **Frage:** Soll die Uhr nur als Pulssensor dienen oder später auch Einheiten selbstständig aufzeichnen und steuern können? Wann kommen ergänzende Uhrenanwendung und Herstelleranbindungen?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 9 (Z. 1424); §3.1 (Z. 78, 80); §24 Phase 4 (Z. 1390).
- **Betroffene Anforderungen:** FR-0007, FR-0009, FR-0010
- **Auswirkung:** non-blocking für Phase 1, weil dort nur kompatible Bluetooth-Pulssensoren genannt sind.
- **Status:** Resolved
- **Entscheidung:** Bis Phase 3 dient die Uhr nur als Pulsquelle über den Bluetooth-Standard. Eine eigene Uhr-App bleibt eine mögliche Erweiterung in Phase 4. Ziel: FR-0007, FR-0009, DEC-0046. 2026-11-03, SRC-003.

### OQ-0010 — Welche Eingaben sind beim Einstieg nötig?
- **Frage:** Welche Werte muss der Nutzer beim Einstieg angeben, und welche können später automatisch gelernt werden? Darf die Profileinrichtung übersprungen werden? Dürfen die Felder „Für Trainingspläne“ fehlen?
- **Auslöser/Quellen:** SRC-001 §26 Nr. 10 (Z. 1425); §2 (Z. 33). Konflikt: §2.1 kennzeichnet Felder als erforderlich „Für Trainingspläne“ (Z. 44–46), §15.1 sagt: „Wenn keine ausreichenden Daten vorliegen, wird ein konservativer Einstiegsplan erstellt.“ (Z. 921).
- **Betroffene Anforderungen:** FR-0001, FR-0002, FR-0140
- **Auswirkung:** blocking — Phase 1, Ersteinrichtung.
- **Status:** Resolved
- **Entscheidung:** Keine Pflichteingaben zum Laufen; die Einrichtung ist überspringbar. Beim Erstellen eines Plans fragt die App fehlende Angaben ab, Pflicht sind dort nur die Trainingstage; sonst entsteht ein konservativer Einstiegsplan. Ob Werte automatisch gelernt werden, ist damit nicht festgelegt. 2026-11-03, SRC-003. Ziel: FR-0001, FR-0002, DEC-0018.

## Durch die Migration aufgedeckt

### OQ-0011 — Automatische Plananpassung oder Bestätigung?
- **Frage:** Welche Planänderungen darf die App selbst vornehmen, und welche brauchen eine Bestätigung?
- **Auslöser/Quellen:** Konflikt in SRC-001. Automatisch: §17.2 „Daraufhin werden zukünftige Trainingseinheiten angepasst.“ (Z. 1084); §19 „Das intensive Training wurde um einen Tag verschoben …“ (Z. 1179); §24 „Automatische Plananpassungen“ (Z. 1364). Bestätigung: §17.4 Nr. 6 „Der Nutzer behält die Kontrolle über die Trainingstermine.“ (Z. 1125); §18.1 „Der Nutzer bestätigt Änderungen, bevor bestehende Kalendereinträge verändert werden.“ (Z. 1150).
- **Betroffene Anforderungen:** FR-0156, FR-0158, FR-0162, FR-0169, FR-0173, FR-0176, FR-0180
- **Auswirkung:** blocking — Phase 2, Kern der Plananpassung.
- **Optionen (Vorschläge):** (a) Alle Terminänderungen brauchen eine Bestätigung; Inhalte künftiger Einheiten passt die App selbst an. (b) Alles braucht eine Bestätigung. (c) Vom Nutzer wählbar.
- **Status:** Resolved
- **Entscheidung:** Inhalt und Intensität künftiger Einheiten passt die App selbst an und begründet größere Änderungen. Termine ändert sie nur nach Bestätigung. 2026-11-03, SRC-003. Ziel: FR-0156, FR-0176, DEC-0016.

### OQ-0012 — Was gilt, wenn Ruhepuls oder HFmax fehlen?
- **Frage:** Wie verhalten sich Zonen, TRIMP und VO₂max, wenn HFmax oder Ruhepuls fehlen? Gibt es einen Ersatz für den Ruhepuls? Dürfen geschätzte Werte in die VO₂max einfließen?
- **Auslöser/Quellen:** Konflikt in SRC-001. §22 „GPS + Herzfrequenz | Herzfrequenzzonen, TRIMP, erste VO₂max-Schätzungen, aerobe Effizienz“ (Z. 1253) gegenüber §2.1, wo Alter, Ruhepuls und HFmax optional sind (Z. 39, 42, 43), und §8.1, wo maximale Herzfrequenz und Ruheherzfrequenz benötigt werden (Z. 335–336). §4.1 nennt die Zone zudem unter den Mindestanzeigen (Z. 139). Für HFmax gibt es eine Näherung (Z. 54), für den Ruhepuls keine.
- **Betroffene Anforderungen:** FR-0004, FR-0026, FR-0055, FR-0060, FR-0068
- **Auswirkung:** blocking — Phase 1.
- **Optionen (Vorschläge):** Funktionen ohne Basiswerte als „nicht verfügbar“ kennzeichnen und zur Eingabe auffordern.
- **Status:** Resolved
- **Entscheidung:** Fehlt ein nötiger Wert, ist die Funktion nicht verfügbar und die App bittet um die Eingabe. Die HFmax-Altersnäherung ist erlaubt und als Schätzung markiert. TRIMP braucht nur HFmax; Reservezonen und VO₂max brauchen zusätzlich den Ruhepuls. 2026-11-03, SRC-003. Ziel: FR-0026, FR-0055, FR-0060, FR-0068, DEC-0017.

### OQ-0013 — Was bedeutet „Laufleistung“?
- **Frage:** Welche Bedeutung hat „Laufleistung“ an den einzelnen Stellen, und welche Einheit gilt für das Profilfeld?
- **Auslöser/Quellen:** SRC-001 verwendet den Begriff unterschiedlich: §2.1 „Aktuelle Laufleistung“ zur Einschätzung des Trainingsniveaus (Z. 45); §3.3 als Sensordatum neben der Kadenz (Z. 106), vermutlich Running Power; §13.1 „maximalen Laufleistung“ als erbrachte Leistung (Z. 824); §15.1 „Aktuelle Laufleistung“ neben dem separat genannten „Wöchentlichen Laufumfang“ (Z. 914, 916).
- **Betroffene Anforderungen:** FR-0002, FR-0021, FR-0136, FR-0139
- **Auswirkung:** blocking — Phase 2, Profil und Ausgangsanalyse; für Phase 1 ohne Folgen, solange das Feld nicht ausgewertet wird.
- **Status:** Resolved
- **Entscheidung:** Das Profilfeld heißt „Aktuelles Leistungsniveau“ und enthält eine aktuelle Zeit über eine Distanz oder eine Selbsteinschätzung. Der Wochenumfang ist ein eigenes Feld. Bei Sensoren heißt der Wert „Laufleistung (Watt)“, bei Prognosen „Referenzleistung“. Ziel: FR-0002, FR-0021, FR-0130, FR-0139, DEC-0037. 2026-11-03, SRC-003.

### OQ-0014 — Zuordnung an Zonengrenzen und außerhalb der Zonen
- **Frage:** In welche Zone fällt ein exakter Grenzwert wie 60 %? Wie zählen Werte über 100 % und beim TRIMP Werte unter 50 % HFmax?
- **Auslöser/Quellen:** SRC-001 §7.2 und §10.1: Die Bereiche überlappen an den Grenzen (Z. 309–313, 554–558). Für die Zeit unter 50 % HFmax nennt §10.1 kein Gewicht.
- **Betroffene Anforderungen:** FR-0062, FR-0092
- **Auswirkung:** blocking — Phase 1, sonst ist der TRIMP nicht eindeutig.
- **Optionen (Vorschläge):** Untergrenze inklusive, Obergrenze exklusive; unter 50 % Gewicht 0; über 100 % zur Zone 5 und zugleich als Plausibilitätshinweis.
- **Status:** Resolved
- **Entscheidung:** Untergrenze inklusive, Obergrenze exklusive. Unter 50 % HFmax hat beim TRIMP das Gewicht 0. Werte über 100 % zählen zur Zone 5 und gelten zugleich als Hinweis auf eine zu niedrige HFmax oder einen Messfehler. 2026-11-03, SRC-003. Ziel: FR-0062, FR-0092, DEC-0019.

### OQ-0015 — Welche einheitliche Skala speist ATL und CTL?
- **Frage:** Welche Skala gilt für L[t], wie werden Tage mit gemischten Quellen behandelt, und wie wird kalibriert? Welche Dauer zählt für sRPE und TRIMP: Bewegungszeit oder Gesamtzeit?
- **Auslöser/Quellen:** SRC-001 §10.2 (Z. 598–602); §10.3 „auf einer einheitlichen Skala“ (Z. 612); §25 Nr. 7 (Z. 1402). Die Skala und das Kalibrierverfahren sind nicht benannt.
- **Betroffene Anforderungen:** FR-0095, FR-0096, FR-0097, FR-0098, FR-0099
- **Auswirkung:** blocking — Phase 2, ATL/CTL.
- **Status:** Resolved
- **Entscheidung:** Der TRIMP des gewählten Modells ist die Hauptskala. Läufe ohne Puls werden über einen persönlichen Faktor aus Läufen mit beiden Werten umgerechnet und gekennzeichnet; bis genug solche Läufe vorliegen, gelten sie als nicht bewertet. Für TRIMP und sRPE zählt die Bewegungszeit. Die Mindestanzahl klärt OQ-0046. Ziel: FR-0095, FR-0097, DEC-0030. 2026-11-03, SRC-003.

### OQ-0016 — Startwerte von ATL/CTL und Vollständigkeit der Historie
- **Frage:** Mit welchen Startwerten beginnen ATL und CTL? Woran erkennt die App, dass die Historie „ausreichend vollständig“ ist? Wie werden Tage mit nicht bewertbarer Belastung gerechnet?
- **Auslöser/Quellen:** SRC-001 §10.6 (Z. 642–646). Die Formeln in §10.3 und §10.4 setzen einen Vorwert voraus.
- **Betroffene Anforderungen:** FR-0098, FR-0099, FR-0102, FR-0103, FR-0104
- **Auswirkung:** blocking — Phase 2, ATL/CTL.
- **Status:** Resolved
- **Entscheidung:** ATL und CTL starten rechnerisch bei 0 und sind in den ersten Wochen als vorläufig markiert, ohne Aussage zur Fitness. Der Nutzer gibt an, ob er alle Trainings erfasst; nur dann gelten leere Tage als trainingsfrei. Unbewertete Einheiten zählen nie als 0. Die Dauer der vorläufigen Phase klärt OQ-0046. Ziel: FR-0098, FR-0099, FR-0102, FR-0103, DEC-0032. 2026-11-03, SRC-003.

### OQ-0017 — Verbindlichkeit der Phasen und fehlende Zuordnungen
- **Frage:** Ist die Phaseneinteilung verbindlich oder nur eine Empfehlung? In welche Phase gehören die Anforderungen ohne Zuordnung, besonders Datenschutz und Löschung?
- **Auslöser/Quellen:** SRC-001 §24 ist mit „Empfohlener Funktionsumfang“ überschrieben (Z. 1330). §25 spricht von „jeweiligen Entwicklungsphasen“, ordnet die Kriterien aber nicht zu (Z. 1394). Nicht in §24 genannt sind unter anderem §3.3, §4.3 (subjektive Angaben), §11.1, §20.3 und §21.
- **Betroffene Anforderungen:** FR-0009, FR-0010, FR-0065, FR-0082, SEC-0001, SEC-0002, SEC-0003, SEC-0004, SEC-0005, SEC-0006, SEC-0007, SEC-0008
- **Auswirkung:** blocking — Zuschnitt von Phase 1.
- **Optionen (Vorschläge):** Datenschutz, Löschung und Gesamtexport in die erste Phase legen, in der personenbezogene Daten gespeichert werden.
- **Status:** Resolved
- **Entscheidung:** Die Phasen sind verbindlich. Datenschutz (SEC-0001 bis SEC-0008), Löschung und Gesamtexport gehören in Phase 1. Die übrigen Zuordnungen klärt OQ-0041. 2026-11-03, SRC-003. Ziel: DEC-0012.

### OQ-0018 — Regel für die Priorisierung von Herzfrequenzquellen
- **Frage:** Nach welcher Regel wird bei mehreren aktiven Quellen priorisiert, und wie wird beim Quellwechsel und Rückfall verfahren?
- **Auslöser/Quellen:** SRC-001 §3.2 verlangt „eine eindeutige Priorisierung“ (Z. 95), nennt aber keine Regel. Das bevorzugte Gerät (Z. 89) ist naheliegend, aber nicht als Regel festgelegt.
- **Betroffene Anforderungen:** FR-0018, FR-0019
- **Auswirkung:** blocking — Phase 1, sobald mehrere Quellen gleichzeitig aktiv sein können.
- **Optionen (Vorschläge):** Das bevorzugte Gerät hat Vorrang; ein Wechsel erfolgt nur manuell oder nach einem Abbruch.
- **Status:** Resolved
- **Entscheidung:** Das bevorzugte Gerät hat Vorrang. Ein Wechsel erfolgt manuell oder nach einem Verbindungsabbruch, mit gespeicherter Herkunft je Zeitabschnitt. 2026-11-03, SRC-003. Ziel: FR-0018, FR-0019, DEC-0020.

### OQ-0019 — Startwerte der Modellparameter und Qualitätsregeln
- **Frage:** Welche Startwerte gelten für Plausibilität, Glättungsfenster, Abschnittsauswahl, Mindestdauer und α? Nach welchen Regeln werden die Qualitätsstufen vergeben? Wie verhält sich „Konfidenz“ zu den Qualitätsstufen?
- **Auslöser/Quellen:** SRC-001 §6.1 (Z. 226–237); §6.2 (Z. 255); §6.3 (Z. 269–271); §8.4 (Z. 417–429); §8.5 (Z. 445); §8.6 (Z. 459).
- **Betroffene Anforderungen:** FR-0047, FR-0048, FR-0051, FR-0053, FR-0060, FR-0073, FR-0075, FR-0077, FR-0079, FR-0090
- **Auswirkung:** blocking — Phase 1, Fitnessberechnungen.
- **Status:** Resolved
- **Entscheidung:** Startwerte aus dem Research-Auftrag sind als Version 1 freigegeben, mit diesen Festlegungen: VO₂max ab 7:28 min/km voll, bis 8:20 min/km vorläufig, langsamer kein Wert. Ohne Höhendaten wird wie auf ebener Strecke gerechnet, höchstens vorläufig. Bei HFmax ≤ HFRuhe ist auch der TRIMP nicht verfügbar. Die Konfidenz geht in den Qualitätsstufen auf. Die Werte sind vorläufig und nicht an eigenen Läufen validiert (OQ-0020). 2026-11-03, SRC-003. Ziel: [model-parameters.md](../model-parameters.md), DEC-0029.

### OQ-0020 — Wie und wann werden Modelle validiert?
- **Frage:** Mit welchen Referenzdaten, welchem Verfahren und welchem Zielwert werden die Modelle validiert? Ist die Validierung Teil der Abnahme einer Phase?
- **Auslöser/Quellen:** SRC-001 §8.3 (Z. 409); §11.2 (Z. 695); §12.4 (Z. 791); §23.1 (Z. 1307).
- **Betroffene Anforderungen:** FR-0072, FR-0075, FR-0110, NFR-0004
- **Auswirkung:** non-blocking für die Umsetzung, weil ohne Validierung nur keine Genauigkeit versprochen werden darf.
- **Status:** Resolved
- **Entscheidung:** Die Validierung erfolgt im Feldtest mit echten Läufen nach dem Validierungsbedarf in [model-parameters.md](../model-parameters.md); Parameter werden nachjustiert. Sie ist kein Release-Gate. Ohne Nachweis gibt die App keine Genauigkeit an. Ziel: NFR-0004, DEC-0048. 2026-11-03, SRC-003.

### OQ-0021 — Verhalten bei GPS-Problemen und Abbrüchen der Aufzeichnung
- **Frage:** Was passiert bei fehlender Standortberechtigung, Lauf ohne GPS (zum Beispiel Laufband), GPS-Verlust, App-Absturz, Neustart oder leerem Akku? Wird ein Lauf ohne GPS überhaupt unterstützt?
- **Auslöser/Quellen:** SRC-001 regelt nur den ausgeschalteten Bildschirm (Z. 164) und den Sensorabbruch (Z. 1398). §6.1 nennt Messunterbrechungen als zu berücksichtigen (Z. 234).
- **Betroffene Anforderungen:** FR-0034, FR-0035, FR-0193, FR-0194, FR-0195
- **Auswirkung:** blocking — Phase 1, zuverlässige Aufzeichnung.
- **Optionen (Vorschläge):** Bereits aufgezeichnete Daten laufend sichern und nach einem Abbruch die Wiederaufnahme anbieten.
- **Status:** Resolved
- **Entscheidung:** Die App sichert laufend und bietet nach einem Abbruch die Wiederaufnahme an. Bei GPS-Verlust laufen Zeit und Puls weiter, die Lücke wird markiert und die Strecke nicht geschätzt. Ohne Standortberechtigung startet kein Lauf. Läufe ohne GPS gibt es in Phase 1 nicht. 2026-11-03, SRC-003. Ziel: FR-0193, FR-0194, FR-0195, DEC-0021.

### OQ-0022 — Wie gelangen Trainings außerhalb der App in die Daten?
- **Frage:** Gibt es eine manuelle Erfassung? Wie erfährt die App von einem „zusätzlichen Training“, das nicht mit ihr aufgezeichnet wurde? Wie zählen andere Sportarten?
- **Auslöser/Quellen:** SRC-001 §17.1 „Zusätzliches Training“ (Z. 1063); §10.6 (Z. 642–644); §3.4 (Z. 117); §24 Phase 4 „Weitere Sportarten“ (Z. 1387). Eine manuelle Erfassung ist nirgends beschrieben.
- **Betroffene Anforderungen:** FR-0157, FR-0199
- **Auswirkung:** blocking — Phase 2.
- **Status:** Resolved
- **Entscheidung:** Der Nutzer trägt Datum, Art, Dauer und RPE nach. Das geht in Belastung und Plan ein, erzeugt aber keine GPS- oder VO₂max-Werte. Andere Sportarten lassen sich als „Sonstiges“ erfassen; volle Unterstützung bleibt Phase 4. Ziel: FR-0199, DEC-0033. 2026-11-03, SRC-003.

### OQ-0023 — Betriebsmodell: lokal, Konto oder Cloud?
- **Frage:** Bleiben die Daten nur auf dem Gerät, oder gibt es Konto, Server oder Backup? Wie funktioniert ein Gerätewechsel?
- **Auslöser/Quellen:** SRC-001 schließt Technik aus (Z. 7), fordert aber Datenhoheit (Z. 28) und Berechnungen ohne zwingende externe Übertragung (Z. 1242). Zu Konto und Gerätewechsel gibt es keine Aussage.
- **Betroffene Anforderungen:** SEC-0006, CON-0002, CON-0008
- **Auswirkung:** blocking — Phase 1, Grundlage der Architektur.
- **Status:** Resolved
- **Entscheidung:** Nur lokal: kein Konto, kein eigener Server. 2026-11-03, SRC-003. Ziel: ADR-0001, DEC-0014.

### OQ-0024 — Schutz gespeicherter Daten und Zugangsdaten
- **Frage:** Wie werden gespeicherte Gesundheitsdaten und Strava-Zugangsdaten geschützt? Dürfen Daten in System-Backups gelangen?
- **Auslöser/Quellen:** SRC-001 §21 bezeichnet die Daten als sensibel (Z. 1235), nennt aber keine Schutzmaßnahmen. §20.2 nennt eine „Einmalige Kontoverknüpfung“ (Z. 1215); dass die Verbindung gespeichert bleibt, ist eine Deutung der Migration.
- **Betroffene Anforderungen:** FR-0185, SEC-0009, SEC-0010
- **Auswirkung:** blocking — Phase 1, Speicherung und Strava-Anbindung.
- **Status:** Resolved
- **Entscheidung:** Datenbank und Zugangsdaten werden verschlüsselt gespeichert. System-Backups sind standardmäßig aus; gesichert wird über den Gesamtexport. 2026-11-03, SRC-003. Ziel: SEC-0009, SEC-0010, DEC-0025.

### OQ-0025 — Reichweite von Einwilligung, Widerruf und Löschung
- **Frage:** Was geschieht bei einem Widerruf mit bereits importierten und daraus berechneten Daten? Wie granular ist das Löschen? Was gilt für Daten, die schon bei Strava liegen? Gilt die Zustimmungspflicht für „Gesundheitsdaten“ auch für live erfasste Herzfrequenz und selbst aufgezeichnete Trainingsdaten, die §21 ebenfalls als sensibel nennt? Was genau sind „externe Daten“, und deckt die Einwilligung auch selbst aufgezeichnete Läufe ab? Welche rechtlichen Vorgaben gelten?
- **Auslöser/Quellen:** SRC-001 §21 (Z. 1235, 1237, 1240, 1243, 1244); §25 Nr. 15 (Z. 1410); §20.2 (Z. 1217, 1221).
- **Betroffene Anforderungen:** FR-0187, FR-0191, SEC-0001, SEC-0004, SEC-0007, SEC-0008
- **Auswirkung:** blocking — Phase 1, Löschung und Strava-Synchronisierung.
- **Status:** Resolved
- **Entscheidung:** Plattform-Import und Strava brauchen je eine Einwilligung, ein selbst gestarteter Lauf mit gekoppeltem Sensor keine weitere. Beim Widerruf stoppt der Datenfluss, und die App fragt, ob importierte Daten gelöscht werden. Löschen geht je Lauf oder komplett. Daten bei Strava bleiben dort, die App weist darauf hin. Eine rechtliche Prüfung ist noch nicht erfolgt. 2026-11-03, SRC-003. Ziel: SEC-0001, SEC-0004, SEC-0007, DEC-0026.

### OQ-0026 — Warnsignale, medizinische Hinweise und Einordnung als Medizinprodukt
- **Frage:** Welche Angaben gelten als Warnsignal? Wie lautet die Empfehlung zur medizinischen Abklärung? Bleibt die App damit außerhalb einer Einordnung als Medizinprodukt?
- **Auslöser/Quellen:** SRC-001 §17.3 „bei entsprechenden Warnsignalen Trainingspause und gegebenenfalls medizinische Abklärung empfehlen“ (Z. 1114); §11.4 „keine medizinische Diagnose“ (Z. 735); §4.3 Schmerzen oder Beschwerden (Z. 186).
- **Betroffene Anforderungen:** FR-0118, FR-0163, FR-0166, FR-0203
- **Auswirkung:** blocking — Phase 2, gesundheitlich relevantes Verhalten.
- **Optionen (Vorschläge):** Rechtliche Prüfung vor der Umsetzung.
- **Status:** Resolved
- **Entscheidung:** Warnsignale sind vom Nutzer gemeldete Schmerzen, Krankheit oder Überlastung. Die App schlägt dann keine intensive Einheit vor und empfiehlt mit festem, neutralem Text Pause und gegebenenfalls ärztliche Abklärung. Sie deutet keine Messwerte medizinisch. Eine rechtliche Prüfung erfolgt vor dem Release von Phase 2. Ziel: FR-0163, DEC-0040. 2026-11-03, SRC-003.

### OQ-0027 — Pläne ohne Zieldatum und bei offenen Zielen
- **Frage:** Wie lang ist ein Plan ohne Zieldatum? Wie funktionieren Phasen und Machbarkeit bei offenen Zielen wie „allgemein fitter werden“?
- **Auslöser/Quellen:** SRC-001 §14.2 (Z. 893, 902); §15.1 „Zeit bis zum Zieldatum“ (Z. 913); §15.2 (Z. 936–938); §16.4 (Z. 1033–1043).
- **Betroffene Anforderungen:** FR-0136, FR-0137, FR-0139, FR-0141, FR-0154
- **Auswirkung:** blocking — Phase 2.
- **Status:** Resolved
- **Entscheidung:** Offene Ziele laufen in fortgeschriebenen Blöcken von 4 Wochen, ohne Wettkampf- und Reduktionsphase. Die Machbarkeit wird nur bei Zielen mit Datum beurteilt; ein offenes Ziel zeigt die Regelmäßigkeit. Ziel: FR-0137, FR-0141, FR-0154, DEC-0036. 2026-11-03, SRC-003.

### OQ-0028 — Konkrete Regeln der Trainingsplanung
- **Frage:** Welche Regeln und Werte gelten für Steigerung, Entlastungswochen, Erholungsabstand, hohe Belastung, Überlastungssignal, Wiedereinstieg und „größere Änderung“? Was umfasst die „einfache“ und die „konservative“ Planung? Wie lang sind die Trainingsphasen? Ab welcher Qualitätsstufe gilt eine VO₂max-Schätzung als unzureichend für Pace-Vorgaben?
- **Auslöser/Quellen:** SRC-001 §1.1 Nr. 2 (Z. 24); §15.1 (Z. 921); §16.1 (Z. 988–1001); §16.2 (Z. 1015); §17.3 (Z. 1092–1096); §17.4 (Z. 1122–1126). Die Quelle nennt bewusst keine pauschale Steigerung (Z. 999).
- **Betroffene Anforderungen:** FR-0140, FR-0141, FR-0145, FR-0147, FR-0148, FR-0149, FR-0150, FR-0151, FR-0152, FR-0155, FR-0160, FR-0166, FR-0167, FR-0170
- **Auswirkung:** blocking — Phase 2; ohne diese Regeln ist kein Plan erzeugbar.
- **Status:** Resolved
- **Entscheidung:** Regeln und Startwerte aus dem Research-Auftrag sind als Version 1 freigegeben, einschließlich der Steigerungsgrenzen. TSB-Schwellen dürfen nur entlasten. Die Entlastungswoche bleibt auch bei offenen Zielen. Die Werte sind vorläufig. Ziel: [planning-rules.md](../planning-rules.md), DEC-0050. 2026-11-03, SRC-003.

### OQ-0029 — Berechnung der Readiness-Zustände
- **Frage:** Wie wird aus dem Wert 0–100 ein Zustand? Wie werden Gewichte bei fehlenden Faktoren behandelt? Gelten die Zustände auch für die Basisstufe?
- **Auslöser/Quellen:** SRC-001 §11.1 (Z. 664); §11.2 (Z. 683–697); §11.4 (Z. 721–727).
- **Betroffene Anforderungen:** FR-0106, FR-0107, FR-0110, FR-0111, FR-0116
- **Auswirkung:** blocking — Phase 3.
- **Status:** Resolved
- **Entscheidung:** 75–100 gut erholt, 50–74 normal belastbar, 25–49 erhöhte Belastung, 0–24 Erholung empfohlen; vorläufig und versioniert. Fehlende optionale Faktoren werden herausgerechnet und ausgewiesen. Die Basisstufe gibt nur Texthinweise. Ziel: FR-0106, FR-0111, FR-0116, DEC-0043. 2026-11-03, SRC-003.

### OQ-0030 — Parameter der Energiereserve
- **Frage:** Welche Werte gelten für Startwert, Aktualisierungsintervall, Raten und die Dauer einer „längeren“ Datenlücke?
- **Auslöser/Quellen:** SRC-001 §12.2 (Z. 771); §12.4 (Z. 791); §12.5 (Z. 805).
- **Betroffene Anforderungen:** FR-0122, FR-0123, FR-0124, FR-0126
- **Auswirkung:** blocking — Phase 3, Energiereserve.
- **Status:** Resolved
- **Entscheidung:** Die Parameter aus Teil C von [planning-rules.md](../planning-rules.md) sind als Startwerte freigegeben. Die Funktion bleibt ausgeblendet, bis sie an echten Daten kalibriert ist. Ziel: FR-0119, FR-0124, DEC-0050. 2026-11-03, SRC-003.

### OQ-0031 — Ablauf der Neuberechnung historischer Werte
- **Frage:** Wird automatisch oder auf Wunsch neu berechnet? Wie lange bleiben Rohdaten und alte Werte erhalten? Welche Wert-Reihe wird nach einer Neuberechnung angezeigt?
- **Auslöser/Quellen:** SRC-001 §2.1 (Z. 59); §23.2 (Z. 1311–1317). Die Neuberechnung setzt gespeicherte Rohdaten voraus.
- **Betroffene Anforderungen:** FR-0006, FR-0058
- **Auswirkung:** blocking — Phase 1, weil das Datenmodell davon abhängt.
- **Status:** Resolved
- **Entscheidung:** Rohdaten bleiben erhalten, solange der Lauf existiert. Nach einer Änderung bietet die App die Neuberechnung an. Ursprüngliche Werte bleiben gespeichert; angezeigt werden danach die neuen, gekennzeichnet mit Methode und Version. 2026-11-03, SRC-003. Ziel: FR-0058, DEC-0027.

### OQ-0032 — Details von Export und Strava-Synchronisierung
- **Frage:** Welche Formatversionen und welches Format für Zusatzmetriken und Gesamtexport gelten? Wie funktioniert der Reimport, den ein Gerätewechsel nach ADR-0001 braucht? Wann wird automatisch synchronisiert, wie oft wird wiederholt, und woran wird ein Duplikat erkannt?
- **Auslöser/Quellen:** SRC-001 §20.1 (Z. 1193–1207); §20.2 (Z. 1217–1220); §20.3 (Z. 1229–1231).
- **Betroffene Anforderungen:** FR-0182, FR-0184, FR-0187, FR-0189, FR-0190, FR-0192, FR-0198
- **Auswirkung:** non-blocking, weil nur noch das separate Format für Zusatzmetriken (Phase 2) offen ist.
- **Status:** Open
- **Entscheidung:** Teilweise, 2026-11-03, SRC-003: Der Gesamtexport ist ein dokumentiertes Archiv mit allen Daten und Rohdaten; der Reimport kommt in Phase 1. Strava synchronisiert nach Laufende, wenn online, mit Wiederholung bei Fehlern und einer Upload-Kennung gegen Duplikate. Ziel: FR-0187, FR-0189, FR-0190, FR-0192, FR-0198, DEC-0028. Formatversionen der Dateiexporte, 2026-11-06, vom Maintainer in WP11 bestätigt: GPX 1.1 mit Garmin TrackPointExtension v1, TCX TrainingCenterDatabase v2, FIT-Protokoll 2.0 mit Profil 21.40 (K29, `docs/contracts/file-export.md`). Archivformat Version 1, 2026-11-07, vom Maintainer in WP12 bestätigt (K30, `docs/contracts/archive.md`).

### OQ-0033 — Welche Gesundheitsplattformen werden unterstützt?
- **Frage:** Welche Plattformen gelten als „kompatibel“? Was bedeutet „nicht ungeprüft“ beim Zusammenführen fremder VO₂max-Werte: Ist ein Zusammenführen nach Prüfung vorgesehen?
- **Auslöser/Quellen:** SRC-001 §3.4 (Z. 113, 124). Die Quelle nennt keine Plattform.
- **Betroffene Anforderungen:** FR-0022, FR-0023, FR-0024, FR-0200
- **Auswirkung:** blocking — Phase 3, Import.
- **Status:** Resolved
- **Entscheidung:** Phase 3 bindet Android Health Connect und zusätzlich direkte Hersteller-APIs an. Fremde VO₂max-Werte werden nur zum Vergleich gezeigt und nie mit eigenen zusammengeführt. Welche Hersteller und ob das ohne eigenen Server geht, klärt OQ-0047. Ziel: FR-0024, FR-0200, DEC-0045. 2026-11-03, SRC-003.

### OQ-0034 — Datengrundlage von Leistungsprognosen
- **Frage:** Wie wird eine geeignete Referenzleistung erkannt oder gewählt? Gibt es ohne Wettkampfdaten eine Prognose?
- **Auslöser/Quellen:** Konflikt in SRC-001: §13 „bevorzugt auf geeigneten tatsächlichen Leistungen“ (Z. 820) lässt andere Grundlagen zu; §22 ordnet Prognosen den „Geeigneten Wettkampfdaten“ zu (Z. 1257); §13.2 schließt die VO₂max allein als verbindliche Grundlage aus (Z. 856).
- **Betroffene Anforderungen:** FR-0055, FR-0129, FR-0131, FR-0134
- **Auswirkung:** blocking — Phase 2, Prognosen.
- **Status:** Resolved
- **Entscheidung:** Prognosen brauchen eine Referenzleistung: eine eingetragene Wettkampf- oder Testzeit oder einen von der App vorgeschlagenen und vom Nutzer bestätigten schnellen Lauf. Ohne Referenz gibt es keine Prognose, sondern einen Hinweis auf einen 5-km-Test. Ziel: FR-0129, FR-0131, DEC-0039. 2026-11-03, SRC-003.

### OQ-0035 — Nichtfunktionale Zielwerte und Rahmen
- **Frage:** Welche Zielwerte gelten für Akkuverbrauch, Genauigkeit und Antwortzeiten? Welche Betriebssystemversionen, Sprachen, Maßeinheiten und Anforderungen an die Barrierefreiheit gelten? Wann und unter welcher Bedingung kommt iOS?
- **Auslöser/Quellen:** SRC-001 nennt nur die Plattform (Z. 4) und enthält dazu sonst keine Aussage.
- **Betroffene Anforderungen:** NFR-0006, CON-0001
- **Auswirkung:** non-blocking für die Spezifikation; vor der Abnahme von Phase 1 zu klären.
- **Status:** Resolved
- **Entscheidung:** Die App ist zweisprachig (Deutsch, Englisch), mit Kilometern und optional Meilen. Die Android-Mindestversion schlägt der Implementierungsagent per ADR vor. Zielwerte für Akku und Genauigkeit werden nach ersten Feldtests festgelegt. Ziel: NFR-0006, DEC-0047. 2026-11-03, SRC-003.

### OQ-0036 — Parameter der aeroben Effizienz
- **Frage:** Welcher Belastungsbereich gilt, Mittelwert oder Median, welcher Referenzzeitraum und welche Mindestdauer für die Drift? Ist der „Aerobe Fitness-Trend“ aus §24 dasselbe wie die aerobe Effizienz aus §9?
- **Auslöser/Quellen:** SRC-001 §9.1 (Z. 492–494); §9.2 (Z. 505); §9.3 (Z. 538); §24 (Z. 1346).
- **Betroffene Anforderungen:** FR-0084, FR-0085, FR-0086, FR-0087
- **Auswirkung:** blocking — Phase 1, aerober Trend.
- **Status:** Resolved
- **Entscheidung:** Bereich 65–75 % der Herzfrequenzreserve, Median. Verglichen werden die letzten 4 Wochen mit den 4 Wochen davor. Der Aerobe Fitness-Trend aus §24 ist diese Kennzahl. 2026-11-03, SRC-003. Ziel: FR-0084, FR-0085, FR-0087, DEC-0022.

### OQ-0037 — Details von Aufzeichnung und Zusammenfassung
- **Frage:** Wie sind Bestpace und die Einordnung gegenüber vorherigen Einheiten definiert? Wann pausiert die App automatisch? Welche akustischen Hinweise gibt es und in welcher Sprache? Wie wird Pace bei Stillstand angezeigt? Kehrt die App nach einem Abbruch automatisch zum bevorzugten Gerät zurück, wenn es wieder verbunden ist?
- **Auslöser/Quellen:** SRC-001 §4.2 (Z. 158, 160); §4.3 (Z. 172, 179).
- **Betroffene Anforderungen:** FR-0029, FR-0037, FR-0050
- **Auswirkung:** blocking — Phase 1 für Bestpace und Einordnung in der Zusammenfassung (FR-0037). Autopause gehört in Phase 1, akustische Hinweise in Phase 2 (OQ-0041).
- **Status:** Resolved
- **Entscheidung:** Bestpace ist der schnellste zusammenhängende Kilometer. Die Einordnung vergleicht mit dem Schnitt der letzten 5 Läufe. Autopause bei rund 10 s ohne Bewegung. Pace im Stillstand wird als „–“ angezeigt. Kein automatischer Rückwechsel des Pulsgeräts während eines Laufs. 2026-11-03, SRC-003. Ziel: FR-0018, FR-0029, FR-0037, FR-0050. Inhalte akustischer Hinweise: OQ-0044.

### OQ-0038 — Doppelte Eingaben in Profil und Ziel
- **Frage:** Sind Trainingstage und Trainingsdauer Angaben des Profils oder des Ziels, und welche Angabe gilt bei Abweichung? Sind sie erforderlich oder freiwillig?
- **Auslöser/Quellen:** Konflikt in SRC-001: §2.1 „Verfügbare Trainingstage | … | Für Trainingspläne“ (Z. 46) gegenüber §14.2 „kann der Nutzer festlegen: … Verfügbare Wochentage“ (Z. 891, 894); §2.1 „Übliche Trainingsdauer“ (Z. 47) gegenüber §14.2 „Maximale Trainingszeit pro Einheit“ (Z. 895).
- **Betroffene Anforderungen:** FR-0002, FR-0136
- **Auswirkung:** blocking — Phase 2, Eingaben für die Planung.
- **Status:** Resolved
- **Entscheidung:** Das Profil enthält die Standardwerte für Trainingstage und Trainingsdauer. Beim Ziel werden sie vorausgefüllt und lassen sich für den Plan ändern; für den Plan gilt der Wert am Ziel. Ziel: FR-0002, FR-0136, DEC-0038. 2026-11-03, SRC-003.

### OQ-0039 — Benennung von CTL in Statistik und Erklärungen
- **Frage:** Dürfen Statistik und Erklärungen andere Bezeichnungen als „langfristiges Belastungsniveau“ verwenden?
- **Auslöser/Quellen:** SRC-001 §10.4 legt die Bezeichnung fest (Z. 626). §5.2 nennt „langfristige Trainingsbelastung“ (Z. 209), das Beispiel in §19 „langfristigen Durchschnitt“ (Z. 1175).
- **Betroffene Anforderungen:** FR-0043, FR-0100, FR-0180
- **Auswirkung:** non-blocking, weil nur der Wortlaut betroffen ist; FR-0100 bleibt bis zur Entscheidung maßgeblich.
- **Status:** Resolved
- **Entscheidung:** In der Oberfläche heißt die CTL überall „langfristiges Belastungsniveau“, auch in Statistik und Erklärungen. Ziel: FR-0043, FR-0100, FR-0180, DEC-0048. 2026-11-03, SRC-003.

### OQ-0040 — Was ist ein „fortgeschrittener Fitnesswert“?
- **Frage:** Für welche Werte gelten die Metadaten aus §6.3?
- **Auslöser/Quellen:** SRC-001 §6.3 „Jeder fortgeschrittene Fitnesswert“ (Z. 261). Der Begriff ist nicht definiert.
- **Betroffene Anforderungen:** FR-0053
- **Auswirkung:** blocking — Phase 1, Datenmodell der Fitnesswerte.
- **Status:** Resolved
- **Entscheidung:** Alle Angaben gelten für VO₂max, aerobe Effizienz, Drift, Readiness, Energiereserve und Prognosen. TRIMP, ATL und CTL tragen nur Methode und Version. 2026-11-03, SRC-003. Ziel: FR-0053.

### OQ-0041 — Phasen der noch nicht zugeordneten Anforderungen
- **Frage:** In welche Phase gehören die übrigen optionalen Live-Anzeigen (FR-0027: Rundenzeiten, Höhenmeter, Schrittfrequenz, Hinweise zum Belastungsbereich) und die Kennzeichnung der Messmethoden (FR-0083)?
- **Auslöser/Quellen:** SRC-001 §24 (Z. 1330–1390) gegenüber §3.3, §3.4, §4.1, §4.2, §4.3, §8.7, §9.3, §11.1 und §20.1. Abgetrennt von OQ-0017.
- **Betroffene Anforderungen:** FR-0027, FR-0083, FR-0192
- **Auswirkung:** non-blocking, weil es um optionale Anzeigen und eine Kennzeichnung für Phase 4 geht.
- **Status:** Resolved
- **Entscheidung:** Phase 1: Runden, Autopause, Rundenzeiten, Höhenmeter, Schrittfrequenz. Phase 2: akustische Hinweise, Herzfrequenzwarnung, Hinweise zum Belastungsbereich, übrige subjektive Angaben, Export von Zusatzmetriken, Basis-Erholungseinschätzung, Laufbandmodus, Wahl des Belastungsprofils. Phase 3: weiterer Datenimport. Phase 4: erweiterte Sensordaten, Herzfrequenzdrift, Kennzeichnung der Messmethoden. 2026-11-03, SRC-003.

### OQ-0042 — Details des Laufbandmodus
- **Frage:** Wie wird die Strecke aus der eingestellten Geschwindigkeit bestimmt? Lässt sich auch die Steigung einstellen? Fließen Laufbandläufe in VO₂max, Effizienz und Bestleistungen ein? Wie werden sie exportiert?
- **Auslöser/Quellen:** SRC-003, Maintainer 2026-11-03: Laufbandmodus später, aktuelle Geschwindigkeit des Bands einstellbar. Berührt SRC-001 §8.2 (Steigung, Z. 350) und §20.1 (GPS-Strecke, Z. 1201).
- **Betroffene Anforderungen:** FR-0196
- **Auswirkung:** non-blocking, weil der Modus nicht zu Phase 1 gehört; vor seiner Umsetzung zu klären.
- **Status:** Resolved
- **Entscheidung:** Die Strecke ergibt sich aus Geschwindigkeit mal Zeit, die Steigung ist optional einstellbar. VO₂max entsteht höchstens als „vorläufig“. Belastung und Statistik zählen normal. Der Export kommt ohne GPS-Strecke aus. Ziel: FR-0196, DEC-0048. 2026-11-03, SRC-003.

### OQ-0043 — Was ist ein Belastungsprofil, und wie weit reicht die Austauschbarkeit?
- **Frage:** Was genau wählt der Nutzer mit einem „Belastungsprofil“: das Rechenmodell wie Edwards oder Banister oder auch Zonen und Gewichte? Welche Algorithmen sind für Nutzer wählbar, welche nur technisch austauschbar? Was geschieht beim Wechsel mit historischen Werten und den Verläufen von ATL und CTL?
- **Auslöser/Quellen:** SRC-003, Maintainer 2026-11-03: „alle verwendeten Algorithmen austauschbar“, „der User kann später sein Belastungsprofil auswählen nachdem gerechnet wird“. Berührt SRC-001 §10.2 (konsistente Skala, Z. 602), §23.2 (Neubewertung, Z. 1311) und FR-0097.
- **Betroffene Anforderungen:** FR-0197, NFR-0005
- **Auswirkung:** blocking — Phase 1, weil der Zuschnitt die Architektur und das Datenmodell bestimmt.
- **Status:** Resolved
- **Entscheidung:** Das Profil wählt das Rechenmodell für die Belastung. Alle übrigen Algorithmen sind technisch austauschbar, aber nicht vom Nutzer wählbar. Beim Wechsel werden alte Läufe nach Bestätigung neu gerechnet. 2026-11-03, SRC-003. Ziel: NFR-0005, FR-0197, DEC-0023.

### OQ-0044 — Inhalte akustischer Hinweise
- **Frage:** Welche akustischen Hinweise gibt es, wann werden sie ausgelöst, und in welcher Sprache?
- **Auslöser/Quellen:** SRC-001 §4.2 (Z. 160). Abgetrennt von OQ-0037.
- **Betroffene Anforderungen:** FR-0031
- **Auswirkung:** blocking — Phase 2, akustische Hinweise.
- **Status:** Resolved
- **Entscheidung:** Sprachansagen, einzeln schaltbar: je Kilometer mit Zeit und Pace, Überschreitung des Pulsbereichs und Intervallwechsel. Die Sprache folgt der App-Sprache (OQ-0035). Ziel: FR-0031, DEC-0041. 2026-11-03, SRC-003.

### OQ-0045 — Welche Belastungsmodelle stehen zur Wahl?
- **Frage:** Welche Modelle neben dem Edwards-TRIMP kann der Nutzer als Belastungsprofil wählen? §26 nennt Banister-TRIMP als Beispiel. Wie passt die Wahl zur einheitlichen Skala aus OQ-0015?
- **Auslöser/Quellen:** SRC-003 (OQ-0043); SRC-001 §26 Nr. 2 (Z. 1417). Für eine echte Wahl braucht Phase 2 mindestens ein zweites Modell.
- **Betroffene Anforderungen:** FR-0197
- **Auswirkung:** blocking — Phase 2, Wahl des Belastungsprofils.
- **Status:** Resolved
- **Entscheidung:** Wählbar sind Edwards und Banister. Ein Verlauf nutzt immer nur ein Modell; nach einem Wechsel wird neu gerechnet. Ohne Ruhepuls bleibt nur Edwards wählbar. Ziel: FR-0197, DEC-0031. 2026-11-03, SRC-003.

### OQ-0046 — Startwerte der Parameter für Phase 2
- **Frage:** Welche Startwerte gelten für die Mindestanzahl gemeinsamer Läufe beim Umrechnungsfaktor von sRPE und für die Dauer der vorläufigen Phase von ATL und CTL?
- **Auslöser/Quellen:** SRC-003 (OQ-0015, OQ-0016). Vergleichbar mit OQ-0019.
- **Betroffene Anforderungen:** FR-0097, FR-0098
- **Auswirkung:** blocking — Phase 2, ATL/CTL.
- **Status:** Resolved
- **Entscheidung:** Mindestens 10 gemeinsame Läufe für den Umrechnungsfaktor (PAR-086). Vorläufige Phase: ATL 21 Tage (PAR-088), CTL und TSB 126 Tage (PAR-089). Ziel: [planning-rules.md](../planning-rules.md), DEC-0050. 2026-11-03, SRC-003.

### OQ-0047 — Welche Hersteller-APIs, und gehen sie ohne eigenen Server?
- **Frage:** Welche Hersteller werden direkt angebunden? Lassen sich ihre APIs ohne eigenen Server nutzen, wie ADR-0001 es vorgibt? Falls nicht: Entfällt der Hersteller, oder wird ADR-0001 geändert?
- **Auslöser/Quellen:** SRC-003 (OQ-0033) gegenüber ADR-0001; SRC-001 §3.1 (Z. 80), §3.4 (Z. 113). Die Daten kämen von externen Servern. Die Bedingungen der Anbieter sind noch nicht geprüft.
- **Betroffene Anforderungen:** FR-0200
- **Auswirkung:** blocking — Phase 3, Import über Hersteller-APIs. Health Connect ist nicht betroffen.
- **Status:** Resolved
- **Entscheidung:** ADR-0001 bleibt. Phase 3 nutzt nur Health Connect. Die Google Health API ist zurückgestellt, bis der Android-Weg ohne Secret und die jährlichen Prüfkosten von 500 bis 4.500 USD geklärt sind. Andere Hersteller folgen erst, wenn sich ein Weg ohne Server ergibt. Secrets werden nicht in der App ausgeliefert. Korrigiert 2026-11-04 nach R002; zuvor waren Health Connect und, bei erfolgreicher Prüfung, die Google Health API vorgesehen. Ziel: FR-0200, ADR-0001, DEC-0049.

### OQ-0048 — Rechtliche Prüfung
- **Frage:** Ist die rechtliche Prüfung beauftragt und abgeschlossen? Sie soll Datenschutz (OQ-0025), die Einordnung als Medizinprodukt (OQ-0026), das in [planning-rules.md](../planning-rules.md) erwähnte Firstbeat-Patent, und die Nutzung der NHS-Abfolge (PAR-065) abdecken.
- **Auslöser/Quellen:** SRC-003, Entscheidung des Maintainers 2026-11-03. Bisher ist keine rechtliche Einschätzung erfolgt.
- **Betroffene Anforderungen:** FR-0122, FR-0140, FR-0163, FR-0203, SEC-0001
- **Auswirkung:** non-blocking für die Umsetzung, aber Voraussetzung für ein Release. Der Maintainer beauftragt sie.
- **Status:** Open
- **Entscheidung:** —

### OQ-0049 — Strava ohne Server und ausgeliefertes Secret
- **Frage:** Wie lässt sich Strava anbinden, wenn der Token-Tausch ein client_secret verlangt?
- **Auslöser/Quellen:** Abschlussprüfung: Strava-Dokumentation (https://developers.strava.com/docs/authentication/) gegenüber ADR-0001 und OQ-0047; SRC-001 §20.2 (Z. 1211–1225), §24 (Z. 1349).
- **Betroffene Anforderungen:** FR-0185, FR-0186, FR-0187, FR-0188, FR-0189, FR-0190, FR-0191, FR-0201
- **Auswirkung:** blocking — war Phase 1.
- **Status:** Resolved
- **Entscheidung:** Die Direktanbindung (FR-0185 bis FR-0191) wird zurückgestellt, bis es einen Weg ohne Secret gibt. Phase 1 bietet Export und Teilen als FIT oder GPX; den Upload macht der Nutzer selbst bei Strava. Ziel: FR-0201, DEC-0051. 2026-11-03, SRC-003.

### OQ-0050 — Schutz des Gesamtexports und Regeln für den Reimport
- **Frage:** Wird das Archiv verschlüsselt, und was gilt beim Reimport?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0192 und FR-0198 gegenüber SEC-0004, SEC-0007, SEC-0008 und SEC-0009.
- **Betroffene Anforderungen:** FR-0192, SEC-0011
- **Auswirkung:** blocking — war Phase 1.
- **Status:** Resolved
- **Entscheidung:** Das Archiv ist immer mit einem Passwort des Nutzers verschlüsselt und enthält keine Zugangsdaten und Einwilligungen. Der Reimport prüft die Datei, geht nur auf einer leeren App oder nach ausdrücklichem Zurücksetzen und verlangt neue Einwilligungen. Die App weist darauf hin, dass ein älteres Archiv gelöschte Daten zurückbringen kann. Ziel: SEC-0011, FR-0192, FR-0198, DEC-0052. 2026-11-03, SRC-003.

### OQ-0051 — TRIMP bei Pulslücken
- **Frage:** Ab wann bekommt ein Lauf mit Pulslücken einen Belastungswert?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0091, FR-0092, FR-0056.
- **Betroffene Anforderungen:** FR-0092
- **Auswirkung:** blocking — war Phase 1.
- **Status:** Resolved
- **Entscheidung:** Liegt für mindestens 80 % der Bewegungszeit Puls vor, zählt der TRIMP aus der vorhandenen Zeit und ist als unvollständig markiert. Darunter gilt der Lauf als nicht bewertet. Die 80 % sind eine Heuristik. Ziel: FR-0092, DEC-0053. 2026-11-03, SRC-003.

### OQ-0052 — Quelle der Schrittfrequenz in Phase 1
- **Frage:** Woher kommt die Schrittfrequenz in Phase 1?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0027 und OQ-0041 gegenüber FR-0021 und dem Bluetooth-Herzfrequenzdienst.
- **Betroffene Anforderungen:** FR-0202
- **Auswirkung:** blocking — war Phase 1.
- **Status:** Resolved
- **Entscheidung:** Der Schrittsensor des Smartphones liefert die Kadenz, mit eigener Android-Berechtigung. Ziel: FR-0202, DEC-0054. 2026-11-03, SRC-003.

### OQ-0053 — Formel und Koeffizienten des Banister-Modells
- **Frage:** Welche Formel gilt, wenn die übliche Fassung unterschiedliche Koeffizienten für Männer und Frauen nutzt?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0197, OQ-0045, PAR-096.
- **Betroffene Anforderungen:** FR-0197
- **Auswirkung:** blocking — war Phase 2.
- **Status:** Resolved
- **Entscheidung:** Ein optionales Profilfeld wählt die Koeffizienten. Ohne Angabe bleibt nur Edwards wählbar. Lehnt der Nutzer die Neuberechnung ab, verfällt die Modellwahl. Ziel: FR-0002, FR-0197, DEC-0054. 2026-11-03, SRC-003. Nachtrag 2026-11-09 (Orchestrator, WP19): Formel und b an Banister et al. 1992 geprüft; k (0,64/0,86) ist nur sekundär belegt und bleibt als verbreitete Variante, weil es für eine Person nur die Skala ändert.

### OQ-0054 — ATL und CTL an Tagen mit unbewerteter Einheit
- **Frage:** Welchen Wert haben Tage mit unbewerteter Einheit?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0098, FR-0099, FR-0102, OQ-0016.
- **Betroffene Anforderungen:** FR-0098, FR-0099, FR-0102
- **Auswirkung:** blocking — war Phase 2.
- **Status:** Resolved
- **Entscheidung:** ATL und CTL bleiben an solchen Tagen unverändert, und der Tag ist gekennzeichnet. Ziel: FR-0098, FR-0099, FR-0102, DEC-0054. 2026-11-03, SRC-003.

### OQ-0055 — Eingabeweg und Dauer von Warnsignalen
- **Frage:** Wie werden Warnsignale gemeldet, und wie lange wirken sie?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0163, FR-0038, PAR-055, OQ-0026.
- **Betroffene Anforderungen:** FR-0203
- **Auswirkung:** blocking — war Phase 2.
- **Status:** Resolved
- **Entscheidung:** Die Meldung ist jederzeit im Plan möglich. Die App plant keine intensiven Einheiten, bis der Nutzer die Meldung aufhebt, und erinnert ihn nach 7 Tagen daran. Der feste Text steht auf Deutsch und Englisch in FR-0203. Ziel: FR-0203, DEC-0054. 2026-11-03, SRC-003.

### OQ-0056 — System-Backups: Schalter oder immer aus?
- **Frage:** Gibt es einen Schalter, mit dem der Nutzer System-Backups einschalten kann?
- **Auslöser/Quellen:** Abschlussprüfung: SEC-0010 und ADR-0001.
- **Betroffene Anforderungen:** SEC-0010
- **Auswirkung:** blocking — war Phase 1.
- **Status:** Resolved
- **Entscheidung:** System-Backups sind immer aus, es gibt keinen Schalter. Gesichert wird nur über das verschlüsselte Archiv; die App kann daran erinnern. 2026-11-03, SRC-003. Ziel: SEC-0010, ADR-0001, DEC-0025.

### OQ-0057 — Fehlende Regeln für Phase 2 und 3
- **Frage:** Welche Regeln gelten für die Zuordnung von Trainingstyp zu Zone, RPE oder Pace, den Intervallaufbau, die Wochen 2 bis 9 der Geh-Lauf-Abfolge, die Qualitätsstufen für Prognose, Readiness, Energiereserve und Drift, die Berechnung des Readiness-Werts und die Auslöser der Basis-Hinweise?
- **Auslöser/Quellen:** Abschlussprüfung: FR-0142, FR-0143, FR-0153, PAR-058, PAR-065, PAR-082, FR-0053, FR-0106, FR-0110.
- **Betroffene Anforderungen:** FR-0106, FR-0110, FR-0142, FR-0143, FR-0153
- **Auswirkung:** blocking — Phase 2 und 3. Phase 1 ist nicht betroffen.
- **Status:** Resolved
- **Entscheidung:** Die Regeln in [phase-2-3-rules.md](../phase-2-3-rules.md) sind als Version 1 freigegeben. Festlegungen: Locker heißt unter 70 % Reserve und unter 80 % HFmax. Ausnahme von FR-0153 für Pace bei lockeren Läufen und Intervallen. 5-km-Test erst nach der Stufe Einsteiger. Schlaf mit festem Anker 7 h. Befinden nur aus der Angabe beim letzten Lauf. Eingeschränkte Einschätzung und „Unzureichende Daten“ getrennt. Text-Hinweis vor Tag 126. Ziel: FR-0053, FR-0106, FR-0110, FR-0142, FR-0143, FR-0153, DEC-0055. 2026-11-03, SRC-003.

### OQ-0058 — Entscheidungen aus der Prüfung von Phase 2 und 3
- **Frage:** Wie werden die Widersprüche aus der letzten Prüfung gelöst?
- **Auslöser/Quellen:** Prüfung von [phase-2-3-rules.md](../phase-2-3-rules.md) gegen Specs und Entscheidungen.
- **Betroffene Anforderungen:** FR-0103, FR-0116, FR-0129, FR-0157, FR-0199, FR-0203
- **Auswirkung:** blocking — war Phase 2 und 3.
- **Status:** Resolved
- **Entscheidung:** Bei „Erhöhte Belastung“ und „Erholung empfohlen“ wird die nächste intensive Einheit automatisch locker. Ohne Schlafsitzung gibt es keinen HRV-Wert. Bei einem Warnsignal plant die App nur Ruhetage bis zur Aufhebung. An leeren Tagen ohne Vollständigkeitszusage bleiben ATL und CTL unverändert und dauerhaft vorläufig. Der 5-km-Test zählt nicht zum Budget. Sonstiges Training zählt nur für Belastung und Pausenende. Ein schneller Lauf wird bei RPE ≥ 8 und mindestens 3 km oder bei geschlagener Referenz vorgeschlagen. 2026-11-04, SRC-003. Ziel: PAR-117, PAR-160, PAR-171, PAR-173, PAR-185, FR-0098, FR-0103, FR-0199, FR-0203, DEC-0056. Korrigiert 2026-11-04, SRC-003 (OQ-0059): Für die Bremsung zählt der Wert am Tag der intensiven Einheit, nicht ein früherer Wert für die nächste Einheit. Ziel der Korrektur: FR-0116, FR-0157, PAR-173.

### OQ-0059 — Wertänderungen aus der Research-Prüfung
- **Frage:** Welche Änderungen an freigegebenen Werten folgen aus den Research-Prüfungen R001 bis R003?
- **Auslöser/Quellen:** Berichte in `docs/migration/research-reviews/`.
- **Betroffene Anforderungen:** FR-0038, FR-0053, FR-0060, FR-0068, FR-0069, FR-0077, FR-0093, FR-0109, FR-0110, FR-0111, FR-0113, FR-0115, FR-0116, FR-0117, FR-0129, FR-0135, FR-0137, FR-0139, FR-0140, FR-0141, FR-0148, FR-0151, FR-0153, FR-0154, FR-0157, FR-0167, FR-0200
- **Auswirkung:** blocking — war Phasen 1 bis 3, bis die Änderungen eingetragen sind.
- **Status:** Resolved
- **Entscheidung:** 2026-11-04, SRC-003: Die erste Woche nach einer Entlastung erreicht höchstens die letzte Woche ohne Entlastung (PAR-052). „Aufbau“ verlangt zusätzlich 6 Monate regelmäßiges Laufen oder eine Selbstauskunft; intensive Einheiten frühestens 8 Wochen nach dem Einstieg, zunächst höchstens 5 % harte Zeit (PAR-051, PAR-054, PAR-062). HRV und Ruhepuls gehen als Mehrtagesmittel ein, und für die Bremsung zählt nur der Wert am Tag der Einheit (PAR-161, PAR-162, PAR-173). Die Bandbreite weitet nur das langsame Ende; das schnelle Ende des Tempodauerlaufs wird das langsamere aus 10-km-Tempo und Riegel-Tempo für 60 min (PAR-190, PAR-102). Längere Pläne: ab 30 min Dauerlauf 10 km 12–16 Wochen, Halbmarathon 22–28 Wochen (PAR-068). Die Untergrenze der VO₂max bleibt und wird offen genannt (PAR-032). Alle übrigen Wertvorschläge der Berichte werden übernommen, sofern sie keiner Entscheidung widersprechen. Ergänzt und, wo nötig, korrigiert am selben Tag: Die Geh-Lauf-Abfolge läuft unverändert über 9 Wochen wie die Vorlage, ohne Entlastungswochen und ohne Rampenregel danach; jede Woche lässt sich wiederholen, die App schlägt das bei hoher Anstrengung vor (PAR-065, PAR-140). Das ist eine Empfehlung ohne ausdrückliche Präferenz des Maintainers, die er ändern kann. Bei „Aufbau“ zielt der Plan im Regelfall auf +10 % je Zyklus (Heuristik) und nutzt mehr nur, wenn das Ziel es verlangt; die Obergrenzen bleiben, entschieden nur für „Aufbau“ (PAR-052). Anstelle der Spannen gelten als kürzeste Längen ab 30 min Dauerlauf: 10 km Einsteiger 15, Aufbau 13, Erfahren 12 Wochen, Halbmarathon mit Zielspitze 90 min 27, 24 und 20 Wochen (PAR-068, PAR-084). Die Frist von 8 Wochen läuft ab dem Ende des Einstiegs, und unter 160 min Umfang gibt es keine intensive Einheit (PAR-054). Bestätigt: `z` aus dem Mittelwert mit MAD/√k (PAR-161, PAR-162, FR-0113); einseitige Bandbreite auch für die Pace aus der VO₂max (PAR-082, PAR-103); Wegfall der Blöcke über 5 min und von 1 × 40 min (PAR-118, PAR-125, PAR-128); Readiness höchstens 74 ohne Belastungsfaktor (PAR-170). Weiter ergänzt am selben Tag, geht bei Abweichung vor: Das Regelziel je Zyklus gilt für alle Stufen: Ziel 5 km und offene Ziele +10 %, 10 km +12,5 %, Halbmarathon +15 %. Das ersetzt das Regelziel +10 % nur für „Aufbau“. Die Obergrenzen bleiben Deckel; mit Zieldatum darf der Plan bis dahin gehen, aber nur so weit, wie das Datum es verlangt (PAR-052). Die Regellängen heißen kürzeste Längen und werden bei genau dieser Länge als „ambitioniert“ bewertet; „realistisch“ gilt, wenn das Datum mit dem Regelziel erreichbar ist (PAR-068, PAR-084). Nach der Geh-Lauf-Abfolge startet der Plan mit 3 × 30 min, weil nur die Laufzeit zählt und das Gehen Auf- und Abwärmen ist; ab Einstieg sind das an den Obergrenzen 10 km 24 und Halbmarathon 36 Wochen (PAR-066, PAR-068, PAR-084). Die App erklärt die RPE-Skala mit eigenen einfachen Wörtern statt mit den Borg-Ankern; das ist eine eigene, nicht validierte Skala, mit Studien nur bedingt vergleichbar, und die Nutzungsrechte der Borg-Anker gehören nicht mehr zu OQ-0048 (PAR-105, FR-0038). Ziel: [model-parameters.md](../model-parameters.md), [planning-rules.md](../planning-rules.md), [phase-2-3-rules.md](../phase-2-3-rules.md), je Version 2, Akzeptanzkriterien der betroffenen Anforderungen, DEC-0057. Letzte Korrekturrunde 2026-11-04, SRC-003, aus [R004](research-reviews/R004-final-review.md), geht bei Abweichung vor: Ist die Zielspitze erreicht, hält der Plan den Umfang; offene Ziele steigern 3 Zyklen und halten dann, bis der Nutzer mehr wählt (PAR-052, PAR-071). Zielspitze: 5 km und 10 km mindestens die Dauer der Distanz im lockeren Tempo, mindestens 30 und 60 min, ohne Tempodaten die Mindestwerte; Halbmarathon 90 min als Regel, bis 120 min für langsame Läufer; lockeres Tempo und „langsam“ als gekennzeichnete Heuristik ohne neue Eingabe (PAR-084, PAR-191). Distanzziele kommen ohne intensive Einheiten aus, die Phase „Spezifisch“ entfällt dann; Zeitziele gelten nur als „realistisch“, wenn 160 min rechtzeitig erreichbar sind; die 160 min gelten für alle Stufen, auch „Erfahren“ (PAR-054, PAR-069, PAR-084, PAR-125, PAR-130). Die übrigen Befunde aus R004 werden mit den dort genannten vorsichtigen Lösungen umgesetzt, soweit sie dem nicht widersprechen, darunter die Definition von „6 Monate“, die Reserve für „realistisch“ mit monotoner Einstufung, RPE 3–4 als Vorgabe (PAR-110), 40 % des langen Laufs auch ab 4 Tagen (PAR-063); für die RMSSD-Quellen genügt ein Validierungspunkt vor Phase 3. Die Geh-Lauf-Abfolge bleibt die empfohlene 9-Wochen-Variante. Version 2 gilt damit als eingefroren; künftige Änderungen brauchen eine neue Version. Umsetzung: [R004-fixes.md](research-reviews/R004-fixes.md). Ziel: PAR-051 bis PAR-054, PAR-062 bis PAR-071, PAR-077, PAR-083 bis PAR-085, PAR-110, PAR-125, PAR-130, PAR-191, FR-0135, FR-0137, FR-0141, FR-0148, FR-0151, FR-0154, DEC-0058. Gezielte Prüfung danach, 2026-11-04, SRC-003, geht bei Abweichung vor: Das 5-km-Zeitziel bleibt ab 3 × 30 min bei 33 Wochen. Die RPE-Wörter sind bestätigt. Ohne ausdrückliche Präferenz des Maintainers, als Empfehlung übernommen und änderbar: Die erlaubte Verbesserung insgesamt aus PAR-083 sinkt über 12 Wochen nie unter den Wert bei 12 Wochen; der Hinweis auf den 5-km-Test erscheint erst, wenn der Plan ihn nach PAR-117 enthalten dürfte. Umsetzung: [R004-check.md](research-reviews/R004-check.md). Ziel: PAR-083, PAR-084, PAR-105, PAR-117, PAR-143, FR-0129, FR-0154, DEC-0059.

### OQ-0060 — Einfacher Trainingsplan
- **Frage:** Wie wird der Trainingsplan einfach, sodass er sich testen lässt und vor allem anpassbar ist?
- **Auslöser/Quellen:** Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** FR-0135, FR-0136, FR-0137, FR-0139, FR-0140, FR-0141, FR-0148, FR-0151, FR-0154, FR-0156, FR-0167, FR-0170
- **Auswirkung:** blocking — war Phase 2, bis die Regeln eingetragen sind.
- **Status:** Resolved
- **Entscheidung:** 2026-11-04, SRC-003: Alle bisherigen Entscheidungen dazu, wie viel Prozent wann gesteigert wird, und die Sonderregeln zum Trainingsplan sind annulliert, einschließlich der entsprechenden Teile von OQ-0028 und OQ-0059 und von DEC-0058 und DEC-0059. Es gelten einfache, ungeprüfte Regeln zum Testen (PAR-192 bis PAR-206). Der Nutzer wählt Ziel, heutigen Stand, Lauftage und mit einem Regler die Wochenzeit, und kann alles später ändern. Harte Einheit: einfacher Schalter, an bei Zeitzielen, sonst aus. Zeitziele gibt es in einfacher Form. Zu knappes Datum: Hinweis mit passendem Datum, der Nutzer entscheidet, der Plan steigert nicht schneller. Von selbst passt die App nur nach unten an, mehr nur nach „zu leicht“ oder einer Einstellung. Die App fragt alle 2 Wochen nach. Die konkreten Prozentwerte sind ein Vorschlag vom Reißbrett und im Feldtest änderbar. Ziel: [planning-rules.md](../planning-rules.md), [phase-2-3-rules.md](../phase-2-3-rules.md), je Version 4, DEC-0061.

### OQ-0061 — Bedeutung der Wiederaufnahme
- **Frage:** Was geschieht nach einem Abbruch mit der Lücke und dem Teillauf?
- **Auslöser/Quellen:** ADR-0005, FR-0193; Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** FR-0193
- **Auswirkung:** blocking — war Phase 1, Aufzeichnung.
- **Status:** Resolved
- **Entscheidung:** Beim nächsten Start wählt der Nutzer: denselben Lauf fortsetzen, die Lücke wird markiert und die Strecke nicht geschätzt, oder ihn als beendeten Lauf speichern. Es gibt keine Frist. 2026-11-04, SRC-003. Ziel: FR-0193, DEC-0062.

### OQ-0062 — Verlust des Datenbankschlüssels
- **Frage:** Was tut die App, wenn sich die verschlüsselte Datenbank nicht mehr öffnen lässt?
- **Auslöser/Quellen:** ADR-0003, SEC-0009; Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** SEC-0009
- **Auswirkung:** blocking — war Phase 1, Speicherung.
- **Status:** Resolved
- **Entscheidung:** Die App erklärt das Problem und bietet einen Neubeginn mit leerer Datenbank und den Reimport aus dem Archiv an. Die alte Datei wird erst nach ausdrücklicher Bestätigung gelöscht. 2026-11-04, SRC-003. Ziel: SEC-0009, DEC-0063.

### OQ-0063 — Vertriebsweg
- **Frage:** Über welchen Weg wird die App vertrieben?
- **Auslöser/Quellen:** ADR-0002, ADR-0007; Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** CON-0001
- **Auswirkung:** non-blocking, weil vorerst kein Vertrieb vorgesehen ist.
- **Status:** Resolved
- **Entscheidung:** Vorerst offen, frühestens vor dem ersten Release zu entscheiden. Die technischen Vorgaben von Google Play werden eingehalten (zum Beispiel Target 36, Dienst-Typen), ohne Store-Eintrag und Erklärungen. 2026-11-04, SRC-003. Ziel: ADR-0002, DEC-0064.

### OQ-0064 — Technische Vorgaben der Aufzeichnung
- **Frage:** Wie oft wird GPS abgefragt? Reicht ungefährer Standort für den Laufstart (FR-0195)? Darf sich derselbe Pulssensor nach einem Abbruch neu verbinden, obwohl OQ-0037 keinen automatischen Rückwechsel vorsieht?
- **Auslöser/Quellen:** ADR-0005, ADR-0006; dem Maintainer am 2026-11-04 als Vorschlag genannt, kein Widerspruch.
- **Betroffene Anforderungen:** FR-0018, FR-0195
- **Auswirkung:** non-blocking, weil bis zu Feldtests der Vorschlag gilt.
- **Optionen (Vorschläge):** GPS einmal je Sekunde. Der Laufstart verlangt genauen Standort. Derselbe Sensor verbindet sich neu; das Rückwechselverbot gilt nur für den Wechsel auf ein anderes Gerät.
- **Status:** Open
- **Entscheidung:** —

### OQ-0065 — Lücken aus dem Plan für Phase 1
- **Frage:** Wie werden die in `work-packages/M1-PLAN.md` gefundenen kleinen Lücken L2 bis L6, L11 und L12 gefüllt?
- **Auslöser/Quellen:** Plan für M1; Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** FR-0002, FR-0029, FR-0037, FR-0041, FR-0043, FR-0193
- **Auswirkung:** blocking — war Phase 1, einzelne Punkte von WP05, WP06, WP08 und WP10.
- **Status:** Resolved
- **Entscheidung:** 2026-11-04, SRC-003: Lauferfahrung und Selbsteinschätzung sind bis Phase 2 zurückgestellt; Alter, Gewicht und Größe verlangen nur positive Zahlen. Persönliche Bestzeiten werden bis zu ihrer Definition nicht angezeigt. Die Einordnung vergleicht die Pace. Die Ausfallzeit nach einem Abbruch zählt zur Gesamtzeit, nicht zur Bewegungszeit. Die Route wird in Phase 1 ohne Kartenmaterial gezeichnet (für die Route abgelöst durch OQ-0074, 2026-11-07). Zonen sind lückenlos und aufsteigend, alte Läufe behalten ihre Zonenzeiten. Die Autopause ist standardmäßig aus. Ziel: DEC-0065.

### OQ-0066 — Weg zum FIT-Export
- **Frage:** Wie werden FIT-Dateien erzeugt, wenn die GPL-Verträglichkeit des Garmin-SDK ungeprüft ist?
- **Auslöser/Quellen:** Plan für M1 (L1); Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** FR-0182
- **Auswirkung:** blocking — war Phase 1, WP11.
- **Status:** Resolved
- **Entscheidung:** Eigener Kodierer ohne Garmin-Code, nach dem öffentlichen Dateiformat. Ob die Formatbeschreibung frei nutzbar ist, gehört zur rechtlichen Prüfung (OQ-0048). 2026-11-04, SRC-003. Ziel: FR-0182, DEC-0066.

### OQ-0067 — Rückfallsprache
- **Frage:** Welche Sprache zeigt die App bei einer Gerätesprache außer Deutsch und Englisch?
- **Auslöser/Quellen:** WP01, im Emulator mit Französisch geprüft; Maintainer, 2026-11-04, SRC-003.
- **Betroffene Anforderungen:** NFR-0006
- **Auswirkung:** non-blocking, Umsetzung in WP05.
- **Status:** Resolved
- **Entscheidung:** Englisch. 2026-11-04, SRC-003. Ziel: NFR-0006, DEC-0067.

### OQ-0068 — GPS-Rauschen im Stand
- **Frage:** Wie stark verfälscht GPS-Rauschen im Stand Strecke und Bewegungszeit, wenn die Geschwindigkeit aus Δs/Δt stammt? Braucht es eine Mindestdistanz, eine Glättung oder `Location.getSpeed()`?
- **Auslöser/Quellen:** WP03: Synthetischer Worst Case mit ±3 m abwechselnd bei 1 Hz über 60 s ergibt 360 m zusätzliche Strecke, der Zustand bleibt `moving`, PAR-014 und PAR-015 lösen nie aus. Echtes Rauschen ist autokorreliert und meist kleiner; der reale Effekt ist unbelegt (Validierungsbedarf in `docs/model-parameters.md`, OQ-0020).
- **Betroffene Anforderungen:** FR-0029, FR-0052
- **Auswirkung:** non-blocking — betrifft auch TRIMP über die Bewegungszeit.
- **Status:** Resolved
- **Entscheidung:** Bis zum Feldtest bleibt es bei der Spec, PAR-002 bis PAR-004, PAR-014 und PAR-015 bleiben unverändert. Laut R007 kommt der Worst Case in echten Daten nicht vor (Dach und Stativ bis 0,43 % Scheinstrecke; feldnah, nur übertragen, 1,41 %). Ein Gegenmittel ist nicht belegt; der Feldtest prüft `getSpeed` als Tor und als Integral. 2026-11-05, SRC-003. Ziel: FR-0029, FR-0052, DEC-0068.

### OQ-0069 — Grenzfälle des Tempowechsels und der Pulslücken
- **Frage:** Wie soll die Einschwingzeit bei Stop-and-Go wirken (20 s Lauf, 9 s Stand im Wechsel lösen nie aus) und bei einem Tempowechsel in einer GPS-Lücke über 240 s (wird nicht erkannt)? Braucht PAR-010 einen Soll-Takt (ein echter 10-s-Sensor besteht die Regel)? Braucht es eine Obergrenze für Zeitstempel in der Zukunft (ein solcher Wert sperrt den Kanal)?
- **Auslöser/Quellen:** WP03, Review; PAR-010, PAR-011.
- **Betroffene Anforderungen:** FR-0052
- **Auswirkung:** non-blocking, bis zu Feldtests gilt das in WP03 umgesetzte Verhalten (Maintainer, 2026-11-04, SRC-003).
- **Optionen:** So lassen, bis Feldtests zeigen, ob es vorkommt; eine neue Zahl wäre eine neue Parameterversion.
- **Status:** Open
- **Entscheidung:** —

### OQ-0070 — Pulsabdeckung bei unregelmäßigem Takt
- **Frage:** Trägt das Abdeckungsmaß aus K10 echte Sensoren? Synthetisch unterschätzt es bei wechselndem Takt und Datenbündeln (73 % und 10 %, nicht bewertet, obwohl nichts fehlt) und überschätzt bei viel Ausfall mit Schwankung (40 % Ausfall, ±250 ms: 66 % statt 59,7 %). Überwiegen Abstände von zwei Takten, wird der längere Abstand zum Takt, und ein Ausfall jedes dritten Werts bleibt unerkannt.
- **Auslöser/Quellen:** WP04, Review; K10, K11, OQ-0051. Die Zeitstempel-Schwankung echter Sensoren ist nicht gemessen.
- **Betroffene Anforderungen:** FR-0092
- **Auswirkung:** non-blocking, bis zu Feldtests gilt K10 (Maintainer, 2026-11-05, SRC-003). Ein Lauf kann fälschlich unbewertet bleiben oder als vollständig gelten.
- **Optionen:** Prüfung mit echten Sensoren im Feldtest; bis dahin so lassen.
- **Status:** Open
- **Entscheidung:** —

### OQ-0071 — Strecke während der erkannten Pause
- **Frage:** Soll Strecke während einer erkannten Pause ruhen? Das ändert das Verfahren, nicht einen Parameter, und brächte laut Rechnung in R007 rund 0,9 % weniger Scheinstrecke, wirkt aber nur, wenn die Pause auch auslöst.
- **Auslöser/Quellen:** R007, `research/R007-gps-rauschen-im-stand/RESULTS.md`.
- **Betroffene Anforderungen:** FR-0029
- **Auswirkung:** non-blocking, bis zur Antwort zählt die Strecke wie in WP03 umgesetzt.
- **Optionen:** Mit dem Feldtest entscheiden, zusammen mit `getSpeed`.
- **Status:** Open
- **Entscheidung:** —

### OQ-0072 — Prüfung auf echten Geräten für die Speicherung
- **Frage:** Hält die Speicherung auf echten Geräten, was der Emulator zeigt: Hardware-Keystore, Kosten von `kdf_iter` 64007 beim Öffnen, echter Stromausfall, Übertragung durch Google-Cloud und Herstellerwerkzeuge, `<cross-platform-transfer>`?
- **Auslöser/Quellen:** WP02, E2E nur im Emulator.
- **Betroffene Anforderungen:** SEC-0009
- **Auswirkung:** non-blocking, Prüfung im Feldtest beim Maintainer.
- **Optionen:** Feldtest auf mindestens einem Gerät mit Hardware-Keystore.
- **Status:** Open
- **Entscheidung:** —

### OQ-0073 — Aerobe Effizienz ohne Höhe
- **Frage:** Soll ein Abschnitt ohne Höhe oder Vertikalgenauigkeit die Stufe der aeroben Effizienz begrenzen, wie „vorläufig“ bei der VO₂max? Heute zählt er mit Steigung 0 ohne Begrenzung; mit Begrenzung wäre die Steigungsregel ohne Höhe wirkungslos.
- **Auslöser/Quellen:** WP09, Teil C.
- **Betroffene Anforderungen:** FR-0086
- **Auswirkung:** non-blocking, bis zur Antwort gilt der Wortlaut (Entscheidung des Maintainers vom 2026-11-06).
- **Optionen:** Wortlaut behalten; Stufe auf „vorläufig“ begrenzen; Abschnitt ausschließen.
- **Status:** Open
- **Entscheidung:** —

### OQ-0074 — Karte der Route
- **Frage:** Soll die App die Route auf einer Karte zeigen, während des Laufs, in Zusammenfassung und Detailansicht und als Miniatur in der Historie? Woher kommt das Kartenmaterial, wenn die App bisher kein Netz nutzt?
- **Auslöser/Quellen:** Wunsch des Maintainers vom 2026-11-07; SRC-001 §4.3 („GPS-Karte“), §5.1 („GPS-Route“); bisher OQ-0065 (ohne Kartenmaterial).
- **Betroffene Anforderungen:** FR-0027, FR-0037, FR-0040, FR-0041, FR-0204, SEC-0008
- **Auswirkung:** non-blocking, entschieden.
- **Optionen:** Kacheln aus dem Netz nach Einwilligung; nur selbst importierte Offline-Kartendatei; Miniaturen nur als Linie oder mit Kartenhintergrund; Live-Karte als eigene Seite oder dauerhaft unter den Werten.
- **Status:** Resolved
- **Entscheidung:** 2026-11-07, SRC-003: Karte in allen vier Ansichten. Kacheln aus dem Netz (vorgesehen OpenFreeMap mit OpenStreetMap-Daten, ohne Schlüssel) nur nach ausdrücklicher, abschaltbarer Einwilligung; ohne Einwilligung oder Netz die Route ohne Karte. Miniaturen in der Historie mit Kartenhintergrund. Live-Karte als eigene Seite zum Wischen. Ziel: FR-0204, ADR-0009, DEC-0069.



### OQ-0075 — Screen-Design und Marke
- **Frage:** Wie werden Screen-Design (`design/`) und Marke (`branding/`) übernommen, und was gilt, wo das Design Funktionen zeigt, die die Spec nicht hat, oder ihr widerspricht?
- **Auslöser/Quellen:** Design und Logo vom Maintainer, eingecheckt 2026-11-08; Wunsch, dass alle Seiten aussehen und sich verhalten wie im Design.
- **Betroffene Anforderungen:** FR-0025, FR-0028, FR-0029, FR-0040, FR-0041, FR-0043, FR-0204, FR-0205, FR-0206, FR-0207, FR-0208, FR-0209, FR-0210, FR-0211, FR-0212
- **Auswirkung:** non-blocking, entschieden.
- **Optionen:** Name mit oder ohne neue Paket-ID; 3 oder 4 Bereiche in der Navigation; „Heute“ reduziert oder mit Platzhaltern; Willkommen einmalig, immer oder nie; Autopause-Vorgabe; Beenden mit oder ohne Rückfrage; Zusatzfunktionen aus dem Design; Design oder Spec bei Widersprüchen; nur hell oder hell und dunkel.
- **Status:** Resolved
- **Entscheidung:** 2026-11-08, SRC-003: Alle Seiten folgen dem Design in Aussehen und Verhalten; bei Widersprüchen gilt die Spec in der Optik des Designs. Name „ramuri“ mit neuer Paket-ID `io.github.brokoskokoli.ramuri`. Navigation mit Heute, Verlauf, Fortschritt, Plan ab Phase 2, Einstellungen über das Profil-Symbol. „Heute“ in Phase 1 ohne Erholung, Plan und Wochenziel. Willkommen nur beim ersten Start. Autopause auf der Startseite, Vorgabe aus; Beenden nach Pause mit Rückfrage. Dazu in Phase 1: Kilometertabelle, Kilometermarken und Gefälle im Detail, Zeitraum mit Summen im Verlauf, Zentrieren und Werte-Blatt auf der Live-Karte, Umschalter Linie/Karte im Detail. Hell und dunkel. Ziel: FR-0205 bis FR-0212, DEC-0070.

### OQ-0076 — Nachschliff der Lauf-Seiten
- **Frage:** Was zeigt die Kilometertabelle bei einem sehr kurzen Restabschnitt mit unplausibler Pace, und was tut die Zurück-Taste im laufenden Lauf?
- **Auslöser/Quellen:** WP16 (Review): 2 m in 8,7 s ergeben 72 min/km; die Zurück-Taste hatte im laufenden Lauf keine Wirkung, was wie ein Hänger wirken kann.
- **Betroffene Anforderungen:** FR-0028, FR-0205, FR-0211
- **Auswirkung:** non-blocking, entschieden.
- **Optionen:** Rest-Pace immer, „–“ unter einer Schwelle oder kurzen Rest weglassen; Zurück-Taste ohne Wirkung, pausieren oder nachfragen.
- **Status:** Resolved
- **Entscheidung:** 2026-11-09, SRC-003: Liegt das Tempo eines Abschnitts unter der Stillstandsschwelle (PAR-014, 0,5 m/s), steht statt der Pace „–“; Länge und Zeit bleiben. Die Zurück-Taste soll im laufenden Lauf nicht ohne Wirkung bleiben (Maintainer); ausgelegt vom Orchestrator: Sie fragt, ob der Lauf pausiert werden soll. Ziel: FR-0028, FR-0211, WP17. Nachtrag 2026-11-09, SRC-003: Bei Pace, Puls und Punkten steht die Einheit in der Beschriftung, die Zahl bleibt groß; Anstieg und Gefälle behalten die Einheit an der Zahl (FR-0205, K40).

### OQ-0077 — Vorgaben zum Start von Phase 2
- **Frage:** Darf die Geh-Lauf-Abfolge vor der Rechtsprüfung in die App? Was zeigt die Karte „Erholung“ ohne Gesundheitsdaten? Was gilt bei den Widersprüchen zwischen Design und Spec bei Plan, Intervall und Zusammenfassung? Wie geht es mit Phase 3 weiter?
- **Auslöser/Quellen:** Go des Maintainers für M2, 2026-11-09; Abgleich von `design/screens/` mit PAR-105, PAR-107, PAR-142, PAR-169, PAR-193 bis PAR-198, FR-0107, FR-0141; ADR-0007.
- **Betroffene Anforderungen:** FR-0107, FR-0140, FR-0141, FR-0205
- **Auswirkung:** non-blocking, entschieden.
- **Optionen:** Abfolge bauen, selbst entwerfen oder weglassen; Texthinweis oder Zahl; Spec, Spec mit kurzen Phasennamen oder Design; Phase 3 nach Prüfung am Gerät, mit Testdaten oder zurückstellen.
- **Status:** Resolved
- **Entscheidung:** 2026-11-09, SRC-003: Die Abfolge kommt als austauschbarer Datensatz ohne Nennung des NHS in die App, ein Release bleibt bis OQ-0048 gesperrt. Die Karte „Erholung“ zeigt in der Basisstufe nur einen Texthinweis, ohne Zahl und Zustand. Bei den übrigen Widersprüchen gilt die Spec in der Optik des Designs; nur die Anzeige der Phasen nutzt die Kurzformen Einstieg, Grundlage, Aufbau, Spezifisch, Reduktion, Ziel. Phase 3 ist zurückgestellt, über sie wird nach den Erfahrungen mit dem Plan neu entschieden. Ziel: FR-0107, FR-0140, FR-0141, FR-0205, DEC-0071.

### OQ-0078 — Puls und HRV mit der Handykamera
- **Frage:** Soll die App Ruhepuls und RMSSD selbst mit der Handykamera messen, und soll Phase 3 darauf statt auf Uhrdaten aufbauen?
- **Auslöser/Quellen:** Versuch des Maintainers in `../puls` (Kamera-PPG, Algorithmus `algo-v0.4-frozen`, eine Vergleichsmessung gegen Polar H9: Puls < 0,5/min, RMSSD < 1 ms über 60 s).
- **Betroffene Anforderungen:** FR-0214, FR-0215
- **Auswirkung:** non-blocking, entschieden; Einzelheiten von Phase 3 nach R009.
- **Optionen:** Kamera-Messung für Ruhepuls (Phase 2) und Morgenmessung (Phase 3); Phase 3 weiter nur über Health Connect.
- **Status:** Resolved
- **Entscheidung:** 2026-11-09, SRC-003: Ruhepuls lässt sich in Profil und Einrichtung mit der Kamera messen, mit beruhigender Ruhephase (überspringbar), Pulskurve zum Justieren und Erklärbild (FR-0214, Phase 2). Für Phase 3 misst der Nutzer morgens 60 s Ruhepuls und RMSSD mit der Kamera, auf Wunsch mit Erinnerung (FR-0215). Phase 3 wird nach M2 auf dieser Grundlage geplant und nicht mehr zurückgestellt; Protokoll, Literatur und Regeln klärt R009. Neue Screens entwirft Claude Design im Stil von `design/`. Ziel: FR-0214, FR-0215, DEC-0073.
