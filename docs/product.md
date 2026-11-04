# Produktdefinition: Adaptive Running & Fitness App

**Status:** Draft (Quelle: SRC-001, Version 0.1 – Entwurf). Keine Aussage dieses Dokuments ist bisher fachlich freigegeben.

## Vision

Die App unterstützt Läufer dabei, ihre Trainingseinheiten aufzuzeichnen, ihre körperliche Leistungsfähigkeit zu verstehen und individuelle Trainingsziele zu erreichen. Sie kombiniert GPS-Aufzeichnung, Herzfrequenzmessung, sportwissenschaftliche Berechnungsmodelle und eine adaptive Trainingsplanung.

Zentrales Merkmal ist die **datengestützte Trainingsplanung**: Statt eines einmaligen, statischen Plans berücksichtigt die App fortlaufend die tatsächlichen Einheiten, die Leistungsentwicklung und, sofern Daten verfügbar sind, den aktuellen Erholungszustand.

**Produktbereich:** Laufaufzeichnung, Fitnessanalyse, Regeneration und adaptive Trainingsplanung.

## Nutzergruppen

Die Quelle spricht allgemein von Läufern und nennt ausdrücklich auch Einsteiger und Wiedereinsteiger (SRC-001 §14.1, §16.2). Eine weitere Segmentierung ist nicht dokumentiert (TBD).

## Zentrale Anwendungsfälle

| Anwendungsfall | Spezifikation |
|---|---|
| Profil einrichten | [profile.md](specs/profile.md) |
| Pulssensor oder Fitnessgerät nutzen | [sensors.md](specs/sensors.md) |
| Gesundheitsdaten importieren | [health-import.md](specs/health-import.md) |
| Lauf aufzeichnen und abschließen | [run-recording.md](specs/run-recording.md) |
| Historie und Statistiken ansehen | [history-statistics.md](specs/history-statistics.md) |
| Fitnesswerte verstehen | [vo2max.md](specs/vo2max.md), [aerobic-efficiency.md](specs/aerobic-efficiency.md), [heart-rate-zones.md](specs/heart-rate-zones.md) |
| Belastung und Erholung einschätzen | [training-load.md](specs/training-load.md), [readiness.md](specs/readiness.md), [energy-reserve.md](specs/energy-reserve.md) |
| Wettkampfzeit abschätzen | [performance-prediction.md](specs/performance-prediction.md) |
| Ziel setzen und Plan nutzen | [goals.md](specs/goals.md), [training-plan.md](specs/training-plan.md), [plan-adaptation.md](specs/plan-adaptation.md), [calendar.md](specs/calendar.md) |
| Empfehlungen nachvollziehen | [explanations.md](specs/explanations.md) |
| Daten exportieren, mit Strava teilen | [export-sync.md](specs/export-sync.md) |

## Grundprinzipien und Constraints

### CON-0001 — Zielplattformen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 Kopf, Z. 4
- **Verwandt:** OQ-0035, OQ-0063

Zielplattform ist Android, später optional iOS.

### CON-0002 — Technik ist nicht Gegenstand der Quelle
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 Kopf, Z. 6–7; Schluss, Z. 1444
- **Verwandt:** OQ-0023

Softwarearchitektur, Programmiersprachen, Frameworks, Datenbanktechnologien und technische Deployment-Entscheidungen sind in der Quelle ausdrücklich ausgeschlossen und damit nicht entschieden. Agenten dürfen sie nicht als entschieden behandeln.

### CON-0003 — Geräteunabhängigkeit
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1, Z. 17; §1.1 Nr. 1, Z. 23
- **Verwandt:** FR-0007, FR-0010

Keine Bindung an eine bestimmte Sportuhr oder einen Pulsmesser. Der Nutzer soll seine bevorzugten Pulssensoren, Fitnessuhren oder Kopfhörer verwenden können.

