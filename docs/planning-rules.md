# Planungsregeln und Startwerte

**Status:** Vom Maintainer festgelegte einfache Startwerte, ungeprüft und zum Testen gedacht. Version 4, Stand 2026-11-04 (DEC-0060, DEC-0061). Version 3 ist in `docs/migration/archive/` gesichert und nicht mehr gültig.

**Hinweis:** Die Werte sind nicht an eigenen Daten validiert. Keine Grenze in diesem Dokument ist eine Sicherheitsaussage (FR-0149). Die App stellt keine Diagnosen (FR-0118).

## Lesehilfe

**Spalte `Art`:** wie in [model-parameters.md](model-parameters.md).
- `belegt`: Der Wert oder Befund steht so in der genannten Quelle. Der Evidenzgrad steht dabei; „belegt“ heißt nicht, dass er auf Freizeitläufer übertragbar ist.
- `abgeleitet`: Der Wert folgt aus einer Quellenangabe oder einem benannten Rechenschritt.
- `Heuristik`: Keine Quelle nennt diesen Wert. Quellen stützen höchstens die Richtung oder die Größenordnung.

**Evidenz insgesamt**
- Für Steigerungsraten gibt es keine belegte sichere Grenze. Eine Übersicht über 36 Studien fand widersprüchliche Ergebnisse [L5].
- Vieles zu Reduktion, Intensitätsverteilung und Erholung stammt von Athleten. Studien an Freizeitläufern sind klein oder beobachtend.
- Die meisten wissenschaftlichen Quellen konnten nur als Abstract gelesen werden (siehe `Quellen`).
- Aussagen zu Verletzungen geben Studienergebnisse wieder. Sie sind keine medizinischen Aussagen und keine Vorhersage für einzelne Nutzer.

**Begriffe**
- `Wochenzeit`: geplante Bewegungszeit je Woche in Minuten, einschließlich Auf- und Abwärmen und Gehpausen. In der Geh-Lauf-Abfolge zählt nur die Laufzeit.
- `TSB%`: `100 · TSB[t] / CTL[t−1]` mit TSB aus FR-0101. Es gilt das rollende Mittel der letzten 7 Tage.
- Quellenkürzel [L1] usw. stehen unter `Quellen`. Kürzel [Q…] verweisen auf die Quellen in [model-parameters.md](model-parameters.md), Kürzel [N…] auf die in [phase-2-3-rules.md](phase-2-3-rules.md).

## Teil A: Einfache Planungsregeln (DEC-0061)

Gesetzt am 2026-11-04 vom Maintainer (DEC-0061): einfach anfangen, testen, dann nachsteuern. Alle Zahlen sind ungeprüfte Startwerte.

| ID | Parameter oder Regel | Startwert | Art | Begründung und Quelle | Anforderung |
|---|---|---|---|---|---|
| PAR-192 | Ausgangslage und Start | Beim Anlegen fragt die App nur: Ziel, heutiger Stand, Lauftage, Regler (PAR-196). **Stand genannt:** Der Plan startet mit dieser Wochenzeit. **Neu oder unbekannt:** Frage „Kannst du 30 min am Stück laufen?“ Ja: Start mit 30 min je Lauftag. Nein: Geh-Lauf-Abfolge (PAR-065), danach ebenso. Vorhandene Läufe in der App ersetzen die Angabe zum Stand. Einstieg und Datenaufbau werden im Plan benannt | Heuristik | Keine Trainingsstufen mehr. Unterschiede entstehen allein aus der Wochenzeit (PAR-193). | FR-0104, FR-0139, FR-0140, FR-0155 |
| PAR-193 | Steigerung | Wochenzeit je Woche: unter 2 h +10 %, von 2 h bis unter 4 h +7 %, ab 4 h +5 % | Heuristik | Anfänger steigern schneller, nach oben wird es langsamer. Ab 3 × 30 min ergibt das rund 10 Wochen bis zu einem längsten Lauf von gut 1 h und rund 18 Wochen bis etwa 100 min. Nicht belegt, im Feldtest zu prüfen; kein Wert gilt als sicher (PAR-049). | FR-0148, FR-0149 |
| PAR-194 | Leichtere Woche | Jede 4. Woche 20 % weniger Wochenzeit, ohne Steigerung. Danach geht es beim Wert der Woche davor weiter. Nicht in der Geh-Lauf-Abfolge | Heuristik | Einfache, übliche Praxis, nicht belegt. | FR-0150 |
| PAR-195 | Längster Lauf | 40 % der Wochenzeit, bei 2 Lauftagen 60 %, bei 1 Lauftag der ganze Lauf. Immer höchstens die maximale Zeit je Einheit (FR-0136) | Heuristik | Einfache Faustregel. | FR-0136, FR-0151 |
| PAR-196 | Regler und Halten | Der Regler legt die höchste Wochenzeit fest, von entspannt bis anspruchsvoll, in Stunden je Woche. Der Plan steigert bis zum Regler oder bis zur Zielspitze (PAR-205) und hält dann den Umfang. „Fitter werden“ läuft ohne Datum und ohne Zieltermin fort. Der Regler lässt sich jederzeit ändern | Heuristik | Wunsch des Maintainers. Ersetzt Stufen und Obergrenzen. | FR-0136, FR-0137, FR-0148 |
| PAR-197 | Einheiten je Woche | 1 Tag: lockerer Lauf. 2 Tage: locker, lang. 3 Tage: locker, locker oder hart (PAR-198), lang. Ab 4 Tagen: wie 3, dazu weitere lockere Läufe. 6 und 7 Tage nur, wenn der Nutzer sie festlegt. Die Wochenzeit verteilt sich nach dem langen Lauf gleichmäßig | Heuristik | Beispiel für 3 Tage aus FR-0151. | FR-0142, FR-0151, FR-0152 |
| PAR-198 | Harte Einheit | Schalter „harte Einheit“. Möglich ab 3 Läufen je Woche und wenn 30 min am Stück gehen, höchstens 1 je Woche. Standard: an bei Zeitzielen, sonst aus; der Nutzer kann jederzeit umschalten. Im Wechsel: Intervalle 4 × 3 min mit 3 min Trabpause, Tempodauerlauf 2 × 8 min mit 2 min Trabpause, progressiver Lauf mit 10 min Endblock. Ab 3 h Wochenzeit: 6 × 3 min, 2 × 12 min, 15 min Endblock. In leichteren Wochen und vor dem Zieltermin die kürzere Form. Passt sie nicht in die maximale Zeit: lockerer Lauf | Heuristik | Wenige feste Formate statt Stufenleitern. Auf- und Abwärmen nach PAR-120 und PAR-121. | FR-0143, FR-0146, FR-0148, FR-0151 |
| PAR-199 | Zieltermin und fernes Ziel | Vor dem Termin weniger Wochenzeit: 5 km und 10 km 1 Woche −30 %, Halbmarathon 2 Wochen −40 %. Liegt das Datum weiter weg als nötig, sinkt die Steigerung aus PAR-193 gleichmäßig, sodass die Zielspitze rund 4 Wochen vor dieser Reduktion erreicht wird | Heuristik | Halbmarathon in 12 Monaten soll eine ruhige Planung ergeben, keinen frühen Gipfel. | FR-0141, FR-0148 |
| PAR-200 | Nachfrage alle 2 Wochen | Die App fragt alle 2 Wochen: „zu leicht, passt oder zu schwer?“ Zu leicht: Wochenzeit ab der nächsten Woche +10 %, höchstens bis zum Regler; am Regler schlägt sie vor, ihn zu erhöhen. Zu schwer: −10 %. Keine Antwort ändert nichts. Der Nutzer kann das auch jederzeit von sich aus sagen | Heuristik | Wunsch des Maintainers (DEC-0061). Nach „zu leicht“ gilt danach wieder PAR-193; ein einzelner guter Lauf allein ändert nichts (FR-0165). Auslegung (K71): Solange die Pausenfrage nach PAR-202 offen ist, bietet die App die Nachfrage nicht an. | FR-0156, FR-0157, FR-0158, FR-0165 |
| PAR-201 | Von selbst nur nach unten | Weniger als die Hälfte der Wochenzeit geschafft: Die Woche wird wiederholt. Hälfte bis 80 %: keine Steigerung. Mindestens 2 der letzten 3 lockeren Läufe mit RPE ≥ 6 oder gemeldete Ermüdung (PAR-188): nächste Woche −10 % und keine harte Einheit. Von selbst steigert die App nie stärker als PAR-193. Zusätzliche Läufe erhöhen den Plan nicht. Ausgefallene Einheiten werden nicht nachgeholt. Warnsignale: FR-0203 | Heuristik | Entschieden (DEC-0061). Texte ohne Vorwurf. | FR-0156, FR-0157, FR-0160, FR-0162, FR-0163, FR-0164, FR-0165, FR-0166 |
| PAR-202 | Pause | Ab 7 Tagen ohne Lauf fragt die App, ob eine Pause war, außer der Nutzer hat zugesagt, alles zu erfassen. 1 bis unter 2 Wochen: Neustart mit 80 % der letzten Wochenzeit, keine harte Einheit in dieser Woche. 2 bis unter 8 Wochen: 50 %, 2 Wochen ohne harte Einheit. Ab 8 Wochen: neuer Start nach PAR-192 | Heuristik | Einfache Staffel, nicht belegt. Auslegung (K71): Der Neustart gilt auch, wenn eine Anpassung (Rückmeldung nach PAR-200, Wochenbewertung, Regelversion) den Anker auf diese oder eine spätere Woche gelegt hat, nicht bei einem in dieser Woche neu angelegten Plan oder geänderten Ziel; die Obergrenze „bisheriger Plan dieser Woche“ ist dann das Minimum aus dieser Woche vor und nach der Anpassung. | FR-0103, FR-0162, FR-0164, FR-0167 |
| PAR-203 | Alles änderbar | Ziel, Datum, Lauftage, Regler, Schalter und einzelne Einheiten sind jederzeit änderbar. Der Plan rechnet dann ab heute neu; absolvierte Einheiten bleiben. Das Ziel ändert nur der Nutzer, Termine nur nach Bestätigung | abgeleitet | FR-0158, FR-0168, FR-0169, OQ-0011. | FR-0158, FR-0168, FR-0169 |
| PAR-204 | Größere Änderung | Wochenzeit ändert sich um mindestens 10 %, oder eine Einheit wechselt zwischen hart, locker und Ruhetag oder entfällt. Dann nennt die App in einem Satz den Grund. Kleineres steht nur im Verlauf | Heuristik | Einfache Grenze. | FR-0156, FR-0170, FR-0180 |
| PAR-205 | Zielspitze | Längster Lauf, den das Ziel braucht: 5 km und 10 km die Strecke im aktuellen lockeren Tempo, Halbmarathon 16 km in diesem Tempo, höchstens 2 h. Lockeres Tempo ist der Median aus mindestens 3 lockeren Läufen in 6 Wochen. Ohne Tempo: 35, 65 und 100 min, und der Text nennt die Zeit | Heuristik | Eigene Wahl, nicht belegt. Wird bei jeder Neuberechnung neu bestimmt. | FR-0135, FR-0154 |
| PAR-206 | Einschätzung des Ziels | **Streckenziel:** Der Plan wird simuliert. Zielspitze zum Datum erreicht: „passt“. Sonst: „das wird knapp, ab etwa Datum X passt es“ mit Angebot dieses Datums. Reicht der Regler für die Zielspitze nicht, sagt die App das. **Zeitziel:** nötige Verbesserung gegenüber den letzten Läufen oder der Referenz (FR-0129, FR-0130) bis 0,25 % je Woche: „passt“; bis 0,5 %: „knapp“; darüber: „eher später“. Ohne Referenz oder mit weniger als 3 Läufen in 4 Wochen: „noch nicht genug Daten“. Bleibt der Nutzer bei einem knappen Datum, plant die App so weit wie möglich, ohne schneller zu steigern. Keine Erfolgsgarantie. Offene Ziele zeigen die Regelmäßigkeit | Heuristik | Entschieden (DEC-0061), Stufen nicht belegt. | FR-0129, FR-0130, FR-0154 |

