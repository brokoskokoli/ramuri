# ADR-0005 — Aufzeichnung im Hintergrund und Wiederanlauf

- **Status:** Accepted (Maintainer, 2026-11-04); Punkt 3 (eine Engine) nach R005 im Emulator bestätigt, FR-0034 im Feld offen
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0021, OQ-0052)
- **Betroffene Anforderungen:** FR-0034, FR-0035, FR-0036, FR-0193, FR-0194, FR-0195, FR-0202, ACC-01, ACC-03, OQ-0021

## Kontext
Ein Lauf muss bei ausgeschaltetem Bildschirm durchgehend weiterlaufen (FR-0034). Nach Absturz, Neustart oder leerem Akku bietet die App beim nächsten Start die Wiederaufnahme an (FR-0193). Ohne Standortberechtigung startet kein GPS-Lauf (FR-0195), ohne Sensor oder Schrittberechtigung läuft die Aufzeichnung normal (FR-0035, FR-0202).

## Entscheidung
**1. Foreground Service, gestartet aus der sichtbaren App.** Standort ist eine While-in-Use-Berechtigung; ein solcher Dienst lässt sich aus dem Hintergrund nicht anlegen [1]. Ein laufender Dienst gilt als Vordergrund-Standortzugriff, deshalb entfällt `ACCESS_BACKGROUND_LOCATION` samt Play-Richtlinie dazu [2].

**2. Diensttypen:** Im Manifest `location|connectedDevice`, an `startForeground()` immer `location` und `connectedDevice` nur bei erteiltem `BLUETOOTH_CONNECT`. Typen lassen sich später ergänzen, fehlt die Voraussetzung, gibt es eine `SecurityException` [3][4]. Androids eigenes Beispiel ist ein Lauf-Tracker mit `location` [4]. Der Typ `health` ist für Fitness-Tracker beschrieben, setzt aber etwa `ACTIVITY_RECOGNITION` voraus [3], die laut FR-0202 fehlen darf; er entfällt, sofern R005 keinen Bedarf zeigt. `POST_NOTIFICATIONS` ist für den Start nicht nötig, die App fragt danach, läuft aber auch ohne [5].

**3. Ein einziger FlutterEngine.** Die Engine wird im `Application`-Objekt erzeugt und überlebt laut Flutter jede Activity, auch im Dienst [6]. Der Dienst ist dünner eigener Kotlin-Code. Die Aufzeichnungslogik läuft in Dart und hängt über Ports an `core` (ADR-0002). So gibt es genau eine Datenbankverbindung; drift kann eine Verbindung nur innerhalb einer Engine teilen [7].

**4. Standort:** Eigener kleiner Kotlin-Adapter auf `LocationManager` mit `GPS_PROVIDER`. Keine Google-Play-Dienste, siehe Alternativen. Rohe GPS-Punkte passen zudem zur eigenen Filterung (PAR-003).

**5. Laufende Sicherung:** Jeder Messwert wandert in kurzen Transaktionen in die verschlüsselte Datenbank (ADR-0003). Der Lauf trägt einen Zustand `aktiv`. Findet die App beim Start einen aktiven Lauf ohne laufenden Dienst, bietet sie die Wiederaufnahme an.

**6. Kein automatischer Neustart.** Kein `BOOT_COMPLETED`-Empfänger, kein Sticky-Neustart als Zusage. Ein Standortdienst lässt sich aus dem Hintergrund ohne Hintergrundstandort nicht verlässlich starten [1], und FR-0193 verlangt nur das Angebot beim nächsten Start.

## Erwogene Alternativen
- **`geolocator` 14.1.2 / `location` 10.0.2 (beide MIT):** Ihre Android-Teile binden `play-services-location` ein (`geolocator_android`, `location`), lizenziert unter der Android-SDK-Lizenz [8][9]. Ob das mit einer GPL-3.0-App verträglich ist, ist rechtlich ungeprüft; vermutlich bräuchte es eine Zusatzerlaubnis. Außerdem hinge die Kernfunktion an einem proprietären Dienst. Die Option `forceLocationManager` entfernt die Abhängigkeit nicht.
- **`flutter_foreground_task` 11.0.3 (MIT) als Dienst:** Weniger eigener Kotlin-Code, unterstützt Diensttypen und Wake Lock. Aber er startet eine zweite Engine [10], womit UI und Aufzeichnung drift nicht teilen können [7], und bringt Boot- und Neustart-Empfänger mit. Fällt Punkt 3 in R005 durch, ist er der Rückfallweg.
- **Aufzeichnung vollständig in Kotlin:** Überlebt den Dart-Teil, aber zwei Datenbank-Stacks mit demselben verschlüsselten Format und doppelte Logik.
- **`WorkManager`:** Für kontinuierliche Aufzeichnung nicht gedacht.
- **Companion Device Service:** Hilft nur bei Sensoren, Läufe ohne Sensor sind Pflicht (FR-0035).

