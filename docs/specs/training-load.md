---
id: FEAT-010
title: Trainingsbelastung
status: Approved
owner: TBD
source_refs: [SRC-001]
related_requirements: [FR-0091, FR-0092, FR-0093, FR-0094, FR-0095, FR-0096, FR-0097, FR-0098, FR-0099, FR-0100, FR-0101, FR-0102, FR-0103, FR-0104, FR-0197, FR-0199]
---

# Trainingsbelastung

## Ziel
Die App erfasst, wie belastend einzelne Einheiten sind und wie sich die gesamte Belastung entwickelt.

**Entschieden:** Für die erste Version gilt der Edwards-TRIMP (OQ-0002). Der TRIMP des gewählten Modells ist die Hauptskala für ATL und CTL (OQ-0015).

## Funktionale Anforderungen

### FR-0091 — Belastung erfassen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §10, Z. 542

Die App soll erfassen, wie belastend einzelne Trainingseinheiten sind und wie sich die gesamte Trainingsbelastung entwickelt.

**Akzeptanzkriterien:**
- [ ] Zu einem Lauf mit verwertbaren Daten liegt ein Belastungswert vor.

### FR-0092 — Edwards-TRIMP als erste Variante
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §10.1, Z. 546–548, 552–576
- **Verwandt:** FR-0093, NFR-0002, OQ-0002, OQ-0014, OQ-0051, OQ-0070

Als erste Variante wird der Edwards-TRIMP verwendet. Die Zeit in fünf Herzfrequenzzonen wird unterschiedlich gewichtet: `TRIMP = Σ t[i] · i`, mit t[i] in Minuten. Die Einheit ist ein relativer Trainingsbelastungspunkt.

| Anteil HFmax | Gewicht |
|---|---:|
| 50–60 % | 1 |
| 60–70 % | 2 |
| 70–80 % | 3 |
| 80–90 % | 4 |
| 90–100 % | 5 |

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 10 min Zone 1, 30 min Zone 2, 10 min Zone 4 ergibt 110.
- [ ] Zeit unter 50 % HFmax hat das Gewicht 0; genau 60 % HFmax zählt zu 60–70 %; über 100 % zählt zu 90–100 % (OQ-0014).
- [ ] Als Zeit zählt die Bewegungszeit (OQ-0015).
- [ ] Mit Puls für mindestens 80 % der Bewegungszeit zählt der TRIMP aus der vorhandenen Zeit und ist als unvollständig markiert; darunter gilt der Lauf als nicht bewertet (OQ-0051).

### FR-0093 — TRIMP-Zonen beziehen sich auf die maximale Herzfrequenz
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §10.1, Z. 550
- **Verwandt:** FR-0062, OQ-0059

Für diese Berechnung beziehen sich die Zonen ausdrücklich auf den Anteil der maximalen Herzfrequenz, nicht auf die Zonen der Herzfrequenzreserve.

**Akzeptanzkriterien:**
- [ ] Eine Änderung der Reservezonen oder des Ruhepulses ändert den Edwards-TRIMP nicht, außer er wird nach PAR-018 unverfügbar.

### FR-0094 — TRIMP nicht als Maß für Ermüdung darstellen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §10.1, Z. 578

Die Zonen und Gewichte sind ein einfaches Belastungsmodell und kein direktes Maß für physiologische Ermüdung oder Trainingsanpassung.

**Akzeptanzkriterien:**
- [ ] Texte der App setzen den TRIMP nicht mit Ermüdung oder Trainingsanpassung gleich.

### FR-0095 — Subjektive Trainingsbelastung (sRPE)
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.2, Z. 582–596
- **Verwandt:** FR-0038, OQ-0015

Wenn keine verlässlichen Pulswerte vorliegen, kann die Belastung anhand der subjektiven Anstrengung geschätzt werden. Verwendet wird eine RPE-Skala von 0 bis 10: `Load_sRPE = Dauer[min] · RPE`.

