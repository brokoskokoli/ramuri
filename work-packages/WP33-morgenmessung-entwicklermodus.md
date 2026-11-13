# WP33 – Morgenmessung mit der Kamera und Entwicklermodus (`core/src/ppg`, `features/measure`, `features/settings`, `adapters`, Android)

**Zuordnung:** M3, Welle 1, nach WP31 und WP24. Parallel zu WP32.

Bezug: FR-0215, FR-0214, FR-0213, FR-0021, FR-0115; PAR-160K, PAR-161K, PAR-164K/165K, PAR-171K, Validierungssperre (K-1); K46, K47, K55, K56, K61, K62 (F1, F3, F4); R009 Abschnitte 1, 5, 5a, 6; ADR-0006, ADR-0011; SEC-0001 bis SEC-0010. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md). Die Bewertung der Reihen (z-Werte, Zahl, Zustände) gehört zu WP34.

## Problem
Nutzer ohne Uhr sollen morgens 60 s mit der Kamera messen und eine eigene Reihe aus Ruhepuls und RMSSD aufbauen. Bis zur bestandenen Validierung ist das nur im Entwicklermodus möglich (**Entscheidung des Maintainers, K62 F1**); nach dem Bestehen gilt K-1 für alle. Für die Validierung braucht der Maintainer im Entwicklermodus Messpaare Kamera gegen Gurt, und Kamera-RMSSD gilt dort schon vorher (K61).

## Inhalt
0. **Screens (Teil 0):** Mit Claude Design, auf Basis von `design/screens/ruhepuls`: Morgen-Einstieg (Hinweis „nach dem Aufwachen, Toilette, vor Kaffee“, Haltung liegend/sitzend), Ruhephase 2 min, Messung, Ergebnis mit Schlafdauer in Stufen (freiwillig), Trend von Ruhepuls und RMSSD ohne Kennzeichnung (K62 Punkt 6), Markierungen nach K-1 für die Zeit nach der Freischaltung („ungenauer als erwartet“, „experimentell, nicht eingeschaltet“), unauffälliger Hinweis „Entwicklermodus aktiv“, Seite „Über“ mit Versionsnummer, Hinweis „Entwicklermodus an“, Abschnitt „Entwickler“ (Gurt-Paare, Export). Freigabe durch den Maintainer.
1. **Entwicklermodus (Teil A):** Neuer Eintrag „Über“ in der Übersicht hinter dem Profil-Symbol mit Name und Versionsnummer; die Lizenzen ziehen dorthin. 10× Tippen auf die Versionsnummer schaltet den Modus ein (Zähler mit Rückmeldung ab dem 7. Tipp), ein Schalter im Abschnitt „Entwickler“ schaltet ihn aus. Zustand als Einstellung; ein lesbarer Port in `core`, den WP34 nutzt.
2. **Speicher (Teil B):** Tabelle der Morgenmessungen (Zeitpunkt mit UTC-Versatz, Haltung, Gerät, Methode und Version, Qualität, Ruhepuls mit einer Nachkommastelle, RMSSD, Zeitrauschen, Schlafstufe, internes Merkmal „vor der Validierung gemessen“ (K62 Punkt 6; ändert weder Anzeige noch Rechnung, dient nur der späteren Trennung der Daten), Kamera-Schlagabstände als BLOB) und Tabelle der Gurt-RR je Morgenmessung (ein BLOB je BLE-Paket wie `raw_rr_packets`, K55). Migration, Archivabschnitte, Vertrag, Vektor, Löschen. Schema und Abschnitte nach der Regel im M3-Plan.
3. **Ablauf (Teil C, FR-0215):** Protokoll nach K-1 mit dem Algorithmus aus WP27 unverändert (`camera-ppg v1`): Haltung liegend als Vorgabe, sitzend wählbar, nie stehend; 2 min Ruhe, jeden Tag gleich; 60 s spontan atmen; Anleitung ohne Atemtempo. Gültigkeit nach PAR-160K: Morgenfenster (Vorgabe 4–11 Uhr, einstellbar), erste Messung des Tages mit ausreichender Qualität zählt, Wiederholung nur bei zu schlechter Qualität. Danach freiwillig Schlafdauer in Stufen (PAR-164K/165K). Kein Schlafgefühl (E4). Einstieg auf „Heute“ und im Profil, **vor bestandener Validierung nur im Entwicklermodus sichtbar** (K62 F1); die Freischaltung hängt am Validierungsstand (Vorentscheidung unten), nicht an einem eigenen Schalter.
4. **Erinnerung (Teil D):** Freiwillige morgendliche Erinnerung zu einer wählbaren Uhrzeit, ungenauer Wecker über die Erinnerungen aus WP22, eigener Kanal, Text ohne Werte. **Entscheidung des Maintainers (K62 F3):** Keine neue Ausnahme zu SEC-0009; die Uhrzeit liegt nur in der verschlüsselten Datenbank, der Boot-Empfänger aus WP22 plant diese Erinnerung nicht. Nach einem Neustart des Geräts plant erst das nächste Öffnen der App sie neu. Ohne Entwicklermodus (vor der Validierung) wird keine Morgen-Erinnerung geplant, und eine bestehende wird beim Ausschalten des Modus gestrichen.
5. **Gurt-Paare und Export (Teil E, K61 Punkt 3):** Im Entwicklermodus speichert die Messung, wenn eine Pulsquelle mit RR verbunden ist, deren RR von Beginn der Ruhephase bis Ende der Messung zur Morgenmessung. Export der Messpaare (je Morgen: Zeitpunkte, Haltung, Gerät, Kamera-Werte und -Schlagabstände, Gurt-RR roh). **Entscheidung des Maintainers (K62 F4):** unverschlüsselte CSV über Teilen, nur im Entwicklermodus, mit Warnhinweis vor dem Teilen wie bei der Zusatzmetriken-CSV (K57); Übergabe aus `cacheDir/exports` wie K29. Format als Vertrag `docs/contracts/morning-pairs-csv.md` (Punkt als Dezimaltrenner, UTF-8, CRLF ohne BOM wie `metrics-csv.md`). Die App zeigt keine Gurt-RMSSD und keine Differenzen (R009, Abschnitt 6, „keine Zwischenauswertung“).

