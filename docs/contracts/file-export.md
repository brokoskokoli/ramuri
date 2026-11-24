# Vertrag: Dateiexport GPX, TCX, FIT

**Status:** Vorschläge (WP11, OQ-0032). Formatversionen vom Maintainer bestätigt (2026-11-06); die Abbildungsregeln sind Vorschläge des Pakets und umkehrbar.
**Anforderungen:** [FR-0182, FR-0183](../specs/export-sync.md), FR-0196, FR-0201, FR-0221, SEC-0003, CON-0008, CON-0010, ACC-13.
**Code:** `app/packages/core/lib/src/export/` (`export_run.dart` Abbildung, `gpx_encoder.dart`, `tcx_encoder.dart`, `xml_text.dart`, `fit_encoder.dart`, `fit_crc.dart`).

## Formatversionen

| Format | Version | Namensraum / Kennung | Schema (nicht im Repository) |
|---|---|---|---|
| GPX | 1.1 | `http://www.topografix.com/GPX/1/1` | `http://www.topografix.com/GPX/1/1/gpx.xsd` |
| GPX-Puls | Garmin TrackPointExtension v1 | `http://www.garmin.com/xmlschemas/TrackPointExtension/v1` | `https://www8.garmin.com/xmlschemas/TrackPointExtensionv1.xsd` |
| TCX | TrainingCenterDatabase v2 | `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2` | `https://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd` |
| TCX-Kadenz | Garmin ActivityExtension v2 | `http://www.garmin.com/xmlschemas/ActivityExtension/v2` | `https://www8.garmin.com/xmlschemas/ActivityExtensionv2.xsd` |
| FIT | Protokoll 2.0, Profilfelder nach Profil 21.x | Nachrichten `file_id`, `event`, `record`, `lap`, `session`, `activity` | eigener Kodierer ohne Garmin-Code (OQ-0066, L1) |

Die TCX-ActivityExtension v2 trägt nur die Schrittfrequenz (`RunCadence`); ihr Namensraum (`xmlns:tpx`) steht nur in Dateien mit Schrittfrequenz, andere Dateien bleiben byte-gleich.

## Abbildungsregeln (Vorschläge)