### Grundsätze und Abstände, weiter gültig

| ID | Parameter oder Regel | Startwert | Art | Begründung und Quelle | Anforderung |
|---|---|---|---|---|---|
| PAR-049 | Grundsatz | Alle Steigerungswerte sind Planungsgrenzen. Texte der App nennen sie nie „sicher“, „unbedenklich“ oder „garantiert“ | abgeleitet | Folgt aus FR-0149. Die Übersicht über 36 Studien (23.047 Läufer) findet keinen konsistenten Zusammenhang und mahnt zur Vorsicht bei Empfehlungen zu optimalen Parametern oder Steigerungen [L5]. | FR-0148, FR-0149 |
| PAR-050 | 10-%-Regel | Nicht als Sicherheitsregel verwenden und nicht zitieren. 10 % darf nur als Planungswert neben anderen Grenzen auftauchen, etwa in PAR-193 | abgeleitet | Keine Quelle formuliert diese Regel; sie ist die eigene Folgerung aus schwacher Evidenz. Randomisiert (532 Laufanfänger, 13 Wochen nach 10-%-Regel gegen 8 Wochen Standardplan, laut [L9] 10,5 gegen 23,7 % je Woche): 20,8 % gegen 20,3 % Verletzte, P = 0,90 [L1]. Kohorte (874 Laufanfänger, GPS, explorativ): über 30 % gegen unter 10 %, bezogen auf einen 2-Wochen-Zeitraum: HR 1,59 (95-%-KI 0,96–2,66) nur für distanzbezogene Verletzungen; insgesamt kein Unterschied [L2]. Kleine Studie (60 Anfänger, 13 Verletzte): In der Woche vor der Verletzung stieg der Umfang der Verletzten um 86 % gegenüber anderen Wochen (95-%-KI 12,9–159,9, p = 0,026); der Vergleich mit den Gesunden (31,6 gegen 22,1 %) war nicht signifikant. Manche vertragen womöglich kurzzeitig 20–25 %, „no clear evidence“ für eine sichere Steigerung [L3]. Systematische Übersicht (nur 4 Arbeiten): 3 fanden einen Zusammenhang, darunter nach den Zahlen [L2] und [L3], eine nicht; Fazit „very limited evidence“ [L4]. Große Kohorte (5.205 Läufer): Verhältnis von Woche zu Woche ohne Zusammenhang [L6]. | FR-0148, FR-0149 |
| PAR-058 | Was als intensiv gilt | Geplant: Intervalle und Tempodauerlauf, sowie der lange Lauf für den Abstand. Absolviert: mindestens 10 min bei mindestens 80 % HFmax oder eine Angabe von RPE ≥ 7. Progressive Läufe zählen nach ihrem harten Anteil | Heuristik | Zwischen den Studien unterscheiden sich die Intensitätsgrenzen, auch solche an der Schwelle [L8, L10, L12]. Die Grenze von 80 % HFmax folgt den Zonen aus FR-0092. 10 min und RPE 7 sind eigene Wahl. | FR-0092, FR-0142, FR-0152, FR-0177 |
| PAR-059 | Mindestabstand | Zwischen zwei intensiven Einheiten liegt mindestens ein voller Kalendertag ohne intensive Einheit. Maßgeblich ist der Kalendertag, nicht die Stundenzahl | Heuristik | Übersicht zur autonomen Erholung bei Athleten und Gesunden: bis 24 h nach geringer, 24–48 h nach Schwellen-, mindestens 48 h nach hoher Intensität [L10]. Die Autoren betonen starke individuelle Unterschiede, und dieses Maß fällt nicht mit der Erholung aller Systeme zusammen. NHS plant einen Ruhetag zwischen allen Läufen [L15]. L10 stützt also nur die Richtung. Ein freier Kalendertag ergibt von Start zu Start rechnerisch gut 24 bis knapp 72 h, Montag 18 Uhr bis Mittwoch 7 Uhr sind 37 h. Die in L10 genannten mindestens 48 h nach hoher Intensität werden also nicht immer erreicht. Es ist eine Plausibilitätsgrenze, keine gemessene vollständige Erholung. | FR-0152, FR-0177 |
| PAR-060 | Prüfung beim Verschieben | Kein voller Tag dazwischen: Konflikt anzeigen, Alternativtage nennen, keine automatische Änderung. Der Nutzer darf trotzdem bestätigen; die intensive Einheit bleibt erkennbar. Überschreitet die Woche den Regler (PAR-196): Hinweis statt Sperre | abgeleitet | Folgt aus PAR-059, FR-0169 und OQ-0011. Die Darstellung als Hinweis statt Sperre ist eigene Wahl. | FR-0152, FR-0169, FR-0177 |
| PAR-065 | Geh-/Laufintervalle | Start: 1 min laufen, 1:30 min gehen, 8 Läufe mit 7 Gehpausen, davor und danach 5 min gehen. Danach die Abfolge aus PAR-132 bis PAR-139, unverändert wie die Vorlage: 9 Programmwochen bis 30 min Dauerlauf, ohne Entlastungswochen und ohne Rampenregel danach. Jede Woche lässt sich wiederholen; bei hoher Anstrengung schlägt die App das vor (PAR-140). PAR-193 und PAR-195 gelten in der Abfolge nicht, weil die Vorlage die Schritte selbst festlegt | belegt (Abfolge), Heuristik (Ausnahmen) | Struktur und Wiederholbarkeit stehen im NHS-Plan [L15]. Die Ausnahmen sind eigene Wahl. **Entschieden als Empfehlung (OQ-0059):** Der Maintainer hat keine Präferenz angegeben; sie bleibt die empfohlene 9-Wochen-Variante (DEC-0058), eine andere Wahl bräuchte eine neue Version. Evidenzgrad: gesundheitsbehördliches Programm. Eine Beobachtungsstudie an einer abgewandelten 9-Wochen-Fassung sagt, das Programm „lacks an evidence base“: 110 Erwachsene, nicht randomisiert, 64 % mit Lauferfahrung, 21 berichtete Verletzungen bei 20 Läufern (dort 19 %, also 0,19 je Läufer). Abschluss laut Abstract 27,3 %, der Ergebnisteil nennt 64,5 % Abbruch; die Arbeit löst das nicht auf. In 15 Interviews hing der Abbruch mit Verletzungen und dem Aufbau des Programms zusammen [L72, N28]. Das ist klein und nicht die NHS-Fassung, relativiert die Vorlage aber. Das Programm stammt laut [N28] von Josh Clark (1996); ob und wie der NHS es lizenziert hat, ist nicht geklärt. App-Texte dürfen den NHS bei einer Abwandlung nicht als Quelle nennen (PAR-142). **Rechnung:** Die Laufminuten je Woche steigen von Woche 3 auf 4 um 78 % (27 auf 48), die Gesamtzeit nur von 75 auf 94,5 min. Innerhalb von Woche 5 steigt der längste Dauerlauf von 8 auf 20 min. Auch dieses verbreitete Programm folgt also keiner 10-%-Regel. Ob die Abfolge frei nutzbar ist, ist rechtlich nicht geprüft (OQ-0048). | FR-0140, FR-0142, FR-0151 |
| PAR-072 | Aussagegrenze | ATL, CTL und TSB lösen Planänderungen aus, begründen aber nie eine Aussage zu Verletzung, Krankheit oder einem festgestellten Erholungszustand. Kein Text nennt ein Verletzungsrisiko aus diesen Werten | abgeleitet | Die Regel ist die eigene Folgerung aus diesen Belegen. Analyse: Keine Evidenz stützt den ACWR im Belastungsmanagement oder für Empfehlungen zur Verletzungsverringerung; das Maß erzeuge Rauschen und statistische Artefakte [L22]. Nachrechnung mit zufälligen Nennern: ähnliche Effekte, kaum Vorhersagekraft (c-Statistik 0,574 gegen 0,5), die Autoren raten zur Abkehr [L23]. Läufer-Kohorte: negative Dosis-Wirkungs-Beziehung des ACWR [L6]. FR-0101 und OQ-0026 begrenzen die Aussage ohnehin. | FR-0094, FR-0101, FR-0118, FR-0166 |
| PAR-073 | Maßzahl | Schwellen gelten für TSB% als rollendes Mittel der letzten 7 Tage, nie in absoluten Punkten. Solange CTL oder ATL nach PAR-088 und PAR-089 vorläufig sind, greifen sie nicht | abgeleitet | Der Begründer des Modells nennt TSB unter −10 und über +10 nur grob, warnt vor wörtlicher Anwendung und bezieht es auf TSS und seine Zeitkonstanten [L25]. Edwards-TRIMP hat eine andere Skala (FR-0092), absolute Werte und die dortige Rampe von 5–7 TSS/d je Woche lassen sich nicht übertragen. Bezug auf CTL macht die Werte skalenunabhängig, auch beim Wechsel des Profils (FR-0197). Das rollende Mittel glättet das Wochenmuster aus R2 und trifft auch das Tief hinter einer Sprungwoche (R3). | FR-0097, FR-0101, FR-0160, FR-0166, FR-0197 |
| PAR-076 | Keine Wirkung nach oben | Ein positiver oder steigender TSB% erhöht die Belastung nie allein. Eine Erhöhung folgt nur aus PAR-193 und PAR-200 | abgeleitet | Folgt aus FR-0101 und FR-0165. Coggan beschreibt positive Werte nur grob als „frische“ Beine, nicht als Leistungsfähigkeit [L25]. | FR-0101, FR-0161, FR-0165 |