## Vorentscheidungen (selbst entschieden, einfachste Lösung)
- **Validierungsstand als Konstante:** Der Stand der Validierung (je Größe `nicht geprüft`, `bestanden`, `eingeschränkt`, `nicht bestanden`, für lnRMSSD je Haltung) steht als versionierte Konstante in `core` am Verfahren `camera-ppg v1` (E7c: Verfahren, nicht Gerät). Heute `nicht geprüft`. WP36 ändert sie nach dem Ergebnis. Opt-in-Schalter und alle Zweige der Sperre werden jetzt gebaut und mit allen Ständen getestet; der Schalter erscheint nur bei `bestanden`.
- **RMSSD-Qualitätsgrenze bis zur Validierung:** Es gibt sie noch nicht. Bis WP36 gilt RMSSD nur bei Qualität „gut“ aus `camera-ppg v1` (Zeitrauschen ≤ 25 ms); als Parameter mit Vermerk „vorläufig bis Validierung“, damit WP36 nur den Wert tauscht.
- **Freischaltung für alle (K62 F1):** Die Morgenmessung wird für alle sichtbar, sobald der Validierungsstand für lnRMSSD liegend „bestanden“ ist (das, was „sicher freigeschaltet“ wird). Ergibt die Validierung ein gemischtes Ergebnis (etwa Ruhepuls bestanden, lnRMSSD nicht), bleibt sie nur im Entwicklermodus; WP36 legt das dem Maintainer vor.
- **Entwicklermodus:** nicht im Archiv (Gerätezustand), „Alles löschen“ setzt ihn zurück; gilt auch im Release-Build (K61). Im Entwicklermodus gelten Ruhepuls und RMSSD wie nach bestandener Validierung, ohne Opt-in und ohne Kennzeichnung (K62 Punkt 6). Das Merkmal „vor der Validierung gemessen“ wird beim Speichern aus dem Validierungsstand gesetzt und bleibt dauerhaft. Wird der Modus vor der Freischaltung ausgeschaltet, bleiben die Messungen gespeichert (mit Archiv und Löschen), sind aber nicht sichtbar und gehen nirgends ein; nach der Freischaltung zählen sie nach K-1.
- **Gerät:** Hersteller und Modell (`Build.MANUFACTURER`, `Build.MODEL`), keine Seriennummer oder Kennung. Eine neue Reihe beginnt bei neuem Gerät oder neuer Haltung (PAR-160K).
- **Kamera-Schlagabstände speichern:** Abgeleitete Zahlen, keine Bilder (FR-0215 verbietet nur Bilder). Sie erlauben die Validierung und ein späteres Nachrechnen.
- **Gurt:** Jeder verbundene Gurt mit RR, nicht nur der H9 (ADR-0006, FR-0021); nur die aktive Pulsquelle (K55). Ohne Gurt läuft die Messung normal.
- **Außerhalb des Morgenfensters:** Die Messung wird gespeichert, aber als „außerhalb des Morgenfensters“ markiert und zählt nicht für die Reihe.
- **Kein Profilvorschlag** aus Morgenwerten (R009, Offene Punkte 5, nicht entschieden); das Profil ändert sich nur über FR-0214 wie bisher.

