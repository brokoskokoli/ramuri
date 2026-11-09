---
id: FEAT-020
title: Oberfläche, Marke und Navigation
status: Approved
owner: TBD
source_refs: [SRC-003]
related_requirements: [FR-0205, FR-0206, FR-0207, FR-0208, FR-0209]
---

# Oberfläche, Marke und Navigation

## Ziel
Alle Seiten der App sehen aus und verhalten sich wie das Screen-Design in [`design/`](../../design/README.md). Name, Logo und Icons kommen aus [`branding/`](../../branding/README.md). Was eine Seite zeigt und berechnet, legen weiter die übrigen Specs fest. Das Design legt nur Aussehen, Anordnung und Bedienung fest.

## Funktionale Anforderungen

### FR-0205 — Erscheinungsbild nach dem Screen-Design
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** NFR-0006, CON-0009, OQ-0075, OQ-0076, OQ-0077, DEC-0070

Jede Seite folgt in Farben, Schrift, Anordnung, Bedienelementen und Verhalten dem zugehörigen Screen des Designs. Seiten ohne eigenen Screen (Einrichtung, Profil, Einstellungen, Sensoren, Zonen, Berechtigungen, Daten, Erklärungen, Dialoge) nutzen dieselben Bausteine und Farben.

**Festlegungen (OQ-0075):**
- Inhalte nach Spec: Widerspricht ein Text, Wert oder eine Aussage im Design einer Anforderung oder Festlegung, gilt die Spec in der Optik des Designs. Elemente, die die Spec verlangt und das Design nicht zeigt (etwa Höhenprofil, Runden, Schrittfrequenz im Lauf, Zeitraumwahl der Statistik, Sensorwechsel, Fehler- und Datenhinweise), bleiben im Stil des Designs erhalten.
- Hell und dunkel: Das helle Erscheinungsbild ist das Design. Ein dunkles folgt der Systemeinstellung; seine Töne werden aus den Markenfarben abgeleitet und erfüllen dieselben Kontrastregeln. Seiten, die im Design schon dunkel sind (Willkommen, Intervall), bleiben in beiden Modi dunkel.
- Farben und Schriftgrößen liegen an einer Stelle (Theme); Seiten verwenden keine eigenen Farbwerte.
- Schriften Sora (Überschriften, Zahlen) und Manrope (Text) sind in der App enthalten und werden nie zur Laufzeit geladen (ADR-0009: Netz nur für Kartenkacheln). Ihre Lizenz (SIL OFL 1.1) steht in den Lizenzangaben der App.
- Kontrast: Text mindestens 4,5 : 1 in beiden Modi, Bedienelemente mindestens 48 dp. Glut ist nie Textfarbe auf hellem Grund.
- Der Glutpunkt kennzeichnet die eigene Position auf der Karte und, vor dem Wort „geschätzt“, geschätzte Werte (CON-0009).
- Alle Texte gibt es auf Deutsch und Englisch (NFR-0006); Einheiten folgen der Einstellung.
- Plan, Intervall und Zusammenfassung (OQ-0077): Ziele stehen als Zeit, Kilometer nur als „ca.“, wenn das lockere Tempo bekannt ist. RPE-Wörter nach PAR-105, Befinden in 5 Stufen (PAR-169), Einheiten nach PAR-197 und PAR-198, Pulshinweise nach PAR-107, also keine in Blöcken unter 4 min. Beispielwerte des Designs sind keine Vorgaben.
- Einheit in Kacheln (OQ-0076): Bei Pace, Puls und Punkten steht die Einheit in der Beschriftung, die Zahl bleibt groß. Anstieg und Gefälle behalten die Einheit an der Zahl und schrumpfen nur bei Platzmangel.
- Seiten aus Phase 2 und 3 (Intervall, Plan, Erholung, subjektive Angaben) folgen dem Design, wenn ihre Phase umgesetzt wird. Ihre Abweichungen von der Spec (Pulswarnung in kurzen Blöcken gegen PAR-107, Phasennamen gegen FR-0141, Erholung als Zahl gegen FR-0107, RPE-Wörter gegen PAR-105, drei statt fünf Stufen beim Befinden gegen PAR-169) werden dann entschieden.

**Akzeptanzkriterien:**
- [ ] Jede Seite mit Screen entspricht ihm in Aufbau, Farben, Schrift und Bedienung; Abweichungen sind im Arbeitspaket begründet.
- [ ] Hell und dunkel sind auf allen Seiten lesbar; Kontrastpaare sind per Test geprüft.
- [ ] Ein Netzwerkmitschnitt zeigt keine Anfrage nach Schriften.

