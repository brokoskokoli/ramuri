# Vertrag: Verschlüsseltes Archiv (Gesamtexport)

**Status:** Vorschlag des Pakets (WP12 Teil A, OQ-0032). Formatversion 1 vom Maintainer bestätigt (2026-11-07); Schema der Datenbank: Version 4. **WP18: Formatversion 2 mit Schema 5** (zusätzliche Abschnitte `run_feedback` und `manual_trainings`, Kopf und Parameter unverändert); Format 1 mit Schema 4 bleibt lesbar. Der Schreiber erzeugt ab WP18 nur noch Format 2. Die Zeilen- und Abschnittsregeln (Inhalt unter der Verschlüsselung) sind Vorschläge des Pakets und umkehrbar, solange kein Archiv der Version 1 ausgeliefert ist.
**Anforderungen:** FR-0192, FR-0198, SEC-0011, ACC-15; Entscheidungen in [ADR-0008](../architecture/adr/ADR-0008-verschluesselung-des-archivs.md) (Verfahren, Parameter), ADR-0004 Punkt 6 (Kennungen).
**Code:** `app/packages/core/lib/src/archive/` (Kopf, Rahmen, Export, Leser), Ports `app/packages/core/lib/ports/archive_cipher.dart`, `archive_source.dart` (Export) und `archive_sink.dart` (Import), Adapter `app/packages/adapters/lib/src/archive/`. Zwischendatenbank und Tausch beim Import sowie die Oberfläche folgen in späteren Teilen von WP12; dieser Vertrag legt sie fest.

Das Dokument beschreibt das Format so, dass es ohne den Dart-Code unabhängig umgesetzt werden kann. „MUSS“, „DARF NICHT“ und „KANN“ sind im Sinn von RFC 2119 gemeint. Alle Zahlen im Kopf sind unsigned und Big-Endian.

## 1. Überblick

```
Datei     = Kopf (36 Byte) Stück{1..n}
Stück     = ChaCha20-Poly1305-Chiffretext (Klartextlänge + 16 Byte Tag)
Klartext  = gzip( JSON Lines )                     # Abschnitt 4 und 5
```

Die Datei hat keine Fußzeile und kein Längenfeld. Das Ende wird durch das mit „letzt“ markierte Stück bewiesen (Abschnitt 3).

## 2. Kopf (Formatversion 1 und 2, genau 36 Byte)

| Offset | Länge | Feld | Wert in Version 1 und 2 |
|---:|---:|---|---|
| 0 | 8 | Magic | ASCII `RUNARCHV` = `52 55 4E 41 52 43 48 56` |
| 8 | 2 | Formatversion (uint16 BE) | `0x0001` (Format 1) oder `0x0002` (Format 2, vom Schreiber erzeugt) |
| 10 | 4 | Argon2-Speicher in KiB (uint32 BE) | `65536` (`00 01 00 00`), also 64 MiB |
| 14 | 4 | Argon2-Durchläufe t (uint32 BE) | `3` |
| 18 | 1 | Argon2-Parallelität p (uint8) | `1` |
| 19 | 1 | Länge des abgeleiteten Schlüssels (uint8) | `32` |
| 20 | 16 | Salz | 16 zufällige Byte je Archiv (kryptografisch sicherer Zufall) |

Die Stücke beginnen bei Offset 36. Das gesamte Kopf-Byte-Feld (Offset 0 bis 35, unverändert) ist die zusätzlich authentifizierte Datei (AAD) jedes Stücks.

**Leser-Regeln (in dieser Reihenfolge, jede scheitert, ohne dass etwas gelesen oder geändert wird, das über die Datei hinausgeht):**

1. Weniger als 8 Byte oder Magic ungleich `RUNARCHV`: **keine Archivdatei**.
2. Weniger als 10 Byte oder Formatversion weder 1 noch 2: **unbekannte Formatversion** (auch 0 und 3). Eine neuere App-Version liest nur die ihr bekannten Versionen; eine ältere App lehnt ein neueres Archiv ab und ändert nichts (Entscheidung C in ADR-0008).
3. Weniger als 36 Byte: **beschädigt**.
4. Speicher, Durchläufe, Parallelität oder Schlüssellänge ungleich den Werten der Tabelle (und damit der Formatversion): **nicht unterstützte Parameter**. Das geschieht **vor** jeder Schlüsselableitung; ein Kopf darf keine Speicheranforderung auslösen, die er nicht selbst als bekannte Konstante trägt (ADR-0008 Punkt 3). Das Salz wird nicht geprüft (jeder Wert ist zulässig).
5. Erst danach wird der Schlüssel abgeleitet und die Stücke werden gelesen.

Beide Formatversionen tragen dieselben Parameter. Stärkere Parameter oder ein anderes Verfahren erscheinen nur als neue Formatversion.

## 3. Schlüsselableitung und Rahmen

### 3.1 Schlüssel

Argon2id nach RFC 9106, Version `0x13` (1.3), Parameter aus dem Kopf (Speicher 65536 KiB, t = 3, p = 1), Salz aus dem Kopf, Länge 32 Byte, **ohne** Secret und **ohne** Associated Data. Passwort: die UTF-8-Bytes der eingegebenen Zeichenfolge, **ohne Normalisierung** (kein NFC/NFKC, kein Trimmen). Das Ergebnis ist unmittelbar der ChaCha20-Poly1305-Schlüssel; es gibt keine weitere Ableitung (je Archiv zufälliges Salz). Die App verlangt mindestens 15 Zeichen; das Format selbst kennt keine Passwortregel, ein leeres Passwort ist ein gültiger Argon2-Eingang.