## Umsetzung
- Teile je ein Coder-Auftrag; 0 und A zuerst, dann B, dann C, D und E.
- Wiederverwendung: Kamera-Adapter, Ruhephase und Messansicht aus WP27 (`features/measure`), Erinnerungen aus WP22, RR-Parser aus WP26. Keine Änderung am Algorithmus (`ppg_analyzer.dart`), nur neue Aufrufer.
- Mutationsbelege: erste gültige Messung des Tages, Morgenfenster, Haltung als eigene Reihe, Qualitätsgrenze je Messung auch im Entwicklermodus, 10-Tipp-Zähler, Speichern der RR nur im Entwicklermodus.
- Keine Mess- oder RR-Werte in Logs.
- **Parallel:** `overview_screen.dart`, `features/measure`, `core/src/ppg` nur hier; Manifest und `release_rechte()` nur WP32. Texte mit Präfix `morning`/`dev`.

## Abnahmekriterien
- [ ] Screens freigegeben, im Repo unter `design/`.
- [ ] Akzeptanzkriterien von FR-0215, soweit sie die Messung betreffen (Protokoll, erste gültige Messung, Gültigkeit nach PAR-160K, Schlafangabe, keine Bilder gespeichert); die Bewertung prüft WP34.
- [ ] Entwicklermodus: 10 Tipps schalten ein, 9 nicht; Ausschalten wirkt; ohne Modus wird keine Gurt-RR zur Morgenmessung gespeichert (Test).
- [ ] Ohne Entwicklermodus ist die Morgenmessung bei Stand „nicht geprüft“, „eingeschränkt“ und „nicht bestanden“ nirgends erreichbar und keine Erinnerung geplant; bei lnRMSSD „bestanden“ für alle (Test je Stand).
- [ ] CSV-Export nur im Entwicklermodus, mit Warnhinweis vor dem Teilen; liefert für einen synthetischen Morgen Kamera- und Gurtdaten im selben Zeitfenster; die App zeigt keine Gurt-RMSSD. Vertrag liegt vor.
- [ ] Archiv mit beiden neuen Tabellen hin und zurück, Vektor erzeugt; Löschen leert sie.
- [ ] E2E auf API 36 und 31 mit Fake-Kamera und Test-Sensor mit RR: Messung liegend und sitzend, schlechte Qualität mit Wiederholung, Messung außerhalb des Fensters, Entwicklermodus an mit Gurt-Paar und Export, Erinnerung ausgelöst, Entwicklermodus aus (Einstieg verschwindet). Hell und dunkel, Bildschirmfotos. Tests, die sich lohnen, committet in `app/integration_test/`. Gate grün auf GitHub.
- [ ] Debug-APK für den Maintainer, mit dem er die Validierungsmessung starten kann.

## Ungeprüft
Echte Kamera morgens, echter Gurt parallel zur Kamera (Funk und Blitz gleichzeitig), Zeitabgleich beider Quellen am Gerät. Prüft der Maintainer bei der Validierungsmessung.
