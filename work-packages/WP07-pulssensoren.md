# WP07 – Pulssensoren (`app/packages/core/lib/src/sensors`, `app/packages/adapters`, `app/android`, `app/lib/features/sensors`, `app/lib/features/run`)

**Zuordnung:** M1.

Bezug: FR-0007, FR-0008, FR-0011 bis FR-0020, FR-0036, CON-0003, ACC-02, ACC-03; ADR-0006; OQ-0018, OQ-0037, OQ-0064 (geltender Vorschlag: derselbe Sensor verbindet sich neu); PAR-007, PAR-008.

Wartet nicht auf R005: Den Bau von `universal_ble` mit Target 36 belegt dieses Paket selbst. Die Verbindung unter dem Dienst prüft WP08.

## Inhalt
1. **Fachlogik in `core`:** Vorrang des bevorzugten Geräts, Wechsel manuell oder nach Abbruch, kein automatischer Rückwechsel auf ein anderes Gerät, Neuverbinden desselben Geräts (OQ-0018, OQ-0037, OQ-0064). Immer nur eine Quelle speist die Reihe, jeder Wert trägt sein Quellgerät (FR-0019, FR-0020). Zeit ohne Werte bleibt nicht verfügbar (FR-0017, FR-0056).
2. **Protokoll:** Auswertung von `0x2A37` einschließlich Wertformat und Kontaktbit (PAR-008), Batterie über `0x2A19`, wenn vorhanden. RR-Intervalle bleiben ungenutzt (ADR-0006 Punkt 1).
3. **Adapter:** `universal_ble` nach ADR-0006 Punkte 2 und 4 hinter dem Port. Suche mit Filter auf den Heart Rate Service. Rechte `BLUETOOTH_SCAN` mit `neverForLocation` und `BLUETOOTH_CONNECT`, erst beim Einrichten abgefragt.
4. **Sensorverwaltung:** Suchen, verbinden, trennen, mehrere bekannte Geräte, bevorzugtes Gerät, aktueller Puls, Batterie (FR-0011 bis FR-0016).
5. **Im Lauf:** Sensorstatus, Wechsel der Quelle, Abbruch und Rückfall im Live-Bildschirm aus WP06 (FR-0017, FR-0018, FR-0036).
6. **Test-Sensor:** Fake-Gerät nur im Debug-Build, um Oberfläche und Lauf im Emulator ohne Funk zu prüfen. Es darf nicht im Release-Build landen.

## Umsetzung
- Aus WP05: Bluetooth-Berechtigungen nur im Manifest eintragen, dann erscheinen sie auf der Berechtigungsseite; Entzug im E2E prüfen.
- Aus WP03: `HeartRateReading` hat noch kein Kontaktbit, das PAR-008 braucht. Aus WP01: Die Form des Ereignisstroms ist in ADR-0006 nicht festgelegt.
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkte 3 und 6 / Teil C: Punkt 4 / Teil D: Punkt 5, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Lizenz der neuen Abhängigkeiten im Baum prüfen (GPL-3.0, ADR-0006). Baut das Plugin nicht mit den Versionen aus ADR-0002: Rückfallweg aus ADR-0006 und melden.
- `connectedDevice` im Dienst und Sensorbetrieb bei gesperrtem Bildschirm gehören zu WP08.
- Research R006 (virtueller Sensor, ADR-0006) ist nicht beauftragt. Dieses Paket setzt ihn nicht voraus; wird er beauftragt und ist fertig, kommt sein Testaufbau hier oder in WP08 dazu.
- Nicht dazu: FR-0009, FR-0010, FR-0021 (Phase 4).
- Parallel: läuft mit WP10. Beide lesen den Lauf; WP10 arbeitet in `app/lib/features/history`, `summary`, `statistics`. Gemeinsam nur die ARB-Dateien und der Zusammenbau in `app/lib`. WP07 ändert `app/android/.../AndroidManifest.xml`, WP10 nicht.

## Abnahmekriterien
- [ ] Protokoll: Testvektoren für 8- und 16-Bit-Wert, Kontaktbit gesetzt, nicht unterstützt und kein Kontakt (PAR-008), verkürztes und ungültiges Paket ohne Absturz; Werte außerhalb PAR-007 verworfen.
- [ ] FR-0019: Zwei aktive Fake-Quellen: Jeder Wert hat genau eine Quelle, keine Vermischung; das bevorzugte Gerät hat Vorrang.
- [ ] FR-0018: Wechsel unterbricht die Aufzeichnung nicht; kein automatischer Rückwechsel, auch wenn das bevorzugte Gerät wieder erreichbar ist; Herkunft je Zeitabschnitt abrufbar; Mutationsbeleg.
- [ ] OQ-0064: Derselbe Sensor verbindet sich nach dem Abbruch neu; das ist kein Quellwechsel.
- [ ] FR-0017, FR-0036, ACC-03 (mit Fake): Abbruch im Status sichtbar, keine Nullwerte, GPS- und Pulsdaten vor und nach dem Abbruch vorhanden.
- [ ] FR-0012: Nach dem Trennen keine Werte mehr. FR-0013, FR-0014: Zwei bekannte Geräte und die Festlegung überstehen den Neustart. FR-0016: Ohne Batteriedienst kein erfundener Wert. FR-0020: Quellgerät eines gespeicherten Laufs abrufbar.
- [ ] FR-0008, FR-0011, CON-0003: Suche filtert auf den Dienst; kein Gerät mit herstellerspezifischer Einrichtung nötig (Test am Port; Nachweis mit echter Funkstrecke ist ungeprüft).
- [ ] Ohne Bluetooth-Rechte oder mit ausgeschaltetem Bluetooth: Lauf ohne Sensor unverändert möglich, klarer Hinweis, kein Absturz (FR-0035). Die Rechte werden nicht beim Lauf-Start ohne Sensor abgefragt.
- [ ] Das Release-APK enthält den Test-Sensor nicht; `universal_ble` baut mit den Versionen aus ADR-0002.
- [ ] E2E (separater Agent), mit Test-Sensor: Suche, verbinden, bevorzugen, Lauf mit Puls und Zone, Abbruch, Wechsel, Ende, Quellen im Lauf sichtbar; Rechte verweigert.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
ACC-02 mit echtem Pulsgurt, echte Funkabbrüche, die Gerätekategorien aus FR-0007, Uhren im Broadcast-Modus, wechselnde Adressen (ADR-0006). Sie bleiben in `STATUS.md` offen und sind kein Abnahmekriterium.
