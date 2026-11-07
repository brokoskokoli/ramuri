# Vertrag: Verschlüsseltes Archiv (Gesamtexport)

**Status:** Vorschlag des Pakets (WP12 Teil A, OQ-0032). Formatversion 1 vom Maintainer bestätigt (2026-11-07); Schema der Datenbank: Version 4. Die Zeilen- und Abschnittsregeln (Inhalt unter der Verschlüsselung) sind Vorschläge des Pakets und umkehrbar, solange kein Archiv der Version 1 ausgeliefert ist.
**Anforderungen:** FR-0192, FR-0198, SEC-0011, ACC-15; Entscheidungen in [ADR-0008](../architecture/adr/ADR-0008-verschluesselung-des-archivs.md) (Verfahren, Parameter), ADR-0004 Punkt 6 (Kennungen).
**Code:** `app/packages/core/lib/src/archive/` (Kopf und Rahmen), Port `app/packages/core/lib/ports/archive_cipher.dart`, Adapter `app/packages/adapters/lib/src/archive/`. Export und Import der Datenbank folgen in späteren Teilen von WP12; dieser Vertrag legt sie fest.

Das Dokument beschreibt das Format so, dass es ohne den Dart-Code unabhängig umgesetzt werden kann. „MUSS“, „DARF NICHT“ und „KANN“ sind im Sinn von RFC 2119 gemeint. Alle Zahlen im Kopf sind unsigned und Big-Endian.

## 1. Überblick

```
Datei     = Kopf (36 Byte) Stück{1..n}
Stück     = ChaCha20-Poly1305-Chiffretext (Klartextlänge + 16 Byte Tag)
Klartext  = gzip( JSON Lines )                     # Abschnitt 4 und 5
```

Die Datei hat keine Fußzeile und kein Längenfeld. Das Ende wird durch das mit „letzt“ markierte Stück bewiesen (Abschnitt 3).

## 2. Kopf (Formatversion 1, genau 36 Byte)

| Offset | Länge | Feld | Wert in Version 1 |
|---:|---:|---|---|
| 0 | 8 | Magic | ASCII `RUNARCHV` = `52 55 4E 41 52 43 48 56` |
| 8 | 2 | Formatversion (uint16 BE) | `0x0001` |
| 10 | 4 | Argon2-Speicher in KiB (uint32 BE) | `65536` (`00 01 00 00`), also 64 MiB |
| 14 | 4 | Argon2-Durchläufe t (uint32 BE) | `3` |
| 18 | 1 | Argon2-Parallelität p (uint8) | `1` |
| 19 | 1 | Länge des abgeleiteten Schlüssels (uint8) | `32` |
| 20 | 16 | Salz | 16 zufällige Byte je Archiv (kryptografisch sicherer Zufall) |

Die Stücke beginnen bei Offset 36. Das gesamte Kopf-Byte-Feld (Offset 0 bis 35, unverändert) ist die zusätzlich authentifizierte Datei (AAD) jedes Stücks.

**Leser-Regeln (in dieser Reihenfolge, jede scheitert, ohne dass etwas gelesen oder geändert wird, das über die Datei hinausgeht):**

1. Weniger als 8 Byte oder Magic ungleich `RUNARCHV`: **keine Archivdatei**.
2. Weniger als 10 Byte oder Formatversion ungleich 1: **unbekannte Formatversion** (auch eine kleinere, auch 0). Eine neuere App-Version liest nur die ihr bekannten Versionen; eine ältere App lehnt ein neueres Archiv ab und ändert nichts (Entscheidung C in ADR-0008).
3. Weniger als 36 Byte: **beschädigt**.
4. Speicher, Durchläufe, Parallelität oder Schlüssellänge ungleich den Werten der Tabelle (und damit der Formatversion): **nicht unterstützte Parameter**. Das geschieht **vor** jeder Schlüsselableitung; ein Kopf darf keine Speicheranforderung auslösen, die er nicht selbst als bekannte Konstante trägt (ADR-0008 Punkt 3). Das Salz wird nicht geprüft (jeder Wert ist zulässig).
5. Erst danach wird der Schlüssel abgeleitet und die Stücke werden gelesen.

Stärkere Parameter oder ein anderes Verfahren erscheinen nur als neue Formatversion.

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

Das Ende der Datei beendet die Prüfung: Nach dem letzten gültigen Stück gibt es keine weiteren Byte.

**Wichtig für Verbraucher des Stroms:** Frühere Stücke können Klartext liefern, bevor das letzte Stück geprüft ist. Ein Leser MUSS das Ergebnis verwerfen, wenn der Strom nicht fehlerfrei bis zum letzten Stück endet (Zwischendatenbank, Tausch erst danach; ADR-0008 Punkt 5).

## 4. Inhalt unter der Verschlüsselung

Der entschlüsselte Klartext ist **ein** gzip-Element (RFC 1952, ein Member, DEFLATE; Stufe und Kopffelder frei, `FNAME`/`FEXTRA`/`FCOMMENT` ungenutzt). Der Leser MUSS CRC32 und ISIZE (mod 2^32) prüfen und DARF NICHT Byte nach dem Element dulden. Die Dekompression erfolgt als Strom; sie darf nicht den ganzen Inhalt im Speicher halten.