### Pace aus der VO₂max, weiter gültig

| ID | Parameter oder Regel | Startwert | Art | Begründung und Quelle | Anforderung |
|---|---|---|---|---|---|
| PAR-081 | Mindeststufe | Pace-Vorgaben aus der VO₂max nur, wenn der Langzeitwert mindestens „ausreichend“ ist (PAR-042), und der letzte verwertbare Lauf mindestens „ausreichend“ (PAR-039) und höchstens 6 Wochen alt ist. „Vorläufig“ (PAR-038, PAR-041) und „nicht bestimmbar“ (PAR-037) gelten als unzureichend. Dann gibt es Herzfrequenzbereiche oder RPE nach FR-0153. Eine eingetragene Referenzleistung hat Vorrang vor der Schätzung | Heuristik | PAR-038 bis PAR-040 bewerten einzelne Läufe, die Vorgabe beruht aber auf dem Langzeitwert; deshalb gelten beide Bedingungen. „Vorläufig“ schließt laut PAR-038 HFmax aus der Altersformel und Einzelabschnitte ein. Stufen sind keine Genauigkeitsangaben; unabhängige Laufstudien fanden 8–10,2 % MAPE bei Wearables [Q2]. **Folge aus PAR-030, PAR-031 und PAR-038:** Wer langsamer als 7:28 min/km läuft, bleibt höchstens „vorläufig“ und erhält auf diesem Weg nie Pace-Vorgaben, also gerade viele Einsteiger nicht. Dasselbe gilt ohne gemeldete Vertikalgenauigkeit (PAR-027). Auch die Referenzleistung fehlt Einsteigern meist, weil der Test erst nach PAR-117 vorgeschlagen wird; ohne Selbstauskunft gibt es für sie mindestens 26 Wochen nur Herzfrequenz oder RPE, außer sie tragen selbst eine Zeit ein. | FR-0053, FR-0145, FR-0153 |
| PAR-082 | Form der Pace-Vorgabe | Stets ein Bereich, nie ein Einzelwert. Die Bandbreite weitet nur das langsame Ende, das schnelle Ende bleibt der berechnete Wert. Langzeitwert „ausreichend“: bis 13 % langsamer. „Gut“ (PAR-043, PAR-040): bis 6 % langsamer. Bei unter 3 Wochen alter Referenzleistung: bis 3 % langsamer, ältere nach PAR-101. Die Grenze für lockere Läufe wird nicht geweitet | abgeleitet (13 %, 6 %, nur langsam), Heuristik (3 %) | Rechnung mit der Formel aus FR-0069 in der Ebene bei 75 % Auslastung, VO₂max 35 und 45: 5 % Fehler verschieben die Pace um rund 6 %, 10 % um 12 bis 13 %. Unabhängige Laufstudien fanden 8–10,2 % MAPE bei Wearables [Q2]; 13 % decken damit einen Fehler von 10 %. Selbst „gut“ kann also keine genaue Pace rechtfertigen. Nur das langsame Ende, weil der Schätzer in der nächsten Laborprüfung zu hoch lag [Q38] und eine alte Referenz die aktuelle Form eher überschätzt (PAR-101); **entschieden** auch für die Pace aus der VO₂max (OQ-0059). Eine zu tiefe Schätzung bleibt dadurch ungedeckt; eine neue Referenz behebt das. Je breiter der Bereich, desto weniger führt er im Training. 3 % bei Referenzleistung sind eigene Wahl. Beispiele: PAR-190. | FR-0145, FR-0146, FR-0153 |