**Nachtrag nach R005 (K9):**
- **Punkt 3:** Trägt im Emulator (API 31 und 36): kein Abstand über 5 s bei Sperre und `force-idle`, solange das System wach ist. Die Stichproben sind klein, auf API 36 lief ein einziger 60-Minuten-Lauf.
- **Punkt 5:** Startwert ist eine Zeile je Transaktion mit `synchronous = FULL`, keine Produktvorgabe; nächster Schritt bei Energie- oder Schreiblast wäre 5 Zeilen. Der Messauftrag zu `adb emu kill` je Transaktionsgröße ist durch `sigkill` ersetzt, Begründung in R005.
- **Punkt 2:** Ob der Typ `health` nötig wird, bleibt offen: Der Schrittsensor fehlt auf beiden Images, die Prüfung gehört in den Feldtest.
- **Rückfallweg:** `flutter_foreground_task` verhindert mit `allowAutoRestart: false` den Neustart nicht (`START_STICKY`, Alarm in `onTaskRemoved`). Ohne Patch oder Prüfung mit `stopWithTask` verletzt er Punkt 6.

**Nachtrag WP22 zu Punkt 6 (Erinnerungen, FR-0174; Entscheidung des Maintainers 2026-11-10):** Punkt 6 verbietet einen Boot-Empfänger, der einen Dienst oder die Aufzeichnung startet. Erlaubt ist genau ein Empfänger `TrainingReminderReceiver`, nicht exportiert (`android:exported="false"`), mit `BOOT_COMPLETED`-Filter, der nur die Wecker der Erinnerungen neu plant. Er startet keinen Dienst und keine Aufzeichnung und liest außer den gespeicherten Erinnerungszeitpunkten samt Art der Einheit keine Daten. Wecker nur inexakt: `SCHEDULE_EXACT_ALARM` und `USE_EXACT_ALARM` sind ausgeschlossen. Das Gate (`release_rechte`, `tool/check_release_manifest.py`) prüft das am Release-APK; eine Wiederaufnahme der Aufzeichnung bietet die App weiterhin nur beim nächsten Start an (Punkt 5).

## Konsequenzen
- Eigener Kotlin-Code wird nötig und braucht später für iOS ein Gegenstück.
- Der Dienst hält für die Dauer des Laufs einen Partial Wake Lock. Das ist eine Entscheidung des Maintainers vom 2026-11-04 und nicht durch Messung belegt: Verlorene Laufdaten kommen nicht wieder, Mehrverbrauch und Android Vitals werden in Kauf genommen. Googles Dokumentation spricht eher dagegen und Wake Locks kosten deutlich Akku [11]. Zeigt der Feldtest den Lock als überflüssig, entfällt er (R005, Abschnitt „Wake Lock“).
- Wiederaufnahme erfordert, dass der Nutzer die App öffnet. Bis dahin entsteht eine Lücke.
- `synchronous = FULL` schreibt häufig auf den Speicher, was die Kosten erhöht.

## Im Emulator nicht belegbar
Kill durch Energiesparmodi der Hersteller, die laut einer Community-Übersicht besonders Huawei, Xiaomi, OnePlus und Samsung betreffen [12]; echte GPS-Qualität; Akkuverbrauch; echter Stromausfall; das Akzeptanzkriterium „durchgehende Daten“ von FR-0034 unter Feldbedingungen. Prüfbar sind Prozess-Kill, Wischen aus den letzten Apps, `dumpsys deviceidle force-idle` und GPS-Wiedergabe. FR-0034 bleibt in `work-packages/STATUS.md` offen.

## Vorschlag Research R005: Durchstich der Aufzeichnung
Prototyp außerhalb von `app/` im Emulator (API 31 und 36), Build mit minSdk 31 und target 36. **Frage:** Trägt Punkt 3? **Messen:** Lücken im Lauf bei gesperrtem Bildschirm und `force-idle` mit und ohne Wake Lock, für Punkt 3 gegen `flutter_foreground_task`; Verlust nach Prozess-Kill und `adb emu kill` je Transaktionsgröße; Schreibkosten mit `synchronous = FULL`; verschlüsseltes WAL (ADR-0003); Schrittsensor unter Typ `location`. **Außerdem:** Lizenzbaum aus `gradle dependencies` und `flutter pub deps`. **Ergebnis:** Empfehlung für Host und Transaktionsgröße, keine Produktgrenzwerte.

## Belege (Abruf 2026-11-04)
[1] https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start ·
[2] https://developer.android.com/develop/sensors-and-location/location/permissions ·
[3] https://developer.android.com/develop/background-work/services/fgs/service-types ·
[4] https://developer.android.com/develop/background-work/services/fgs/launch ·
[5] https://developer.android.com/develop/ui/views/notifications/notification-permission ·
[6] https://docs.flutter.dev/add-to-app/android/add-flutter-screen ·
[7] https://drift.simonbinder.eu/isolates/ ·
[8] https://pub.dev/packages/geolocator_android (`android/build.gradle` im Archiv 5.2.1), https://pub.dev/packages/location ·
[9] https://dl.google.com/android/maven2/com/google/android/gms/play-services-location/21.2.0/play-services-location-21.2.0.pom ·
[10] https://pub.dev/packages/flutter_foreground_task (`ForegroundTask.kt` im Archiv 11.0.3) ·
[11] https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/set ·
[12] https://dontkillmyapp.com/ (nicht offiziell)