Dekomprimiert ist es ein JSON-Lines-Text (UTF-8 ohne BOM): Jede Zeile ist **ein** JSON-Objekt (RFC 8259) auf einer Zeile, Zeilentrenner genau `\n` (auch nach der letzten Zeile), keine leeren Zeilen. Der Schreiber erzeugt kompaktes JSON ohne Leerraum; der Leser liest jedes gültige JSON. Eine Zeile ist höchstens 16 MiB lang (Leser-Grenze gegen Speicherbomben). Ganze Zahlen sind 64-Bit-Ganzzahlen und MÜSSEN verlustfrei gelesen werden (Mikrosekunden seit Epoch passen nicht in jede Gleitkommadarstellung). Objekte dürfen keinen Schlüssel doppelt tragen.

### 4.1 Zeilenfolge

1. **Manifest** (genau eine, erste Zeile): `{"type":"manifest","format":1,"schema_version":4,"created_at_us":<int>}`. `format` ist die Formatversion des Kopfes (gleich), `schema_version` das Datenbankschema der Zeilen, `created_at_us` der Erstellzeitpunkt in Mikrosekunden seit Epoch (UTC). Der Leser lehnt `format` ungleich 1 und `schema_version` ungleich 4 ab (ein größeres Schema: „neueres Archiv“, ohne Änderung; ein kleineres ist nicht vorgesehen, Format 1 beginnt mit Schema 4). Unbekannte weitere Schlüssel im Manifest sind ein Fehler.
2. **Abschnitte** in der festen Reihenfolge der Tabelle in 4.3, **alle** 19 Abschnitte, auch leere. Jeder Abschnitt beginnt mit `{"type":"section","name":"<Abschnittsname>"}`, darauf folgen seine Zeilen `{"type":"row","data":{<Spalte>:<Wert>,...}}`. Eine Zeile gehört zum zuletzt begonnenen Abschnitt.
3. **Ende** (genau eine, letzte Zeile): `{"type":"end","rows":{"runs":<n>,"laps":<n>,...}}` mit der Zeilenzahl **jedes** der 19 Abschnitte (auch 0), in der Reihenfolge der Abschnitte. Der Leser zählt mit und lehnt jede Abweichung ab.

Abweichungen sind Fehler: fehlender oder doppelter Abschnitt, falsche Reihenfolge, Zeile außerhalb eines Abschnitts, Zeile nach der Endzeile, fehlende Endzeile, unbekannter `type`, unbekannter Abschnittsname.

### 4.2 Zeilen (`data`)

- `data` enthält **genau** die Spalten der Tabelle laut 4.3 (in Schemareihenfolge geschrieben, der Leser darf jede Reihenfolge lesen), **jede** Spalte, `NULL` als `null`. Ein fehlender oder zusätzlicher Schlüssel ist ein Fehler.
- INTEGER: JSON-Ganzzahl (ohne Bruch und Exponent). REAL: endliche JSON-Zahl (der Schreiber bricht den Export ab, wenn ein Wert nicht endlich ist); eine Ganzzahl-Schreibweise ist für REAL zulässig. TEXT: JSON-String (gültiges Unicode, keine einzelnen Surrogate). BOOLEAN-Spalten sind SQLite-Ganzzahlen: `0` oder `1`.
- Spalten, die JSON-Text enthalten (`rated_sections.gps_gaps`, `computed_values.sources`, `value_sections.reasons`), werden als **String** mit dem gespeicherten Text übertragen, nicht als verschachteltes JSON; der Leser setzt sie unverändert ein.
- **Kennungen bleiben erhalten:** Alle `id`-Spalten und Verweise (`run_id`, `computed_value_id`, `raw_id`) tragen die Werte der Quelldatenbank. Der Leser stellt die Zeilen unter diesen Kennungen wieder her (die Verweise in `preprocessed_samples.raw_id` hängen daran) und lässt die Datenbank Fremdschlüssel, CHECKs und Trigger prüfen; jede Verletzung lehnt das ganze Archiv ab.
- **Zeilenreihenfolge:** innerhalb eines Abschnitts aufsteigend nach dem Primärschlüssel (`id`, bei `settings` nach `key`). Die Datenbank-Trigger verlangen beim Wiederherstellen: erst `runs`, dann deren Rohdaten (nur anhängen); bei Laufwerten je `computed_values`-Zeile `original`, dann dessen `value_sections`, dann `current`, jeweils in aufsteigender `id` (Trigger `value_sections_original_no_late_insert` prüft, dass die Zeile des Werts die zuletzt vergebene ist). Weil `value_sections` hinter `computed_values` steht, MUSS der Leser dafür zwischenspeichern oder die Reihenfolge herstellen; der Zwischenspeicher darf nicht der Klartext auf dem Datenträger sein (ADR-0008 Punkt 5).
- **Unbekannte `value_key`s** (und unbekannte `method`-Namen, `unavailable_reason`-Codes, `source`-Namen) werden unverändert durchgereicht: Der Leser prüft sie nicht gegen eine Liste. Ein Code, den die App beim späteren Lesen nicht versteht, ist dort ein Datenfehler wie im bisherigen Schema.
- Laufwerte (`computed_values`) tragen **beide** Rollen (`original`, `current`) mit `unavailable_reason`, Basis (`hr_max_bpm`, `hr_rest_bpm`, `hr_max_is_estimated`), Quellen, Versionen und Qualität. Zonenzeiten und `trimp_run` sind Laufwerte und stehen hier; sie sind nicht aus den Rohdaten rekonstruierbar.