1. **Umfang:** Nur Läufe im Zustand `finished`. Nur Rohwerte mit Zustand `present`; `estimated`, `discarded` und `unavailable` fehlen im Export.
2. **Nur gemessene Werte:** Position, Höhe, Puls, Schrittfrequenz (aus dem gespeicherten Schrittzähler, Regel 11) und Zeitstempel. Keine Profilwerte, keine berechneten Eigenwerte (Zonen, TRIMP, VO₂max, Vorverarbeitung), keine Sensornamen oder Gerätekennungen. Ausnahme sind Pflichtfelder eines Formats, die minimal aus den exportierten Rohwerten gefüllt werden (siehe Feldabbildung).
3. **Zeit:** UTC. GPX und TCX: ISO 8601 mit Millisekunden, Mikrosekunden werden abgeschnitten. FIT: ganze Sekunden seit 1989-12-31 00:00 UTC. Je Kanal und Zeitschritt (1 ms bzw. 1 s) gilt der erste gespeicherte Wert; weitere Werte desselben Zeitschritts fallen weg (dokumentierter Verlust).
4. **Zusammenführung:** Ein Exportpunkt je Zeitstempel. TCX und FIT: Ein Punkt trägt nur die Werte, die zu seinem Zeitstempel gemessen wurden; Punkte nur mit Puls oder nur mit Höhe sind erlaubt, ein Ort wird nie erfunden. GPX: Ein `trkpt` entsteht nur aus einer gemessenen Position; Höhe und Puls kommen vom zeitlich nächsten Wert desselben Abschnitts innerhalb von ±1 s (bei Gleichstand der frühere), sonst fehlen sie.
5. **Pausen und Lücken:** `manualPause` und `interruption` trennen Abschnitte (GPX neues `trkseg`, TCX neuer `Track`, FIT Timer-Ereignis `stop_all`/`start`). Eine Pause gilt von ihrem Beginn (einschließlich) bis zu ihrem Ende (ausschließlich); Werte darin fehlen. Eine offene Pause endet am Laufende. `positionLoss` und `heartRateLoss` erzeugen nur fehlende Werte: keine Interpolation, nie 0.
6. **Runden:** Jede markierte Runde wird eine Runde des Formats (vom vorigen Rundenende bzw. Laufstart bis zur Markierung); der Rest bis zum Laufende ist eine weitere Runde. Ohne Markierung gibt es eine Runde über den ganzen Lauf. Ein Punkt gehört zur letzten Runde, deren Start nicht nach ihm liegt.
7. **Leer und kurz:** Ein Lauf ohne exportierbare Werte ergibt eine gültige Datei ohne Punkte (GPX: `trk` ohne `trkseg`; TCX: eine Runde ohne `Track`). Ein Lauf mit einem Punkt ergibt eine gültige Datei mit einem Punkt.
8. **Name:** `run-YYYYMMDD-HHMMSS` aus der Startzeit in Ortszeit über den UTC-Versatz am Laufende, sonst UTC. Dateiname: Name, beschränkt auf `A–Z a–z 0–9 . _ -` (anderes wird `_`, führende `.`/`_` entfallen, leer wird `run`), plus Erweiterung. In XML werden `& < > " '` escaped und in XML 1.0 unzulässige Zeichen entfernt.
9. **Ungültige Werte:** Positionen außerhalb von Breite −90…90 und Länge −180…<180 sowie nicht endliche Werte und Puls außerhalb 1…255 fehlen, weil die Formate sie nicht darstellen. Werte vor dem Start oder nach dem Ende des Laufs fehlen.
10. **Logs:** keine Werte, Koordinaten oder Zeitstempel.
11. **Schrittfrequenz (FR-0183, FR-0202; Methode `steps-counter-window`, Version 1):** Quelle ist der kumulierte Schrittzähler `raw_steps` ([Datenmodell](../architecture/data-model.md)), nur Werte mit Zustand `present`. Je Abschnitt (Regel 5) in Zeitfolge erhält jeder Zählerwert die Schrittfrequenz (Zähler − Zähler des frühesten Werts desselben Abschnitts, der höchstens 10 s davor liegt) / Zeitabstand · 60 in Schritten je Minute; das Fenster ist dasselbe wie in der Anzeige (`CadenceEstimator.defaultWindow`). Ohne solchen Vorgänger (erster Wert eines Abschnitts), bei Zeitabstand 0 oder fallendem Zähler fehlt der Wert: keine Interpolation, nie ein erfundenes 0. Gerechnet wird vor dem Abrunden der Zeit (Regel 3); jeder Zählerwert mit Schrittfrequenz ist ein eigener Exportpunkt (Regel 4). FIT und TCX tragen Doppelschritte je Minute (Schritte je Minute / 2, gerundet), wie für Laufen üblich; Werte außerhalb 0…254 fehlen. GPX trägt keine Schrittfrequenz.

## Feldabbildung

| Inhalt (FR-0183) | GPX 1.1 | TCX v2 | FIT (Teil B) |
|---|---|---|---|
| Quelle | `gpx/@creator = "ramuri"` | – | `file_id`: Hersteller „development“ (255) |
| Name | `metadata/name`, `trk/name` | – | – |
| Sportart | `trk/type = running` | `Activity/@Sport = Running` | `lap`/`session.sport` = running (1), `session.sub_sport` = generic (0) (Bandlauf treadmill (1)); andere Sportart siehe unten |
| Laufstart | `metadata/time` | `Activity/Id`, `Lap/@StartTime` der ersten Runde | `file_id.time_created`, `session.start_time` |
| Laufende | – (kein Feld) | – (kein Feld; nur Rundenstart + Trackpoint-Zeiten) | `session.timestamp`, `activity.timestamp` |
| Position | `trkpt/@lat`, `@lon` (Dezimal ohne Exponent, verlustfrei) | `Trackpoint/Position/LatitudeDegrees`, `LongitudeDegrees` | `record.position_lat`, `position_long` (sint32, Semicircles = Grad · 2³¹/180, gerundet) |
| Zeitstempel | `trkpt/time` | `Trackpoint/Time` | `record.timestamp` (ganze Sekunden) |
| Höhe | `trkpt/ele` (Regel 4) | `Trackpoint/AltitudeMeters` | `record.altitude` (uint16, (m + 500) · 5, gerundet: 0,2 m Auflösung) |
| Puls | `trkpt/extensions/gpxtpx:TrackPointExtension/gpxtpx:hr` (Regel 4) | `Trackpoint/HeartRateBpm/Value` | `record.heart_rate` (uint8, bpm) |
| Schrittfrequenz (Regel 11) | – | `Trackpoint/Extensions/tpx:TPX/tpx:RunCadence` (ActivityExtension v2, Doppelschritte je Minute, letztes Kind des `Trackpoint`) | `record.cadence` (Feld 4, uint8, Doppelschritte je Minute) |
| Abschnitt | `trkseg` (nur mit Punkten) | `Track` je Abschnitt und Runde (nur mit Punkten) | `event` timer `start` am Abschnittsbeginn, `stop_all` am Abschnittsende |
| Runde | – (GPX kennt keine Runden) | `Lap` | `lap` am Rundenende |