### 3.2 Stücke (STREAM wie age v1, C2SP age.md)

- Der Klartext wird in Stücke zu **65536 Byte** geteilt; alle außer dem letzten sind genau so lang. Das letzte Stück hat 0 bis 65536 Byte.
- Der Klartext ist nur dann leer, wenn die Datei genau **ein** leeres letztes Stück enthält (Chiffretext = nur der 16-Byte-Tag). Ist der Klartext nicht leer, ist das letzte Stück **nicht leer**: Ist seine Länge ein Vielfaches von 65536, ist das letzte Stück ein volles Stück, und es folgt **kein** zusätzliches leeres Stück.
- Chiffretext je Stück = ChaCha20-Poly1305 (RFC 8439) mit dem Schlüssel aus 3.1, der Nonce unten, AAD = Kopf (36 Byte), Ausgabe `Chiffre ‖ Tag` (Tag 16 Byte, hinten). Länge: Klartext + 16.
- **Nonce (12 Byte):** Byte 0 bis 10: der Stückzähler als 11-Byte-Big-Endian-Zahl, das erste Stück hat Zähler 0, jedes weitere +1. Byte 11: `0x01` beim **letzten** Stück, sonst `0x00`.
- Aufbau der Datei: Kopf, dann die Chiffretexte in Zählerreihenfolge ohne Trennung. Volle Stücke belegen 65552 Byte (65536 + 16).

**Lesen:** Ab Offset 36 gilt: Folgen nach den nächsten 65552 Byte noch weitere Byte, ist das Stück nicht das letzte (Flag `0x00`); sonst ist der Rest (16 bis 65552 Byte) das letzte Stück (Flag `0x01`). Jedes Stück MUSS erst nach erfolgreicher Prüfung des Tags verwendet werden. Fehler (jeder bricht ab):

| Lage | Fehler |
|---|---|
| Kein Stück vorhanden (Datei endet nach dem Kopf), oder das **erste** Stück scheitert (Tag), oder das einzige Stück ist kürzer als 16 Byte | falsches Passwort **oder** beschädigter Anfang (technisch nicht unterscheidbar) |
| Ein **späteres** Stück scheitert (Tag), der Rest nach einem vollen Stück fehlt (Abschneiden an einer Stückgrenze: das letzte vorhandene Stück ist mit Flag `0x00` geschrieben und scheitert als letztes), Stücke vertauscht oder doppelt (falscher Zähler), Bytes angehängt (das echte letzte Stück erscheint dann als nicht-letztes) | beschädigt |
| Ein leeres letztes Stück (Klartext 0 Byte), das nicht das einzige Stück ist (Zähler > 0) | beschädigt |

**Vorrang:** Scheitert das **erste** Stück, gilt immer Zeile 1, auch wenn zugleich eine Beschreibung der Zeile 2 passt. Das betrifft das Abschneiden unmittelbar nach dem ersten vollen Stück (es wird dann mit Flag `0x01` gelesen und scheitert) und ein einziges volles Stück, das mit Flag `0x00` geschrieben wurde. Zeile 2 gilt erst, wenn das erste Stück die Prüfung bestanden hat. Ein Rest von 1 bis 15 Byte nach einem vollen Stück ist kein Tag und damit „beschädigt“ (Zeile 2); ein einziges Stück unter 16 Byte ist Zeile 1.

Das Ende der Datei beendet die Prüfung: Nach dem letzten gültigen Stück gibt es keine weiteren Byte.

**Wichtig für Verbraucher des Stroms:** Frühere Stücke können Klartext liefern, bevor das letzte Stück geprüft ist. Ein Leser MUSS das Ergebnis verwerfen, wenn der Strom nicht fehlerfrei bis zum letzten Stück endet (Zwischendatenbank, Tausch erst danach; ADR-0008 Punkt 5).

## 4. Inhalt unter der Verschlüsselung

Der entschlüsselte Klartext ist **ein** gzip-Element (RFC 1952, ein Member, DEFLATE; Stufe und Kopffelder frei; der Schreiber setzt `FNAME`/`FEXTRA`/`FCOMMENT`/`FHCRC` nicht, der Leser duldet sie, wenn die Dart-zlib-Anbindung sie als gültigen gzip-Kopf annimmt, ohne sie auszuwerten). Der Leser MUSS CRC32 und ISIZE (mod 2^32) prüfen und DARF NICHT Byte nach dem Element dulden; ein abgeschnittenes, ein zweites oder ein um Byte verlängertes Element ist „beschädigt“. (Die Zlib-Anbindung von Dart prüft das nicht streng; der Leser vergleicht deshalb die letzten 8 Byte des entschlüsselten Stroms mit CRC32 und Länge der gesamten entpackten Ausgabe.) Zeitstempel (`MTIME`) und `OS`-Byte des gzip-Kopfs sind beliebig. Die Dekompression erfolgt als Strom; sie darf nicht den ganzen Inhalt im Speicher halten.