### Annullierte Regeln

Diese Regeln gelten nicht mehr (DEC-0061). Der alte Wortlaut steht in `docs/migration/archive/planning-rules-v3.txt`.

| ID | Stand | Ersetzt durch |
|---|---|---|
| PAR-051 | annulliert | PAR-192 |
| PAR-052 | annulliert | PAR-193 |
| PAR-053 | annulliert | PAR-195 |
| PAR-054 | annulliert | PAR-198 |
| PAR-055 | annulliert | PAR-201 |
| PAR-056 | annulliert | PAR-194 |
| PAR-057 | annulliert | PAR-194 |
| PAR-061 | annulliert | PAR-198 |
| PAR-062 | annulliert | PAR-197 |
| PAR-063 | annulliert | PAR-195 |
| PAR-064 | annulliert | PAR-192 |
| PAR-066 | annulliert | PAR-192 |
| PAR-067 | annulliert | PAR-192 |
| PAR-068 | annulliert | PAR-206 |
| PAR-069 | annulliert | PAR-199 |
| PAR-070 | annulliert | PAR-199 |
| PAR-071 | annulliert | PAR-196 |
| PAR-074 | annulliert | PAR-201 |
| PAR-075 | annulliert | PAR-201 |
| PAR-077 | annulliert | PAR-202 |
| PAR-078 | annulliert | PAR-202 |
| PAR-079 | annulliert | PAR-202 |
| PAR-080 | annulliert | PAR-204 |
| PAR-083 | annulliert | PAR-206 |
| PAR-084 | annulliert | PAR-206 |
| PAR-085 | annulliert | PAR-206 |
| PAR-191 | annulliert | PAR-205 |

## Teil B: Startwerte (OQ-0046)

| ID | Parameter oder Regel | Startwert | Art | Begründung und Quelle | Anforderung |
|---|---|---|---|---|---|
| PAR-086 | Mindestanzahl gemeinsamer Läufe | 10 Läufe mit beiden Werten in den letzten 180 Tagen, davon mindestens 2 mit RPE ≥ 6 und 2 mit RPE ≤ 4. Vorher bleiben Läufe ohne Puls „nicht bewertet“ | abgeleitet | Laborwerte für 10 Freizeitsportler: sRPE 28,1 % CV, Banister-TRIMP 15,6 % CV [L31]. Unter Annahme unabhängiger Fehler ergibt das rund 32 % CV des Verhältnisses und einen 95-%-Bereich des Mittels von ±28 % bei 5, ±20 % bei 10, ±14 % bei 20 Läufen. Das gilt für das Mittel. PAR-087 nutzt den Median, der bei Normalverteilung stärker streut: rund ±34 / ±24 / ±17 % (eigene Simulation), ±20 % erst bei rund 16 Läufen. Unter 20 Läufen zeigt die App den Faktor ohnehin als „noch wenig gesichert“ (PAR-087). Die Zielgenauigkeit ±20 % ist eigene Wahl. Edwards ist darin nicht gemessen, und 18-min-Laboreinheiten sind nicht freie Läufe. Die Mischung der Intensitäten folgt daraus, dass die Abweichung von der gelaufenen Intensität abhängt [L30]. | FR-0097 |
| PAR-087 | Berechnung des Faktors | Faktor = Median aus TRIMP / sRPE-Punkte über die letzten 20 geeigneten Läufe. Geeignet ist, wer die Pulsregeln aus PAR-010 erfüllt. Getrennt je Belastungsprofil. Umgerechnete Werte bleiben immer gekennzeichnet. Unter 20 Läufen zeigt die App ihn als „noch wenig gesichert“. Weicht der Faktor um mehr als 25 % vom Vorwert der letzten 6 Monate ab, bietet sie eine Neuberechnung an | Heuristik | Korrelation der Summated-Heart-Rate-Zone-Methode mit Session-RPE r = 0,84 (95-%-KI 0,70–0,92; 33 Personen, 2 Wochen), also rund 71 % gemeinsame Varianz; TRIMP zum Vergleich r = 0,76, rund 58 %; je mit systematischen Abweichungen nach Zonen [L30]. Die Methode ist dem Edwards-TRIMP aus FR-0092 am nächsten: Das Abstract nennt für die Zonen 1, 2 und 4 dieselben Grenzen. Die Gleichsetzung ist eigene Einordnung. Validität von sRPE in vielen Sportarten bestätigt [L32], auch der Ursprung nennt einen konsistenten Zusammenhang bei abweichender Skala [L24]. Ein persönlicher Faktor ist naheliegend, aber kein Beleg, dass er gut umrechnet. Der Median ist robust gegen Ausreißer (eigene Wahl). Keine Quelle prüft dieses Verfahren. | FR-0096, FR-0097, FR-0197, FR-0199 |
| PAR-088 | Vorläufige Phase ATL | 21 Tage ab dem ersten bewerteten Lauf | abgeleitet | Nach eigener Rechnung (Archiv, R1) hat ATL dann 96 % des Dauerwerts erreicht. Die Zahl folgt aus der Formel; die 96 % als „genug“ sind eigene Wahl. | FR-0098 |
| PAR-089 | Vorläufige Phase CTL und TSB | **126 Tage (entschieden).** Anzeigen bleiben mit „vorläufig“ möglich; TSB-Schwellen greifen erst danach | abgeleitet | Nach eigener Rechnung (Archiv, R1) hat CTL bei 84 Tagen 87 % erreicht, bei gleichbleibender Last bleibt TSB% rund −15. Bei 42 Tagen wäre TSB% −57: Jeder Nutzer sähe ohne Überlastung ein starkes Signal. Der Startfehler addiert sich zum Aufbau, deshalb wäre eine Schwelle kurz nach Tag 84 noch fehleranfällig; bei 126 Tagen ist der Fehler −5, dafür gibt es 4 Monate kein Signal. PAR-178 ergänzt nur einen Text ohne Planänderung. Coggan verlangt eine lange Datenhistorie oder Startwerte [L25]. | FR-0098, FR-0099, FR-0104 |
| PAR-090 | Rückfall in „vorläufig“ | Fehlen in den letzten 42 Tagen über 10 % der erwarteten Einheiten als bewertet, gelten CTL und TSB wieder als vorläufig. Der Rückfall endet, sobald im 42-Tage-Fenster wieder höchstens 10 % der erwarteten Einheiten fehlen. Hat der Nutzer nicht zugesagt, alle Trainings zu erfassen, bleiben sie dauerhaft vorläufig | abgeleitet (Beginn), Heuristik (Ende) | Coggan: Fehlende Dateien verfälschen CTL und TSB, besonders über rund 10 % [L25], bezogen auf Radfahren mit Leistungsmessung. Er rät dann zu Vorsicht und zum Schätzen fehlender Werte, nicht zum Abschalten; das Abschalten ist eigene Wahl. Bei 3 Einheiten je Woche sind 18 in 42 Tagen erwartet, also genügen 2 unbewertete Läufe. Weil die Schwellen nur entlasten, entfällt damit auch die Entlastung. Deshalb endet der Rückfall ohne Wartezeit; zwei unbewertete Läufe halten ihn höchstens bis zum Ende des Fensters, also bis zu 42 Tage. Der letzte Teil folgt aus FR-0103. **Dauerhafte Folge ohne Zusage:** Der Belastungsfaktor fehlt immer, der Readiness-Wert bleibt also höchstens 74. „Gut erholt“ und die Stufe „gut“ sind nie erreichbar (PAR-150, PAR-170). | FR-0102, FR-0103 |

## Teil C: Energiereserve (OQ-0030)

**Zurückgestellt auf Phase 4 (DEC-0060).** Für die Phasen 1 bis 3 nicht umzusetzen, die Werte bleiben unverändert.

**Es gibt keine öffentlichen Formeln.** Alle Raten sind eigene Annahmen. Weil FR-0124 ohnehin eine empirische Kalibrierung verlangt, sind sie nur Startwerte für diese Kalibrierung.

