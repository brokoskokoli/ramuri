# Funktionales Konzept – Adaptive Running & Fitness App

**Version:** 0.1 – Entwurf  
**Zielplattformen:** Android, später optional iOS  
**Produktbereich:** Laufaufzeichnung, Fitnessanalyse, Regeneration und adaptive Trainingsplanung  
**Dokumenttyp:** Funktionale Produktspezifikation einschließlich Berechnungsmodellen  
**Ausgeschlossen:** Softwarearchitektur, Programmiersprachen, Frameworks, Datenbanktechnologien und technische Deployment-Entscheidungen

---

# 1. Produktvision

Die App soll Läufer dabei unterstützen, ihre Trainingseinheiten aufzuzeichnen, ihre körperliche Leistungsfähigkeit zu verstehen und individuelle Trainingsziele zu erreichen.

Sie kombiniert GPS-Aufzeichnung, Herzfrequenzmessung, sportwissenschaftliche Berechnungsmodelle und eine adaptive Trainingsplanung.

Der Nutzer soll seine bevorzugenen Pulssensoren, Fitnessuhren oder Kopfhörer verwenden können, ohne an einen bestimmten Hersteller gebunden zu sein.

Ein zentrales Merkmal ist die **datengestützte Trainingsplanung**: Statt einen einmaligen, statischen Trainingsplan zu erstellen, berücksichtigt die App fortlaufend die tatsächlichen Trainingseinheiten, die Leistungsentwicklung und – sofern entsprechende Daten verfügbar sind – den aktuellen Erholungszustand.

## 1.1 Grundprinzipien

1. **Geräteunabhängigkeit:** Keine Bindung an eine bestimmte Sportuhr oder einen Pulsmesser.
2. **Funktionalität ohne Wearable:** GPS-Aufzeichnung, Laufstatistiken und einfache Trainingsplanung müssen allein mit dem Smartphone funktionieren.
3. **Transparente Berechnungen:** Fitnesswerte sollen nachvollziehbar sein. Der Nutzer kann sehen, auf welchen Daten eine Schätzung beruht.
4. **Adaptive Trainingsplanung:** Trainingspläne passen sich an Fortschritte, verpasste Trainingseinheiten und Belastung an.
5. **Optionale Gesundheitsdaten:** Zusätzliche Daten verbessern die Analyse, dürfen aber keine Voraussetzung für die Grundfunktionen sein.
6. **Datenhoheit:** Aufgezeichnete Läufe und Fitnessdaten müssen unabhängig von externen Fitnessplattformen nutzbar und exportierbar bleiben.
7. **Kennzeichnung von Unsicherheit:** Geschätzte Werte und unvollständige Daten müssen klar erkennbar sein.

# 2. Nutzerprofil und persönliche Einstellungen

Beim ersten Start richtet der Nutzer ein persönliches Profil ein.

## 2.1 Persönliche Daten

| Datenfeld | Zweck | Erforderlich |
|---|---|---|
| Alter oder Geburtsjahr | Näherung für maximale Herzfrequenz | Optional |
| Körpergewicht | Optionale Energieverbrauchsschätzung | Optional |
| Körpergröße | Erweiterte Analysen | Optional |
| Ruheherzfrequenz | Intensitäts- und VO₂max-Schätzung | Optional |
| Maximale Herzfrequenz | Belastungszonen und Fitnessberechnung | Optional |
| Fitness-/Lauferfahrung | Auswahl des anfänglichen Trainingsplans | Für Trainingspläne |
| Aktuelle Laufleistung | Einschätzung des Trainingsniveaus | Für Trainingspläne |
| Verfügbare Trainingstage | Trainingskalender | Für Trainingspläne |
| Übliche Trainingsdauer | Trainingsplanung | Optional |

Eine gemessene maximale Herzfrequenz ist einer altersbasierten Schätzung vorzuziehen.

Wenn kein Wert bekannt ist, kann vorläufig verwendet werden:

$$
HF_{max}=208-0{,}7\cdot Alter
$$

Diese Näherung besitzt eine erhebliche individuelle Streuung. Der Nutzer kann den Wert jederzeit korrigieren.

Änderungen an persönlichen Basiswerten müssen zu einer nachvollziehbaren Neuberechnung der davon abhängigen Fitnesswerte führen können.

# 3. Verbindung von Sensoren und Fitnessgeräten

Die App unterstützt verschiedene Quellen für Herzfrequenz- und Gesundheitsdaten.

## 3.1 Direkte Herzfrequenzmessung

Unterstützte Gerätekategorien:

- Bluetooth-Brustgurte
- Bluetooth-Oberarmsensoren
- Fitnessuhren mit Herzfrequenz-Broadcast
- Fitnessarmbänder mit geeigneter Schnittstelle
- Kopfhörer mit integrierter Herzfrequenzmessung
- Weitere kompatible Herzfrequenzsensoren

Die App soll standardisierte Bluetooth-Herzfrequenzgeräte automatisch erkennen können.

Fitnessuhren ohne standardisierte Live-Übertragung sollen gegebenenfalls durch eine ergänzende Uhrenanwendung unterstützt werden können.

Herstellerspezifische Anbindungen sind optionale Erweiterungen.

## 3.2 Sensorverwaltung

Der Nutzer kann:

- Verfügbare Geräte suchen
- Ein Gerät verbinden und trennen
- Mehrere bekannte Geräte speichern
- Ein bevorzugtes Gerät festlegen
- Die aktuelle Herzfrequenz anzeigen
- Den Batteriestand anzeigen, sofern bereitgestellt
- Verbindungsabbrüche erkennen
- Während eines Trainings die Datenquelle wechseln

Bei mehreren aktiven Herzfrequenzquellen muss eine eindeutige Priorisierung erfolgen. Unterschiedliche Messwerte dürfen nicht unkontrolliert vermischt werden.

Die App dokumentiert, von welchem Gerät die Messwerte stammen.

## 3.3 Erweiterte Sensordaten

Falls vorhanden, können zusätzlich aufgezeichnet werden:

- RR-Intervalle zwischen Herzschlägen
- Herzfrequenzvariabilität (HRV)
- Laufkadenz
- Laufleistung
- Zusätzliche Bewegungsdaten

Die Verfügbarkeit dieser Daten ist geräteabhängig.

## 3.4 Import vorhandener Gesundheitsdaten

Mit Zustimmung des Nutzers können kompatible Gesundheitsplattformen als zusätzliche Datenquellen dienen.

Mögliche Daten:

- Historische Trainingseinheiten
- Herzfrequenzverlauf
- Ruheherzfrequenz
- HRV
- Schlafdauer und Schlafphasen
- Bereits vorhandene VO₂max-Schätzwerte

Importierte VO₂max-Werte anderer Hersteller dürfen zum Vergleich angezeigt werden, sollen aber nicht ungeprüft mit selbst berechneten Werten zu einer Zeitreihe zusammengeführt werden.

# 4. Aufzeichnung von Laufeinheiten

## 4.1 Trainingsstart

Der Nutzer startet eine freie Laufeinheit oder eine Trainingseinheit aus einem Trainingsplan.

Während des Trainings zeigt die App mindestens:

- Verstrichene Zeit
- Aktuelle Geschwindigkeit oder Pace
- Durchschnittliche Pace
- Zurückgelegte Strecke
- Aktuelle Herzfrequenz, sofern verfügbar
- Herzfrequenzzone
- GPS- und Sensorstatus

