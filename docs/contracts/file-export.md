# Vertrag: Dateiexport GPX, TCX, FIT

**Status:** Vorschläge (WP11, OQ-0032). Formatversionen vom Maintainer bestätigt (2026-11-06); die Abbildungsregeln sind Vorschläge des Pakets und umkehrbar.
**Anforderungen:** [FR-0182, FR-0183](../specs/export-sync.md), FR-0201, SEC-0003, CON-0008, CON-0010, ACC-13.
**Code:** `app/packages/core/lib/src/export/` (`export_run.dart` Abbildung, `gpx_encoder.dart`, `tcx_encoder.dart`, `xml_text.dart`, `fit_encoder.dart`, `fit_crc.dart`).

## Formatversionen

| Format | Version | Namensraum / Kennung | Schema (nicht im Repository) |
|---|---|---|---|
| GPX | 1.1 | `http://www.topografix.com/GPX/1/1` | `http://www.topografix.com/GPX/1/1/gpx.xsd` |
| GPX-Puls | Garmin TrackPointExtension v1 | `http://www.garmin.com/xmlschemas/TrackPointExtension/v1` | `https://www8.garmin.com/xmlschemas/TrackPointExtensionv1.xsd` |
| TCX | TrainingCenterDatabase v2 | `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2` | `https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd` |
| FIT | Protokoll 2.0, Profilfelder nach Profil 21.x | Nachrichten `file_id`, `event`, `record`, `lap`, `session`, `activity` | eigener Kodierer ohne Garmin-Code (OQ-0066, L1) |

Die TCX-ActivityExtension v2 wird nicht gebraucht und nicht verwendet.

## Abbildungsregeln (Vorschläge)

1. **Umfang:** Nur Läufe im Zustand `finished`. Nur Rohwerte mit Zustand `present`; `estimated`, `discarded` und `unavailable` fehlen im Export.
2. **Nur gemessene Werte:** Position, Höhe, Puls und Zeitstempel. Keine Kadenz (wird nicht gespeichert), keine Profilwerte, keine berechneten Eigenwerte (Zonen, TRIMP, VO₂max, Vorverarbeitung), keine Sensornamen oder Gerätekennungen. Ausnahme sind Pflichtfelder eines Formats, die minimal aus den exportierten Rohwerten gefüllt werden (siehe Feldabbildung).
3. **Zeit:** UTC. GPX und TCX: ISO 8601 mit Millisekunden, Mikrosekunden werden abgeschnitten. FIT: ganze Sekunden seit 1989-12-31 00:00 UTC. Je Kanal und Zeitschritt (1 ms bzw. 1 s) gilt der erste gespeicherte Wert; weitere Werte desselben Zeitschritts fallen weg (dokumentierter Verlust).
4. **Zusammenführung:** Ein Exportpunkt je Zeitstempel. TCX und FIT: Ein Punkt trägt nur die Werte, die zu seinem Zeitstempel gemessen wurden; Punkte nur mit Puls oder nur mit Höhe sind erlaubt, ein Ort wird nie erfunden. GPX: Ein `trkpt` entsteht nur aus einer gemessenen Position; Höhe und Puls kommen vom zeitlich nächsten Wert desselben Abschnitts innerhalb von ±1 s (bei Gleichstand der frühere), sonst fehlen sie.
5. **Pausen und Lücken:** `manualPause` und `interruption` trennen Abschnitte (GPX neues `trkseg`, TCX neuer `Track`, FIT Timer-Ereignis `stop_all`/`start`). Eine Pause gilt von ihrem Beginn (einschließlich) bis zu ihrem Ende (ausschließlich); Werte darin fehlen. Eine offene Pause endet am Laufende. `positionLoss` und `heartRateLoss` erzeugen nur fehlende Werte: keine Interpolation, nie 0.
6. **Runden:** Jede markierte Runde wird eine Runde des Formats (vom vorigen Rundenende bzw. Laufstart bis zur Markierung); der Rest bis zum Laufende ist eine weitere Runde. Ohne Markierung gibt es eine Runde über den ganzen Lauf. Ein Punkt gehört zur letzten Runde, deren Start nicht nach ihm liegt.
7. **Leer und kurz:** Ein Lauf ohne exportierbare Werte ergibt eine gültige Datei ohne Punkte (GPX: `trk` ohne `trkseg`; TCX: eine Runde ohne `Track`). Ein Lauf mit einem Punkt ergibt eine gültige Datei mit einem Punkt.
8. **Name:** `run-YYYYMMDD-HHMMSS` aus der Startzeit in Ortszeit über den UTC-Versatz am Laufende, sonst UTC. Dateiname: Name, beschränkt auf `A–Z a–z 0–9 . _ -` (anderes wird `_`, führende `.`/`_` entfallen, leer wird `run`), plus Erweiterung. In XML werden `& < > " '` escaped und in XML 1.0 unzulässige Zeichen entfernt.
9. **Ungültige Werte:** Positionen außerhalb von Breite −90…90 und Länge −180…<180 sowie nicht endliche Werte und Puls außerhalb 1…255 fehlen, weil die Formate sie nicht darstellen. Werte vor dem Start oder nach dem Ende des Laufs fehlen.
10. **Logs:** keine Werte, Koordinaten oder Zeitstempel.