**Akzeptanzkriterien:**
- [ ] Grundfunktionen setzen kein Gerät eines bestimmten Herstellers voraus.

### CON-0004 — Funktionalität ohne Wearable
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1.1 Nr. 2, Z. 24
- **Verwandt:** FR-0035, FR-0155, ACC-01

GPS-Aufzeichnung, Laufstatistiken und einfache Trainingsplanung müssen allein mit dem Smartphone funktionieren.

**Akzeptanzkriterien:**
- [ ] Alle drei Funktionen sind ohne gekoppeltes Gerät nutzbar (einfache Planung ab Phase 2).

### CON-0005 — Transparente Berechnungen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1.1 Nr. 3, Z. 25
- **Verwandt:** FR-0053, FR-0059, FR-0179

Fitnesswerte sollen nachvollziehbar sein. Der Nutzer kann sehen, auf welchen Daten eine Schätzung beruht.

**Akzeptanzkriterien:**
- [ ] Siehe FR-0059.

### CON-0006 — Adaptive Trainingsplanung
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §1, Z. 19; §1.1 Nr. 4, Z. 26
- **Verwandt:** FR-0156

Trainingspläne passen sich an Fortschritte, verpasste Einheiten und Belastung an.

### CON-0007 — Optionale Gesundheitsdaten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1.1 Nr. 5, Z. 27
- **Verwandt:** FR-0022, FR-0119

Zusätzliche Daten verbessern die Analyse, dürfen aber keine Voraussetzung für die Grundfunktionen sein.

**Akzeptanzkriterien:**
- [ ] Ohne jede Gesundheitsdaten-Freigabe bleiben die Grundfunktionen nutzbar.

### CON-0008 — Datenhoheit
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1.1 Nr. 6, Z. 28
- **Verwandt:** FR-0182, FR-0192, SEC-0004, OQ-0023

Aufgezeichnete Läufe und Fitnessdaten müssen unabhängig von externen Fitnessplattformen nutzbar und exportierbar bleiben.

**Akzeptanzkriterien:**
- [ ] Ohne Konto bei einer externen Fitnessplattform lassen sich Läufe ansehen und exportieren.

### CON-0009 — Kennzeichnung von Unsicherheit
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §1.1 Nr. 7, Z. 29
- **Verwandt:** FR-0057, FR-0067

Geschätzte Werte und unvollständige Daten müssen klar erkennbar sein.

**Akzeptanzkriterien:**
- [ ] Jeder angezeigte geschätzte Wert ist als solcher erkennbar.

### CON-0010 — Unabhängigkeit von externen Plattformen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §20.2, Z. 1223–1225; §25 Nr. 14, Z. 1409
- **Verwandt:** FR-0182, FR-0185, SEC-0003, ACC-14

Die Strava-Verbindung ist vollständig optional. Die App darf nicht davon abhängig sein, dass Strava verfügbar ist, und bleibt ohne externe Fitnessplattform nutzbar.

**Akzeptanzkriterien:**
- [ ] Bei nicht erreichbarem Strava bleiben alle Funktionen außer dem Upload nutzbar (ACC-14).

## Nichtziele und ausdrückliche Abgrenzungen

- Keine medizinische Diagnose (FR-0118).
- Die VO₂max-Schätzung ist keine Messung (FR-0067), CTL ist keine gemessene Fitness (FR-0100), die Energiereserve ist keine physikalische Energie (FR-0124).
- Qualitätsstufen sind keine statistisch validierten Genauigkeitsangaben (FR-0054).
- Die Machbarkeitseinschätzung ist keine Erfolgsgarantie (FR-0154).
- Keine pauschale Trainingssteigerung gilt als garantiert sicher (FR-0149).
- Technische Festlegungen gehören nicht zur Quelle (CON-0002).

## Fachliche Entscheidungen

Die Tabelle fasst Entscheidungen aus der Quelle und vom Maintainer (SRC-003) zusammen. Maßgeblich ist jeweils die verlinkte Anforderung.