**Pflichtfelder der TCX-Runde** (Schema verlangt sie): `TotalTimeSeconds` = Zeit der Runde ohne Pausen; `DistanceMeters` = Summe der Großkreisabstände (Haversine mit mittlerem Erdradius 6 371 008,8 m wie in `geo.dart`) aufeinanderfolgender exportierter Positionen desselben Abschnitts, der Runde des späteren Punkts zugerechnet, auf Millimeter gerundet (über einen Positionsverlust hinweg zählt die gerade Verbindung, über eine Pause nicht); `Calories` = 0, nur weil das Schema den Wert verlangt; `Intensity` = `Active`; `TriggerMethod` = `Manual`. Nicht ausgegeben werden die optionalen Felder `MaximumSpeed`, `AverageHeartRateBpm`, `MaximumHeartRateBpm`, `Cadence` (Runde und `Trackpoint/Cadence`, die für Radfahren gedacht sind) und `Trackpoint/DistanceMeters`.

**FIT-Datei** (Protokoll 2.0, Profil 21.40 im Kopf, eigener Kodierer): 14-Byte-Kopf mit `.FIT`, Datengröße und Kopf-CRC; danach Nachrichten mit normalem Kopf, little-endian, je Nachrichtenart ein lokaler Typ, definiert vor der ersten Datennachricht; am Ende die Datei-CRC über Kopf und Daten. CRC: CRC-16/ARC (Polynom 0xA001 bitumgekehrt, Start 0), wie im FIT-Protokoll; Referenzwert `"123456789"` → 0xBB3D. Keine komprimierten Zeitstempel, keine Entwicklerfelder.

| Nachricht | Felder (Profilname = Wert) |
|---|---|
| `file_id` | `type` = activity (4), `manufacturer` = development (255), `time_created` = Laufstart. Kein `product`, keine `serial_number`. |
| `event` | `timestamp`, `event` = timer (0), `event_type` = start (0) am Beginn jedes Abschnitts bzw. stop_all (4) an seinem Ende. Ohne Abschnitt (Lauf ganz in Pause): start und stop_all am Laufstart. |
| `record` | je Exportpunkt: `timestamp`, `position_lat`, `position_long`, `altitude`, `heart_rate`, und nur wenn der Lauf eine Schrittfrequenz hat zusätzlich `cadence` als letztes Feld der Definition (Läufe ohne Schritte bleiben byte-gleich). Ein fehlender Wert steht als Invalid-Wert des Typs (sint32 0x7FFFFFFF, uint16 0xFFFF, uint8 0xFF), nie als 0. |
| `lap` | je Runde am Rundenende, Nachrichtenfolge zeitlich: `message_index`, `timestamp` = Rundenende, `event` = lap (9), `event_type` = stop (1), `start_time`, `total_elapsed_time` (Ende − Start), `total_timer_time` (ohne Pausen), `total_distance` (wie TCX `DistanceMeters`, Zentimeter), `lap_trigger` = manual (0) für markierte Runden, session_end (7) für die letzte, `sport` = running. |
| `session` | eine: `message_index` = 0, `timestamp` = Laufende, `event` = session (8), `event_type` = stop, `start_time`, `sport`, `sub_sport`, `total_elapsed_time`, `total_timer_time`, `total_distance` (Summe der Runden), `first_lap_index` = 0, `num_laps`, `trigger` = activity_end (0). |
| `activity` | eine: `timestamp` = Laufende, `total_timer_time`, `num_sessions` = 1, `type` = manual (0), `event` = activity (26), `event_type` = stop. Kein `local_timestamp`. |