Dekomprimiert ist es ein JSON-Lines-Text (UTF-8 ohne BOM): Jede Zeile ist **ein** JSON-Objekt (RFC 8259) auf einer Zeile, Zeilentrenner genau `\n` (auch nach der letzten Zeile), keine leeren Zeilen. Der Schreiber erzeugt kompaktes JSON ohne Leerraum; der Leser liest jedes gültige JSON. Eine Zeile ist höchstens 16 MiB lang (Leser-Grenze gegen Speicherbomben). Ganze Zahlen sind 64-Bit-Ganzzahlen (signed) und MÜSSEN verlustfrei gelesen werden (Mikrosekunden seit Epoch passen nicht in jede Gleitkommadarstellung); eine Ganzzahl außerhalb von −2^63 bis 2^63−1 ist ein Fehler, nie ein Ersatz durch eine Gleitkommazahl. Objekte dürfen keinen Schlüssel doppelt tragen. Der Leser nimmt jede Schreibweise gültigen JSONs an (auch Escapes wie `\ud83c\udfc3` statt direktem UTF-8, `-0` als Ganzzahl 0, Leerraum einschließlich `\r`), aber keinen Text mit einzelnem Surrogat (auch nicht als `\ud800`), kein BOM und keine ungültige UTF-8-Folge.

### 4.1 Zeilenfolge

1. **Manifest** (genau eine, erste Zeile): `{"type":"manifest","format":2,"schema_version":5,"created_at_us":<int>}` (Format 1: `"format":1,"schema_version":4`). `format` ist die Formatversion des Kopfes (gleich), `schema_version` das Datenbankschema der Zeilen, `created_at_us` der Erstellzeitpunkt in Mikrosekunden seit Epoch (UTC). Format 1 gehört zu Schema 4, Format 2 zu Schema 5; jede andere Paarung (Format 3 oder 0, Format 2 mit Schema 4, Format 1 mit Schema 5) ist ein Widerspruch (beschädigt). Ein Schema größer als 5 ist „neueres Archiv“ (ohne Änderung), ein Schema kleiner als 4 „Schema nicht unterstützt“, solange es keine Migration gibt. Unbekannte weitere Schlüssel im Manifest sind ein Fehler, **außer** bei einem größeren Schema: Der Leser wertet `schema_version` zuerst aus, ein größeres Schema ist „neueres Archiv“, auch wenn das Manifest weitere Schlüssel trägt. `format` im Manifest ungleich der Formatversion des Kopfes ist ein Widerspruch (beschädigt).
2. **Abschnitte** in der festen Reihenfolge der Tabelle in 4.3, **alle** Abschnitte der Formatversion (Format 2: 21, Format 1: die 19 ohne `run_feedback` und `manual_trainings`), auch leere. Ein Abschnitt, den die Formatversion nicht kennt, und ein fehlender sind Fehler: Format 1 mit den neuen Abschnitten und Format 2 ohne sie werden abgelehnt. Jeder Abschnitt beginnt mit `{"type":"section","name":"<Abschnittsname>"}`, darauf folgen seine Zeilen `{"type":"row","data":{<Spalte>:<Wert>,...}}`. Eine Zeile gehört zum zuletzt begonnenen Abschnitt.
3. **Ende** (genau eine, letzte Zeile): `{"type":"end","rows":{"runs":<n>,"laps":<n>,...}}` mit der Zeilenzahl **jedes** Abschnitts der Formatversion (auch 0), in der Reihenfolge der Abschnitte. Der Leser zählt mit und lehnt jede Abweichung ab. Jeder Zähler ist eine Ganzzahl (`0.0` ist keine); die Reihenfolge der Schlüssel in `rows` ist beliebig, der Schlüsselsatz muss genau die Abschnitte der Formatversion sein.

Abweichungen sind Fehler: fehlender oder doppelter Abschnitt, falsche Reihenfolge, Zeile außerhalb eines Abschnitts, Zeile nach der Endzeile, fehlende Endzeile, unbekannter `type`, unbekannter Abschnittsname.

### 4.2 Zeilen (`data`)