| ID | Entscheidung | Maßgeblich | Vorbehalt |
|---|---|---|---|
| DEC-0001 | Readiness hat zwei Stufen: Basis ohne Uhr, erweitert mit Gesundheitsdaten | FR-0105 | — |
| DEC-0002 | Die Trainingsplanung ist regelbasiert | FR-0147 | — |
| DEC-0003 | CTL heißt „langfristiges Belastungsniveau“ und ist keine Fitness | FR-0100 | — |
| DEC-0004 | TRIMP und sRPE werden getrennt geführt und nicht ohne Kalibrierung addiert | FR-0096 | OQ-0015 |
| DEC-0005 | Energiereserve und Training Readiness bleiben getrennt | FR-0127 | — |
| DEC-0006 | Fremde VO₂max-Werte werden nie in die eigene Zeitreihe übernommen (OQ-0033) | FR-0024 | — |
| DEC-0007 | Edwards-TRIMP ist die erste Belastungsvariante | FR-0092 | Entschieden (OQ-0002); Startvariante, austauschbar (NFR-0005) |
| DEC-0008 | ACSM und Herzfrequenzreserve bilden den ersten VO₂max-Schätzer | FR-0069, FR-0071 | Entschieden (OQ-0001); Kalibrierung für Phase 4 vorgesehen |
| DEC-0009 | Die App stellt keine medizinische Diagnose | FR-0118 | OQ-0026 |
| DEC-0010 | Ein Ziel wird nicht ohne Zustimmung geändert | FR-0168 | — |
| DEC-0011 | Vier Qualitätsstufen: vorläufig, ausreichend, gut, nicht bestimmbar | FR-0053 | OQ-0019 |
| DEC-0012 | Vier verbindliche Entwicklungsphasen; Datenschutz, Löschung und Gesamtexport in Phase 1 (Maintainer, SRC-003) | Abschnitt „Phasen“ | Entschieden (OQ-0017, OQ-0041) |
| DEC-0013 | Prognosen beruhen auf tatsächlichen Leistungen (Riegel-Modell); die VO₂max allein dient nicht der verbindlichen Vorhersage | FR-0129, FR-0130, FR-0134 | OQ-0008; zur Referenz siehe DEC-0039 |
| DEC-0014 | Daten bleiben lokal, ohne Konto und eigenen Server (Maintainer, SRC-003) | [ADR-0001](architecture/adr/ADR-0001-nur-lokale-datenhaltung.md) | Entschieden (OQ-0023) |
| DEC-0016 | Inhalt und Intensität künftiger Einheiten passt die App selbst an; Termine nur nach Bestätigung (Maintainer, SRC-003) | FR-0156, FR-0176 | Entschieden (OQ-0011) |
| DEC-0017 | Fehlende Pulswerte machen betroffene Funktionen nicht verfügbar, mit Hinweis zur Eingabe (Maintainer, SRC-003) | FR-0055, FR-0060, FR-0068 | Entschieden (OQ-0012) |
| DEC-0018 | Keine Pflichteingaben zum Laufen; beim Plan sind nur die Trainingstage Pflicht (Maintainer, SRC-003) | FR-0001, FR-0002 | Entschieden (OQ-0010) |
| DEC-0019 | Zonengrenzen: unten inklusive; unter 50 % HFmax Gewicht 0; über 100 % Zone 5 mit Hinweis (Maintainer, SRC-003) | FR-0062, FR-0092 | Entschieden (OQ-0014) |
| DEC-0020 | Das bevorzugte Gerät hat Vorrang vor anderen Pulsquellen (Maintainer, SRC-003) | FR-0019 | Entschieden (OQ-0018) |
| DEC-0021 | Laufende Sicherung mit Wiederaufnahme; kein Lauf ohne GPS in Phase 1 (Maintainer, SRC-003) | FR-0193, FR-0194, FR-0195 | Entschieden (OQ-0021) |
| DEC-0022 | Aerobe Effizienz: 65–75 % der Reserve, Median, 4 gegen 4 Wochen (Maintainer, SRC-003) | FR-0085, FR-0087 | Entschieden (OQ-0036) |
| DEC-0023 | Alle Algorithmen sind austauschbar; der Nutzer wählt in Phase 2 sein Belastungsmodell (Maintainer, SRC-003) | NFR-0005, FR-0197 | Entschieden (OQ-0043, OQ-0045) |
| DEC-0024 | In Phase 2 gibt es einen Laufbandmodus mit einstellbarer Bandgeschwindigkeit (Maintainer, SRC-003) | FR-0196 | OQ-0042 |
| DEC-0025 | Daten und Zugangsdaten verschlüsselt; System-Backups immer aus (Maintainer, SRC-003) | SEC-0009, SEC-0010 | Entschieden (OQ-0024, OQ-0056) |
| DEC-0026 | Einwilligung je Plattform-Import und Strava; beim Widerruf fragt die App nach dem Löschen (Maintainer, SRC-003) | SEC-0001, SEC-0004, SEC-0007 | Entschieden (OQ-0025); rechtliche Prüfung OQ-0048 |
| DEC-0027 | Rohdaten bleiben; Neuberechnung nach Bestätigung (Maintainer, SRC-003) | FR-0058 | Entschieden (OQ-0031) |
| DEC-0028 | Gesamtexport als Archiv mit Reimport in Phase 1 (Maintainer, SRC-003) | FR-0192, FR-0198 | Entschieden (OQ-0032) |
| DEC-0029 | Startwerte der Modellparameter als Version 1 freigegeben; vorläufig und nicht validiert (Maintainer, SRC-003) | [model-parameters.md](model-parameters.md) | Entschieden (OQ-0019); Validierung OQ-0020 |
| DEC-0030 | Der TRIMP des gewählten Modells ist die Hauptskala; sRPE wird persönlich umgerechnet (Maintainer, SRC-003) | FR-0097 | Entschieden (OQ-0015, OQ-0046) |
| DEC-0031 | Wählbare Belastungsmodelle: Edwards und Banister (Maintainer, SRC-003) | FR-0197 | Entschieden (OQ-0045) |
| DEC-0032 | ATL und CTL starten bei 0 und gelten zunächst als vorläufig (Maintainer, SRC-003) | FR-0098, FR-0103 | Entschieden (OQ-0016, OQ-0046) |
| DEC-0033 | Trainings lassen sich manuell nachtragen, auch andere Sportarten (Maintainer, SRC-003) | FR-0199 | Entschieden (OQ-0022) |
| DEC-0034 | Phase 2 deckt Ziele bis zum Halbmarathon und offene Fitnessziele ab (Maintainer, SRC-003) | FR-0135 | Entschieden (OQ-0004) |
| DEC-0035 | Automatische Anpassung nach Planungsregeln, innerhalb der Grenzen des Nutzers (Maintainer, SRC-003) | FR-0156, FR-0158 | Entschieden (OQ-0005) |
| DEC-0036 | Offene Ziele laufen in Blöcken von 4 Wochen ohne Machbarkeitsprüfung (Maintainer, SRC-003) | FR-0137, FR-0154 | Entschieden (OQ-0027) |
| DEC-0037 | Begriffe: Leistungsniveau im Profil, Laufleistung (Watt) bei Sensoren, Referenzleistung bei Prognosen (Maintainer, SRC-003) | FR-0002, FR-0021, FR-0130 | Entschieden (OQ-0013) |
| DEC-0038 | Trainingstage und Dauer: Standard im Profil, für den Plan gilt der Wert am Ziel (Maintainer, SRC-003) | FR-0002, FR-0136 | Entschieden (OQ-0038) |
| DEC-0039 | Prognosen nur mit Referenzleistung (Maintainer, SRC-003) | FR-0129 | Entschieden (OQ-0034) |
| DEC-0040 | Warnsignale nur aus Selbstauskunft; Messwerte werden nicht medizinisch gedeutet (Maintainer, SRC-003) | FR-0163 | Entschieden (OQ-0026); rechtliche Prüfung OQ-0048 |
| DEC-0041 | Akustische Hinweise als einzeln schaltbare Sprachansagen (Maintainer, SRC-003) | FR-0031 | Entschieden (OQ-0044); Sprachen OQ-0035 |
| DEC-0042 | Readiness-Zahl nur mit HRV, Schlaf und persönlicher Referenz (Maintainer, SRC-003) | FR-0109 | Entschieden (OQ-0006) |
| DEC-0043 | Feste Readiness-Bänder; die Basisstufe gibt nur Texthinweise (Maintainer, SRC-003) | FR-0116 | Entschieden (OQ-0029) |
| DEC-0044 | Energiereserve nur mit kontinuierlichen Daten (Maintainer, SRC-003) | FR-0120, FR-0121 | Entschieden (OQ-0007) |
| DEC-0045 | Import ohne eigenen Server, Umfang siehe DEC-0049; fremde VO₂max-Werte nie zusammenführen (Maintainer, SRC-003) | FR-0024, FR-0200 | Entschieden (OQ-0033); Umfang siehe DEC-0049 |
| DEC-0046 | Reservezonen bis Phase 3, nur Riegel-Prognose, Uhr nur als Pulsquelle; Erweiterungen in Phase 4 (Maintainer, SRC-003) | FR-0065, FR-0130, FR-0009 | Entschieden (OQ-0003, OQ-0008, OQ-0009) |
| DEC-0047 | App auf Deutsch und Englisch, Kilometer und optional Meilen (Maintainer, SRC-003) | NFR-0006 | Entschieden (OQ-0035) |
| DEC-0048 | Validierung im Feldtest ohne Release-Gate; CTL überall „langfristiges Belastungsniveau“; Laufbandmodus mit vorläufiger VO₂max (Maintainer, SRC-003) | NFR-0004, FR-0100, FR-0196 | Entschieden (OQ-0020, OQ-0039, OQ-0042) |
| DEC-0049 | Hersteller-Import: nur Health Connect, Google Health API zurückgestellt; kein eigener Server, kein ausgeliefertes Secret (Maintainer, SRC-003) | FR-0200, ADR-0001 | Entschieden (OQ-0047) |
| DEC-0050 | Planungsregeln und Startwerte als Version 1 freigegeben; Energiereserve bleibt ausgeblendet bis zur Kalibrierung (Maintainer, SRC-003) | [planning-rules.md](planning-rules.md) | Entschieden (OQ-0028, OQ-0030, OQ-0046) |
| DEC-0051 | Strava-Direktanbindung zurückgestellt; Phase 1 bietet Export und Teilen (Maintainer, SRC-003) | FR-0185, FR-0201 | Entschieden (OQ-0049) |
| DEC-0052 | Archiv immer verschlüsselt; Reimport nur auf leerer App mit neuer Einwilligung (Maintainer, SRC-003) | SEC-0011, FR-0198 | Entschieden (OQ-0050) |
| DEC-0053 | TRIMP ab 80 % Pulsabdeckung, darunter nicht bewertet (Maintainer, SRC-003) | FR-0092 | Entschieden (OQ-0051) |
| DEC-0054 | Schrittfrequenz aus dem Smartphone; Banister mit optionalem Profilfeld; ATL und CTL an unbewerteten Tagen unverändert; Warnsignale gelten bis zur Aufhebung (Maintainer, SRC-003) | FR-0202, FR-0197, FR-0098, FR-0203 | Entschieden (OQ-0052 bis OQ-0055) |
| DEC-0055 | Regeln für Phase 2 und 3 als Version 1 freigegeben, mit den Festlegungen aus OQ-0057 (Maintainer, SRC-003) | [phase-2-3-rules.md](phase-2-3-rules.md) | Entschieden (OQ-0057); Validierung OQ-0020 |
| DEC-0056 | Readiness bremst den Plan; Warnsignal heißt nur Ruhetage; leere Tage ohne Zusage ändern ATL und CTL nicht; Sonstiges zählt nur für Belastung und Pausenende (Maintainer, SRC-003) | FR-0203, FR-0103, FR-0199, PAR-173 | Entschieden (OQ-0058) |
| DEC-0057 | Modellparameter, Planungsregeln und Regeln für Phase 2 und 3 als Version 2 freigegeben; löst Version 1 aus DEC-0029, DEC-0050 und DEC-0055 ab. Enthält die Wertänderungen aus R001 bis R003, die Geh-Lauf-Abfolge über 9 Wochen ohne Entlastung (Empfehlung ohne ausdrückliche Präferenz, änderbar), +10 % je Zyklus als Regelfall bei „Aufbau“ und Regellängen je Stufe. Ergänzt: Regelziel je Zyklus in allen Stufen (5 km und offene Ziele +10 %, 10 km +12,5 %, Halbmarathon +15 %) mit den Obergrenzen als Deckel, kürzeste Längen statt Regellängen, „ambitioniert“ bei genau dieser Länge und „realistisch“ nach dem Regelziel, Start nach der Abfolge mit 3 × 30 min, eigene nicht validierte RPE-Skala statt der Borg-Anker (Maintainer, SRC-003) | [model-parameters.md](model-parameters.md), [planning-rules.md](planning-rules.md), [phase-2-3-rules.md](phase-2-3-rules.md) | Entschieden (OQ-0059); Validierung OQ-0020 |
| DEC-0058 | **Aufgehoben durch DEC-0061, soweit Planregeln.** Letzte Korrekturrunde aus R004, Version 2 danach eingefroren; künftige Änderungen brauchen eine neue Version. An der Zielspitze hält der Plan den Umfang, offene Ziele steigern 3 Zyklen und halten dann, bis der Nutzer mehr wählt. Zielspitze 5 km und 10 km mindestens die Dauer im lockeren Tempo, mindestens 30 und 60 min; Halbmarathon 90 min, bis 120 min für langsame Läufer. Distanzziele ohne intensive Einheiten und ohne Phase „Spezifisch“. Zeitziele nur mit rechtzeitig erreichbaren 160 min „realistisch“; die 160 min gelten für alle Stufen. Die Geh-Lauf-Abfolge bleibt die empfohlene 9-Wochen-Variante (Maintainer, SRC-003) | PAR-052, PAR-054, PAR-071, PAR-084, PAR-125, PAR-191, FR-0148, FR-0154 | Entschieden (OQ-0059); Validierung OQ-0020 |
| DEC-0059 | **Aufgehoben durch DEC-0061, soweit Planregeln; RPE-Wörter und Hinweis auf den 5-km-Test bleiben.** Gezielte Prüfung nach R004: Planungsregeln und Regeln für Phase 2 und 3 als Version 3 eingefroren, Modellparameter bleiben Version 2. Die erlaubte Verbesserung insgesamt aus PAR-083 sinkt über 12 Wochen nie unter den Wert bei 12 Wochen, der Hinweis auf den 5-km-Test folgt PAR-117; beides Empfehlungen ohne ausdrückliche Präferenz, änderbar. Das 5-km-Zeitziel bleibt ab 3 × 30 min bei 33 Wochen, die RPE-Wörter sind bestätigt (Maintainer, SRC-003) | PAR-083, PAR-084, PAR-105, PAR-117, PAR-143, FR-0129, FR-0154 | Entschieden (OQ-0059); Validierung OQ-0020 |
| DEC-0060 | Energiereserve von Phase 3 auf Phase 4 verschoben, um den Umfang zu verringern. Ihre Regeln bleiben als Startwerte erhalten, die Anforderungen sind bis zur Freigabe von Phase 4 `Draft` (Maintainer, SRC-003) | FR-0119 bis FR-0127, PAR-091 bis PAR-099, PAR-151 bis PAR-154 | Entschieden |
| DEC-0061 | Einfacher Trainingsplan statt präziser Kurven: Ziel, Stand, Lauftage und Regler; +10, +7 oder +5 % je Woche nach Wochenzeit; jede 4. Woche leichter; alle 2 Wochen Nachfrage; von selbst nur nach unten; alles änderbar. Hebt die Planregeln aus DEC-0057, DEC-0058 und DEC-0059 auf (Maintainer, SRC-003) | PAR-192 bis PAR-206, FR-0148, FR-0154, FR-0156 | Entschieden (OQ-0060); Startwerte zum Testen, Validierung OQ-0020 |
| DEC-0062 | Wiederaufnahme: fortsetzen mit markierter Lücke oder als beendet speichern, ohne Frist (Maintainer, SRC-003) | FR-0193 | Entschieden (OQ-0061) |
| DEC-0063 | Schlüsselverlust: erklären, Neubeginn und Reimport anbieten, alte Datei erst nach Bestätigung löschen (Maintainer, SRC-003) | SEC-0009 | Entschieden (OQ-0062) |
| DEC-0064 | Vertriebsweg vorerst offen; technische Play-Vorgaben werden eingehalten (Maintainer, SRC-003) | ADR-0002 | Entschieden (OQ-0063) |
| DEC-0065 | Kleine Lücken für Phase 1 nach Empfehlung gefüllt, im Einzelnen in OQ-0065 (Maintainer, SRC-003) | FR-0002, FR-0029, FR-0037, FR-0041, FR-0043, FR-0061, FR-0193 | Entschieden (OQ-0065) |
| DEC-0066 | FIT-Export über eigenen Kodierer ohne Garmin-Code (Maintainer, SRC-003) | FR-0182 | Entschieden (OQ-0066) |
| DEC-0067 | Rückfallsprache Englisch bei jeder anderen Gerätesprache (Maintainer, SRC-003) | NFR-0006 | Entschieden (OQ-0067) |

