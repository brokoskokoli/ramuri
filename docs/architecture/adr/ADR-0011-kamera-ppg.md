# ADR-0011 — Puls mit der Handykamera (Kamera-PPG)

- **Status:** Accepted (entschieden vom Orchestrator, 2026-11-10)
- **Datum:** 2026-11-10
- **Quellen:** SRC-003 (OQ-0078, DEC-0073, DEC-0074), R009, Referenz `../puls` (Tag `algo-v0.4-frozen`)
- **Betroffene Anforderungen:** FR-0214, FR-0215 (Wiederverwendung), FR-0002, FR-0060, SEC-0001 bis SEC-0010, NFR-0001, NFR-0005

## Kontext
FR-0214 verlangt eine Ruhepulsmessung per Finger auf Rückkamera und Blitz, FR-0215 (Phase 3) dieselbe Messung als Morgenmessung mit RMSSD. Die Referenz `../puls` zeigt den Weg: Rückkamera mit Torch, ca. 320×240, feste Bildrate (bevorzugt 60 fps), Belichtung und Weißabgleich nach 2,5 s gesperrt, je Bild Sensor-Zeitstempel und Mittelwerte von Rot und Grün in der Bildmitte sowie in 4×4 Teilbereichen. Die Auswertung (`PpgAnalyzer.kt`) ist reines Kotlin ohne Android-Bezug. Die Referenz nutzt CameraX 1.6.1 mit Camera2-Interop; die eigentlich wichtigen Einstellungen (Bildrate, AE-/AWB-Sperre) setzt sie über Camera2-Schlüssel. ramuri hat heute weder eine Kamera-Abhängigkeit noch das Recht `CAMERA` (minSdk 31, targetSdk 36).

## Entscheidung
**1. Aufteilung:** Bildstatistik nativ in Kotlin im Android-Teil, Auswertung als reines Dart in `core/src/ppg`. Über die Plattformgrenze gehen nur Zahlen je Bild (Zeitstempel, R/G der Mitte, 16 × R und 16 × G), nie Pixel. Port `PpgCamera` in `core/ports` (Verfügbarkeit, Start, Bildstrom, Stop), Adapter in `adapters` über MethodChannel und EventChannel wie die Schrittfrequenz (`method_channel_cadence.dart`, `StepSensor.kt`), Fake in `core/fakes`.

**2. Kamera-API: Camera2 direkt, keine neue Abhängigkeit.** Camera2 ist Teil der Plattform und deckt alles ab, was die Referenz braucht: `CONTROL_AE_TARGET_FPS_RANGE` aus `CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES` (höchste feste Rate, 60 vor 30), `FLASH_MODE_TORCH`, `CONTROL_AE_LOCK` und `CONTROL_AWB_LOCK` nach 2,5 s, `ImageReader` mit `YUV_420_888` in ca. 320×240 und `Image.getTimestamp()` (Sensorzeit). Ein Bild wird nach der Statistik sofort geschlossen.

**3. Ablauf und Parameter wie in der Referenz** (`ALGORITHMUS.md` Abschnitt 2): Einschwingen 5 s, Messfenster 60 s, Filter ab 3 s, Auflösung, Raster, Luma nach BT.601. Werte, die in `core` gebraucht werden, sind benannte Konstanten mit Verweis auf `ALGORITHMUS.md`; sie werden nicht neu gewählt.

**4. Algorithmus:** Port von `PpgAnalyzer.kt` (Stand `algo-v0.4-frozen`) ohne fachliche Änderung. Ausgabe: Puls, RMSSD (berechnet, in WP27 nicht angezeigt), Qualität „gut“, „eingeschränkt“ oder „unbrauchbar“ (PAR-160K), Grund bei „unbrauchbar“, Methode und Version (NFR-0001, ADR-0004). Bei „unbrauchbar“ gibt es keinen Wert. Die Morgenmessung (WP28) nutzt denselben Code; ihre strengere RMSSD-Grenze kommt dort dazu.

**5. Berechtigung:** `CAMERA` im Manifest, `uses-feature` für Kamera und Blitz mit `required="false"` (die App bleibt ohne Kamera installierbar). Abgefragt wird erst beim Start der Messung über den vorhandenen Rechte-Kanal. Ohne Recht, Kamera oder Blitz bleibt die manuelle Eingabe (FR-0214). Die Release-Rechte-Prüfung in `tool/gate.sh` prüft `CAMERA` und `uses-feature required=false` am APK.