## Feldabbildung

| Inhalt (FR-0183) | GPX 1.1 | TCX v2 | FIT (Teil B) |
|---|---|---|---|
| Quelle | `gpx/@creator = "running-app"` | – | `file_id`: Hersteller „development“ (255) |
| Name | `metadata/name`, `trk/name` | – | – |
| Sportart | `trk/type = running` | `Activity/@Sport = Running` | `lap`/`session.sport` = running (1), `session.sub_sport` = generic (0) |
| Laufstart | `metadata/time` | `Activity/Id`, `Lap/@StartTime` der ersten Runde | `file_id.time_created`, `session.start_time` |
| Laufende | – (kein Feld) | – (kein Feld; nur Rundenstart + Trackpoint-Zeiten) | `session.timestamp`, `activity.timestamp` |
| Position | `trkpt/@lat`, `@lon` (Dezimal ohne Exponent, verlustfrei) | `Trackpoint/Position/LatitudeDegrees`, `LongitudeDegrees` | `record.position_lat`, `position_long` (sint32, Semicircles = Grad · 2³¹/180, gerundet) |
| Zeitstempel | `trkpt/time` | `Trackpoint/Time` | `record.timestamp` (ganze Sekunden) |
| Höhe | `trkpt/ele` (Regel 4) | `Trackpoint/AltitudeMeters` | `record.altitude` (uint16, (m + 500) · 5, gerundet: 0,2 m Auflösung) |
| Puls | `trkpt/extensions/gpxtpx:TrackPointExtension/gpxtpx:hr` (Regel 4) | `Trackpoint/HeartRateBpm/Value` | `record.heart_rate` (uint8, bpm) |
| Kadenz | – (nicht gespeichert) | – | – |
| Abschnitt | `trkseg` (nur mit Punkten) | `Track` je Abschnitt und Runde (nur mit Punkten) | `event` timer `start` am Abschnittsbeginn, `stop_all` am Abschnittsende |
| Runde | – (GPX kennt keine Runden) | `Lap` | `lap` am Rundenende |

**Pflichtfelder der TCX-Runde** (Schema verlangt sie): `TotalTimeSeconds` = Zeit der Runde ohne Pausen; `DistanceMeters` = Summe der Großkreisabstände (Haversine mit mittlerem Erdradius 6 371 008,8 m wie in `geo.dart`) aufeinanderfolgender exportierter Positionen desselben Abschnitts, der Runde des späteren Punkts zugerechnet, auf Millimeter gerundet (über einen Positionsverlust hinweg zählt die gerade Verbindung, über eine Pause nicht); `Calories` = 0, nur weil das Schema den Wert verlangt; `Intensity` = `Active`; `TriggerMethod` = `Manual`. Nicht ausgegeben werden die optionalen Felder `MaximumSpeed`, `AverageHeartRateBpm`, `MaximumHeartRateBpm`, `Cadence` und `Trackpoint/DistanceMeters`.

**FIT-Datei** (Protokoll 2.0, Profil 21.40 im Kopf, eigener Kodierer): 14-Byte-Kopf mit `.FIT`, Datengröße und Kopf-CRC; danach Nachrichten mit normalem Kopf, little-endian, je Nachrichtenart ein lokaler Typ, definiert vor der ersten Datennachricht; am Ende die Datei-CRC über Kopf und Daten. CRC: CRC-16/ARC (Polynom 0xA001 bitumgekehrt, Start 0), wie im FIT-Protokoll; Referenzwert `"123456789"` → 0xBB3D. Keine komprimierten Zeitstempel, keine Entwicklerfelder.