## Phasen

Die Quelle überschreibt diese Einteilung mit „Empfohlener Funktionsumfang“. Der Maintainer hat sie für verbindlich erklärt und Datenschutz, Löschung und Gesamtexport Phase 1 zugeordnet (OQ-0017). Die übrigen Zuordnungen stehen unter OQ-0041.

| Phase | Ziel | Enthalten laut Quelle |
|---|---|---|
| 1 – Laufaufzeichnung und grundlegende Fitnessanalyse | Vollständig verwendbare Lauf-App mit eigener Trainingshistorie und ersten Fitnessberechnungen | Nutzerprofil; kompatible Bluetooth-Pulssensoren; GPS-Laufaufzeichnung; Live-Anzeige der Herzfrequenz; Trainingshistorie; Routen und Statistiken; Herzfrequenzzonen; VO₂max-Schätzung; aerober Fitness-Trend; TRIMP-Berechnung; FIT-/TCX-/GPX-Export; optionale Strava-Synchronisierung |
| 2 – Adaptiver Trainingscoach | Trainingsziele und personalisierte Trainingsplanung | Trainingsziele; Trainingskalender; individuelle Trainingspläne; strukturierte Einheiten; subjektive Trainingsbelastung; ATL-/CTL-Verlauf; Leistungsprognosen; automatische Plananpassungen; erklärbare Empfehlungen |
| 3 – Erweiterte Gesundheits- und Erholungsanalyse | Weitere Personalisierung mit Gesundheitsdaten | Import von Schlaf- und HRV-Daten; individuelle Ruhepuls- und HRV-Referenzwerte; erweiterte Training Readiness; erholungsbasierte Trainingsanpassungen; Energiereserve, sofern ausreichend kontinuierliche Daten verfügbar sind |
| 4 – Erweiterter persönlicher Trainingscoach | Mögliche Zusatzfunktionen | Individuell kalibrierte Fitnessmodelle; erweiterte Leistungsprognosen; Planung für mehrere gleichzeitige Ziele; weitere Sportarten; optionale sprachbasierte Bedienung; optionaler KI-Dialog für Trainingsfragen; erweiterte Anbindung verschiedener Smartwatches |

