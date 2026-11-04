# R002 Nachbesserung: Umsetzung der Befunde

Bezug: [R002-planning-rules.md](R002-planning-rules.md). Geändert wurde nur [planning-rules.md](../../planning-rules.md). Stand: 2026-11-04.

**Ergebnis:** Von 30 Befunden sind 22 vom Typ `Beleg/Text`, 8 vom Typ `Wert`. Von den 22 sind 18 voll und 4 teilweise umgesetzt; kein Befund war insgesamt falsch. Die 8 `Wert`-Befunde sind auftragsgemäß nicht umgesetzt. Unter den Blockern gibt es keinen `Beleg/Text`-Befund.

**Prüfweg:** Studien über die NCBI-E-Utilities als Abstract, Volltexte und Anbieterseiten als Rohtext abgerufen und gezielt durchsucht, Rechnungen selbst nachgerechnet. Geprüft ist maschinell: ID, Parameter, `Startwert` und `Anforderung` aller 51 PAR-Zeilen sind unverändert. Geändert sind nur `Art` und `Begründung und Quelle`, dazu Lesehilfe-Tabelle R1 und R3, Teil D, `Entscheidungsbedarf`, `Quellen`, `Nicht abrufbar`, `Validierungsbedarf`.

**Version:** Der Status bleibt „Version 1, Stand 2026-11-03“, weil kein freigegebener Wert geändert wurde und [index.md](../../index.md) sowie OQ-0028 auf Version 1 verweisen. Ob Begründungen nach NFR-0001 eine neue Version auslösen, entscheidet der Maintainer.

## `Beleg/Text`

| Befund | Status | Quelle geprüft | Was umgesetzt ist, und Grund für Abweichungen |
|---|---|---|---|
| M1 | **Teilweise** | Nachgerechnet | R3 und PAR-074 berichtigt. **Nicht umgesetzt:** die Festlegung auf das rollende Mittel in Lesehilfe und PAR-073, weil sie Ergebnisse ändert und der Auftrag das ausschließt. R3 zeigt deshalb beide Mittel. Der Befund stimmt im Kern, seine Zahlen sind aber ungenau: Muster Mo, Mi, Fr ergibt −19,6 und −36,9, also −20 und −37 statt −19 und −36. Seine Spanne ist zu eng: über alle Verteilungen auf 3 Tage −17 bis −21 und −33 bis −40. Im Kalenderwochen-Mittel ergeben sich bei Mo, Mi, Fr −16 und −31; nur bei täglich gleicher Last −14 und −25, in der Nähe der alten Werte. |
| M6 | Umgesetzt | L2, L3, L4, L9, Damsted 2019 | Alle Zitate stimmen. Die Evidenz steht nun in beiden Richtungen in PAR-050 und PAR-052, Damsted 2019 ist L71. Ergänzt: Die 3 Arbeiten in L4 enthalten nach den Zahlen L2 und L3, sind also nicht unabhängig davon. Der Satzteil „die Wochengrenzen bleiben darunter“ blieb stehen, siehe B1. |
| M7 | **Teilweise** | L10, Rechnung | Art auf `Heuristik`, Begründung nennt die tatsächliche Spanne. **Nicht umgesetzt:** das Ersetzen von „rund 48 h“, denn die Wörter stehen in der Spalte `Startwert`. Sie bleiben stehen; die Begründung ordnet sie ein, `Entscheidungsbedarf` nennt sie. Abweichend vom Befund: gut 24 bis knapp 72 h statt „etwa 25 bis über 60 h“. |
| M8 | Umgesetzt | L11, L12, L13 | Art `Heuristik`, Herkunft der 20 % genannt. |
| M9 | **Teilweise** | Relph 2023, L15 | Relph als L72, Sprung in Woche 5 (8 auf 20 min) und Trennung der Art umgesetzt. **Nicht umgesetzt:** die Festlegung, ob PAR-056 während der Abfolge gilt, und das aktive Anbieten der Wiederholung. Beides sind neue Regeln und ändern den `Startwert`; die Lücke steht offen in der Begründung und in `Entscheidungsbedarf`. |
| M10 | Umgesetzt | L30, FR-0092 | r = 0,84 und 0,76 genannt. Das Abstract nennt nur die Zonen 1, 2 und 4; die Gleichsetzung ist als eigene Einordnung gekennzeichnet. |
| M11 | **Teilweise** | L25, Rechnung, PAR-178 | Lücke in PAR-055, PAR-089, PAR-090 genannt, Start bei 0 in R1 und PAR-074 ergänzt. −30,0 für Aufbau an Tag 126 bestätigt. Ergänzt: −25 Einsteiger, −35 Erfahren; PAR-178 gibt vor Tag 126 nur Text. Der Befund sagt „nur Teilnahme und Selbstauskunft“; es wirken auch PAR-052 und PAR-053. **Nicht umgesetzt:** das Ende des Rückfalls in PAR-090, eine neue Regel in der Spalte `Startwert`. |
| M12 | Umgesetzt | `/health/app-verification`, `/health/setup`, Codelab, `/health/about`, `/health/scopes`, L59, L61, L62, Android-Anleitung | Kosten, Dauer, Pflicht und Widerspruch zu L62 eingetragen, Quelle für Restricted korrigiert. Android-Anleitung gelesen: Sie zeigt Android-Client ohne Secret, also bleibt der Weg denkbar, „Wohl ja“ wurde zu „Offen, technisch denkbar“. Dass der Betrag jährlich anfällt, steht nicht wörtlich dort; es ist als Planungsannahme gekennzeichnet. OQ-0047 bleibt. |
| M13 | Umgesetzt | Garmin-PDF, FAQ | `client_secret` und PKCE bestätigt. Die PDF-Metadaten nennen 2025-06-11; das PDF ist also älter als der Neustart, was der Befund nur vermutete. Das steht in der Zeile. |
| M14 | Umgesetzt | Suunto FAQ, How to start | Bestätigt. Ergänzt, was der Befund auslässt: Die FAQ nennt die Anmeldung „optimized for mobile use“, aber kein SDK. |
| S1 | Umgesetzt | Gabbett 2016 | Als Entsprechung und ausdrücklich nicht als Beleg genannt. |
| S2 | Umgesetzt | ProjectRun21, Studiendesign | 784 und 14 Wochen bestätigt. Abweichend vom Befund steht nicht „die Teilnehmer liefen schon“: Der Einschluss verlangt keinen Mindestumfang („Runners at all levels“). |
| S3 | Umgesetzt | Kluitenberg 2016 | In PAR-054, PAR-062, PAR-064 mit Einschränkung. |
| S4 | Umgesetzt | Abstract, Volltext gezielt | Zahlen bestätigt. Ergänzt: nur kurze Interventionen und Hochtrainierte, beides laut Autoren nicht trennbar; L12 und L13 sind darin enthalten. Punkt aus `Nicht abrufbar` gestrichen. |
| S5 | Umgesetzt | Lesehilfe | PAR-050, PAR-072, PAR-091 `abgeleitet`, PAR-065 getrennt, eigene Wahl in PAR-064 und PAR-070 ergänzt. |
| S6 | Umgesetzt | L16, L17, L18 | Unterschied und eigene Wahl genannt. L18 senkt die Häufigkeit leicht, der `Startwert` hält sie; das bleibt. |
| S8 | Umgesetzt | Simulation | Richtung stimmt. Der Faktor 1,25 gilt erst asymptotisch. Simulation mit Normalverteilung: ±34 / ±24 / ±17 statt ±35 / ±25 / ±18; ±20 % bei rund 16 Läufen bestätigt. Der Wert 10 bleibt. |
| S9 | Umgesetzt | L12 | Ausgangsniveau genannt, Grenzen für Einsteiger als eigene Annahme. |
| S10 | Umgesetzt | Rechnung | Eigenschaft in PAR-094, PAR-096, PAR-099 und `Validierungsbedarf`. Die Spanne des Befunds gilt nur für eine Einheit früh am Tag: −2,2 Punkte; 1 h vor dem Schlaf −5,1. Im Text steht deshalb −2 bis −5. |
| S12 | Umgesetzt | Lizenzvertrag, L49 | Kosten mit Vorbehalt eingetragen, Stand 2025-08-22. |
| S13 | Umgesetzt | L67, L69 | Ergänzt: Die Signatur gilt laut L67 für Vertragspartner. PKCE: 0 Treffer. |
| S14 | Umgesetzt | L47 | Abschnitt „Limited Use“ bestätigt; der Folgesatz untersagt alle anderen Weitergaben. Befund für ADR-0001 neu gefasst. |