| Nachricht | Felder (Profilname = Wert) |
|---|---|
| `file_id` | `type` = activity (4), `manufacturer` = development (255), `time_created` = Laufstart. Kein `product`, keine `serial_number`. |
| `event` | `timestamp`, `event` = timer (0), `event_type` = start (0) am Beginn jedes Abschnitts bzw. stop_all (4) an seinem Ende. Ohne Abschnitt (Lauf ganz in Pause): start und stop_all am Laufstart. |
| `record` | je Exportpunkt: `timestamp`, `position_lat`, `position_long`, `altitude`, `heart_rate`. Ein fehlender Wert steht als Invalid-Wert des Typs (sint32 0x7FFFFFFF, uint16 0xFFFF, uint8 0xFF), nie als 0. |
| `lap` | je Runde am Rundenende, Nachrichtenfolge zeitlich: `message_index`, `timestamp` = Rundenende, `event` = lap (9), `event_type` = stop (1), `start_time`, `total_elapsed_time` (Ende − Start), `total_timer_time` (ohne Pausen), `total_distance` (wie TCX `DistanceMeters`, Zentimeter), `lap_trigger` = manual (0) für markierte Runden, session_end (7) für die letzte, `sport` = running. |
| `session` | eine: `message_index` = 0, `timestamp` = Laufende, `event` = session (8), `event_type` = stop, `start_time`, `sport`, `sub_sport`, `total_elapsed_time`, `total_timer_time`, `total_distance` (Summe der Runden), `first_lap_index` = 0, `num_laps`, `trigger` = activity_end (0). |
| `activity` | eine: `timestamp` = Laufende, `total_timer_time`, `num_sessions` = 1, `type` = manual (0), `event` = activity (26), `event_type` = stop. Kein `local_timestamp`. |

Nicht ausgegeben: `total_calories`, Durchschnitts- und Höchstwerte, `distance` und `speed` je `record`, `enhanced_altitude`, `cadence`. Die Pflichtangaben von `lap` und `session` sind nur aus Zeiten und exportierten Positionen gerechnet (Regel 2).

**FIT-Zeit und Zusammenführung:** Der Lauf wird mit Auflösung 1 s abgebildet (`exportSecond`); Zeiten mit Bruchteilen lehnt der Kodierer ab. Fallen nach dem Abrunden zwei Abschnitte in dieselbe Sekunde (Pause unter einer Sekunde), entsteht dort ein `record`, der die Werte des früheren Punkts trägt und nur fehlende Kanäle aus dem späteren ergänzt (erster Wert je Kanal und Sekunde). Ein Punkt gehört zur letzten Runde, deren Start nicht nach ihm liegt; ein Abschnittsende zur Runde davor.

**FIT-Wertebereiche:** Höhe außerhalb −500 … 12 606,8 m und Puls 255 (Invalid-Wert von uint8) fehlen. Länge: Der Rundungswert 2³¹ (= 180°) wird −2³¹ (= −180°); der Wert 2³¹ − 1 fiele mit dem Invalid-Wert zusammen und wird 2³¹ − 2 (eine Einheit, unter 1 cm).

**Bekannte Verluste:** GPX trägt Puls und Höhe ohne gleichzeitige Position nicht; GPX hat keine Runden und kein Laufende. TCX hat kein Namensfeld. FIT hat kein Namensfeld (nur der Dateiname), Zeit nur in ganzen Sekunden und Höhe in 0,2 m.

## Übergabe an das System (FR-0201)

**Code:** Port `app/packages/core/lib/ports/file_handoff.dart`, Adapter `app/packages/adapters/lib/src/export/method_channel_file_handoff.dart`, Android `FileHandoffChannel.kt`, `FileHandoffFlow.kt`, `ExportFiles.kt`. Kanal `running_app/file_handoff`.