**6. Fehler und Lebenszyklus:** keine Rückkamera, kein Blitz, Recht verweigert, Kamera belegt oder getrennt, keine feste Bildrate ≥ 30 fps. Jeder Fall endet als Ergebniszustand mit Grund, nie als Absturz. Geht die App in den Hintergrund oder tritt ein Fehler auf, bricht die Messung ab: Torch aus, Sitzung und Gerät geschlossen, Strom beendet. Das prüft ein Test auf der Dart- und, wo möglich, auf der Kotlin-Seite.

**7. Datenschutz:** Keine Bilder speichern oder übertragen, keine Bildreihen auf Platte, keine Puls- oder PPG-Werte in Logs (SEC-0001 bis SEC-0010). Gespeichert wird nur der übernommene Ruhepuls.

**8. Speicherung ohne Schemaänderung:** Der Ruhepuls bleibt in `profile.resting_heart_rate_bpm`. Haltung, Zeitpunkt und Quelle der Messung liegen als Schlüssel in `settings` (sie sind schon Teil von Archiv, Reimport und Löschen). Eine manuelle Änderung des Werts entfernt sie. Erst WP28 braucht eine eigene Reihe je Haltung und Gerät (PAR-160K); die bekommt dort ihre Tabelle.

**9. Prüfung ohne echte Kamera:** Der Emulator hat keine Kamera mit Puls. Im Debug-Build gibt es eine Fake-Quelle, die synthetische Bildstatistik einspielt (Puls, schlechtes Signal, Fehlerfälle), auf demselben Kanal. Sie ist wie der Test-Sensor nicht im Release-APK, das prüft das Gate.

## Erwogene Alternativen
- **CameraX 1.6.1 wie in der Referenz:** weniger Code für Sitzung und Lebenszyklus, näher an der Referenz. Dafür drei Gradle-Abhängigkeiten (`camera-core`, `camera-camera2`, `camera-lifecycle`), Eintrag in der Netz-Freigabeliste, und die entscheidenden Einstellungen laufen trotzdem über Camera2-Interop. **Rückfallweg**, falls Camera2 auf Geräten des Maintainers nicht dieselben Bilder liefert.
- **Flutter-Plugin `camera`:** setzt weder Bildrate noch AE-/AWB-Sperre zuverlässig und liefert Bilder nach Dart; mehr Daten über die Grenze, kein Gewinn.
- **Auswertung in Kotlin (Referenz unverändert übernehmen):** spart den Port, verletzt aber die Regel „Berechnung in `core`, einzeln testbar“ und wäre für WP28 und die Neuberechnung nicht in Dart verfügbar.
- **Neue Spalten in `profile` für Haltung und Zeitpunkt:** sauberer im Schema, braucht aber Migration und neue Archivformatversion, während WP20 parallel das Schema ändert. Für einen einzelnen Wert lohnt das nicht.

## Konsequenzen
- Mehr eigener Kotlin-Code (Camera2-Sitzung, ca. 300 Zeilen), dafür keine neue Abhängigkeit und keine Änderung der Netz-Freigabeliste.
- Ein Abgleichtest gegen die Referenz: die synthetischen Vektoren aus `PpgAnalyzerTest.kt` im Repo (Puls auf 0,1/min, RMSSD auf 0,5 ms) und ein lokaler, übersprungbarer Test gegen `../puls/messungen/`, der nur Abweichungen meldet.
- Das neue Recht steht im selben Commit wie seine Gate-Prüfung.

## Im Emulator nicht belegbar
Echte Kamera: erreichte Bildrate, Wirkung der AE-/AWB-Sperre, Torch, Wärme, Unterschiede zwischen Geräten und zwischen Camera2 direkt und CameraX. Das prüft der Maintainer mit der Debug-APK.

## Offene Punkte
- Validierung gegen Polar H9 regelt R009, Abschnitt 6 (WP28).

**Nachtrag 2026-11-11 (WP27, Umsetzung):** Für das Signal am Ende der Ruhephase (Ton oder Vibration, FR-0214) kommt das Recht `VIBRATE` dazu (normales Recht, ohne Dialog erteilt). Der Ton läuft über `ToneGenerator`, die Vibration über `VibratorManager`, beides über einen eigenen Kanal ohne neue Abhängigkeit; die Release-Rechte-Prüfung erwartet `VIBRATE`. Die Kamera wählt die höchste feste Bildrate zwischen 30 und 60 fps; ohne feste Rate in diesem Bereich misst sie nicht (Maintainer 2026-11-11). Größte erlaubte Bildlücke 1 s (Maintainer 2026-11-11, PAR-Nummer offen). Sicherungen der Ablauf-Steuerung (keine Messparameter, Wahl des Supervisors): Startfrist 5 s bis zum Kamerastart, 3 s Wanduhr ohne Bild, Gesamtfrist = Ende des Messfensters + Start- und Bildfrist + 12 s Reserve (86,5 s); Live-Anzeige über die letzten 12 s.