Optional:

- Rundenzeiten
- Höhenmeter
- Schrittfrequenz
- Soll-/Ist-Vergleich bei strukturierten Trainings
- Hinweise zum geplanten Belastungsbereich

## 4.2 Trainingssteuerung

Funktionen:

- Starten
- Pausieren
- Fortsetzen
- Beenden
- Optional automatisches Pausieren
- Manuelle Rundenmarkierung
- Akustische Trainingshinweise
- Warnung bei Überschreitung festgelegter Herzfrequenzbereiche
- Hinweise zum nächsten Trainingsintervall

Ein Training muss auch bei ausgeschaltetem Smartphone-Bildschirm weiter aufgezeichnet werden können.

## 4.3 Abschluss einer Einheit

Nach dem Lauf erscheint eine Zusammenfassung mit:

- Strecke
- Bewegungszeit und Gesamtzeit
- Durchschnitts- und Bestpace
- Durchschnitts- und Maximalpuls
- Herzfrequenzzonen
- Höhenprofil
- GPS-Karte
- Rundenzeiten
- Trainingsbelastung
- Einordnung gegenüber vorherigen Einheiten
- Optional aktualisierter VO₂max-Schätzung

Der Nutzer kann zusätzlich erfassen:

- Subjektive Anstrengung (RPE, 0–10)
- Allgemeines Befinden
- Schmerzen oder Beschwerden
- Freitextnotiz

Diese Eingaben können bei der künftigen Trainingsplanung berücksichtigt werden.

# 5. Trainingshistorie und Statistiken

Alle Laufeinheiten werden in einer Trainingshistorie dargestellt.

## 5.1 Einzelansicht

Jeder Lauf verfügt über eine Detailansicht mit GPS-Route, Zeitverlauf und Messwertdiagrammen.

Im Diagramm sollen beispielsweise Pace und Herzfrequenz zeitlich miteinander verglichen werden können.

## 5.2 Statistische Auswertungen

| Bereich | Kennzahlen |
|---|---|
| Umfang | Laufkilometer, Laufzeit, Trainingshäufigkeit |
| Geschwindigkeit | Durchschnittspace, Bestpace, Runden |
| Herzfrequenz | Durchschnitt, Maximum, Zonenverteilung |
| Fitness | Geschätzte VO₂max, aerobe Effizienz |
| Belastung | TRIMP, kurzfristige und langfristige Trainingsbelastung |
| Entwicklung | Wochen- und Monatsvergleiche |
| Leistung | Persönliche Bestzeiten, prognostizierte Wettkampfzeiten |
| Erholung | Training Readiness und optional Energiereserve |

Die App soll Statistiken nach einzelnen Läufen, Kalenderwochen, Monaten und frei wählbaren Zeiträumen anbieten.

# 6. Gemeinsame Grundlagen aller Berechnungen

Fitnessberechnungen sollen nicht unmittelbar auf ungefilterten Sensordaten stattfinden.

Daher wird vor der eigentlichen Berechnung eine gemeinsame Qualitätsbewertung durchgeführt.

## 6.1 Datenvorverarbeitung

Die Aufzeichnungen werden anhand ihrer Zeitstempel synchronisiert.

Zu berücksichtigen sind:

- GPS-Ungenauigkeiten
- Unplausible Positionssprünge
- Fehlende Herzfrequenzwerte
- Offensichtliche Sensorausreißer
- Zeitliche Verzögerung der Herzfrequenz
- Trainingspausen
- Messunterbrechungen
- Höhenmessungsfehler

Jeder für eine Fitnessberechnung verwendete Abschnitt erhält eine Qualitätsbewertung.

## 6.2 Grundlegende Bewegungswerte

Die zurückgelegte Strecke ergibt sich aus der Summe plausibler Positionsdistanzen.

Für die momentane Geschwindigkeit gilt:

$$
v=\frac{\Delta s}{\Delta t}
$$

Die Pace wird in Minuten beziehungsweise Sekunden pro Kilometer dargestellt:

$$
Pace_{s/km}=\frac{1000}{v_{m/s}}
$$

Für kurzfristige Tempoanzeigen werden geeignete gleitende Zeit- oder Distanzfenster verwendet, damit GPS-Schwankungen nicht zu ständig springenden Werten führen.

Die Bewegungszeit wird von der gesamten verstrichenen Zeit getrennt.

## 6.3 Qualität der Schätzwerte

Jeder fortgeschrittene Fitnesswert besitzt zusätzlich:

- Berechnungszeitpunkt
- Zugrunde liegenden Datenzeitraum
- Anzahl verwertbarer Messungen
- Datenquellen
- Verwendete Berechnungsmethode
- Versionsstand der Berechnung
- Qualitätsstufe: vorläufig, ausreichend, gut oder nicht bestimmbar

Die Qualitätsstufen sind zunächst produktinterne Regeln. Sie dürfen nicht als statistisch validierte Genauigkeitsangaben dargestellt werden.

# 7. Herzfrequenz und Trainingszonen

## 7.1 Herzfrequenzreserve

Die Herzfrequenzreserve bildet eine Grundlage für die individualisierte Belastungsbewertung.

$$
HFR=HF_{max}-HF_{Ruhe}
$$

Die relative Auslastung wird berechnet als:

$$
r=\frac{HF_{aktuell}-HF_{Ruhe}}{HF_{max}-HF_{Ruhe}}
$$

Beispiel:

- Maximale Herzfrequenz: 190 bpm
- Ruhepuls: 60 bpm
- Aktuelle Herzfrequenz: 151 bpm

$$
r=\frac{151-60}{190-60}=0{,}70
$$

Die relative Herzfrequenzreserve beträgt 70 %.

## 7.2 Herzfrequenzzonen

Die App bietet fünf konfigurierbare Trainingszonen.

Als vorläufiges Modell können Zonen auf Grundlage der Herzfrequenzreserve verwendet werden:

| Zone | Anteil der Herzfrequenzreserve | Bezeichnung |
|---|---|---|
| 1 | 50–60 % | Sehr leicht |
| 2 | 60–70 % | Leicht |
| 3 | 70–80 % | Moderat |
| 4 | 80–90 % | Hoch |
| 5 | 90–100 % | Sehr hoch |

Bereiche unterhalb von Zone 1 werden separat ausgewiesen.

Diese Einteilung ist eine konfigurierbare Näherung. Sie ersetzt keine individuell bestimmten ventilatorischen oder Laktatschwellen.

Später können Herzfrequenzzonen auch aus individuellen Leistungstests oder gemessenen Schwellen abgeleitet werden.

# 8. VO₂max-Schätzung

Die App soll die maximale Sauerstoffaufnahme anhand gewöhnlicher Laufeinheiten schätzen können.

Ein standardisierter Maximaltest ist dafür nicht zwingend erforderlich.

Der berechnete Wert ist eine indirekte Schätzung und keine tatsächliche Messung der maximalen Sauerstoffaufnahme.

## 8.1 Eingabedaten

Benötigt:

- Laufgeschwindigkeit
- Herzfrequenz
- Maximale Herzfrequenz
- Ruheherzfrequenz
- Zeitstempel

Optional:

- Streckensteigung
- Umgebungsbedingungen
- Individuelle Kalibrierungsdaten

## 8.2 Sauerstoffbedarf beim Laufen

Ein mögliches Basismodell ist die ACSM-Laufformel:

$$
VO_2=3{,}5+0{,}2v+0{,}9vG
$$

Dabei gilt:

- $VO_2$: Sauerstoffaufnahme in ml/kg/min
- $v$: Geschwindigkeit in Metern pro Minute
- $G$: Steigung als Dezimalzahl

Bei einer ebenen Strecke gilt vereinfacht:

$$
VO_2=3{,}5+0{,}2v
$$

Die Formel beschreibt einen geschätzten Sauerstoffbedarf bei geeigneter, annähernd gleichförmiger Laufbelastung. Sie ist insbesondere bei sehr langsamem Laufen, starkem Gefälle, Geländewechseln und wechselnder Laufökonomie begrenzt.

## 8.3 Hochrechnung auf VO₂max

Als einfaches Anfangsmodell wird angenommen, dass der Anteil der Herzfrequenzreserve ungefähr dem Anteil der genutzten Sauerstoffaufnahme-Reserve entspricht.

$$
VO_{2max}\approx3{,}5+\frac{VO_2-3{,}5}{r}
$$

mit

$$
r=\frac{HF-HF_{Ruhe}}{HF_{max}-HF_{Ruhe}}
$$

**Beispiel:**

- Laufgeschwindigkeit: 10 km/h
- Herzfrequenz: 150 bpm
- Maximalpuls: 190 bpm
- Ruhepuls: 60 bpm
- Ebene Strecke

Sauerstoffbedarf:

$$
VO_2=3{,}5+0{,}2\cdot166{,}67=36{,}83
$$

Herzfrequenzreserve:

$$
r=\frac{150-60}{190-60}=0{,}6923
$$

VO₂max-Schätzung:

$$
VO_{2max}\approx3{,}5+\frac{36{,}83-3{,}5}{0{,}6923}\approx51{,}6
$$

Ergebnis: ungefähr **51,6 ml/kg/min**.

Dieses Modell stellt bewusst einen nachvollziehbaren ersten Schätzer dar. Es muss durch Referenzdaten validiert werden, bevor eine bestimmte Messgenauigkeit versprochen werden kann.

## 8.4 Auswahl geeigneter Trainingsabschnitte

Nicht jeder Abschnitt eines Laufs ist zur VO₂max-Schätzung geeignet.

Verwendet werden bevorzugt gleichmäßige Belastungsphasen.

Vorläufige Auswahlregeln:

1. Mehrere Minuten annähernd konstante Bewegung
2. Keine Pause oder unmittelbar vorausgegangener Tempowechsel
3. Stabiler und plausibler Puls
4. Ausreichende GPS-Qualität
5. Keine starke Steigung oder starkes Gefälle
6. Keine offensichtlichen Messausreißer
7. Ausreichende Belastungsintensität

Für die erste, auf der ACSM-Laufformel basierende Implementierung werden vor allem Abschnitte mit klarer Laufgeschwindigkeit berücksichtigt. Sehr langsames Laufen oder Gehen darf nicht mit derselben Formel unkritisch bewertet werden.

Die konkreten Schwellenwerte für Geschwindigkeit, Stabilität und Mindestdauer sind zu validierende Modellparameter.

## 8.5 Verarbeitung eines Laufs

Der Ablauf:

1. Relevante Messdaten synchronisieren.
2. Geschwindigkeit und Herzfrequenz vorsichtig glätten.
3. Geeignete gleichmäßige Abschnitte identifizieren.
4. Für jeden Abschnitt Sauerstoffbedarf berechnen.
5. Für jeden Abschnitt eine VO₂max-Schätzung bestimmen.
6. Unplausible Schätzungen verwerfen.
7. Verbleibende Abschnitte nach Datenqualität gewichten.
8. Einen robusten Gesamtwert, beispielsweise einen gewichteten Median, berechnen.
9. Qualitätsbewertung für den Lauf vergeben.

Stark voneinander abweichende Schätzungen sollen die Konfidenz reduzieren.

## 8.6 Langfristige VO₂max

Der angezeigte langfristige VO₂max-Wert soll nicht bei jedem einzelnen Lauf stark schwanken.

Dafür werden mehrere geeignete Läufe berücksichtigt.

Eine mögliche Glättung ist:

$$
V_t=V_{t-1}+\alpha(V_{neu}-V_{t-1})
$$

Dabei ist $\alpha$ ein von Datenqualität und Datenmenge abhängiger Glättungsfaktor.

Bei unzureichender Datenqualität wird der Wert nicht aktualisiert.

Die App unterscheidet zwischen:

- Schätzung aus einem einzelnen Lauf
- Aktueller langfristiger VO₂max-Schätzung
- Verlauf über mehrere Wochen und Monate

Eine einzelne gute oder schlechte Trainingseinheit soll nicht als deutliche Fitnessveränderung interpretiert werden.

## 8.7 Individuelle Kalibrierung

Optional kann der Nutzer bekannte Leistungsdaten eingeben:

- Ergebnisse von Wettkämpfen
- Zeiten aus definierten Laufleistungstests
- Laborbestimmte VO₂max
- Bekanntes maximales Herzfrequenzniveau

Diese Werte können zur Bewertung und späteren Kalibrierung des Schätzmodells verwendet werden.

Laborwerte und indirekte Schätzwerte bleiben als unterschiedliche Messmethoden gekennzeichnet.

# 9. Aerobe Effizienz und Fitnessentwicklung

Zusätzlich zur VO₂max soll die App eine Kennzahl für die aerobe Laufeffizienz bieten.

Die Idee lautet: Wie schnell kann der Nutzer bei vergleichbarer relativer Herzbelastung laufen?

## 9.1 Referenzgeschwindigkeit

Die App sammelt geeignete Laufabschnitte in einem definierten Belastungsbereich, beispielsweise zwischen 65 und 75 % der Herzfrequenzreserve.

Für diese Abschnitte wird die mittlere oder mediane Geschwindigkeit berechnet.

Die Auswertung erfolgt bevorzugt unter vergleichbaren Bedingungen:

- Ähnlicher Herzfrequenzbereich
- Gleichmäßiges Tempo
- Vergleichbare Steigung
- Ausreichende Messqualität

## 9.2 Veränderung der aeroben Effizienz

$$
\Delta E=\left(\frac{v_{aktuell}}{v_{referenz}}-1\right)\cdot100
$$

Beispiel:

- Frühere Referenzgeschwindigkeit: 9,0 km/h
- Aktuelle Referenzgeschwindigkeit: 9,5 km/h

$$
\Delta E=5{,}56\%
$$

Die App zeigt eine Verbesserung der Geschwindigkeit bei vergleichbarer relativer Herzbelastung von ungefähr 5,6 %.

Diese Kennzahl ist keine direkte Messung der VO₂max. Sie wird unter anderem von Laufökonomie, Temperatur, Untergrund, Wind und Tagesform beeinflusst.

## 9.3 Herzfrequenzdrift

Optional kann die aerobe Entkopplung bei längeren gleichmäßigen Läufen untersucht werden.

Dabei wird geprüft, ob die Herzfrequenz im Verhältnis zur Geschwindigkeit im Laufe des Trainings ansteigt.

Ein mögliches Modell:

$$
D=\left(\frac{HF_2/v_2}{HF_1/v_1}-1\right)\cdot100
$$

Die Indizes bezeichnen die erste und zweite vergleichbare Hälfte eines geeigneten Laufabschnitts.