| Methode | Argumente | Antwort |
|---|---|---|
| `share`, `save` | `fileName` (sicherer Name), `mimeType`, genau eins von `bytes` (Inhalt) oder `path` (absolute Datei unter dem Ordner aus `exportDirectory`) | `completed`, `cancelled` oder Fehler mit Code (`bad_arguments`, `not_foreground`, `busy`, `share_failed`, `save_failed`, `write_failed`, `detached`); Dart bildet Fehler auf `failed` ab |
| `pickFile` | – | `cancelled`, oder der absolute Pfad der Kopie (`cacheDir/imports/archive.bin`), oder Fehler mit Code (`not_foreground`, `busy`, `pick_failed`, `read_failed`, `detached`); Dart bildet Fehler und alles andere auf `failed` ab |
| `discardPicked` | – | leert `cacheDir/imports`, antwortet danach leer; Dart ignoriert Fehler |
| `exportDirectory` | – | absoluter, kanonischer Pfad von `cacheDir/exports` (wird angelegt) oder Fehler `no_directory` |

- **Quellen:** Kleine Dateien (ein Lauf) als `bytes`. Große Dateien (z. B. ein Archiv) schreibt Dart vorher selbst in den Ordner aus `exportDirectory` und übergibt nur `path`; die Bytes gehen dann nicht über den Kanal, und `save` streamt aus der Datei in die Dokument-URI.
- **Pfadprüfung:** Ein `path` gilt nur, wenn er absolut ist, nach Auflösen von `..` und symbolischen Links eine reguläre Datei echt unterhalb von `cacheDir/exports` bezeichnet und die Datei selbst `fileName` heißt (`ExportFiles.source`; Dart prüft dasselbe in `ExportFile.inExportDirectory`); sonst `bad_arguments`. Dart lehnt schon vorher Pfade mit `.`/`..`-Abschnitten ab.
- **Aufräumen:** `cacheDir/exports` wird beim Prozessstart und vor jedem Teilen geleert; beim Teilen über `path` bleibt nur der Eintrag mit dieser Datei. Alle Schreib- und Aufräumaufträge laufen nacheinander auf einem Thread für den ganzen Prozess, auch über einen Neuaufbau der Activity hinweg.
- **Öffnen (`pickFile`, Reimport, WP12):** `ACTION_OPEN_DOCUMENT` mit `*/*` und `CATEGORY_OPENABLE`; es wird nur gelesen, es entsteht kein Dokument und kein Dauerrecht. Die gewählte URI wird als Strom (kein Zwischenpuffer, Hintergrundthread `ExportFiles.io`) nach `cacheDir/imports/archive.bin` kopiert; der Ordner wird vorher geleert, der Name ist fest und stammt nie aus der URI. `imports/` ist nicht im FileProvider freigegeben und liegt im vom Backup ausgenommenen Cache. Dart liest die Kopie per Pfad (nur Lesen). Es wird nur abgelegt, was der Nutzer wählt; die App erwartet Chiffretext (Archive sind verschlüsselt), schreibt aber nie Klartext dorthin. **Keine Größengrenze:** Der Nutzer wählt die Datei, der Strom braucht keinen Arbeitsspeicher, und ein volles Gerät ergibt `read_failed` (Teilkopie wird entfernt); eine willkürliche Grenze würde große, gültige Archive ablehnen. Höchstens ein Öffnen oder eine andere Übergabe zugleich (`busy`). Aufräumen: Prozessstart (`RunningApplication`), vor jedem neuen Öffnen und `discardPicked`, das Dart nach dem Import (auch nach Fehlern) aufruft. Fehler tragen nur den Klassennamen, nie Pfade oder Inhalte.
- **Verwaistes Dokument:** Kommt eine Dokument-URI an, ohne dass ein Speichern offen ist (Activity neu erzeugt, Prozess im Dokumentenziel beendet), entfernt die App das vom System schon angelegte leere Dokument; Dart hat dann bereits eine Antwort.
- **Bekannte Unschärfe beim Teilen:** Android meldet die Wahl des Ziels asynchron. Schließt ein Ziel sofort (oder bei der Aktion „Kopieren“ ab Android 14), kann die App vorher wieder vorne sein; dann lautet das Ergebnis `cancelled`, obwohl geteilt wurde. Folge nur eine fehlende Bestätigung in der Oberfläche, kein Datenrisiko. Der E2E-Test beobachtet das.

## Prüfung

Golden-Dateien und Rücklesetests: `app/packages/core/test/export/`. Die Validierung gegen die veröffentlichten Schemas (siehe Tabelle) läuft außerhalb des Repositorys und des Gates; das Ergebnis steht im Abschlussbericht des Pakets. FIT wird ebenso außerhalb mit einem unabhängigen Decoder geprüft; im Repository prüft ein eigener Minimal-Leser (`test/export/fit_reader.dart`) Kopf, Längen und beide CRC.