| ID | Parameter oder Regel | Startwert | Art | Begründung und Quelle | Anforderung |
|---|---|---|---|---|---|
| PAR-091 | Grundlage | Eigenes Modell auf Basis der Form aus FR-0122, keine Nachbildung eines Herstellerwerts. Vorbilder dienen nur als Beleg, welche Signale üblich sind | abgeleitet | Die Regel ist eigene Entwurfsentscheidung aus diesen Belegen. Das Firstbeat-Papier beschreibt Zustände aus Herzschlagdaten und Atmung sowie Ressourcen, die sich aufbauen und abbauen, nennt aber keine Raten und verweist auf ein erteiltes Patent [L36]. Polar nennt Sleep Charge, ANS Charge und den Vergleich mit 28 Tagen, ohne Formel [L37]. Google nennt für Readiness HRV, Ruhepuls und Schlaf gegen eine persönliche Referenz, ohne Gewichte [L38]. Garmins eigene Seiten zu Body Battery waren nicht abrufbar. | FR-0122, FR-0124 |
| PAR-092 | Startwert | Rechnerisch 50, gesetzt am Ende der ersten vollständig erfassten Nacht. Als Zahl sichtbar erst mit 14 gültigen HRV-Messungen in 28 Tagen; bis dahin „unvollständig“ | Heuristik | 50 ist die Mitte der Skala und trägt keine Information. Nach einem Tag mit 8 h Schlaf ist der Startwert im Modell aus PAR-094 und PAR-095 zu rund 94 % ausgeglichen (eigene Rechnung). Die Mengen übernehmen die Readiness-Referenz aus OQ-0006, die dort ebenfalls Heuristik ist. | FR-0121, FR-0122 |
| PAR-093 | Aktualisierungsintervall | 15 min, nachträglich aus den über Health Connect importierten Daten berechnet (OQ-0047). Die Anzeige nennt den Stand des letzten Imports | Heuristik | Android empfiehlt 15 min als Sync-Takt für Schlafdaten beim Schreiben [L43]; das Lesebeispiel in der Dokumentation nutzt 1 h [L41]. Welchen Takt Quell-Apps in Health Connect tatsächlich schreiben, wurde nicht geprüft; Polars eigene API, die nicht angebunden ist, liefert Dauerpuls alle 5 min [L49]. Die Verzögerung der Quell-Apps wurde nicht gemessen; „laufend“ heißt daher nicht in Echtzeit. | FR-0122, FR-0125 |
| PAR-094 | Zuwachs im Schlaf | Je 15 min: `R = (100 − B) · 0,058 · f`. Das entspricht τ = 4,2 h. `f` liegt zwischen 0,5 und 1,25 und setzt sich aus der Abweichung der nächtlichen HRV (FR-0113) und dem Wachanteil zusammen. Ohne Schlafdaten: 0 | Heuristik | Keine Quelle für Energie. Die Form ist vom Prozess S der Schlafregulation entlehnt, einer Größe für Schlafdruck, nicht Energie [L39]. Die Zeitkonstanten 4,2 h und 18,2 h stammen aus einer Software, die Daan et al. 1984 zitiert [L40]; die Originalarbeit war nicht abrufbar. `f` ist eigene Wahl. Rechnung mit 16 h wach und 8 h Schlaf: morgens 91, abends 38. Bei 5 h Schlaf: 78 und 28. Das Ergebnis ist für den Tagesverlauf plausibel, aber nicht validiert. **Bekannte Eigenschaft:** Von −36 aus 240 TRIMP bleiben am nächsten Morgen je nach Tageszeit der Einheit nur rund −2 bis −5 Punkte, auch bei 7 solchen Tagen in Folge rund −3. Der Morgenwert hängt fast nur von Schlafdauer und `f` ab (nach einer Nacht `f` = 0,5: 76; `f` = 1,25: 94). Mehrtägige Ermüdung bildet das Modell kaum ab. | FR-0122, FR-0123, FR-0124 |
| PAR-095 | Abnahme im Wachzustand | Je 15 min: `D = B · 0,0136`. Das entspricht τ = 18,2 h | Heuristik | Siehe PAR-094. Durch die Form sinkt die Reserve bei hohen Werten absolut schneller; das ist eine Modellannahme ohne eigenen Beleg. | FR-0122, FR-0123, FR-0124 |
| PAR-096 | Abnahme durch Sport | Zusätzlich `D = 0,15 · TRIMP` des Intervalls. Beispiele: 60 TRIMP: −9. 110 TRIMP aus FR-0092: −16,5. 240 TRIMP: −36. Ohne Puls: sRPE mit Faktor (PAR-087); ist er nicht bekannt, gilt die Einheit als Lücke | Heuristik | Keine Quelle für den Faktor. Er ist so gewählt, dass eine harte Stunde spürbar, aber nicht bestimmend ist; am nächsten Morgen ist die Wirkung fast verschwunden (PAR-094). Hängt am gewählten Profil, daher beim Profilwechsel neu zu kalibrieren. | FR-0097, FR-0123, FR-0124, FR-0197 |
| PAR-097 | Stress und Ruhe im Wachzustand | Mindestens 30 min ruhig, ohne Bewegung, Puls nahe Ruhepuls: `D` entfällt, je 15 min `R = (100 − B) · 0,01`. Mindestens 15 min Puls um mindestens 20 bpm über dem persönlichen Ruhewert ohne Bewegung: `D` verdoppelt | Heuristik | Firstbeat beschreibt Erholung und Stress als Zustände außerhalb körperlicher Aktivität, ohne diese Zahlen [L36]; sie sind eigene Wahl. Erhöhter Puls ohne Bewegung ist kein eindeutiges Zeichen für Stress; die App stellt ihn nicht als Befund dar (FR-0118). | FR-0118, FR-0123 |
| PAR-098 | Dauer einer „längeren“ Datenlücke | Bis 30 min: Wert fortführen mit dem Wachsatz. Über 30 min bis 2 h: Wert einfrieren, Bereich markieren. Über 2 h oder fehlende Hauptschlafphase: „veraltet“ oder „unvollständig“, keine Fortschreibung. Über 24 h: Neustart nach PAR-092. Kontinuierliche Daten bedeuten mindestens 90 % abgedeckte Tageszeit | Heuristik | Keine Quelle. FR-0126 verlangt nur die Kennzeichnung, und OQ-0007 verlangt kontinuierliche Daten. Bei einem Rechenintervall von 15 min ist eine Lücke von 30 min noch 2 Intervalle; der Takt der Quell-Apps in Health Connect ist nicht geprüft (PAR-093). Die übrigen Zahlen sind eigene Wahl. | FR-0120, FR-0121, FR-0126 |
| PAR-099 | Kalibrierung | Alle Raten als versionierter Parametersatz. Vor einer Freigabe der Funktion an eigenen Daten kalibrieren. Die App zeigt den Wert als modellierte Schätzung ohne Einheit und nicht als gemessene Energie | abgeleitet | Folgt aus FR-0124, NFR-0001 und §12.4 der Quelle. Prüfplan unter `Validierungsbedarf`, einschließlich der Eigenschaft aus PAR-094. | FR-0124, FR-0125, FR-0127 |

## Teil D: Hersteller-APIs (OQ-0047)

**Entschieden (OQ-0047):** Phase 3 nutzt nur Health Connect. Die Google Health API ist zurückgestellt, bis der Android-Weg ohne Secret und die jährlichen Prüfkosten von 500 bis 4.500 USD geklärt sind. Andere Hersteller folgen erst, wenn sich ein Weg ohne eigenen Server ergibt. Secrets werden nicht in der App ausgeliefert. Die Tabelle ist eine Bestandsaufnahme für eine spätere Neubewertung, keine Empfehlung. **Abrufdatum: 2026-11-03, für L77 bis L82 2026-11-04.** Die Bedingungen ändern sich gerade stark: Google hat die Fitbit Web API laut seiner Health-API-Seite am 2026-11-02 abgeschaltet (die Fitbit-Dokumentation nennt den 2026-10-30), Garmin hat sein Programm im Oktober 2026 neu aufgesetzt. „Offiziell“ heißt, die Angabe steht in der Dokumentation des Anbieters; „Dritte“ heißt, sie stammt aus Fachpresse oder fremder Integrationsdokumentation und ist ungeprüft.