Eine positive Drift kann unter anderem durch Ermüdung, Hitze oder Flüssigkeitsverlust entstehen.

Der Wert wird nur für geeignete, ausreichend lange, weitgehend gleichmäßige Läufe berechnet.

# 10. Trainingsbelastung

Die App soll erfassen, wie belastend einzelne Trainingseinheiten sind und wie sich die gesamte Trainingsbelastung entwickelt.

## 10.1 Herzfrequenzbasierter Training Impulse (TRIMP)

Als erste Variante wird der Edwards-TRIMP verwendet.

Die Zeit in fünf Herzfrequenzzonen wird unterschiedlich gewichtet.

Für diese Berechnung beziehen sich die Zonen ausdrücklich auf den Anteil der **maximalen Herzfrequenz**, nicht auf die zuvor beschriebenen Zonen der Herzfrequenzreserve.

| Anteil HFmax | Gewicht |
|---|---:|
| 50–60 % | 1 |
| 60–70 % | 2 |
| 70–80 % | 3 |
| 80–90 % | 4 |
| 90–100 % | 5 |

$$
TRIMP=\sum_{i=1}^{5}t_i\cdot i
$$

Dabei ist $t_i$ die Anzahl der Minuten in der jeweiligen Zone.

Beispiel:

- 10 Minuten in Zone 1
- 30 Minuten in Zone 2
- 10 Minuten in Zone 4

$$
TRIMP=10\cdot1+30\cdot2+10\cdot4=110
$$

Die Einheit ist ein relativer Trainingsbelastungspunkt.

Die Zonen und Gewichte sind ein einfaches Belastungsmodell und kein direktes Maß für physiologische Ermüdung oder Trainingsanpassung.

## 10.2 Subjektive Trainingsbelastung

Wenn keine verlässlichen Pulswerte vorliegen, kann die Belastung anhand der subjektiven Anstrengung geschätzt werden.

Verwendet wird eine RPE-Skala von 0 bis 10.

$$
Load_{sRPE}=Dauer_{min}\cdot RPE
$$

Beispiel:

$$
45\cdot5=225
$$

Die subjektive Trainingsbelastung beträgt 225 Punkte.

Wichtig: TRIMP- und sRPE-Punkte sind unterschiedliche Skalen und dürfen nicht ohne Kalibrierung addiert werden.

Die App führt beide Werte zunächst getrennt.

Für langfristige Belastungsverläufe wird eine konsistente Messskala verwendet. Ein Wechsel zwischen den Skalen muss gekennzeichnet beziehungsweise individuell kalibriert werden.

## 10.3 Kurzfristige Trainingsbelastung – ATL

ATL bildet die jüngere Trainingsbelastung ab.

$$
ATL_t=ATL_{t-1}+\frac{L_t-ATL_{t-1}}{7}
$$

Dabei bezeichnet $L_t$ die gesamte Belastung des Tages auf einer einheitlichen Skala.

Das Modell verwendet einen exponentiell gewichteten Verlauf mit einer Zeitkonstante von sieben Tagen.

## 10.4 Langfristige Trainingsbelastung – CTL

CTL bildet die über einen längeren Zeitraum gewohnte Belastung ab.

$$
CTL_t=CTL_{t-1}+\frac{L_t-CTL_{t-1}}{42}
$$

Die Zeitkonstante beträgt 42 Tage.

CTL wird in der App als **langfristiges Belastungsniveau** bezeichnet und nicht mit der physiologisch gemessenen Fitness gleichgesetzt.

## 10.5 Training Stress Balance

$$
TSB_t=CTL_{t-1}-ATL_{t-1}
$$

Ein deutlich negativer TSB bedeutet, dass die jüngere Belastung höher liegt als die langfristig gewohnte Belastung.

Ein positiver TSB bedeutet eine relativ geringe jüngere Belastung.

Daraus ergibt sich aber nicht automatisch, ob eine Person tatsächlich vollständig erholt oder leistungsfähig ist.

## 10.6 Unvollständige Daten

Wenn Trainingseinheiten fehlen oder die Belastung mangels Puls- beziehungsweise RPE-Daten nicht bewertet werden kann, muss die App dies berücksichtigen.

Nicht aufgezeichnete Tage dürfen nur dann als trainingsfrei behandelt werden, wenn der Nutzer seine Trainingshistorie ausreichend vollständig führt.

Ein zunächst fehlender Datenbestand darf nicht automatisch als niedriges Fitnessniveau interpretiert werden.

# 11. Erholungszustand und Training Readiness

Die App soll den aktuellen Trainingsbereitschaftszustand einschätzen können.

Dabei werden zwei Stufen unterschieden.

## 11.1 Basis-Erholungseinschätzung

Auch ohne Fitnessuhr sind verfügbar:

- Kurzfristige Trainingsbelastung
- Langfristige Trainingsbelastung
- Tage seit dem letzten Training
- Subjektive Anstrengung vorheriger Trainings
- Optional selbst eingegebenes Wohlbefinden

Daraus kann die App Hinweise zur Trainingssteuerung ableiten.

Beispiel:

„Deine Trainingsbelastung lag in den letzten sieben Tagen deutlich über deinem bisherigen Niveau. Für heute wird ein lockerer Lauf empfohlen.“

Es wird jedoch nicht behauptet, dass daraus der tatsächliche körperliche Erholungszustand vollständig bestimmbar sei.

## 11.2 Erweiterte Training Readiness

Wenn zusätzliche Gesundheitsdaten vorhanden sind, kann die App weitere Faktoren verwenden:

- Nächtliche HRV
- Ruheherzfrequenz
- Schlafdauer
- Schlafqualität, soweit verfügbar
- Trainingsbelastung
- Subjektives Wohlbefinden

Der erweiterte Zustand wird mit einem Wert zwischen 0 und 100 und einer erklärenden Einordnung dargestellt.

Beispielhafte Faktoren:

| Faktor | Vorläufige Gewichtung |
|---|---:|
| HRV-Abweichung vom persönlichen Normalbereich | 25 % |
| Ruhepuls-Abweichung | 20 % |
| Schlaf | 30 % |
| Trainingsbelastung | 15 % |
| Subjektives Befinden | 10 % |

Diese Gewichtungen sind **Produktannahmen für einen später zu validierenden Algorithmus**, keine wissenschaftlich gesicherten Koeffizienten.

Fehlende Faktoren werden nicht automatisch als „normal“ bewertet. Die App zeigt gegebenenfalls nur eine eingeschränkte Einschätzung.

## 11.3 Individuelle Referenzwerte

Bei HRV und Ruhepuls sind individuelle Veränderungen aussagekräftiger als ein Vergleich mit pauschalen Bevölkerungswerten.

Deshalb verwendet die App einen persönlichen Referenzzeitraum, beispielsweise 28 Tage mit ausreichenden gültigen Messungen.

Eine robuste Abweichungsbewertung kann auf Median und Median Absolute Deviation (MAD) basieren:

$$
z=\frac{x-\operatorname{Median}(X)}{1{,}4826\cdot MAD(X)}
$$

Für HRV kann eine logarithmische Transformation vor der Berechnung sinnvoll sein.

Bei nicht ausreichender Streuung oder Datenmenge darf keine künstlich präzise standardisierte Abweichung erzeugt werden.

Messungen sollen nur dann direkt verglichen werden, wenn Messmethode und Messbedingungen ausreichend konsistent sind.