- `data` enthält **genau** die Spalten der Tabelle laut 4.3 (in Schemareihenfolge geschrieben, der Leser darf jede Reihenfolge lesen), **jede** Spalte, `NULL` als `null`. Ein fehlender oder zusätzlicher Schlüssel ist ein Fehler.
- INTEGER: JSON-Ganzzahl (ohne Bruch und Exponent). REAL: endliche JSON-Zahl (der Schreiber bricht den Export ab, wenn ein Wert nicht endlich ist); eine Ganzzahl-Schreibweise ist für REAL zulässig. TEXT: JSON-String (gültiges Unicode, keine einzelnen Surrogate). BOOLEAN-Spalten sind SQLite-Ganzzahlen: `0` oder `1`.
- Spalten, die JSON-Text enthalten (`rated_sections.gps_gaps`, `computed_values.sources`, `value_sections.reasons`), werden als **String** mit dem gespeicherten Text übertragen, nicht als verschachteltes JSON; der Leser setzt sie unverändert ein.
- **Kennungen bleiben erhalten:** Alle `id`-Spalten und Verweise (`run_id`, `computed_value_id`, `raw_id`) tragen die Werte der Quelldatenbank. Der Leser stellt die Zeilen unter diesen Kennungen wieder her (die Verweise in `preprocessed_samples.raw_id` hängen daran) und lässt die Datenbank Fremdschlüssel, CHECKs und Trigger prüfen; jede Verletzung lehnt das ganze Archiv ab.
- **Zeilenreihenfolge:** innerhalb eines Abschnitts aufsteigend nach dem Primärschlüssel (`id`, bei `settings` nach `key`, bei `run_feedback` nach `run_id`). Der Leser lehnt nicht aufsteigende oder doppelte `id`s ab (Abschnitt 4.5); die Reihenfolge der Schlüssel in `settings` und doppelte Schlüssel dort prüft die Datenbank (Primärschlüssel). Der Schreiber vergibt die `id`s so, dass sie in jedem Abschnitt in der Dateireihenfolge wachsen, auch `value_sections.id` mit der Reihenfolge der `computed_values`-Zeilen, zu denen sie gehören. Die Datenbank-Trigger verlangen beim Wiederherstellen: erst `runs`, dann deren Rohdaten (nur anhängen); bei Laufwerten je `computed_values`-Zeile `original`, dann dessen `value_sections`, dann `current`, jeweils in aufsteigender `id` (Trigger `value_sections_original_no_late_insert` prüft, dass die Zeile des Werts die zuletzt vergebene ist). Weil `value_sections` hinter `computed_values` steht, MUSS der Leser dafür zwischenspeichern oder die Reihenfolge herstellen; der Zwischenspeicher darf nicht der Klartext auf dem Datenträger sein (ADR-0008 Punkt 5).
- **Unbekannte `value_key`s** (und unbekannte `method`-Namen, `unavailable_reason`-Codes, `source`-Namen) werden unverändert durchgereicht: Der Leser prüft sie nicht gegen eine Liste. Ein Code, den die App beim späteren Lesen nicht versteht, ist dort ein Datenfehler wie im bisherigen Schema.
- **Zulässige Werte der TEXT-Spalten:** Der Leser prüft Typ und Form, nicht diese Mengen; sie prüft die Datenbank beim Wiederherstellen (CHECK in `schema.drift`, Schema 4 und 5), und jede Verletzung lehnt das ganze Archiv ab. Maßgeblich ist `schema.drift`; zur Orientierung:

  | Spalte | Zulässig |
  |---|---|
  | `runs.state` | `active`, `paused`, `finished` |
  | `run_gaps.kind` | `manual_pause`, `position_loss`, `heart_rate_loss`, `interruption` |
  | `raw_positions`, `raw_heart_rates`, `raw_altitudes`, `raw_steps`: `state`; `preprocessed_samples.state` | `present`, `estimated`, `unavailable`, `discarded` (Wertspalten nur bei `unavailable` leer) |
  | `raw_*.source` | beliebiger Text (Gerät oder Quelle, kein Fremdschlüssel) |
  | `raw_heart_rates.contact` | `good`, `poor`, `unsupported` |
  | `preprocessed_samples.channel` | `position`, `heart_rate`, `altitude`, `steps` |
  | `preprocessed_samples.discard_reason` | `null` oder `accuracy`, `hardJump`, `softJump`, `nonMonotonicTime`, `implausibleHeartRate`, `noContact`, `heartRateOutlier`, `verticalAccuracy`, `invalidValue` |
  | `preprocessed_spans.kind` | `moving`, `settling`, `position_gap`, `heart_rate_gap` |
  | `computed_values.role` | `original`, `current` (je Lauf oder Tag und `value_key` genau eine Zeile je Rolle) |
  | `computed_values.quality` | `provisional`, `sufficient`, `good`, `undeterminable` |
  | `computed_values.run_id` / `day` | genau eines von beiden gesetzt; `day` ist ein ISO-Datum |
  | `computed_values.value_key`, `unit`, `method`, `unavailable_reason`, `sources` | beliebiger Text (siehe unbekannte `value_key`s); `value_real` ist genau dann `null`, wenn `unavailable_reason` gesetzt ist (Trigger) |
  | `value_sections.status` | `eligible`, `provisional`, `rejected` |
  | `value_sections.discard` | `null` oder `implausible`, `incomplete`, `zeroWeight` |
  | `rated_sections.gps_gaps` | gültiger JSON-Text (als String übertragen), Format `[[start_us, end_us, open], …]` mit `open` = 0 oder 1 (Schema-Kommentar, `derived_access.dart`); der Leser prüft nur `json_valid`, die App lehnt beim Lesen anderes ab (fail-closed) |
  | `value_sections.reasons` | gültiger JSON-Text (als String übertragen) |
  | `preprocessing_results.method`, `rated_sections.method` | beliebiger Text |

  Zahlenbereiche (zum Beispiel `ended_utc_offset_s` −64800 bis 64800, `training_days_mask` 0 bis 127, positive Werte in `profile`, `end_us >= start_us`) stehen ebenfalls als CHECK in `schema.drift`. Fehlende Werte sind `null`, nie 0.
- Laufwerte (`computed_values`) tragen **beide** Rollen (`original`, `current`) mit `unavailable_reason`, Basis (`hr_max_bpm`, `hr_rest_bpm`, `hr_max_is_estimated`), Quellen, Versionen und Qualität. Zonenzeiten und `trimp_run` sind Laufwerte und stehen hier; sie sind nicht aus den Rohdaten rekonstruierbar.

### 4.3 Abschnitte und Spalten (Schema 5)

Quelle der Spalten: `app/packages/adapters/lib/src/storage/schema.drift` (Schemaversion 5). Typen: I = INTEGER, R = REAL, T = TEXT, B = BOOLEAN (0/1). `?` = darf `null` sein.