### FR-0206 — Name, Icon und Systemsymbole
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0034, OQ-0075, DEC-0070

Die App heißt „ramuri“, in allen Sprachen kleingeschrieben. Launcher-Icon, Benachrichtigungssymbol und System-Splash kommen aus `branding/`.

**Festlegungen (OQ-0075):**
- Die Android-Paket-ID ist `io.github.brokoskokoli.ramuri`. Mit der neuen ID gilt die App als neue App; bestehende Testinstallationen übernehmen ihre Daten nur über das Archiv (FR-0198).
- Launcher: Adaptive Icon mit monochromer Ebene für Themed Icons. Benachrichtigung der Aufzeichnung: einfarbiges Symbol `ic_stat_ramuri`.
- System-Splash: Logo auf Nacht, ohne eigenen Text.

**Akzeptanzkriterien:**
- [ ] Launcher, App-Titel, Benachrichtigung und Systemeinstellungen zeigen „ramuri“ und das Icon.
- [ ] Das Release-APK hat die Paket-ID `io.github.brokoskokoli.ramuri`.

### FR-0207 — Willkommensbildschirm
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0001, OQ-0075

Beim ersten Start zeigt die App einmalig einen Willkommensbildschirm mit Logo, kurzem Satz und „Los geht's“. Danach folgt die Einrichtung (FR-0001).

**Festlegung (OQ-0075):** Der Text verspricht nichts, was mit der Karteneinwilligung nicht mehr gilt; etwa „Deine Läufe bleiben auf deinem Handy“ statt „Deine Daten bleiben auf deinem Handy“.

**Akzeptanzkriterien:**
- [ ] Der Bildschirm erscheint nur vor der ersten Einrichtung, auch nach einem Neustart der App mitten in der Einrichtung höchstens bis zu deren Abschluss.
- [ ] Nach einem Reimport aus der Ersteinrichtung erscheint er nicht erneut.

### FR-0208 — Navigation
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0209, OQ-0075

Die App hat unten eine Navigation mit den Bereichen Heute, Verlauf und Fortschritt. Ab Phase 2 kommt der Bereich Plan hinzu, an zweiter Stelle wie im Design. Lauf vorbereiten, Lauf, Zusammenfassung und Detailansicht sind Vollbilder ohne Navigation.

**Festlegung (OQ-0075):** Profil, Einstellungen, Sensoren, Zonen, Berechtigungen und Daten (Export, Archiv, Löschen) erreicht man über das Profil-Symbol oben rechts auf „Heute“.

**Akzeptanzkriterien:**
- [ ] Jede bisher erreichbare Seite ist über die neue Navigation erreichbar.
- [ ] Die Zurück-Taste führt aus einem Bereich zu „Heute“ und von dort aus der App.

### FR-0209 — Startseite „Heute“
- **Status:** Approved | **Phase:** 1 (Erholung, geplante Einheit und Wochenziel mit ihrer Phase)
- **Quelle:** SRC-003 (Maintainer 2026-11-08, OQ-0075)
- **Verwandt:** FR-0025, FR-0043, FR-0106, FR-0148, OQ-0075

„Heute“ zeigt in Phase 1 den Knopf „Frei laufen“, die laufende Woche Montag bis Sonntag mit den Tagen, an denen gelaufen wurde, und der Summe der Kilometer sowie den letzten Lauf mit Sprung in seine Detailansicht.

**Festlegung (OQ-0075):** Erholung (FR-0106), geplante Einheit (FR-0025, FR-0143) und Wochenziel (FR-0148) erscheinen erst, wenn ihre Phase umgesetzt ist; bis dahin ohne Platzhalter.

**Akzeptanzkriterien:**
- [ ] Ohne Läufe zeigt die Seite einen Hinweis statt leerer Werte.
- [ ] Die Wochensumme entspricht der Wochenstatistik (FR-0044).

## Offene Fragen
<!-- BEGIN OQ -->
- [OQ-0075](../migration/open-questions.md#oq-0075--screen-design-und-marke) (entschieden): Screen-Design und Marke
- [OQ-0076](../migration/open-questions.md#oq-0076--nachschliff-der-lauf-seiten) (entschieden): Nachschliff der Lauf-Seiten
- [OQ-0077](../migration/open-questions.md#oq-0077--vorgaben-zum-start-von-phase-2) (entschieden): Vorgaben zum Start von Phase 2
<!-- END OQ -->

## Quellen
- SRC-003: Entscheidungen des Maintainers vom 2026-11-08 zum Screen-Design (OQ-0075)
