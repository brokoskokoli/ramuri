# WP17 – Nachschliff Lauf-Seiten (`app/packages/core/lib/src/statistics`, `app/lib/features/run`, `summary`, `history`)

**Zuordnung:** M1, nachgereicht am 2026-11-09 (OQ-0076, offene Punkte aus WP16). Nach WP16.

Bezug: FR-0028, FR-0037, FR-0041, FR-0057, FR-0205, FR-0211, FR-0212; PAR-014; OQ-0076; K38, K39.

## Inhalt
1. **Rest-Pace (Teil A, FR-0211, OQ-0076):** In der Kilometertabelle steht „–“ statt der Pace, wenn das Tempo des Abschnitts unter 0,5 m/s liegt (PAR-014, Wert aus dem Parameter, nicht neu als Zahl). Länge und Zeit bleiben; die Summe der Zeiten bleibt gleich der Bewegungszeit. Der Pace-Balken entfällt für diese Zeile. Berechnung in `core`.
2. **Zurück-Taste im Lauf (Teil A, FR-0028, OQ-0076):** Im laufenden Lauf fragt die Zurück-Taste „Lauf pausieren?“ mit „Pausieren“ / „Weiterlaufen“. Bis zur Antwort läuft die Aufzeichnung unverändert; „Pausieren“ wirkt wie der Pause-Knopf. Im pausierten Lauf bleibt das Verhalten aus WP16. Autopause-Zustand wie laufend.
3. **Summen im Verlauf (Teil B, FR-0212):** Im E2E zeigte die Wochensumme 18:52, die Summe der sieben Zeilen 18:50. Ursache klären (Rundung je Zeile oder abweichende Zeitbasis). Gilt die Summe der Statistik (Akzeptanzkriterium FR-0212), bleibt sie; dann Rundung so, dass die Abweichung erklärbar ist, oder im Paket begründen. Nicht auf Verdacht ändern.
4. **Texte und Umbruch (Teil B, aus WP16 offen d):**
   - Belastungs-Kachel ohne Puls nennt den fehlenden Puls als Grund, nicht „Pulswerte im Profil prüfen“ (FR-0057).
   - Pulskarte zeigt „nicht verfügbar“ nur einmal, nicht zusätzlich „Zone nicht verfügbar“.
   - Einheit bleibt bei der Zahl („+1200 m“ bei 360 dp, Schriftfaktor 1,0 bis 1,3), nicht in eigener Zeile.
   - Test, dass die Kachel den kurzen Schlüssel `sumNoBasisShort` nutzt.

## Umsetzung
- Teil A und Teil B je ein Coder-Auftrag ohne Übergabe. Mutationsbelege für Rest-Pace-Schwelle, Rückfrage der Zurück-Taste (inkl. „Weiterlaufen“ ändert nichts) und den `sumNoBasisShort`-Test.
- `gen-l10n` vor jedem Testlauf (in WP16 testeten Coder und Reviewer mehrfach mit veralteter l10n).
- Keine neuen Abhängigkeiten. Aufzeichnungsdienst unverändert (ADR-0005).
- Nicht dazu: TalkBack-Prüfung, Verkleinerung der Kilometertabelle bei Schriftfaktor 2,0 (bleibt FittedBox).

## Abnahmekriterien
- [ ] OQ-0076: Abschnitt unter 0,5 m/s zeigt „–“, darüber die Pace; Summe der Zeiten = Bewegungszeit (Test in `core` mit Mutationsbeleg).
- [ ] OQ-0076: Zurück im laufenden Lauf zeigt die Rückfrage; „Weiterlaufen“ lässt den Lauf laufen, „Pausieren“ pausiert; die Aufzeichnung erhält keinen Befehl ohne Antwort (Widget-Test mit Mutationsbeleg).
- [ ] FR-0212: Ursache der Abweichung 18:52 / 18:50 benannt; Summen weiter gleich der Statistik (Test).
- [ ] Texte nach Punkt 4, de und en; Einheit bricht nicht von der Zahl (Widget-Test bei 360 dp, Faktor 1,3).
- [ ] E2E (separater Agent), API 36 und 31, hell und dunkel, auf dem letzten Stand: Lauf mit Pause und Zurück-Taste, Zusammenfassung, Detail mit kurzem Rest, Verlauf mit Summen; Bildschirmfotos neben dem Design. Gate grün.

## Ungeprüft
Bedienung mit Handschuhen und im Laufen auf echtem Gerät.