**Akzeptanzkriterien:**
- [ ] Testfall aus der Quelle: 45 min bei RPE 5 ergibt 225 Punkte.
- [ ] Als Dauer zählt die Bewegungszeit (OQ-0015).

### FR-0096 — TRIMP und sRPE getrennt führen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.2, Z. 598–600
- **Verwandt:** OQ-0015

TRIMP- und sRPE-Punkte sind unterschiedliche Skalen und dürfen nicht ohne Kalibrierung addiert werden. Die App führt beide Werte zunächst getrennt.

**Akzeptanzkriterien:**
- [ ] Beide Werte werden getrennt gespeichert und angezeigt.
- [ ] Ohne Kalibrierung entsteht keine Summe aus beiden Skalen.

### FR-0097 — Konsistente Skala für Belastungsverläufe
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.2, Z. 602; §25 Nr. 7, Z. 1402
- **Verwandt:** ACC-07, OQ-0015, OQ-0046

Für langfristige Belastungsverläufe wird eine konsistente Messskala verwendet. Ein Wechsel zwischen den Skalen muss gekennzeichnet beziehungsweise individuell kalibriert werden.

**Akzeptanzkriterien:**
- [ ] Ein Verlauf enthält keine ungekennzeichnete Mischung der Skalen (ACC-07).
- [ ] Läufe ohne Puls werden über einen persönlichen Faktor aus Läufen mit beiden Werten umgerechnet und gekennzeichnet (OQ-0015).
- [ ] Bis genug solche Läufe vorliegen, gelten sie als nicht bewertet (OQ-0015, OQ-0046).

### FR-0098 — Kurzfristige Trainingsbelastung (ATL)
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.3, Z. 606–614
- **Verwandt:** FR-0097, OQ-0015, OQ-0016, OQ-0046, OQ-0054

ATL bildet die jüngere Belastung ab: `ATL[t] = ATL[t−1] + (L[t] − ATL[t−1]) / 7`. L[t] ist die gesamte Tagesbelastung auf einer einheitlichen Skala. Das Modell ist exponentiell gewichtet mit einer Zeitkonstante von sieben Tagen.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): ATL[t−1] = 70, L[t] = 140 ergibt ATL[t] = 80.
- [ ] ATL und CTL starten bei 0 und sind zunächst als vorläufig markiert (OQ-0016, OQ-0046).
- [ ] An Tagen mit unbewerteter Einheit bleiben ATL und CTL unverändert, und der Tag ist gekennzeichnet (OQ-0054).

### FR-0099 — Langfristige Trainingsbelastung (CTL)
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.4, Z. 618–624
- **Verwandt:** FR-0097, OQ-0015, OQ-0016, OQ-0054

CTL bildet die über einen längeren Zeitraum gewohnte Belastung ab: `CTL[t] = CTL[t−1] + (L[t] − CTL[t−1]) / 42`. Die Zeitkonstante beträgt 42 Tage.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): CTL[t−1] = 42, L[t] = 84 ergibt CTL[t] = 43.

### FR-0100 — CTL als langfristiges Belastungsniveau bezeichnen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.4, Z. 626
- **Verwandt:** OQ-0039

CTL wird in der App als „langfristiges Belastungsniveau“ bezeichnet und nicht mit der physiologisch gemessenen Fitness gleichgesetzt.

**Akzeptanzkriterien:**
- [ ] Die Oberfläche verwendet überall diese Bezeichnung, auch in Statistik und Erklärungen, und keinen Begriff wie „Fitness“ für CTL (OQ-0039).

### FR-0101 — Training Stress Balance (TSB)
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.5, Z. 630–638

`TSB[t] = CTL[t−1] − ATL[t−1]`. Ein deutlich negativer TSB bedeutet, dass die jüngere Belastung höher liegt als die langfristig gewohnte. Ein positiver TSB bedeutet eine relativ geringe jüngere Belastung. Daraus ergibt sich nicht automatisch, ob eine Person tatsächlich vollständig erholt oder leistungsfähig ist.