Zusätzlich vom Maintainer zugeordnet (OQ-0017, OQ-0041):

- **Phase 1:** Datenschutz, Löschung, Gesamtexport, Reimport, Teilen von Exportdateien, Runden, Autopause, Sprachen und Einheiten, Live-Anzeige von Rundenzeiten, Höhenmetern und Schrittfrequenz
- **Phase 2:** Laufbandmodus, Wahl des Belastungsprofils, akustische Hinweise, Herzfrequenzwarnung, übrige subjektive Angaben, Export von Zusatzmetriken, Basis-Erholungseinschätzung
- **Phase 4:** Energiereserve, abweichend von der Tabelle oben aus Phase 3 verschoben (DEC-0060)
- **Phase 3:** weiterer Datenimport
- **Phase 4:** erweiterte Sensordaten, Herzfrequenzdrift, Kennzeichnung der Messmethoden

Die Strava-Direktanbindung aus Phase 1 ist zurückgestellt; Phase 1 bietet Export und Teilen (OQ-0049).

Die Funktionen der Phase 4 sind nur als mögliche Zusatzfunktionen genannt und deshalb nicht als Anforderungen erfasst, außer sie werden an anderer Stelle der Quelle beschrieben.

## Begriffe

| Begriff | Bedeutung | Hinweis |
|---|---|---|
| HFmax, HFRuhe | Maximale Herzfrequenz, Ruheherzfrequenz | |
| HFR, r | Herzfrequenzreserve; relative Auslastung der Reserve | FR-0060 |
| Zone | Bereich der Herzfrequenz | **Zwei Modelle:** Reservezonen (FR-0062) und TRIMP-Zonen auf HFmax-Basis (FR-0093). Immer das Modell nennen. |
| VO₂max | Maximale Sauerstoffaufnahme; in der App immer eine Schätzung, außer bei Laborwerten | FR-0067, FR-0083 |
| TRIMP | Training Impulse, relative Belastungspunkte | FR-0092 |
| RPE, sRPE | Subjektive Anstrengung 0–10; Dauer · RPE | FR-0095 |
| ATL, CTL, TSB | Kurzfristige Belastung, langfristiges Belastungsniveau, Training Stress Balance | FR-0098 bis FR-0101 |
| HRV, RMSSD, SDNN | Herzfrequenzvariabilität und zwei nicht identische Maße dafür | FR-0115 |
| Training Readiness | Einschätzung der Trainingsbereitschaft | FR-0105 |
| Energiereserve | Modellierter Zustand 0–100, Body-Battery-ähnlich | FR-0122 |
| Qualitätsstufe | vorläufig, ausreichend, gut, nicht bestimmbar; „Konfidenz“ geht darin auf (OQ-0019) | FR-0053 |
| Leistungsniveau | Aktuelle Zeit über eine Distanz oder Selbsteinschätzung; im Konzept „Aktuelle Laufleistung“ | OQ-0013 |
| Laufleistung (Watt) | Sensorwert, nur bei Sensoren verwendet | OQ-0013 |
| Referenzleistung | Wettkampf- oder Testzeit als Grundlage von Prognosen | OQ-0013, FR-0129 |
| Pace | Zeit pro Kilometer | FR-0050 |
| Grundfunktionen | In der Quelle nicht abschließend definiert; mindestens die in CON-0004 genannten Funktionen | |