Insbesondere RMSSD und SDNN dürfen nicht als identische HRV-Werte behandelt werden.

## 11.4 Interpretation

Mögliche Zustände:

- Gut erholt
- Normal belastbar
- Erhöhte Belastung
- Erholung empfohlen
- Unzureichende Daten

Die App erklärt die wichtigsten Ursachen einer Bewertung.

Beispiel:

„Deine nächtliche HRV liegt unter deinem üblichen Bereich. Gleichzeitig ist dein Ruhepuls erhöht. Deshalb wird heute ein weniger intensives Training vorgeschlagen.“

Die App stellt daraus keine medizinische Diagnose.

# 12. Energiereserve – Body-Battery-ähnliche Funktion

Optional soll die App eine laufend aktualisierte Schätzung der körperlichen Energiereserve darstellen.

Diese Funktion setzt zusätzliche Daten voraus.

## 12.1 Voraussetzungen

Für eine aussagekräftige Schätzung werden insbesondere benötigt:

- Kontinuierliche oder ausreichend häufige Herzfrequenzmessungen
- Regelmäßige HRV-Daten
- Bewegungs- und Ruhephasen
- Schlafinformationen
- Trainingshistorie

Bei fehlenden Daten bleibt die Funktion deaktiviert oder wird ausdrücklich als unvollständig gekennzeichnet.

Eine normale Pulsaufzeichnung nur während des Laufens reicht dafür nicht aus.

## 12.2 Berechnungsmodell

Die Energiereserve wird als modellierter Zustand auf einer Skala von 0 bis 100 dargestellt.

$$
B_{t+1}=\operatorname{clamp}(B_t+R_t-D_t,0,100)
$$

Dabei gilt:

- $B_t$: bisherige Energiereserve
- $R_t$: modellierter Regenerationszuwachs
- $D_t$: modellierte Belastung

Die Aktualisierung erfolgt in regelmäßigen Zeitintervallen.

## 12.3 Regenerationskomponente

Die Regeneration steigt beispielsweise bei:

- Erholsamem Schlaf
- Längeren Ruhephasen
- Günstigen HRV-Werten gegenüber dem persönlichen Referenzbereich
- Niedriger physiologischer Belastung

## 12.4 Belastungskomponente

Die Energiereserve sinkt beispielsweise bei:

- Sportlicher Belastung
- Erhöhtem physiologischem Stress
- Schlechter Erholung
- Längerer Wachzeit

Die konkreten Zuwachs- und Abnahmeraten müssen empirisch kalibriert werden.

Die Werte stellen keine physikalisch messbare Energie dar.

## 12.5 Darstellung

Die App zeigt:

- Aktuelle Energiereserve
- Tagesdiagramm
- Veränderungen während des Schlafs
- Veränderungen während sportlicher Belastung
- Optional historische Trends

Bei längeren Datenlücken soll der Zustand nicht einfach mit einer angenommenen Standardbelastung weitergeführt werden. Stattdessen wird die Schätzung als veraltet beziehungsweise unvollständig gekennzeichnet.

Die Energiereserve und die Training Readiness werden getrennt geführt. Sie können ähnliche Eingangssignale verwenden, beschreiben aber unterschiedliche Konzepte.

# 13. Leistungsprognosen

Die App soll abschätzen können, welche Laufzeiten ein Nutzer über bestimmte Distanzen erreichen könnte.

Mögliche Distanzen:

- 5 km
- 10 km
- Halbmarathon
- Marathon

Die Prognose soll bevorzugt auf geeigneten tatsächlichen Leistungen basieren.

## 13.1 Riegel-Modell

Ausgehend von einer bekannten Wettkampf- oder vergleichbaren maximalen Laufleistung:

$$
T_2=T_1\left(\frac{D_2}{D_1}\right)^{1{,}06}
$$

Beispiel:

Ein Nutzer läuft 5 km in 25 Minuten.

$$
T_{10km}=25\cdot(10/5)^{1{,}06}
$$

Ergebnis: ungefähr 52 Minuten und 7 Sekunden.

Das Modell setzt voraus, dass die zugrunde liegende Referenzleistung ausreichend repräsentativ und der Nutzer für die neue Distanz entsprechend trainiert ist.

Ein normaler lockerer Lauf darf nicht ohne Weiteres als maximale Referenzleistung verwendet werden.

## 13.2 Prognosequalität

Die Zuverlässigkeit hängt ab von:

- Aktualität des Referenzlaufs
- Ähnlichkeit der Distanzen
- Trainingsumfang
- Regelmäßigkeit des Trainings
- Vorhandensein geeigneter Wettkampfergebnisse

Die App unterscheidet zwischen einer allgemeinen Leistungsschätzung und der Prognose für das konkret geplante Wettkampfziel.

Die VO₂max allein soll nicht zur verbindlichen Vorhersage einer Wettkampfzeit verwendet werden.

# 14. Individuelle Trainingsziele

Der Nutzer kann ein persönliches Trainingsziel definieren.

## 14.1 Zieltypen

**Distanzziele**

Beispiele:

- Erstmals 5 km durchlaufen
- 10 km ohne Pause laufen
- Halbmarathon absolvieren

**Zeitziele**

Beispiele:

- 5 km unter 25 Minuten
- 10 km unter 60 Minuten
- Halbmarathon unter zwei Stunden

**Allgemeine Fitnessziele**

Beispiele:

- Regelmäßig dreimal pro Woche laufen
- Ausdauer verbessern
- Laufumfang vorsichtig steigern
- Wieder mit dem Laufen beginnen

## 14.2 Zusätzliche Angaben

Für die Planung kann der Nutzer festlegen:

- Gewünschtes Zieldatum
- Verfügbare Wochentage
- Maximale Trainingszeit pro Einheit
- Gewünschte Anzahl Trainingstage pro Woche
- Bevorzugte Trainingstage
- Bekannte Einschränkungen
- Aktuelles Leistungsniveau
- Optional bisherige Wettkampfzeiten

Die App darf keine feste Zielzeit voraussetzen. Auch offene Ziele wie „allgemein fitter werden“ sind zulässig.

# 15. Automatische Erstellung eines Trainingsplans

Die App erzeugt auf Basis des Nutzerziels einen individuellen Trainingsplan.

## 15.1 Ausgangsanalyse

Zunächst werden folgende Informationen ausgewertet:

1. Gewünschtes Trainingsziel
2. Zeit bis zum Zieldatum
3. Aktuelle Laufleistung
4. Bisherige Trainingshäufigkeit
5. Wöchentlicher Laufumfang
6. Belastungshistorie
7. Aktueller Fitness- und Erholungszustand
8. Verfügbare Trainingstage

Wenn keine ausreichenden Daten vorliegen, wird ein konservativer Einstiegsplan erstellt.

Der erste Trainingsabschnitt dient dann zugleich dem Aufbau einer individuellen Datenbasis.

## 15.2 Trainingsphasen

Ein längerer Plan kann in unterschiedliche Phasen unterteilt werden.

| Phase | Hauptziel |
|---|---|
| Einstieg | Belastbarkeit und Ausgangsniveau bestimmen |
| Grundlagentraining | Aerobe Ausdauer und Trainingskontinuität |
| Aufbau | Trainingsumfang und spezifische Leistung entwickeln |
| Spezifisches Training | Vorbereitung auf das konkrete Laufziel |
| Reduktion vor Wettkampf | Belastung senken und Erholung ermöglichen |
| Zieltermin | Wettkampf oder Leistungstest |