Nicht ausgegeben: `total_calories`, Durchschnitts- und Höchstwerte, `distance` und `speed` je `record`, `enhanced_altitude`, `fractional_cadence`, Durchschnitts- und Höchstkadenz in `lap` und `session`. Die Pflichtangaben von `lap` und `session` sind nur aus Zeiten und exportierten Positionen gerechnet (Regel 2).

**FIT-Zeit und Zusammenführung:** Der Lauf wird mit Auflösung 1 s abgebildet (`exportSecond`); Zeiten mit Bruchteilen lehnt der Kodierer ab. Fallen nach dem Abrunden zwei Abschnitte in dieselbe Sekunde (Pause unter einer Sekunde), entsteht dort ein `record`, der die Werte des früheren Punkts trägt (auch die Schrittfrequenz) und nur fehlende Kanäle aus dem späteren ergänzt (erster Wert je Kanal und Sekunde). Ein Punkt gehört zur letzten Runde, deren Start nicht nach ihm liegt; ein Abschnittsende zur Runde davor.

**FIT-Wertebereiche:** Höhe außerhalb −500 … 12 606,8 m und Puls 255 (Invalid-Wert von uint8) fehlen. Länge: Der Rundungswert 2³¹ (= 180°) wird −2³¹ (= −180°); der Wert 2³¹ − 1 fiele mit dem Invalid-Wert zusammen und wird 2³¹ − 2 (eine Einheit, unter 1 cm).

**Bandläufe (FR-0196, WP25):** Ein Lauf im Laufbandmodus hat keine Position und keine Höhe; Strecke und Tempo sind die eingestellten Werte (Integral der Bandgeschwindigkeit über die aktive Zeit), nicht gemessen. Abweichend von Regel 1 und 2 gilt für sie:

- **GPX gesperrt:** GPX hat nichts zu tragen (kein `trkpt` ohne Position, Regel 4). Der Kodierer lehnt den Lauf ab (`ArgumentError`); das Exportfenster blendet GPX mit Grund aus und wählt TCX vor.
- **Punkte:** Aus den Bandeinstellungen entsteht je volle Sekunde ab Abschnittsbeginn und am Abschnittsende ein Punkt (1-s-Raster, kein Messwert); Puls-Punkte tragen ebenfalls die Strecke. Jeder Punkt trägt die kumulierte Strecke und die eingestellte Geschwindigkeit; Pausen und Unterbrechungen bleiben Abschnittsgrenzen (Regel 5).
- **TCX:** `Trackpoint` ohne `Position` und ohne `AltitudeMeters`, mit `DistanceMeters` (kumuliert, Meter); Schrittfrequenz wie oben. `Lap/DistanceMeters` ist der Zuwachs der Punktstrecke in der Runde (statt Haversine). Sport `Running`; TCX kennt keine Laufbandkennzeichnung, keine Speed-Extension.
- **FIT:** eigene `record`-Definition mit `timestamp`, `heart_rate`, `distance` (uint32, Zentimeter, Feld 5), `speed` (uint16, Millimeter je Sekunde, Feld 6; über 65,5 m/s fehlt der Wert) und ohne `position_lat`, `position_long`, `altitude`; mit Schrittfrequenz zusätzlich `cadence` wie oben; `session.sub_sport` = treadmill (1). `lap.total_distance` und `session.total_distance` sind der Streckenzuwachs. Alle übrigen Nachrichten wie oben.
- **Schrittfrequenz:** wie bei GPS-Läufen (Regel 11), der Schrittzähler läuft auch auf dem Laufband.
- GPS-Läufe bleiben byte-gleich (Goldens).

**Andere Sportart (FR-0221; Maintainer 2026-11-20):** Eine Einheit mit `runs.mode = sport` exportiert nur Puls und Zeit. Zusätzlich zu den Regeln oben gilt für sie:

- **GPX gesperrt:** wie beim Bandlauf; der Kodierer lehnt die Einheit ab (`ArgumentError`), das Exportfenster zeigt nur TCX und FIT (ohne GPX-Feld und ohne Hinweis) und wählt TCX vor.
- **Punkte:** nur aus dem Puls (Regel 4); Positionen, Höhen und Schritte werden nicht exportiert, auch wenn gespeichert. Kein 1-s-Raster, keine Strecke, keine Geschwindigkeit, keine Schrittfrequenz.
- Pausen und Runden wie oben (Regeln 5 und 6).