| Anbieter | Ohne eigenen Server rein aus der App? | HRV | Schlaf | Ruhepuls | Zulassung | Kosten | Wichtige Einschränkungen | Belege |
|---|---|---|---|---|---|---|---|---|
| **Android Health Connect** | **Ja.** Lokale Schnittstelle auf dem Gerät | Ja, nur RMSSD, `HeartRateVariabilityRmssdRecord`, 1–200 ms (offiziell). Kein SDNN gefunden | Ja, Sitzung mit Phasen (offiziell) | Ja (offiziell) | Google-Play-Erklärung „Health apps“, Begründung je Datentyp, Datenschutzerklärung, Data-Safety-Angaben; Zugriff je Paket freigegeben (offiziell) | Keine genannt | Liefert nur, was Quell-Apps schreiben. Hintergrundlesen und Daten älter als 30 Tage brauchen eigene Berechtigungen. Ratenlimits ohne veröffentlichte Zahlen, im Hintergrund strenger. Weitergabe an Dritte nur mit ausdrücklicher Einwilligung und nur zu Sicherheitszwecken, wegen rechtlicher Pflichten oder bei Fusionen; alles andere ist untersagt (offiziell). Google Health schreibt Schlaf, Puls, HRV und Ruhepuls hinein (offiziell). Garmin: laut Tom's Guide Schlaf und Puls ja, „HRV Status“ nein; ob RMSSD fließt, ist unklar; keine offizielle Garmin-Seite gefunden. Polar, Suunto und Withings wurden hierfür nicht geprüft | L41, L42, L43, L44, L45, L46, L47, L48 |
| **Garmin, Personal API** | **Technisch ja, nur für eigene Daten.** Pull. Jeder Nutzer müsste selbst einen Schlüssel erzeugen und eingeben. Offiziell „not intended for commercial applications serving multiple end users“ | Nicht offiziell bestätigt, Swagger-Doku nicht lesbar; „Health Data“ als JSON | Nicht bestätigt, siehe HRV | Nicht bestätigt, siehe HRV | Keine; Nutzer akzeptiert Bedingungen im eigenen Konto. Bedingungen hinter Login | Keine genannt | Schlüssel läuft nach 30 Tagen bis 1 Jahr ab, Zugriffstoken 24 h, keine Refresh-Tokens. Dritte: Berechnete Werte fehlen womöglich. Eignung für eine verteilte App ist eine Frage der nicht gelesenen Bedingungen | L50, L51, L52, L53 |
| **Garmin, Business (Starter, Enterprise)** | **Nur mit eingebettetem Secret, PKCE ändert daran nichts (offiziell).** Der Token-Tausch verlangt `code_verifier` und `client_secret`. Das PDF stammt laut Metadaten von 2025-06, also vor dem Neustart; die FAQ bestätigt nur OAuth 2.0. **Starter zusätzlich nein** (abgeleitet aus „Push only“, offiziell; Empfänger muss erreichbar sein). Enterprise: „Push or Ping/Pull“, Details hinter Login | Auf der öffentlichen Seite nicht genannt; „Enhanced Beat-To-Beat Interval“ nur Enterprise (offiziell) | Ja (offiziell) | Nicht einzeln genannt; „Heart Rate“ (offiziell) | Antrag, Freigabe, dann Portal; Integration 1–4 Wochen (offiziell). Dritte: Starter „unverified“ bis zur Prüfung, öffentliche Website und Datenschutzerklärung nötig | Starter: offiziell keine Angabe; Dritte: kostenlos bis 1.000 Nutzer. Enterprise: individuell; Dritte: nach aktiven Nutzern ab 2027-04-01 | Starter ohne Historie, begrenzte Nutzerzahl (offiziell). Body Battery ist Datenart des Health API (offiziell). Programm war 2026 pausiert, seit 2026-10-21 wieder offen (Dritte). Dritte: KI-Training mit den Daten untersagt | L52, L53, L54, L55, L80 |
| **Google Health API (Fitbit, Pixel Watch), zurückgestellt** | **Offen, technisch denkbar.** Googles allgemeine Android-Anleitung nutzt eine Android-Client-ID (Paketname, SHA-1) ohne Secret und Zugriffstokens auf dem Gerät; Refresh-Tokens gehören dort auf den Server [L79]. Die Health-API-Anleitung und das Codelab zeigen dagegen nur „Web Server“ bzw. „Web Application“ mit Client-Secret [L78]. L61 gilt für Desktop-Apps. Es gibt Listenabfragen neben Webhooks. Eine Health-API-Anleitung für reine Android-Clients wurde nicht gefunden | Ja, Stichproben und täglich (offiziell) | Ja (offiziell) | Täglich (offiziell) | Alle Scopes „Restricted“ [L56], die Prüfseite sagt „Most scopes“ [L77]: Prüfung nötig, Testmodus bis 100 Nutzer. Die Produktseite verlangt für Restricted Scopes ein jährliches Assessment nach CASA, ohne Bedingung zu Servern [L77], die Checkliste einen Sicherheits-Review [L59]. Die allgemeine Google-Seite verlangt es nur, wenn Daten über einen Server laufen [L62]. Klärung mit Google nötig, falls die API wieder aufgenommen wird; bis dahin gilt die Produktseite | API selbst: keine Angabe. Assessment: $500–4.500 an den externen Prüfer, je nach Komplexität; Dauer 2–3 Wochen (Tier 2), 4–6 Wochen (Tier 3) (offiziell). Annahme: Dieser Betrag fällt jährlich an (abgeleitet aus der jährlichen Wiederholung) | Nutzer müssen sich vor der Einwilligung in der Google-Health-App anmelden [L78]. Fitbit Web API seit 2026-11-02 abgeschaltet (HTTP 410). Weitere Datentypen bis Q1 2027 angekündigt. Fitbit-Daten gelangen auch über Health Connect in die App (Zeile oben) | L46, L56, L57, L58, L59, L60, L61, L62, L77, L78, L79 |
| **Polar AccessLink** | **Nur mit eingebettetem Secret.** Pull ohne Webhook möglich, aber der Token-Tausch nutzt offiziell Basic Auth mit `client_id:client_secret`. PKCE nicht beschrieben. RFC 8252 behandelt solche Secrets in verteilten Apps als nicht vertraulich | Ja: `heart_rate_variability_avg`, `hrv_samples` in Nightly Recharge (offiziell) | Ja, mit Phasen (offiziell), letzte 28 Tage | Nur als Profilfeld `resting_heart_rate` (Beispielantworten, offiziell); nachts `heart_rate_avg` | Polar-Flow-Konto, Client im Admin-Portal, Nutzer registrieren (offiziell) | „At the moment“ kostenlos, künftige Gebühren vorbehalten (offiziell, Lizenzvertrag Stand 2025-08-22) | Tokens laufen nicht von selbst ab. Dauerpuls alle 5 min. Limit steigt mit Nutzern. Ein Webhook je Client | L49, L63, L82 |
| **Suunto** | **Nur mit eingebettetem Secret und Subscription-Key (offiziell), PKCE nicht beschrieben.** Der Token-Tausch nutzt Basic Auth mit Client-ID und Secret, jeder API-Aufruf den Subscription-Key. Die FAQ nennt die Anmeldung „optimized for mobile use“, aber kein mobiles SDK. Ein Webhook muss öffentlich erreichbar sein und gilt laut FAQ für Workouts; Tagesaktivität wird abgerufen. Laut Dritten sind Webhooks optional | Nur Dritte: als RMSSD über 247-Daten | Nur Dritte | Nur Dritte: aus den Schlafdaten | Nur Unternehmen und Organisationen mit öffentlichem Angebot; Prüfung wöchentlich, höchstens 2 Wochen; keine persönliche Nutzung (offiziell) | „We do not charge from the use of the API“ (offiziell) | Offizielle Startseite nennt nur Workout-Daten; die API-Referenz ist nur für Partner sichtbar. Ob eine App ohne Firma zugelassen wird, ist offen | L64, L65, L66, L81 |
| **Withings** | **Nur mit eingebettetem Secret, praktisch fraglich.** OAuth mit `client_secret` (offiziell); die Signatur für Vertragspartner entsteht ebenfalls mit dem Secret. PKCE wird nicht beschrieben. Notifications optional, Polling höchstens alle 10 min je Nutzer (offiziell). Dritte: Ohne konforme Webhook-URL höchstens 10 verknüpfte Nutzer | Ja: `rmssd`, `sdnn_1` in OpenAPI; „Heart Rate Variability“ in der Biomarker-Liste (offiziell). Dritte: nur bezahlte Pläne | Ja, je nach Gerät und Region (offiziell) | Nicht als eigener Wert gelistet; „Sleep Heart Rate“ (offiziell) | Public API ohne Vertrag; Registrierung im Partner Hub (offiziell) | Offiziell auf den lesbaren Seiten keine Preise. Dritte: frei bis 1.000 aktive Nutzer | Manche Werte erfordern den Plan „Advanced Biomarkers“ (offiziell). Refresh-Token 1 Jahr, Rotation (offiziell) | L67, L68, L69, L70 |

