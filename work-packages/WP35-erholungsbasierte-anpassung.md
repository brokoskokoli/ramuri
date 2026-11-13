# WP35 – Erholungsbasierte Plananpassung und Schalter „adaptiv/fix“ (`core/src/plan`, `features/plan`, `home`)

**Zuordnung:** M3, Welle 3, nach WP34.

Bezug: FR-0156, FR-0157, FR-0158 (jeweils „3 (Erholung)“), FR-0159, FR-0160, FR-0165, FR-0166, FR-0170, FR-0116 (Tag der Einheit), FR-0203; PAR-058, PAR-173, PAR-204; ADR-0010; OQ-0011, OQ-0058; K58, K60, K61 Punkt 1. Allgemeine Regeln: [M3-PLAN.md](M3-PLAN.md).

## Problem
Der Plan soll auf einen niedrigen Readiness-Wert reagieren, aber nur, wenn der Nutzer das will: Am Trainingsplan wählt er „adaptiv“ oder „fix“ (K61). Bei „fix“ werden Gesundheitsdaten erhoben und angezeigt, ändern den Plan aber nicht; die Anpassungen aus M2 und das Warnsignal gelten immer.

## Inhalt
1. **Schalter (Teil A):** Auf der Plan-Seite „Plananpassung an Erholung: adaptiv / fix“ mit einem Satz Erklärung; Vorgabe „fix“. Gespeichert in `settings`, mit Archiv und Löschen. Ein Wechsel wirkt ab heute, nie rückwirkend; er erzeugt nur dann eine neue Fassung, wenn heute eine intensive Einheit betroffen ist.
2. **Regel (Teil B, `core`, PAR-173):** Nur bei „adaptiv“: Liegt für den Tag einer geplanten intensiven Einheit (PAR-058) ein Wert im Band „Erhöhte Belastung“ oder „Erholung empfohlen“ vor, wird diese Einheit automatisch locker, mit Begründung aus FR-0117. Nur der Wert dieses Tages zählt; nichts wird vorgezogen oder übertragen. Ein hoher Wert erhöht nie etwas. Eine eingeschränkte Einschätzung ohne Zahl wirkt nicht. Warnsignal hat Vorrang (K58). Festlegungen des Nutzers (`fixed`) bleiben (ADR-0010).
3. **Auslöser und Prüfung (Teil C, FR-0157, FR-0158):** Neuberechnung beim Import neuer Gesundheitsdaten und nach einer Morgenmessung, nur bei „adaptiv“ und nur für heute. Die wöchentliche Prüfung nimmt die Erholungsdaten nur über diese Regel auf.
4. **Anzeige (Teil D):** Karte „Plan angepasst“ (aus WP23) mit Grund „Erholung“ nach PAR-204; Verlauf der Änderungen. Bei „fix“ steht unter der Karte „Erholung“ in diesen Bändern nur der Satz „Für heute wird ein lockerer Lauf empfohlen“ mit dem Knopf „locker laufen“ (Ersetzen aus WP22); der Plan bleibt unverändert.

## Vorentscheidungen (selbst entschieden, einfachste Lösung)
- **Kein neuer Auslöser im Schema:** Fassungen wegen Erholung laufen als Auslöser `feedback` mit Grund-Code `readiness` (wie `warning` in K58), damit der CHECK auf `plans.trigger` und Schema 11 bleiben.
- **Die Lockerung bleibt für den Tag:** Wird der Wert am selben Tag später besser (etwa nach einem späten Import), kehrt die harte Einheit nicht zurück (PAR-173: ein hoher Wert erhöht nie). Wird der Plan am selben Tag aus anderem Grund neu gerechnet, gilt die Lockerung weiter (`plans.summary`, wie `warningHeld` in K60).
- **Entwicklermodus (Entscheidung des Maintainers, K62 Punkt 6):** Ein Wert aus Kamera-Morgenwerten im Entwicklermodus wirkt bei „adaptiv“ wie jeder andere, ohne Sonderbehandlung und ohne Kennzeichnung in der Begründung.
- **Vorgabe „fix“** gilt auch für vorhandene Installationen (es gibt keine ausgelieferten).
- **`planMethodVersion` 4 → 5**, einmalige Neuberechnung nur der Zukunft; absolvierte Einheiten bleiben (FR-0158).

## Umsetzung
- Teile je ein Coder-Auftrag; A und B zuerst, dann C und D.
- **Eigenschaftstests:** Bei „fix“ ist der Plan für beliebige Readiness-Reihen gleich dem Plan ohne Gesundheitsdaten; bei „adaptiv“ steigt keine Einheit durch Readiness, und nur Einheiten am Tag mit niedrigem Wert ändern sich.
- Simulation über 8 Wochen mit Readiness-Reihen, Warnsignal, Pause und Moduswechseln.
- Mutationsbelege: Bandgrenzen 49/50, Tag der Einheit, Vorrang Warnsignal, Modus „fix“.
- **Parallel:** keines in Welle 3. Texte mit Präfix `planAdapt`.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0157 und FR-0158 (Teil Erholung) und FR-0116 (Tag der Einheit) bei „adaptiv“; bei „fix“ keine Planänderung durch Gesundheitsdaten (Test), Warnsignal und M2-Anpassungen wirken weiter (Test).
- [ ] Jede Lockerung zeigt einen Grund (FR-0170, ACC-10).
- [ ] E2E auf API 36 und 31: Modus wechseln, niedriger Wert am Tag einer Intervalleinheit bei „adaptiv“ (Einheit wird locker, Karte „Plan angepasst“) und bei „fix“ (Plan gleich, Empfehlung mit „locker laufen“). Hell und dunkel, Bildschirmfotos. Tests, die sich lohnen, committet in `app/integration_test/`. Gate grün auf GitHub.