**Akzeptanzkriterien:**
- [ ] Testfall (abgeleitet): CTL[t−1] = 50, ATL[t−1] = 70 ergibt TSB[t] = −20.
- [ ] Ein positiver TSB wird nicht als „vollständig erholt“ dargestellt.

### FR-0102 — Unvollständige Belastungsdaten berücksichtigen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.6, Z. 642
- **Verwandt:** OQ-0016, OQ-0054

Wenn Einheiten fehlen oder die Belastung mangels Puls- beziehungsweise RPE-Daten nicht bewertet werden kann, muss die App dies berücksichtigen.

**Akzeptanzkriterien:**
- [ ] Eine nicht bewertbare Einheit zählt nicht als Belastung 0 und ist erkennbar.

### FR-0103 — Nicht aufgezeichnete Tage nur bedingt als trainingsfrei
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.6, Z. 644
- **Verwandt:** OQ-0016, OQ-0058

Nicht aufgezeichnete Tage dürfen nur dann als trainingsfrei behandelt werden, wenn der Nutzer seine Trainingshistorie ausreichend vollständig führt.

**Akzeptanzkriterien:**
- [ ] Der Nutzer gibt an, ob er alle Trainings erfasst; nur dann gelten leere Tage als trainingsfrei (OQ-0016).
- [ ] Ohne diese Angabe bleiben ATL und CTL an leeren Tagen unverändert und dauerhaft vorläufig (OQ-0058).

### FR-0104 — Fehlender Datenbestand ist kein niedriges Fitnessniveau
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §10.6, Z. 646
- **Verwandt:** OQ-0016

Ein zunächst fehlender Datenbestand darf nicht automatisch als niedriges Fitnessniveau interpretiert werden.

**Akzeptanzkriterien:**
- [ ] Ein neuer Nutzer wird nicht allein wegen fehlender Historie als wenig fit eingestuft.

## Erfassung außerhalb der App

### FR-0199 — Training manuell nachtragen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-001 §17.1, Z. 1063; SRC-003 (OQ-0022)
- **Verwandt:** FR-0157, FR-0095, OQ-0022, OQ-0058

Der Nutzer kann ein Training mit Datum, Art, Dauer und RPE nachtragen. Es geht in Belastung und Plan ein, erzeugt aber keine GPS- oder VO₂max-Werte. Andere Sportarten lassen sich als „Sonstiges“ erfassen.

**Akzeptanzkriterien:**
- [ ] Ein nachgetragenes Training erscheint in der Belastung als gekennzeichneter umgerechneter sRPE-Wert, solange der Faktor nach PAR-086 fehlt als „nicht bewertet“.
- [ ] Es erzeugt keine VO₂max-Schätzung.
- [ ] „Sonstiges“ zählt für Belastung und Pausenende, aber nicht für Trainingsstand und längste Einheit (OQ-0058).

## Später wählbares Belastungsprofil

### FR-0197 — Belastungsprofil wählen
- **Status:** Approved | **Phase:** 2
- **Quelle:** SRC-003 (Maintainer 2026-11-03)
- **Verwandt:** FR-0097, NFR-0005, OQ-0043, OQ-0045, OQ-0053

Der Nutzer kann in Phase 2 sein Belastungsprofil auswählen, nach dem gerechnet wird. Startvariante ist der Edwards-TRIMP (OQ-0002).