Die Dauer der Phasen hängt vom Ziel, Trainingsstand und verfügbaren Zeitraum ab.

## 15.3 Trainingstypen

Der Trainingsplan kann enthalten:

- Lockere Dauerläufe
- Längere Dauerläufe
- Regenerationsläufe
- Intervalle
- Tempodauerläufe
- Progressive Läufe
- Optional Geh-/Laufintervalle für Anfänger
- Ruhetage

Jede Einheit besitzt eine klare Zielsetzung.

## 15.4 Beschreibung einer Trainingseinheit

Eine Einheit enthält mindestens:

- Bezeichnung
- Geplanten Tag
- Trainingsziel
- Dauer oder Distanz
- Zielintensität
- Optional Aufwärmphase
- Optional Hauptabschnitte
- Optional Abwärmphase

Die Zielintensität kann definiert werden durch:

- Herzfrequenzbereich
- Pace-Bereich
- Subjektive Anstrengung

Dabei ist zu beachten, dass eine genaue Pace-Vorgabe nicht aus einer unzureichenden VO₂max-Schätzung abgeleitet werden darf.

Bei Intervallen können Pace oder RPE geeigneter sein als eine unmittelbare Herzfrequenzsteuerung, da der Puls verzögert reagiert.

# 16. Algorithmus für die Trainingsplanung

Die Trainingsplanung erfolgt regelbasiert und berücksichtigt die vorhandenen Leistungsdaten.

## 16.1 Belastungsbudget

Für jede Trainingswoche wird ein geplanter Umfang und eine geplante Intensitätsverteilung bestimmt.

Die Ausgangswerte ergeben sich aus dem bisherigen Training und den persönlichen Voraussetzungen.

Die geplante Belastung wird bei ausreichender Erholung und guter Trainingsverträglichkeit schrittweise erhöht.

Dabei werden berücksichtigt:

- Belastungsniveau der vergangenen Wochen
- Bisherige Trainingskontinuität
- Anzahl der Trainingstage
- Intensitätsverteilung
- Subjektive Beschwerden und Ermüdung
- Zeitpunkt des Zielwettkampfs

Es wird keine pauschale prozentuale Steigerung für alle Nutzer als garantiert sicher angenommen.

Regelmäßige Wochen mit reduziertem Trainingsumfang können vorgesehen werden.

## 16.2 Verteilung der Einheiten

Bei drei Trainingstagen pro Woche wäre beispielsweise folgende Aufteilung möglich:

- Ein lockerer Dauerlauf
- Eine zielgerichtete intensivere Einheit
- Ein längerer, überwiegend lockerer Lauf

Für Einsteiger kann der Plan zunächst ausschließlich lockere beziehungsweise kombinierte Geh- und Lauftrainings enthalten.

Der Anteil intensiver Einheiten richtet sich nach Leistungsstand, Belastbarkeit und Ziel.

Intensive Trainingseinheiten sollen normalerweise nicht ohne ausreichende Erholung direkt aufeinanderfolgen.

## 16.3 Ableitung der Zielintensität

Die Trainingsintensitäten werden aus den verfügbaren Daten abgeleitet.

Bevorzugt:

1. Individuell bestimmte Schwellenwerte oder geeignete Leistungstests
2. Aktuelle aussagekräftige Wettkampfleistungen
3. Ausreichend belastbare Pace-/Puls-Beziehungen
4. Allgemeine Herzfrequenzzonen
5. Subjektive Anstrengung, falls andere Daten fehlen

Die Unsicherheit der Intensitätsvorgaben muss bei fehlenden Daten berücksichtigt werden.

## 16.4 Machbarkeit des Ziels

Die App soll beurteilen, ob das Ziel mit dem vorhandenen Zeitraum und Trainingsumfang plausibel erreichbar erscheint.

Dabei berücksichtigt sie:

- Aktuelles Leistungsniveau
- Differenz zum Zielniveau
- Verfügbare Trainingswochen
- Trainingshäufigkeit
- Bisherige Fortschrittsrate
- Notwendigen Aufbau der Ausdauer

Die Einschätzung wird beispielsweise dargestellt als:

- Ziel erscheint realistisch
- Ziel ist ambitioniert
- Ziel erscheint mit dem vorgesehenen Umfang eher unrealistisch
- Noch nicht ausreichend Daten vorhanden

Dies ist eine modellbasierte Einschätzung und keine Erfolgsgarantie.

# 17. Adaptive Anpassung des Trainingsplans

Der Trainingsplan wird fortlaufend an tatsächlich absolvierte Trainingseinheiten angepasst.

## 17.1 Relevante Ereignisse

Eine Neuberechnung kann ausgelöst werden durch:

- Abgeschlossenen Lauf
- Ausgefallenes Training
- Zusätzliches Training
- Deutliche Änderung der Trainingsbelastung
- Veränderungen der langfristigen Leistungsentwicklung
- Veränderten Erholungszustand
- Änderungen des Trainingsziels
- Änderungen der verfügbaren Trainingstage
- Nutzerfeedback zu Schmerzen, Krankheit oder Überlastung

## 17.2 Regelmäßige Anpassung

Die App überprüft den Trainingsplan mindestens wöchentlich.

Dabei werden ausgewertet:

- Geplanter und tatsächlicher Trainingsumfang
- Durchgeführte Trainingsarten
- Belastungsentwicklung
- Leistungsentwicklung
- Konsistenz der Trainingsteilnahme
- Verfügbare Erholungsdaten

Daraufhin werden zukünftige Trainingseinheiten angepasst.

## 17.3 Kurzfristige Anpassung

Vor einer geplanten Trainingseinheit kann die App eine erneute Empfehlung ausgeben.

Beispiele:

**Hohe Belastung**

Ursprünglich: Intensives Intervalltraining

Angepasst: Lockerer Dauerlauf oder Ruhetag

**Deutlich bessere Leistungsentwicklung**

Ursprünglich: Dauerlauf mit älterem Zieltempo

Angepasst: Moderat aktualisierter Zielbereich auf Grundlage mehrerer geeigneter Trainingseinheiten

**Training ausgefallen**

Ursprünglich: Intervalltraining am Dienstag

Angepasst: Trainingswoche neu verteilen, ohne automatisch sämtliche ausgefallenen Einheiten nachzuholen

**Beschwerden oder Krankheit**

Ursprünglich: Langer Dauerlauf

Angepasst: Keine intensive Einheit vorschlagen; bei entsprechenden Warnsignalen Trainingspause und gegebenenfalls medizinische Abklärung empfehlen

## 17.4 Planungsregeln

Folgende Regeln gelten grundsätzlich:

1. Langfristige Kontinuität ist wichtiger als das exakte Nachholen einzelner Einheiten.
2. Die Trainingsbelastung soll nicht aufgrund einer einzelnen positiven Messung stark erhöht werden.
3. Deutliche Überlastungssignale sollen konservative Anpassungen auslösen.
4. Pausen und Wiedereinstiege werden berücksichtigt.
5. Ein Trainingsziel wird nicht ohne Zustimmung des Nutzers verändert.
6. Der Nutzer behält die Kontrolle über die Trainingstermine.
7. Größere Änderungen werden begründet.

# 18. Trainingskalender

Die App stellt alle geplanten und absolvierten Trainingseinheiten in einem Kalender dar.