| Inhalt | Seilspringen (`rope`) | Radfahren (`cycling`) | Rudern/Ergometer (`rowing`) | Sonstiges (`other`) |
|---|---|---|---|---|
| GPX | nicht verfügbar | nicht verfügbar | nicht verfügbar | nicht verfügbar |
| TCX `Activity/@Sport` | `Other` | `Biking` | `Other` | `Other` |
| FIT `session.sport`, `lap.sport` (Profil 21.40, Typ `sport`) | generic (0) | cycling (2) | rowing (15) | generic (0) |
| FIT `session.sub_sport` | generic (0) | generic (0) | generic (0) | generic (0) |

- **TCX:** `Trackpoint` nur mit `Time` und `HeartRateBpm`; kein `Position`, `AltitudeMeters`, `DistanceMeters`, keine `Extensions`. Die Pflichtfelder der Runde wie oben, `Lap/DistanceMeters` = 0.
- **FIT:** eigene `record`-Definition nur mit `timestamp` und `heart_rate`; `lap` und `session` ohne `total_distance` (die übrigen Felder wie oben). Alle übrigen Nachrichten wie oben.
- GPS- und Bandläufe bleiben byte-gleich (Goldens).

**Bekannte Verluste:** GPX trägt Puls und Höhe ohne gleichzeitige Position nicht; GPX hat keine Runden und kein Laufende. GPX trägt keine Schrittfrequenz. TCX hat kein Namensfeld. FIT hat kein Namensfeld (nur der Dateiname), Zeit nur in ganzen Sekunden und Höhe in 0,2 m.

## Übergabe an das System (FR-0201)

**Code:** Port `app/packages/core/lib/ports/file_handoff.dart`, Adapter `app/packages/adapters/lib/src/export/method_channel_file_handoff.dart`, Android `FileHandoffChannel.kt`, `FileHandoffFlow.kt`, `ExportFiles.kt`. Kanal `ramuri/file_handoff`.

| Methode | Argumente | Antwort |
|---|---|---|
| `share`, `save` | `fileName` (sicherer Name), `mimeType`, genau eins von `bytes` (Inhalt) oder `path` (absolute Datei unter dem Ordner aus `exportDirectory`) | `completed`, `cancelled` oder Fehler mit Code (`bad_arguments`, `not_foreground`, `busy`, `share_failed`, `save_failed`, `write_failed`, `detached`); Dart bildet Fehler auf `failed` ab |
| `pickFile` | – | `cancelled`, oder der absolute Pfad der Kopie (`cacheDir/imports/archive.bin`), oder Fehler mit Code (`not_foreground`, `busy`, `pick_failed`, `read_failed`, `detached`); Dart bildet Fehler und alles andere auf `failed` ab |
| `discardPicked` | – | leert `cacheDir/imports`, antwortet danach leer; Dart ignoriert Fehler |
| `exportDirectory` | – | absoluter, kanonischer Pfad von `cacheDir/exports` (wird angelegt) oder Fehler `no_directory` |
| `clearExports` | `unlessBusy` (bool, fehlt = `false`), `exportsOnly` (bool, fehlt = `false`) | leert `cacheDir/exports` und `cacheDir/imports` samt Unterordnern auf `ExportFiles.io` (beide werden versucht), mit `exportsOnly` nur `cacheDir/exports` (Neubeginn nach Schlüsselverlust: die gewählte Archivkopie in `imports/` wird danach noch gelesen): `cleared`; mit `unlessBusy` und offener Übergabe nichts geleert: `busy` (kein Fehler); ein zu leerender Ordner nicht leer: Fehler `clear_failed`. Dart: `cleared`, `busy` (nur mit `unlessSharing`) → `keptWhileSharing`, alles andere → `failed` |