**Befund für ADR-0001:** Der einzige Weg ohne eigenen Server und ohne Secret und damit der einzige vorgesehene ist Health Connect; er liefert aber nur, was Quell-Apps schreiben. Bei Polar, Withings, Suunto und Garmin Business ginge es technisch nur mit einem in der App ausgelieferten Secret [L63, L80, L81], bei Garmin Starter wegen „Push only“ auch damit nicht. Bei Google ist ein Weg ohne Secret nach der allgemeinen Android-Anleitung denkbar, für die Health API aber nicht bestätigt; auch deshalb ist sie zurückgestellt. Alle Hersteller-Wege übertragen Daten zwischen Hersteller und Gerät, also sind SEC-0002 und SEC-0008 weiter zu beachten.

## Entscheidungsbedarf

Patent und Nutzung der NHS-Abfolge gehören zur rechtlichen Prüfung (OQ-0048).

## Quellen

L1 bis L70 abgerufen am 2026-11-03, L71 bis L82 am 2026-11-04. Studien mit PubMed-Link wurden über die NCBI-E-Utilities im Abstract gelesen, weil die PubMed-Seite selbst nicht direkt lesbar war. Volltexte nur wo vermerkt.

**Steigerung und Verletzungen**
- [L1] Buist et al. 2008, Am J Sports Med (RCT, Anfänger): https://pubmed.ncbi.nlm.nih.gov/17940147/
- [L2] Nielsen et al. 2014, JOSPT (Kohorte): https://vbn.aau.dk/da/publications/excessive-progression-in-weekly-running-distance-and-risk-of-runn
- [L3] Nielsen et al. 2013, J Strength Cond Res: https://pubmed.ncbi.nlm.nih.gov/22990565/
- [L4] Damsted et al. 2018, Int J Sports Phys Ther: https://pubmed.ncbi.nlm.nih.gov/30534459/
- [L5] Fredette et al. 2022, J Athl Train: https://pubmed.ncbi.nlm.nih.gov/34478518/
- [L6] Frandsen et al. 2025, Br J Sports Med (Abstract): https://researchportal.lih.lu/en/publications/how-much-running-is-too-much-identifying-high-risk-running-sessio/
- [L7] Autorenbeitrag zu [L6], BJSM Blog: https://blogs.bmj.com/bjsm/?p=11751
- [L8] Ramskov et al. 2018, JOSPT (RCT): https://pubmed.ncbi.nlm.nih.gov/29895234/
- [L9] Run-Clever-Studiendesign (Volltext): https://pmc.ncbi.nlm.nih.gov/articles/PMC4842282/
- [L71] Damsted et al. 2019, JOSPT (Kohorte, Abstract): https://pubmed.ncbi.nlm.nih.gov/30526231/
- [L74] Damsted et al. 2019, J Sci Med Sport, ProjectRun21 (Kohorte, Abstract): https://pubmed.ncbi.nlm.nih.gov/30190100/ und Studiendesign (Volltext, gezielt gelesen: Einschluss und Pläne): https://pmc.ncbi.nlm.nih.gov/articles/PMC5673057/
- [L75] Kluitenberg et al. 2016, J Sci Med Sport (Kohorte, Abstract): https://pubmed.ncbi.nlm.nih.gov/26452583/

**Erholung, Verteilung, Einstieg, Reduktion**
- [L10] Stanley et al. 2013, Sports Med: https://pubmed.ncbi.nlm.nih.gov/23912805/
- [L11] Seiler 2010, Int J Sports Physiol Perform: https://pubmed.ncbi.nlm.nih.gov/20861519/
- [L12] Muñoz et al. 2014, Int J Sports Physiol Perform: https://pubmed.ncbi.nlm.nih.gov/23752040/
- [L13] Festa et al. 2020, Front Sports Act Living: https://pubmed.ncbi.nlm.nih.gov/33344993/
- [L14] Rosenblat et al. 2019, J Strength Cond Res: https://pubmed.ncbi.nlm.nih.gov/29863593/
- [L76] Silva Oliveira et al. 2024, Sports Med (Abstract; Volltext gezielt gelesen: Studienmerkmale, Diskussion): https://pubmed.ncbi.nlm.nih.gov/38717713/ und https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/
- [L15] NHS Couch to 5K: https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/ und https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/
- [L72] Relph et al. 2023, Int J Environ Res Public Health (Couch to 5K, Abstract): https://pubmed.ncbi.nlm.nih.gov/37681822/
- [L16] Bosquet et al. 2007, Med Sci Sports Exerc: https://pubmed.ncbi.nlm.nih.gov/17762369/
- [L17] Wang et al. 2023, PLoS One: https://pubmed.ncbi.nlm.nih.gov/37163550/
- [L18] Mujika und Padilla 2003, Med Sci Sports Exerc: https://pubmed.ncbi.nlm.nih.gov/12840640/
- [L19] Smyth und Lawlor 2021, Front Sports Act Living (Marathon): https://pubmed.ncbi.nlm.nih.gov/34651125/
- [L20] Scharhag-Rosenberger et al. 2009, Med Sci Sports Exerc: https://pubmed.ncbi.nlm.nih.gov/19346973/
- [L21] Fokkema et al. 2019, J Sci Med Sport: https://pubmed.ncbi.nlm.nih.gov/29934211/
- [L34] Bell et al. 2023, Sports Med Open (Kraftsport): https://pubmed.ncbi.nlm.nih.gov/37730925/
- [L35] Mølmen et al. 2019, Open Access J Sports Med: https://pubmed.ncbi.nlm.nih.gov/31802956/

**Belastungsschwellen und Pausen**
- [L22] Impellizzeri et al. 2020, Int J Sports Physiol Perform: https://pubmed.ncbi.nlm.nih.gov/32502973/
- [L23] Impellizzeri et al. 2021, Sports Med: https://pubmed.ncbi.nlm.nih.gov/33332011/
- [L25] Coggan, TrainingPeaks, The Science of the Performance Manager (Radsport-Herkunft): https://www.trainingpeaks.com/learn/articles/the-science-of-the-performance-manager/
- [L73] Gabbett 2016, Br J Sports Med (Volltext, gezielt gelesen): https://pmc.ncbi.nlm.nih.gov/articles/PMC4789704/
- [L26] Coyle et al. 1984, J Appl Physiol: https://pubmed.ncbi.nlm.nih.gov/6511559/
- [L27] Mujika und Padilla 2001, Med Sci Sports Exerc: https://pubmed.ncbi.nlm.nih.gov/11252068/
- [L33] Foster 1998, Med Sci Sports Exerc: https://pubmed.ncbi.nlm.nih.gov/9662690/

**Machbarkeit und sRPE**
- [L28] Vickers und Vertosick 2016, BMC Sports Sci Med Rehabil: https://pubmed.ncbi.nlm.nih.gov/27570626/
- [L29] Milanović et al. 2015, Sports Med: https://pubmed.ncbi.nlm.nih.gov/26243014/
- [L24] Foster et al. 2001, J Strength Cond Res: https://pubmed.ncbi.nlm.nih.gov/11708692/
- [L30] Borresen und Lambert 2008, Int J Sports Physiol Perform: https://pubmed.ncbi.nlm.nih.gov/19193951/
- [L31] Wallace et al. 2014, J Strength Cond Res: https://pubmed.ncbi.nlm.nih.gov/24662229/
- [L32] Haddad et al. 2017, Front Neurosci: https://pubmed.ncbi.nlm.nih.gov/29163016/

**Energiereserve**
- [L36] Firstbeat, Stress and Recovery Analysis Method, 2014 (Volltext): https://www.firstbeat.com/wp-content/uploads/2015/10/Stress-and-recovery_white-paper_20145.pdf
- [L37] Polar, Nightly Recharge: https://www.polar.com/us-en/smart-coaching/nightly-recharge
- [L38] Google Health Help, Daily Readiness: https://support.google.com/googlehealth/answer/14236710?hl=en
- [L39] Borbély et al. 2016, J Sleep Res: https://pubmed.ncbi.nlm.nih.gov/26762182/ und Borbély 2022, J Sleep Res (ohne Zahlen): https://pmc.ncbi.nlm.nih.gov/articles/PMC9540767
- [L40] Two Process Model, Softwaredokumentation (Sekundärquelle für τ): https://twoprocessmodel.readthedocs.io/