| # | Abschnitt | Spalten |
|--:|---|---|
| 1 | `runs` | id I, state T, started_at_us I, ended_at_us I?, ended_utc_offset_s I? |
| 2 | `laps` | id I, run_id I, lap_index I, marked_at_us I, lap_time_s R |
| 3 | `run_gaps` | id I, run_id I, kind T, start_us I, end_us I? |
| 4 | `raw_positions` | id I, run_id I, time_us I, source T, state T, latitude_deg R?, longitude_deg R?, accuracy_m R?, speed_mps R?, speed_accuracy_mps R?, vertical_accuracy_m R? |
| 5 | `raw_heart_rates` | id I, run_id I, time_us I, source T, state T, bpm I?, contact T |
| 6 | `raw_altitudes` | id I, run_id I, time_us I, source T, state T, altitude_m R?, vertical_accuracy_m R? |
| 7 | `raw_steps` | id I, run_id I, time_us I, source T, state T, step_count I? |
| 8 | `preprocessing_results` | id I, run_id I, method T, method_version I, parameter_version I, computed_at_us I, total_time_s R?, moving_time_s R?, distance_m R?, bridged_distance_m R?, average_bpm R?, max_bpm I?, median_bpm R?, best_pace_s_per_km R?, lap_count I?, heart_rate_time_s R? |
| 9 | `preprocessed_samples` | id I, run_id I, channel T, raw_id I, time_us I, state T, discard_reason T? |
| 10 | `preprocessed_spans` | id I, run_id I, kind T, start_us I, end_us I? |
| 11 | `rated_sections` | id I, run_id I, start_us I, end_us I, method T, method_version I, parameter_version I, assessed_at_us I, heart_rate_present I, heart_rate_estimated I, heart_rate_unavailable I, heart_rate_discarded I, position_present I, position_estimated I, position_unavailable I, position_discarded I, missing_heart_rate_share R, longest_heart_rate_gap_s R, meets_heart_rate_gap_rule B, settling_overlap_s R, settling_share R, gps_gaps T |
| 12 | `computed_values` | id I, run_id I?, day T?, value_key T, role T, value_real R?, unit T, computed_at_us I, data_from_us I?, data_to_us I?, measurement_count I, sources T, method T, method_version I, parameter_version I, quality T, unavailable_reason T?, hr_max_bpm I?, hr_rest_bpm I?, hr_max_is_estimated B? |
| 13 | `value_sections` | id I, computed_value_id I, position I, start_us I, end_us I, gps_median_accuracy_m R?, weight R, late_factor R, status T, discard T?, reasons T, oxygen_demand R?, estimate R? |
| 14 | `profile` | id I (immer 1), birth_year I?, body_weight_kg R?, body_height_m R?, resting_heart_rate_bpm I?, max_heart_rate_bpm I?, weekly_run_minutes I?, training_days_mask I?, usual_training_minutes I? |
| 15 | `settings` | key T, value T, updated_at_us I |
| 16 | `known_devices` | id I, device_id T, display_name T?, is_preferred B, added_at_us I |
| 17 | `run_feedback` | run_id I, rpe I?, wellbeing I?, complaints T?, warning_answer T?, note T?, srpe_points R?, srpe_duration_s R?, srpe_method T?, srpe_method_version I? |
| 18 | `manual_trainings` | id I, day T, kind T, duration_s I, rpe I |
| 19 | `goals` | (leer, siehe unten) |
| 20 | `plans` | (leer, siehe unten) |
| 21 | `active_warning` | (leer, siehe unten) |

**Seit WP18, nur Format 2 (Abschnitte 17 und 18):** `run_feedback` trägt die Angaben zum Lauf (höchstens eine Zeile je Lauf, Schlüssel `run_id`, Fremdschlüssel auf `runs`), `manual_trainings` die nachgetragenen Trainings (eigene Tabelle, nie in `runs`). Der Leser prüft Typ und Grenzen, ohne zu klemmen oder zu runden, und lehnt das ganze Archiv ab bei: `rpe` außerhalb 0 bis 10 oder nicht ganzzahlig (5.5, 11), `wellbeing` außerhalb 1 bis 5, sRPE-Spalten nicht alle gesetzt oder alle leer (gesetzt nur mit `rpe`), sRPE-Wert ungleich `srpe_duration_s / 60 · rpe` (nur bei Methode `srpe_duration_rpe` Version 1; ältere Methoden rechnet der Leser nicht nach), `duration_s` ≤ 0, `rpe` eines Trainings fehlend oder außerhalb 0 bis 10, doppelter oder nicht aufsteigender Schlüssel. Die Datenbank lehnt zusätzlich ab (CHECK, Fremdschlüssel): `warning_answer` ohne `complaints` oder nicht `yes`/`no`, ungültiges Datum (`day` ist `JJJJ-MM-TT` und existiert), `kind` nicht `run` oder `other`, `run_id` ohne Lauf. Ein Training mit `day` **nach heute** (Ortstag, Uhr-Port beim Einlesen, einmal je Einlesen festgelegt) lehnt das ganze Archiv ab (beschädigt), wie die Eingabe (`ManualTraining.requireNotAfter`); heute selbst wird angenommen. Die Prüfung läuft im Leser, bevor `commit` kommt; wie bei jeder Zeilenprüfung können frühere Stapel schon im Ziel liegen, der Abbruch verwirft sie (3.2). Fehlermeldungen nennen keine Inhalte (RPE, Befinden, Beschwerden, Notiz).

Nicht im Archiv: die Tabellen `storage_meta` (technisch), `consents` (Einwilligungen, SEC-0011) sowie Datenbankschlüssel und Zugangsdaten (liegen nie in der Datenbank). Nach dem Import sind Einwilligungen nicht erteilt.

**Leere Abschnitte (Format 2: 19 bis 21; Format 1: 17 bis 19):** `goals`, `plans`, `active_warning` sind für spätere Phasen vorgesehen (FR-0192, L13). In beiden Formaten haben sie **0 Zeilen**; der Leser lehnt einen Abschnitt mit Zeilen ab, weil er sie nicht speichern kann (nicht stillschweigend verwerfen). Ihre Spalten legt das Schema fest, das sie einführt (mit neuem `schema_version`, nötigenfalls neuer Formatversion).