### 4.3 Abschnitte und Spalten (Schema 4)

Quelle der Spalten: `app/packages/adapters/lib/src/storage/schema.drift` (Schemaversion 4). Typen: I = INTEGER, R = REAL, T = TEXT, B = BOOLEAN (0/1). `?` = darf `null` sein.

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
| 17 | `goals` | (leer, siehe unten) |
| 18 | `plans` | (leer, siehe unten) |
| 19 | `active_warning` | (leer, siehe unten) |

Nicht im Archiv: die Tabellen `storage_meta` (technisch), `consents` (Einwilligungen, SEC-0011) sowie Datenbankschlüssel und Zugangsdaten (liegen nie in der Datenbank). Nach dem Import sind Einwilligungen nicht erteilt.

**Leere Abschnitte (17 bis 19):** `goals`, `plans`, `active_warning` sind für spätere Phasen vorgesehen (FR-0192, L13). In Version 1 mit Schema 4 haben sie **0 Zeilen**; der Leser lehnt einen Abschnitt mit Zeilen ab, weil er sie nicht speichern kann (nicht stillschweigend verwerfen). Ihre Spalten legt das Schema fest, das sie einführt (mit neuem `schema_version`, nötigenfalls neuer Formatversion).

**Technische Merker in `settings`:** Der Schreiber lässt die Schlüssel `values.calculationPending`, `values.refreshPending` und `recalculation.pending` weg. Sie sind Merker für unterbrochene Hintergrundarbeit oder ein offenes Angebot der Quellinstallation (`core/lib/src/recalculation/`) und gehören nicht in einen Wiederherstellungsstand; sie würden nach dem Import auf Zustände zeigen, die dort nicht gelten. Alle anderen Schlüssel (auch unbekannte) werden übernommen. Der Leser nimmt jeden Schlüssel an, den er findet. (Die Liste ist an den Quelltext gebunden: Kommt ein neuer technischer Merker hinzu, ist sie hier und im Schreiber zu ergänzen; der Schreiber-Teil von WP12 soll sie per Test gegen die Konstanten prüfen.)

### 4.4 Beispiel (Klartext, bevor gzip angewendet wird; Werte synthetisch, gekürzt)

```
{"type":"manifest","format":1,"schema_version":4,"created_at_us":1793000000000000}
{"type":"section","name":"runs"}
{"type":"row","data":{"id":1,"state":"finished","started_at_us":1792000000000000,"ended_at_us":1792000600000000,"ended_utc_offset_s":3600}}
{"type":"section","name":"laps"}
...
{"type":"section","name":"goals"}
{"type":"section","name":"plans"}
{"type":"section","name":"active_warning"}
{"type":"end","rows":{"runs":1,"laps":0,...,"goals":0,"plans":0,"active_warning":0}}
```

## 5. Sicherheitsaussagen und Grenzen

- Ohne Passwort ist kein Inhalt lesbar; auch Zeilenzahlen und Abschnitte stehen nur im verschlüsselten Teil. Sichtbar sind Magic, Formatversion, Parameter, Salz und die ungefähre Gesamtgröße.
- Veränderung, Vertauschen, Duplizieren, Abschneiden und Anhängen werden erkannt (Tags, Zähler, Endmarke im Nonce, Kopf als AAD). Nicht erkannt wird, dass jemand mit dem Passwort ein gültiges Archiv neu schreibt.
- Falsches Passwort und beschädigter Anfang sind nicht unterscheidbar; die App nennt beides.
- Es gibt keinen Rettungsweg ohne Passwort (SEC-0011).
- Fehlermeldungen, Logs und Ausnahmen enthalten weder Passwort noch Inhalte noch Zeilenzahlen aus der Datei.
- Das Passwort kann im Speicher bleiben (Dart-Strings sind nicht überschreibbar, ADR-0008).

## 6. Testvektoren

Feste Vektoren (Kopf, Schlüssel, einzelne Stücke, ganze Dateien) aus einer unabhängigen Umsetzung folgen in einem späteren Teil von WP12 und werden hier verlinkt. Bis dahin ist dieser Text die Definition.

## 7. Änderungen am Format

Ein anderes Schema oder andere Parameter bedeuten eine neue Formatversion (Kopf Offset 8). Eine App liest nur ihr bekannte Versionen und lehnt andere ab, ohne Daten zu ändern. Wächst das Datenbankschema (zum Beispiel um Ziele und Pläne), wächst dieser Vertrag mit: neuer `schema_version`, neue Spalten in 4.3, Leseregeln für ältere Schemata.