## `Wert`: nicht umgesetzt

| Befund | Grund |
|---|---|
| B1, B2, M2, M3, M4, M5, S7, S11 | Typ `Wert`, Entscheidung beim Maintainer. Nicht nachgeprüft. |

## Offen für den Maintainer

**OQ-0059:** Die Frage ist offen und nennt Entscheidungen zu B1, B2 und M5 sowie: „Alle übrigen Wertvorschläge der Berichte werden übernommen, sofern sie keiner Entscheidung widersprechen. Noch einzutragen.“ Diese Nachbesserung trägt davon auftragsgemäß nichts ein. Ob die vier Punkte unten darunter fallen, muss der Maintainer sagen; `Entscheidungsbedarf` im Dokument verweist deshalb auf OQ-0059.

**Berühren Werte, aus `Beleg/Text`-Befunden:**
1. M1: 7-Tage-Mittel rollend oder je Kalenderwoche. Bei Kalenderwoche hängt von der Verteilung ab, ob ein verdoppelter Umfang auslöst.
2. M7: „rund 48 h“ in der Spalte `Startwert` von PAR-059.
3. M9: PAR-056 während der NHS-Abfolge, Wiederholung aktiv anbieten.
4. M11: Ende des Rückfalls in PAR-090.

**Zur Kenntnis:**
- `docs/phase-2-3-rules.md`, PAR-178, zitiert „nach R3 […] erst TSB% −14“. Der Wert ist nun überholt (rollend −20, Kalenderwoche −16). Die Datei lag außerhalb des Auftrags.
- PAR-052 sagt weiter „die Wochengrenzen bleiben darunter“. Das stimmt nur gegenüber der Bezugswoche; B1 zeigt +37,5 bis +50 % nach der Entlastung.
- PAR-084 enthält weiter das Beispiel, das M5 als zu kurz gedacht einstuft.
- R2 war kein Befund und blieb unverändert. Meine Rechnung liegt je nach Verteilung bis zu −55,8 bei +50 % (Dokument −52), der Schluss ändert sich nicht.
- Kosten der Google-Prüfung: OQ-0047 bleibt gültig, setzt aber nun sichtbar $500–4.500 je Assessment voraus, jährlich angenommen.