**Technische Merker in `settings`:** Der Schreiber lässt die Schlüssel `values.calculationPending`, `values.refreshPending`, `recalculation.pending`, `load.profile_pending` (die noch unbestätigte Profilwahl zu einem offenen Angebot), `load.coefficients_pending` (die noch unbestätigte Änderung der Koeffizienten-Angabe), `load.factor_pending` (der angebotene neue persönliche Faktor) und `load.factor_declined` (der zuletzt abgelehnte Faktor) weg. Sie sind Merker für unterbrochene Hintergrundarbeit oder ein offenes Angebot der Quellinstallation (`core/lib/src/recalculation/`) und gehören nicht in einen Wiederherstellungsstand; sie würden nach dem Import auf Zustände zeigen, die dort nicht gelten. Alle anderen Schlüssel (auch unbekannte) werden übernommen. Der Leser nimmt jeden Schlüssel an, den er findet. (Die Liste ist an den Quelltext gebunden: Kommt ein neuer technischer Merker hinzu, ist sie hier und im Schreiber zu ergänzen; der Schreiber-Teil von WP12 soll sie per Test gegen die Konstanten prüfen.)

### 4.4 Beispiel (Klartext, bevor gzip angewendet wird; Werte synthetisch, gekürzt)

```
{"type":"manifest","format":2,"schema_version":5,"created_at_us":1793000000000000}
{"type":"section","name":"runs"}
{"type":"row","data":{"id":1,"state":"finished","started_at_us":1792000000000000,"ended_at_us":1792000600000000,"ended_utc_offset_s":3600}}
{"type":"section","name":"laps"}
...
{"type":"section","name":"run_feedback"}
{"type":"section","name":"manual_trainings"}
{"type":"section","name":"goals"}
{"type":"section","name":"plans"}
{"type":"section","name":"active_warning"}
{"type":"end","rows":{"runs":1,"laps":0,...,"goals":0,"plans":0,"active_warning":0}}
```

### 4.5 Leser: Ablauf, Ziel und Fehlerarten

Der Leser (`ArchiveImporter`, `readArchive`) arbeitet als Strom in einem Arbeits-Isolate: Datei lesen → Kopf prüfen → entschlüsseln (Port `ArchiveCipher`) → gunzip → in Zeilen an `\n` teilen → je Zeile JSON strikt lesen und prüfen → geprüfte Zeilen in Stapeln an das Ziel (Port `ArchiveSink`: `begin`, `insert`, `commit`, `abort`). Es entsteht keine Datei und kein Klartext auf dem Datenträger.

**Prüfungen je Zeile (jede Verletzung: „beschädigt“):** Manifest zuerst; Abschnitt nur mit dem als nächstes erwarteten Namen (damit sind doppelte, fehlende, vertauschte und unbekannte Abschnitte ausgeschlossen); Zeile nur innerhalb eines Abschnitts und nie in einem der drei reservierten; genau die Schlüssel `type`/`name` (Abschnitt), `type`/`data` (Zeile), `type`/`rows` (Ende); genau die Spalten laut 4.3 mit passendem Typ; `id` je Abschnitt streng aufsteigend; Endzeile erst nach allen Abschnitten der Formatversion, Zähler gleich den gelesenen Zeilen; nach der Endzeile nichts, auch keine Zeile und kein Byte; Ende des Stroms ohne halbe Zeile; Zeile höchstens 16 MiB, nicht leer.

**Wann `commit` kommt:** Erst wenn der entschlüsselte Strom ohne Fehler bis zum letzten Stück geendet hat (Tags aller Stücke, Zähler, Endmarke im Nonce), das gzip-Element samt CRC32 und ISIZE vollständig und ohne Byte danach ist **und** die Endzeile mit den Zählern stimmt. Eine gültige Endzeile allein genügt nicht: Sie kann in einem früheren Stück stehen als das letzte. Bei **jedem** anderen Ausgang (Fehler, Abbruch, Fehler des Ziels) folgt `abort` und nie `commit`. Das Ziel bekommt Zeilen schon vor dem `commit` und muss sie bis dahin verwerfbar halten (Zwischendatenbank).

**Fehlerarten (ohne Inhalte, Zeilenzahlen und Passwort):**

| Lage | Fehler |
|---|---|
| Magic fehlt, Datei zu kurz | keine Archivdatei |
| Formatversion weder 1 noch 2 (auch 0, auch 3) | unbekannte Formatversion |
| Parameter im Kopf ungleich Version 1 und 2 | nicht unterstützte Parameter |
| erstes Stück scheitert, Datei endet nach dem Kopf | falsches Passwort oder beschädigter Anfang (eine Meldung) |
| späteres Stück, Datei zwischen 10 und 35 Byte, gzip, UTF-8, JSON, Zeilen-, Abschnitts-, Spalten-, Typ- oder Zählerverletzung, Endzeile fehlt, Inhalt nach der Endzeile | beschädigt |
| `schema_version` größer als 5 | neueres Archiv (Datenbank unverändert) |
| `schema_version` kleiner als 4 | Schema nicht unterstützt |
| Format und Schema passen nicht zusammen, Format im Manifest ungleich Kopf, Abschnitte nicht die der Formatversion, Angaben außerhalb der Grenzen (4.3) | beschädigt |
| Datei nicht lesbar | Lesefehler |
| Ziel lehnt ab (Fremdschlüssel, CHECK, Trigger: beschädigt; sonst Speicher, E/A: Zielfehler) | beschädigt oder Zielfehler |
| Vom Aufrufer abgebrochen | abgebrochen |