**Health Connect**
- [L41] Android, Read data: https://developer.android.com/health-and-fitness/health-connect/read-data
- [L42] Android, Data types: https://developer.android.com/health-and-fitness/guides/health-connect/plan/data-types
- [L43] Android, Sleep guide: https://developer.android.com/health-and-fitness/health-connect/experiences/sleep
- [L44] Android, Rate limiting: https://developer.android.com/health-and-fitness/guides/health-connect/plan/rate-limiting
- [L45] Android, Declare access: https://developer.android.com/health-and-fitness/guides/health-connect/publish/declare-access
- [L46] Google Health Help, Health Connect: https://support.google.com/googlehealth/answer/14506680?hl=en
- [L47] Google Play Policy, Health Connect: https://support.google.com/googleplay/android-developer/answer/9888170
- [L48] Android, HeartRateVariabilityRmssdRecord: https://developer.android.com/reference/kotlin/androidx/health/connect/client/records/HeartRateVariabilityRmssdRecord und Tom's Guide (Dritte): https://www.tomsguide.com/wellness/fitness-trackers/garmin-clarifies-what-data-its-sharing-with-google-health-connect-heres-the-full-list

**Hersteller**
- [L49] Polar AccessLink API v3: https://www.polar.com/accesslink-api/
- [L50] Garmin Personal API: https://developer.garmin.com/gc-developer-program/personal/personal-api/
- [L51] Garmin Personal API FAQ: https://developer.garmin.com/gc-developer-program/personal/personal-faq/
- [L52] Garmin Program Overview: https://developer.garmin.com/gc-developer-program/overview/
- [L53] the5krunner, Personal API (Dritte): https://the5krunner.com/2026/10/22/garmin-personal-api/
- [L54] Garmin Business FAQ und Health API: https://developer.garmin.com/gc-developer-program/enterprise/program-faq/ und https://developer.garmin.com/gc-developer-program/enterprise/health-api/
- [L55] Open Wearables, Garmin (Dritte): https://openwearables.io/blog/garmin-connect-developer-program-reopened
- [L56] Google Health API, About: https://developers.google.com/health/about
- [L57] Google Health API, Data types: https://developers.google.com/health/data-types und Device compatibility: https://developers.google.com/health/data-types/device-compatibility
- [L58] Google Health API, Migration: https://developers.google.com/health/migration
- [L59] Google Health API, Checklist: https://developers.google.com/health/developer-checklist
- [L60] Google Health API, Rate limits: https://developers.google.com/health/rate-limits und Scopes: https://developers.google.com/health/scopes
- [L61] Google, OAuth für native Apps: https://developers.google.com/identity/protocols/oauth2/native-app
- [L62] Google, Restricted Scope Verification: https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification
- [L63] RFC 8252, OAuth 2.0 for Native Apps: https://www.rfc-editor.org/rfc/rfc8252.html
- [L77] Google Health API, App verification (Stand 2026-09-25): https://developers.google.com/health/app-verification
- [L78] Google Health API, Setup: https://developers.google.com/health/setup und Codelab: https://developers.google.com/health/codelabs/make-your-first-api-call
- [L79] Android, Authorize access to Google user data: https://developer.android.com/identity/authorization
- [L80] Garmin, OAuth2.0 PKCE Specification (PDF): https://developerportal.garmin.com/sites/default/files/OAuth2PKCE.pdf
- [L64] Suunto API Zone: https://apizone.suunto.com/
- [L65] Open Wearables, Suunto (Dritte): https://openwearables.io/docs/providers/suunto-api-integration
- [L66] Tredict, Suunto HRV und Schlaf, 2024 (Dritte): https://www.tredict.com/blog/suunto_hrv_and_sleep_data/
- [L81] Suunto, FAQ: https://apizone.suunto.com/faq und How to start: https://apizone.suunto.com/how-to-start
- [L82] Polar API Limited License Agreement (gezielt gelesen): https://www.polar.com/en/legal/polar-api-agreement
- [L67] Withings Developer und Kurzreferenz: http://developer.withings.com/ und https://developer.withings.com/llms.md
- [L68] Withings, Available Health Data: https://developer.withings.com/developer-guide/v3/data-api/all-available-health-data/
- [L69] Withings OpenAPI: https://developer.withings.com/openapi.yaml
- [L70] Open Wearables, Withings (Dritte): https://openwearables.io/docs/providers/withings-api-integration.md

## Nicht abrufbar

- Hal Higdon, Trainingspläne für 5 km, 10 km und Halbmarathon: Verbindung abgelehnt. Das TrainingPeaks-Angebot desselben Plans nennt keine Länge. Daher kein Beleg.
- Garmin, eigene Seiten zu Body Battery (Blog und Technologieseite 403, garmin.ae 404).
- Garmin Personal API Swagger-Doku (Inhalt nur per Skript), Dokumentation im Developer Portal (Login), Bedingungen der Personal API.
- Google Health API, Anleitung zur Authentifizierung unter `/health/authentication` (404); die Einrichtung steht unter `/health/setup` [L78].
- Withings: Preise und Unterseiten zur Einrichtung (Weiterleitung auf die Startseite). Suunto: API-Referenz nur für Partner; die Seite `/apis` zeigte keine Liste.
- Daan et al. 1984 (Originalwerte für τ), nur über [L40].
- Lolli et al. 2019, BJSM (403); deshalb nicht als Beleg zur mathematischen Kopplung verwendet.
- Eine PubMed-Suche nach Studien zu Entlastungswochen und zu Trainingspausen bei Läufern (Metaanalyse) ergab keine passenden Treffer. Bücher wie Daniels oder Pfitzinger wurden nicht als Volltext gesucht.

## Validierungsbedarf

Die Validierung erfolgt im Feldtest und ist kein Release-Gate (OQ-0020). Die unsichersten Werte, geordnet nach Risiko:

| Werte | Warum unsicher | Prüfung |
|---|---|---|
| PAR-192 bis PAR-206 | Einfache, gesetzte Startwerte ohne Beleg. Für Steigerungsraten gibt es keine belegte sichere Grenze [L4, L5]. | Im Feldtest: Antworten „zu leicht“ und „zu schwer“ je Wochenzeit, Abbrüche, wiederholte Wochen, gemeldete Beschwerden. Ob Ziele zum Datum erreicht werden. Daraus keine medizinische Aussage ableiten. |
| PAR-073, PAR-089 | TSB% wirkt nicht mehr auf den Plan, nur noch auf die Readiness (PAR-168). Unregelmäßiges Training und der Einschwingfehler können falsche Werte erzeugen. | Historien mit geplanten und ungeplanten Wochen auswerten. |
| PAR-086, PAR-087 | Die CV-Werte stammen aus 10 Personen im Labor. Unbekannt, wie stabil der persönliche Faktor über Monate ist. | Läufe mit Puls und RPE: Faktor aus den ersten 10 Läufen gegen die folgenden Läufe vorhersagen. Abweichung und Zeitdrift messen. |
| PAR-081, PAR-082 | Auch Stufe „gut“ sagt nichts zur Genauigkeit. | Pace-Bereich gegen Wettkampf- und Testzeiten prüfen. Anteil der Nutzer ohne Pace-Vorgabe ermitteln, besonders unter 8 km/h. |
| PAR-091 bis PAR-099 | Reine Annahmen. Prozess S ist kein Energiemodell. | FR-0124: Mindestens 8 Wochen Tagesdaten. Verlauf gegen Selbstauskunft zu Erholung prüfen, Empfindlichkeit für τ, `f` und Sport messen, auch den Übertrag über die Nacht (PAR-094), Takt und Datenverzögerung von Health Connect je Quell-App messen. |
| Teil D | Bedingungen ändern sich, und Teile sind nur aus Drittquellen bekannt. | Health Connect vor der Umsetzung neu abrufen und je Quell-App die gelieferten Datenarten prüfen. Zurückgestellte Wege erst bei einer Neubewertung von OQ-0047 klären, dann direkt beim Anbieter: Google (Sicherheitsprüfung, Weg für reine Android-Clients) und Garmin (Geltung der PKCE-Spezifikation nach dem Neustart, Ping/Pull, Bedingungen der Personal API). |

Personenbezogene Daten bleiben dabei unter den Regeln von SEC-0001 bis SEC-0010.