## 18.1 Kalenderfunktionen

- Wochen- und Monatsübersicht
- Anzeige geplanter Trainings
- Anzeige abgeschlossener Trainings
- Kennzeichnung ausgefallener Einheiten
- Training verschieben
- Training ersetzen
- Ruhetage festlegen
- Optional Trainingszeiten definieren
- Erinnerungen vor geplanten Trainings

Die App kann neue Termine empfehlen.

Beispiel:

„Der lange Dauerlauf passt besser auf Sonntag, da zwischen dem Tempotraining und dem langen Lauf mehr Erholungszeit liegt.“

Der Nutzer bestätigt Änderungen, bevor bestehende Kalendereinträge verändert werden.

## 18.2 Anpassung bei Terminverschiebungen

Wenn der Nutzer einen Termin verschiebt, prüft die App:

- Abstand zu intensiven Trainingseinheiten
- Verbleibende Trainingszeit
- Belastung der betreffenden Woche
- Verfügbare Alternativtage

Bei Konflikten werden Alternativen vorgeschlagen.

# 19. Erklärbare Trainingsempfehlungen

Die App soll nicht nur Zahlen und Trainingseinheiten anzeigen, sondern deren Bedeutung erklären.

Beispiele:

**Fitnessentwicklung**

„Deine geschätzte VO₂max ist in den vergangenen sechs Wochen von 43 auf 46 gestiegen. Die Schätzung basiert auf fünf geeigneten Läufen.“

**Trainingsempfehlung**

„Für morgen ist ein lockerer Dauerlauf vorgesehen. Deine kurzfristige Trainingsbelastung liegt aktuell über deinem langfristigen Durchschnitt.“

**Planänderung**

„Das intensive Training wurde um einen Tag verschoben, weil sich dadurch ein zusätzlicher Erholungstag ergibt.“

**Datenqualität**

„Für diesen Lauf konnte keine zuverlässige VO₂max-Schätzung berechnet werden. Die Geschwindigkeit und Herzfrequenz waren über längere Abschnitte nicht stabil genug.“

Erklärungen müssen auf tatsächlich vorhandenen Daten und den verwendeten Berechnungsregeln beruhen.

# 20. Export und externe Fitnessplattformen

## 20.1 Dateiexport

Die App soll aufgezeichnete Laufeinheiten in standardisierten Formaten exportieren können.

Unterstützte Formate:

- GPX
- TCX
- FIT

Exportiert werden sollen je nach Format:

- GPS-Strecke
- Zeitstempel
- Herzfrequenz
- Höhenwerte
- Gegebenenfalls Kadenz und weitere vorhandene Trainingsdaten

Nicht unterstützte Zusatzmetriken, beispielsweise eine selbst berechnete VO₂max, müssen bei Bedarf separat exportierbar sein.

## 20.2 Strava-Integration

Optional kann der Nutzer sein Strava-Konto verbinden.

Funktionen:

- Einmalige Kontoverknüpfung
- Manueller Upload einzelner Läufe
- Optionale automatische Synchronisierung
- Anzeige des Upload-Status
- Behandlung von Uploadfehlern
- Vermeidung doppelter Uploads
- Trennung der Verbindung durch den Nutzer

Die Verbindung ist vollständig optional.

Die App darf nicht davon abhängig sein, dass Strava verfügbar ist.

## 20.3 Allgemeiner Datenexport

Neben einzelnen Aktivitäten soll ein Gesamtexport der Nutzerdaten möglich sein.

Dazu gehören Trainingshistorie, persönliche Einstellungen und verfügbare berechnete Fitnesswerte.

# 21. Datenschutz und Datenkontrolle

Da Herzfrequenz-, Schlaf- und Trainingsinformationen sensible persönliche Daten darstellen, gelten folgende funktionale Anforderungen:

- Gesundheitsdaten werden nur mit ausdrücklicher Zustimmung verwendet.
- Der Nutzer kann einzelne Datenquellen getrennt freigeben.
- Externe Synchronisierung ist optional.
- Export und Löschung der eigenen Daten sind möglich.
- Es muss erkennbar sein, welche Daten aus welchen Quellen stammen.
- Fitnessberechnungen sollen ohne zwingende externe Datenübertragung möglich sein.
- Der Nutzer kann Berechtigungen widerrufen.
- Externe Daten dürfen nicht ohne Einwilligung an Dritte übertragen werden.

# 22. Verhalten bei fehlenden Daten

Die App arbeitet mit unterschiedlichen Datenverfügbarkeitsstufen.

| Datenbasis | Verfügbare Funktionen |
|---|---|
| Nur Smartphone/GPS | Laufaufzeichnung, Pace, Strecke, Grundstatistik, einfache Trainingsplanung |
| GPS + Herzfrequenz | Herzfrequenzzonen, TRIMP, erste VO₂max-Schätzungen, aerobe Effizienz |
| Mehrwöchige Trainingshistorie | ATL/CTL, Fitness-Trends, verbesserte adaptive Trainingsplanung |
| Zusätzlich valide HRV-/Schlafdaten | Erweiterte Training Readiness |
| Kontinuierliche Tages- und Schlafdaten | Optionaler Energiereserve-Verlauf |
| Geeignete Wettkampfdaten | Leistungsprognosen und verbesserte Zielplanung |

Ein fehlender Sensorwert darf nicht als Nullmessung interpretiert werden.

Die App unterscheidet ausdrücklich zwischen:

- Messwert vorhanden
- Messwert geschätzt
- Messwert nicht verfügbar
- Messwert wegen schlechter Qualität verworfen

# 23. Berechnungs- und Modellqualität

Alle fitnessbezogenen Algorithmen müssen versionierbar und nachvollziehbar sein.

Für die spätere Produktentwicklung gelten folgende Anforderungen:

## 23.1 Wissenschaftliche Grundlage

Es wird zwischen drei Kategorien unterschieden:

**A. Etablierte Rechenverfahren**

Beispiele:

- Herzfrequenzreserve
- ACSM-Gleichungen zur Sauerstoffbedarfschätzung
- TRIMP
- Exponentiell gewichtete Trainingsbelastung
- Riegel-Leistungsprognose

**B. Eigene, heuristische Verfahren**

Beispiele:

- Gewichtung einzelner VO₂max-Segmente
- Qualitätsbewertung
- Training-Readiness-Score
- Energiereserve
- Regelbasierte Trainingsanpassung

**C. Individuell kalibrierte Verfahren**

Beispiele:

- Nutzerabhängige VO₂max-Korrektur
- Individuelle Trainingszonen
- Individuelle Belastungsverträglichkeit
- Prognosen anhand eigener Leistungshistorie

Eigene Heuristiken dürfen nicht als wissenschaftlich validiert dargestellt werden, solange keine entsprechende Validierung stattgefunden hat.

## 23.2 Neubewertung von Berechnungen

Eine Änderung des Berechnungsalgorithmus oder persönlicher Basiswerte kann dazu führen, dass historische Fitnesswerte neu berechnet werden müssen.

Die App soll dann unterscheiden können zwischen:

- Ursprünglich berechnetem Wert
- Aktuell neu berechnetem Wert
- Ursprünglicher Datenqualität

## 23.3 Konfidenz und Nachvollziehbarkeit

Ein geschätzter Fitnesswert soll mindestens folgende Fragen beantworten können:

- Aus welchen Daten wurde er berechnet?
- Wie alt sind diese Daten?
- Wie viele geeignete Messungen wurden verwendet?
- Welche Methode wurde verwendet?
- Ist das Ergebnis ausreichend zuverlässig?
- Wurde der Wert direkt gemessen oder geschätzt?

# 24. Empfohlener Funktionsumfang nach Entwicklungsphase

## Phase 1 – Laufaufzeichnung und grundlegende Fitnessanalyse

**Ziel:** Vollständig verwendbare Lauf-App mit eigener Trainingshistorie und ersten Fitnessberechnungen.

Enthalten:

- Nutzerprofil
- Verbindung kompatibler Bluetooth-Pulssensoren
- GPS-Laufaufzeichnung
- Live-Anzeige der Herzfrequenz
- Trainingshistorie
- Routen und Statistiken
- Herzfrequenzzonen
- VO₂max-Schätzung
- Aerober Fitness-Trend
- TRIMP-Berechnung
- FIT-/TCX-/GPX-Export
- Optionale Strava-Synchronisierung

## Phase 2 – Adaptiver Trainingscoach

**Ziel:** Trainingsziele und personalisierte Trainingsplanung.

Enthalten:

- Trainingsziele
- Trainingskalender
- Individuelle Trainingspläne
- Strukturierte Trainingseinheiten
- Subjektive Trainingsbelastung
- ATL-/CTL-Verlauf
- Leistungsprognosen
- Automatische Plananpassungen
- Erklärbare Trainingsempfehlungen

## Phase 3 – Erweiterte Gesundheits- und Erholungsanalyse

**Ziel:** Weitere Personalisierung mit Gesundheitsdaten.

Enthalten:

- Import von Schlafdaten
- Import von HRV-Daten
- Individuelle Ruhepuls- und HRV-Referenzwerte
- Erweiterte Training Readiness
- Erholungsbasierte Trainingsanpassungen
- Body-Battery-ähnliche Energiereserve, sofern ausreichend kontinuierliche Daten verfügbar sind

## Phase 4 – Erweiterter persönlicher Trainingscoach

Mögliche Zusatzfunktionen:

- Individuell kalibrierte Fitnessmodelle
- Erweiterte Leistungsprognosen
- Trainingsplanung für mehrere gleichzeitige Ziele
- Weitere Sportarten
- Optionale sprachbasierte Bedienung
- Optionaler KI-Dialog für Trainingsfragen
- Erweiterte Anbindung verschiedener Smartwatches

# 25. Funktionale Abnahmekriterien

Das funktionale Konzept gilt in seinen jeweiligen Entwicklungsphasen als erfüllt, wenn mindestens folgende Anforderungen nachweisbar sind:

1. Ein Nutzer kann einen Lauf vollständig ohne Pulssensor aufzeichnen.
2. Ein kompatibler Bluetooth-Pulssensor kann verbunden und während eines Laufs live ausgelesen werden.
3. Ein Verbindungsabbruch führt nicht zum Verlust des übrigen Laufs.
4. Die Trainingshistorie zeigt aufgezeichnete Läufe mit Strecke, Dauer, Pace und vorhandenen Herzfrequenzdaten.
5. Eine VO₂max-Schätzung wird nur aus dafür geeigneten Daten berechnet und als Schätzung gekennzeichnet.
6. Der Nutzer kann nachvollziehen, warum ein Fitnesswert berechnet oder nicht berechnet wurde.
7. Trainingsbelastung und langfristige Belastungstrends verwenden eine konsistente Berechnungsskala.
8. Ein Trainingsplan kann anhand eines Ziels und verfügbarer Trainingstage erstellt werden.
9. Der Plan reagiert auf zusätzliche oder ausgefallene Trainingseinheiten.
10. Größere Planänderungen werden begründet.
11. Eine Training-Readiness-Bewertung berücksichtigt fehlende Daten und persönliche Referenzwerte.
12. Eine Energiereserve wird nicht ohne geeignete kontinuierliche Daten als zuverlässiger aktueller Wert dargestellt.
13. Ein Lauf kann unabhängig von Strava exportiert werden.
14. Die App bleibt ohne externe Fitnessplattform nutzbar.
15. Persönliche Daten können vom Nutzer exportiert und gelöscht werden.

# 26. Offene fachliche Entscheidungen für die nächste Konzeptphase

Vor der technischen Spezifikation sollten insbesondere folgende Punkte fachlich entschieden werden:

1. **VO₂max-Modell:** Reicht der transparente ACSM-/Herzfrequenzreserve-Schätzer als erste Version oder soll von Anfang an ein auf Leistungsdaten kalibriertes Modell vorgesehen werden?
2. **Belastungsmodell:** Edwards-TRIMP als Standard oder ein kontinuierliches Modell wie Banister-TRIMP?
3. **Trainingsintensität:** Werden Herzfrequenzzonen allein genutzt oder wird möglichst früh ein individuelles Schwellenmodell ergänzt?
4. **Trainingspläne:** Welche konkreten Trainingsziele und Trainingsarten sollen zunächst abgedeckt werden?
5. **Personalisierung:** Welche Trainingsparameter darf das Modell automatisch verändern?
6. **Erholung:** Welche Mindestdatenqualität wird für einen numerischen Readiness-Wert vorausgesetzt?
7. **Energiereserve:** Soll diese ausschließlich mit kontinuierlicher Wearable-Datenerfassung angeboten werden?
8. **Leistungsprognosen:** Reicht zunächst die Riegel-Methode oder sollen mehrere Prognoseverfahren angeboten werden?
9. **Smartwatch-Nutzung:** Soll die Uhr nur als Pulssensor dienen oder später auch Trainingseinheiten selbstständig aufzeichnen und steuern können?
10. **Dateneingaben:** Welche Werte muss der Nutzer beim Einstieg angeben und welche können später automatisch gelernt werden?

# 27. Wissenschaftliche und fachliche Referenzen

Die nachfolgenden Quellen dienen als Ausgangspunkt für die spätere Vertiefung und Validierung:

- [Firstbeat – Automated Fitness Level Estimation with Heart Rate and Speed Data](https://assets.firstbeat.com/firstbeat/uploads/2015/10/white_paper_VO2max_11-11-2014.pdf)
- [Systematische Untersuchung der VO₂max-Genauigkeit bei Fitness-Wearables](https://pmc.ncbi.nlm.nih.gov/articles/PMC9213394/)
- [ACSM-Gleichungen zur Sauerstoffaufnahme](https://pmc.ncbi.nlm.nih.gov/articles/PMC12419060/)
- [Edwards-TRIMP – Zonenbasierte Trainingsbelastung](https://www.trainingimpulse.com/edwards-trimp)
- [TrainingPeaks – Wissenschaftliche Grundlagen des Belastungsmodells](https://www.trainingpeaks.com/learn/articles/the-science-of-the-performance-manager/)
- [HRV-gesteuertes Training – Systematische Übersichtsarbeit](https://pubmed.ncbi.nlm.nih.gov/34489178/)
- [Strava – Offizielle Upload-API](https://developers.strava.com/docs/uploads/)
- [Bluetooth – Heart Rate Service](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html)

---

**Ende des funktionalen Konzeptentwurfs v0.1.**

Die Spezifikation definiert die Produktfunktionen, benötigten Eingangsdaten, Berechnungsgrundlagen und fachlichen Abhängigkeiten. Die konkrete technische Umsetzung ist ausdrücklich noch nicht festgelegt.