Die Reihenfolge der Wiederherstellung (`value_sections` hinter `computed_values`, Original vor Abschnitten vor `current`) stellt das Ziel her (Zwischenspeicher oder Zwischendatenbank), nicht der Leser.

### 4.6 Wiederherstellung: Zwischendatenbank, Tausch, Voraussetzung

**Wann:** Nur auf **leerer App** oder nach **ausdrücklichem Zurücksetzen** (Bestätigung des Nutzers, Hinweis aus OQ-0050). Leer heißt (`ArchiveRestoreService.isEmpty`): keine Läufe, kein Profilwert, keine bekannten Geräte, keine Einstellung außer den technischen Merkern (`archiveExcludedSettingKeys`, 4.3). Einwilligungen zählen nicht (sie werden ohnehin nicht übernommen), ebenso Tageswerte (`computed_values.day`): Sie sind aus Läufen abgeleitet, ohne Läufe nichts Eigenes, und der Port bietet keine Auflistung; sie werden mit dem Tausch ersetzt. Sonst Fehler „nicht leer“ und nichts geschieht (keine Zwischendatenbank, keine Änderung). Das Zurücksetzen löscht nichts vorab: Die alten Daten verschwinden erst mit dem Tausch. Aufnahme und Neuberechnung laufen nicht parallel (der Aufrufer reicht `serialize`, in der App `RecalculationController.exclusive`).

**Zwischendatenbank** (`DriftArchiveSink`): neue Datei `<aktive Datei>.import` im selben Ordner (gleiches Dateisystem, damit das Umbenennen atomar bleibt), geöffnet mit **demselben Datenbankschlüssel** und derselben Einrichtung wie die aktive (sqlite3mc, `ConnectionSetup`, nie Klartext), Schema 5 frisch (bei Format 1 bleiben die zwei neuen Tabellen leer). Einfügen in Dateireihenfolge, je Stapel eine Transaktion. `computed_values` und `value_sections` kommen zuerst in Hilfstabellen derselben Datei und werden in `commit` je Wert in `id`-Reihenfolge eingefügt (Wert, dann dessen Abschnitte), damit die Trigger (4.2) greifen; `id`s bleiben wie im Archiv. `commit`: Hilfstabellen zusammenführen und löschen, Zeilenzahlen je Tabelle gegen die gelieferten (der Leser hat sie gegen die Endzeile geprüft), `PRAGMA foreign_key_check` leer, `wal_checkpoint(TRUNCATE)` ohne Sperre, Datei schließen. Verletzung einer Beschränkung (CHECK, Trigger, Fremdschlüssel, Eindeutigkeit, Zähler) heißt „beschädigt“, anderes „Zielfehler“. `abort` schließt und löscht die Zwischendatenbank samt `-wal`, `-shm`, `-journal`.

**Tausch** (`DatabaseFiles.replaceWithImport`, erst nach `commit`): aktive Sitzung schließen (SQLite checkpointet beim Schließen der letzten Verbindung; der Nachweis folgt im nächsten Schritt). Dann **fail-closed**: Ist ein aktives `-wal` länger als 0 Byte, bricht der Tausch ab (nichts gelöscht, `swapFailed`, alter Stand; das `-wal` wird beim Wiederöffnen übernommen). Sonst `-wal`/`-shm`/`-journal` der aktiven Datei löschen, die der Zwischendatenbank löschen, **ein** atomares `rename` der Zwischen- auf die aktive Hauptdatei, neu öffnen. Das Verzeichnis wird nicht eigens synchronisiert (Dart bietet keinen Aufruf); nach Stromausfall kann das Umbenennen fehlen, dann gilt der alte Stand. Ein Prozessende an jeder Stelle hinterlässt entweder die alte oder die vollständige neue Hauptdatei, nie eine gemischte oder fehlende. Bei `swapFailed` trägt die Ausnahme die neu geöffnete Sitzung (`ArchiveRestoreException.session`); die alte ist dann geschlossen. Die Einwilligungen sind danach leer (nicht erteilt), der Schlüssel bleibt.

**Oberfläche (D2).** *Daten-Bildschirm:* Hinweis (OQ-0050) immer, bei nicht leerer App zusätzlich die Warnung, dass alle Daten ersetzt werden, und die ausdrückliche Bestätigung (`resetConfirmed`); danach Dateiwahl (`FileHandoff.pickFile`), Passwort einmal (verdeckt, ohne Autofill; ein falsches fragt erneut), Einlesen, Tausch. Danach übernimmt `StorageStartController.adoptSession` die neue Sitzung (bei `swapFailed` die der Ausnahme, bei `reopenFailed` `restart`); die Oberfläche baut sich mit der Sitzung neu auf. Ein offener Lauf sperrt den Import (vorab und innerhalb von `serialize`). Die gewählte Kopie wird immer mit `discardPicked` entsorgt. *Dialog „nicht zu öffnen“ (SEC-0009):* Datei, Passwort, das Archiv vollständig prüfen (`verifyArchive`): Es wird in eine echte Zwischendatenbank (`DriftArchiveSink` auf `<aktive Datei>.import`) mit einem flüchtigen Zufallsschlüssel (`generateStorageKey`, nie im KeyStore, nie gespeichert) gelesen, damit auch alle Beschränkungen der Datenbank greifen wie beim Dienst; die Zwischendatei wird auf jedem Weg gelöscht, die aktive Datei bleibt unberührt; erst dann die Bestätigung zum Löschen der alten Datei, dann `resetStorage(restoreInto)`: Neubeginn, Einspielen in die frische leere Sitzung, bevor die App bereit meldet. Scheitert das Einspielen, bleibt die leere App; scheitert das Öffnen nach dem Tausch, meldet der Start „nicht zu öffnen“ ohne weiteren Neubeginn. `ArchiveRestoreFailure.keyUnavailable`: Schlüssel nicht lesbar, bevor etwas geschah (Sitzung offen, Datenbank unverändert).