**Akzeptanzkriterien:**
- [ ] Nach einer Auswahl rechnet die App mit dem gewählten Profil, und das verwendete Profil ist erkennbar.
- [ ] Das Profil wählt das Rechenmodell für die Belastung (OQ-0043).
- [ ] Beim Wechsel werden alte Läufe nach Bestätigung neu gerechnet, sodass ATL und CTL auf einer Skala bleiben (OQ-0043).
- [ ] Wählbar sind Edwards und Banister; ohne Ruhepuls oder ohne Angabe der Koeffizienten bleibt nur Edwards wählbar (OQ-0045, OQ-0053).
- [ ] Banister: `TRIMP = Σ t[min] · r · k · e^(b · r)` mit r aus FR-0060; männlich k = 0,64, b = 1,92; weiblich k = 0,86, b = 1,67. Die Werte stammen aus Sekundärquellen und sind vor der Umsetzung an der Originalarbeit zu prüfen (OQ-0053).
- [ ] Testfall: männlich, 30 min, HF 130, HFmax 200, HFRuhe 40 ergibt rund 32.
- [ ] Lehnt der Nutzer die Neuberechnung ab, verfällt die Modellwahl (OQ-0053).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0002](../migration/open-questions.md#oq-0002--welches-belastungsmodell-ist-standard) (entschieden): Welches Belastungsmodell ist Standard?
- [OQ-0014](../migration/open-questions.md#oq-0014--zuordnung-an-zonengrenzen-und-außerhalb-der-zonen) (entschieden): Zuordnung an Zonengrenzen und außerhalb der Zonen
- [OQ-0015](../migration/open-questions.md#oq-0015--welche-einheitliche-skala-speist-atl-und-ctl) (entschieden): Welche einheitliche Skala speist ATL und CTL?
- [OQ-0016](../migration/open-questions.md#oq-0016--startwerte-von-atlctl-und-vollständigkeit-der-historie) (entschieden): Startwerte von ATL/CTL und Vollständigkeit der Historie
- [OQ-0022](../migration/open-questions.md#oq-0022--wie-gelangen-trainings-außerhalb-der-app-in-die-daten) (entschieden): Wie gelangen Trainings außerhalb der App in die Daten?
- [OQ-0039](../migration/open-questions.md#oq-0039--benennung-von-ctl-in-statistik-und-erklärungen) (entschieden): Benennung von CTL in Statistik und Erklärungen
- [OQ-0043](../migration/open-questions.md#oq-0043--was-ist-ein-belastungsprofil-und-wie-weit-reicht-die-austauschbarkeit) (entschieden): Was ist ein Belastungsprofil, und wie weit reicht die Austauschbarkeit?
- [OQ-0045](../migration/open-questions.md#oq-0045--welche-belastungsmodelle-stehen-zur-wahl) (entschieden): Welche Belastungsmodelle stehen zur Wahl?
- [OQ-0046](../migration/open-questions.md#oq-0046--startwerte-der-parameter-für-phase-2) (entschieden): Startwerte der Parameter für Phase 2
- [OQ-0051](../migration/open-questions.md#oq-0051--trimp-bei-pulslücken) (entschieden): TRIMP bei Pulslücken
- [OQ-0053](../migration/open-questions.md#oq-0053--formel-und-koeffizienten-des-banister-modells) (entschieden): Formel und Koeffizienten des Banister-Modells
- [OQ-0054](../migration/open-questions.md#oq-0054--atl-und-ctl-an-tagen-mit-unbewerteter-einheit) (entschieden): ATL und CTL an Tagen mit unbewerteter Einheit
- [OQ-0058](../migration/open-questions.md#oq-0058--entscheidungen-aus-der-prüfung-von-phase-2-und-3) (entschieden): Entscheidungen aus der Prüfung von Phase 2 und 3
- [OQ-0059](../migration/open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung) (entschieden): Wertänderungen aus der Research-Prüfung
- [OQ-0070](../migration/open-questions.md#oq-0070--pulsabdeckung-bei-unregelmäßigem-takt) (non-blocking): Pulsabdeckung bei unregelmäßigem Takt
<!-- END OQ -->

## Quellen
- SRC-001: §10, Z. 540–646; §25 Nr. 7