- **Quellen:** Kleine Dateien (ein Lauf) als `bytes`. Große Dateien (z. B. ein Archiv) schreibt Dart vorher selbst in den Ordner aus `exportDirectory` und übergibt nur `path`; die Bytes gehen dann nicht über den Kanal, und `save` streamt aus der Datei in die Dokument-URI.
- **Pfadprüfung:** Ein `path` gilt nur, wenn er absolut ist, nach Auflösen von `..` und symbolischen Links eine reguläre Datei echt unterhalb von `cacheDir/exports` bezeichnet und die Datei selbst `fileName` heißt (`ExportFiles.source`; Dart prüft dasselbe in `ExportFile.inExportDirectory`); sonst `bad_arguments`. Dart lehnt schon vorher Pfade mit `.`/`..`-Abschnitten ab.
- **Aufräumen:** `cacheDir/exports` wird beim Prozessstart und vor jedem Teilen geleert; beim Teilen über `path` bleibt nur der Eintrag mit dieser Datei. **Beim Löschen (SEC-0004)** leert `clearExports` `exports/` und `imports/`: „Alles löschen“ immer (auch bei offener Übergabe), „Lauf löschen“ nach dem Löschen des Laufs nur ohne offene Übergabe, weil das System die geteilte Datei womöglich noch liest – sonst räumt der nächste Prozessstart. Der Neubeginn nach Verlust des Datenbankschlüssels leert `exports/` (nicht `imports/`, dort liegt bei der Wiederherstellung das gewählte Archiv; es entfernt `discardPicked`). Bleibt `exports/` nicht sicher leer, scheitert der Neubeginn wie bei einem Fehler des Kartenspeichers, es wird kein neuer Schlüssel angelegt. Bleiben die Ordner nicht sicher leer (Fehler, kein Kanal), endet das Löschen mit `deletedNotErased`; die Daten in der Datenbank bleiben gelöscht. Alle Schreib- und Aufräumaufträge laufen nacheinander auf einem Thread für den ganzen Prozess, auch über einen Neuaufbau der Activity hinweg.
- **Öffnen (`pickFile`, Reimport, WP12):** `ACTION_OPEN_DOCUMENT` mit `*/*` und `CATEGORY_OPENABLE`; es wird nur gelesen, es entsteht kein Dokument und kein Dauerrecht. Die gewählte URI wird als Strom (kein Zwischenpuffer, Hintergrundthread `ExportFiles.io`) nach `cacheDir/imports/archive.bin` kopiert; der Ordner wird vorher geleert, der Name ist fest und stammt nie aus der URI. `imports/` ist nicht im FileProvider freigegeben und liegt im vom Backup ausgenommenen Cache. Dart liest die Kopie per Pfad (nur Lesen). Es wird nur abgelegt, was der Nutzer wählt; die App erwartet Chiffretext (Archive sind verschlüsselt), schreibt aber nie Klartext dorthin. **Keine Größengrenze:** Der Nutzer wählt die Datei, der Strom braucht keinen Arbeitsspeicher, und ein volles Gerät ergibt `read_failed` (Teilkopie wird entfernt); eine willkürliche Grenze würde große, gültige Archive ablehnen. Höchstens ein Öffnen oder eine andere Übergabe zugleich (`busy`). Aufräumen: Prozessstart (`RunningApplication`), vor jedem neuen Öffnen, `discardPicked`, das Dart nach dem Import (auch nach Fehlern) aufruft, und `clearExports` beim Löschen (siehe oben). Fehler tragen nur den Klassennamen, nie Pfade oder Inhalte.
- **Verwaistes Dokument:** Kommt eine Dokument-URI an, ohne dass ein Speichern offen ist (Activity neu erzeugt, Prozess im Dokumentenziel beendet), entfernt die App das vom System schon angelegte leere Dokument; Dart hat dann bereits eine Antwort.
- **Bekannte Unschärfe beim Teilen:** Android meldet die Wahl des Ziels asynchron. Schließt ein Ziel sofort (oder bei der Aktion „Kopieren“ ab Android 14), kann die App vorher wieder vorne sein; dann lautet das Ergebnis `cancelled`, obwohl geteilt wurde. Folge nur eine fehlende Bestätigung in der Oberfläche, kein Datenrisiko. Der E2E-Test beobachtet das.

## Prüfung

Golden-Dateien und Rücklesetests: `app/packages/core/test/export/`. Die Validierung gegen die veröffentlichten Schemas (siehe Tabelle) läuft außerhalb des Repositorys und des Gates; das Ergebnis steht im Abschlussbericht des Pakets. FIT wird ebenso außerhalb mit einem unabhängigen Decoder geprüft; im Repository prüft ein eigener Minimal-Leser (`test/export/fit_reader.dart`) Kopf, Längen und beide CRC.