**Ersteinrichtung (D3).** Der erste Bildschirm der Ersteinrichtung bietet „Aus Archiv wiederherstellen“ (Gerätewechsel). Dort ist die App leer im Sinne dieses Abschnitts: Die Einrichtung schreibt erst beim Abschluss (`setup.done`, Profil), darum meldet `isEmpty` `true`, es gibt keine Ersetzen-Warnung und kein `resetConfirmed`. Wer schon mit Hinweisen ein Profil gespeichert hat, gilt als nicht leer und sieht die Warnung wie im Daten-Bildschirm. Der Ablauf ist derselbe wie im Daten-Bildschirm (`ArchiveImportAction`): Hinweis (OQ-0050), Dateiwahl, Passwort, Einlesen, Tausch, `discardPicked` auf jedem Weg. Nach dem Tausch trägt der Import die Einstellungen und das Profil des Archivs; fehlt dort `setup.done`, setzt die Oberfläche es auf der neuen Sitzung, bevor sie übernommen wird, damit die Einrichtung nicht erneut erscheint. Das Schreiben geschieht erst **nach** dem Tausch; scheitert es (oder endet der Prozess zwischen Tausch und Schreiben), wird die neue Sitzung trotzdem übernommen bzw. beim Neustart geöffnet: Die Daten sind dann eingespielt, die Einrichtung erscheint aber erneut. Ein erneuter Import zeigt dort die Ersetzen-Warnung (die App ist nicht leer); „Überspringen“ beendet die Einrichtung, es geht nichts verloren. Einwilligungen gelten als nicht erteilt. Bei Fehler oder Abbruch vor dem Tausch bleibt die Einrichtung stehen, geschrieben wurde nichts (die Zwischendatenbank wird vom Dienst verworfen).

**Start:** `StorageStartController._load` löscht vor allem anderen Reste einer Zwischendatenbank (`deleteImport`); sie wird nie weiterverwendet. Schlägt das Löschen fehl, geht der Start weiter. `DatabaseFiles.exist` meint nur die aktive Datenbank: Reste allein lösen keinen Neubeginn und keinen neuen Schlüssel aus.

## 5. Sicherheitsaussagen und Grenzen

- Ohne Passwort ist kein Inhalt lesbar; auch Zeilenzahlen und Abschnitte stehen nur im verschlüsselten Teil. Sichtbar sind Magic, Formatversion, Parameter, Salz und die ungefähre Gesamtgröße.
- Veränderung, Vertauschen, Duplizieren, Abschneiden und Anhängen werden erkannt (Tags, Zähler, Endmarke im Nonce, Kopf als AAD). Nicht erkannt wird, dass jemand mit dem Passwort ein gültiges Archiv neu schreibt.
- Falsches Passwort und beschädigter Anfang sind nicht unterscheidbar; die App nennt beides.
- Es gibt keinen Rettungsweg ohne Passwort (SEC-0011).
- Fehlermeldungen, Logs und Ausnahmen enthalten weder Passwort noch Inhalte noch Zeilenzahlen aus der Datei.
- Das Passwort kann im Speicher bleiben (Dart-Strings sind nicht überschreibbar, ADR-0008).

## 6. Testvektoren

Feste Vektoren (Kopf, Schlüssel, einzelne Stücke, ganze Dateien, Negativfälle) aus einer unabhängigen Umsetzung in Python: Erzeuger `tool/archive_vectors/make_vectors.py`, Dateien in `app/packages/adapters/test/archive/vectors/`. Dieser Text bleibt die Definition. Die Vektoren `archive_small` (Format 1, Schema 4) und `archive_v2` (Format 2, Schema 5, 21 Abschnitte mit `run_feedback` und `manual_trainings`, ein Training genau auf „heute“ 2026-11-20) sowie `neg_v2_training_after_today` (Rahmen gültig, Training am Tag danach: abgelehnt) tragen im `vectors.json` Feld `format` und `today`. Die Zeilen von `archive_small` prüfen Format und Zähler; ihre Werte sind seit aefdf32 DB-gültig (Wertemengen nach 4.2, `original` und `current` je Wert) und werden im Test gegen die echte Datenbank importiert (`archive_restore_test.dart`, Anzahl und `id`s je Tabelle).

## 7. Änderungen am Format

Ein anderes Schema oder andere Parameter bedeuten eine neue Formatversion (Kopf Offset 8). Eine App liest nur ihr bekannte Versionen und lehnt andere ab, ohne Daten zu ändern. Wächst das Datenbankschema (zum Beispiel um Ziele und Pläne), wächst dieser Vertrag mit: neuer `schema_version`, neue Spalten in 4.3, Leseregeln für ältere Schemata.

**Änderungsvermerk WP18 (Formatversion 2):** Format 2 = Schema 5 und die Abschnitte `run_feedback` und `manual_trainings` (4.3), Kopf und Parameter unverändert. Der Leser kennt 1 und 2; Format 1 wird ohne die neuen Abschnitte eingespielt (die Tabellen bleiben leer). Der Schreiber erzeugt nur Format 2. Die Testvektoren in Abschnitt 6 enthalten Format 1 (belegt, dass es lesbar bleibt) und Format 2; `neg_version_2` ist darum kein Negativvektor mehr, der Test setzt dort die Formatversion 3.
