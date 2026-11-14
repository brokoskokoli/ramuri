# Vertrag: Messpaare-CSV (Kamera-Morgenmessung gegen Gurt-RR)

**Status:** Vorschlag des Pakets (WP33 Teil E, FR-0215). Die Eckpunkte hat der Maintainer entschieden (K62 F4: unverschlüsselte CSV über Teilen, nur im Entwicklermodus, mit Warnhinweis vor dem Teilen wie bei der Zusatzmetriken-CSV, K57; Übergabe aus `cacheDir/exports` wie K29); die Spalten und Einzelregeln sind Vorschläge und umkehrbar, solange keine Datei der Formatversion 1 ausgeliefert ist.
**Anforderungen:** FR-0215, FR-0201, SEC-0003.
**Code:** `app/packages/core/lib/src/export/morning_pairs_csv.dart`; Einstieg `app/lib/features/settings/morning_pairs_section.dart` (Seite „Über“, Abschnitt Entwickler).

Zweck: Der Maintainer vergleicht für die Validierung (K61) die Kamera-Werte einer Morgenmessung mit der Gurt-RR derselben Zeit. Die Datei liefert beide Seiten roh; **die App berechnet und zeigt weder eine Gurt-RMSSD noch Differenzen** (keine Zwischenauswertung). Das Dokument beschreibt das Format so, dass es ohne den Dart-Code gelesen werden kann.

## 1. Überblick

Eine Datei `running-morgenpaare-JJJJMMTT.csv` (MIME `text/csv`, Datum = heutiger UTC-Tag) enthält alle gespeicherten Morgenmessungen, auch ohne Gurt und auch unbrauchbare (K68, mit `usable` = `0` markiert; sie zählen in keiner Auswertung der App). Je Morgen stehen mehrere Zeilen, eine je Wert (lange Form mit Typspalte). Die Datei ist ein Export, kein Archiv (Reimport: [archive.md](archive.md)).

## 2. Kodierung und Aufbau (RFC 4180)

Wie [metrics-csv.md](metrics-csv.md) Abschnitt 2: UTF-8 **ohne** Byte-Order-Mark, Zeilenende CRLF auch nach der letzten Zeile, Trennzeichen Komma, Felder mit Komma, Anführungszeichen, CR oder LF in Anführungszeichen (`"` verdoppelt), Kopfzeile immer vorhanden, **Dezimaltrenner immer der Punkt**, **nie Exponentschreibweise** (sehr kleine Werte in fester Form, etwa `0.0000001`), keine Einheit im Wertfeld. Zeitpunkte sind ISO 8601 in UTC mit `Z`. Textfelder (`device_manufacturer`, `device_model`) werden unverändert geschrieben; ein Leser in einer Tabellenkalkulation behandelt Felder, die mit `=`, `+`, `-` oder `@` beginnen, selbst als Text.

## 3. Formatversion und Spalten

Kopfzeile (Formatversion 2, genau diese Namen und Reihenfolge); `format_version` steht in jeder Zeile, ein Leser lehnt eine unbekannte Version ab:

```
format_version,morning_id,row_type,key,seq,sub,time,value,unit
```

| Spalte | Inhalt |
|---|---|
| `format_version` | `2` (Version 1: ohne Fenster, Stufe unbrauchbar und Rohsignal; nie ausgeliefert) |
| `morning_id` | Kennung der Morgenmessung im Speicher (ganze Zahl); gleich für alle Zeilen eines Morgens |
| `row_type` | `meta`, `camera`, `camera_ibi`, `belt_rr` oder `raw_frame` |
| `key` | Name des Werts (Abschnitt 4) |
| `seq` | laufende Nummer ab 1: bei `camera_ibi` das Intervall, bei `belt_rr` das BLE-Paket des Morgens, bei `raw_frame` das Bild; sonst leer |
| `sub` | bei `belt_rr` die Position des Werts im Paket ab 1; sonst leer |
| `time` | UTC-Zeitpunkt: bei `meta`/`measured_at` der Beginn der Aufnahme, bei `belt_rr` die **Empfangszeit des Pakets** (alle Werte eines Pakets tragen dieselbe); sonst leer |
| `value` | Wert (Punkt als Dezimaltrenner) oder Text; **leer = nicht verfügbar bzw. ungültig**, nie `0` und nie `NaN` (FR-0068) |
| `unit` | Einheit: `s`, `bpm`, `ms`, `ns`, `1/1024 s`; leer bei Text- und Kennzahlen |

## 4. Zeilenarten je Morgen (in dieser Reihenfolge)

**`meta`** (je eine Zeile, `value` wie angegeben): `measured_at` (nur `time`), `utc_offset` (Versatz des Ortes zu UTC in ganzen Sekunden, Einheit `s`), `posture` (`lying`/`sitting`), `device_manufacturer`, `device_model` (Telefon, keine Seriennummer), `method`, `method_version`, `quality` (`good`/`limited`/`unusable`), `usable` (`1`/`0`, `0` genau bei `unusable`), `quality_reason` (nur bei `unusable`, sonst leer: `insufficientData`, `invalidInput`, `weakSignal`, `tooManyDisturbances`, `frameGap` u. a. Namen der Grund-Aufzählung der App; leer auch, wenn der Grund fehlt), `window_start` und `window_end` (`s`, Anfang und Ende des ausgewerteten Fensters in Sekunden seit Aufnahmebeginn, Zeitachse des `t` der `raw_frame`-Zeilen; leer = Verfahren ohne Fenstersuche oder keins gefunden), `rest_skipped_after` (`s`, Sekunden nach Beginn der Ruhephase, nach denen sie übersprungen wurde; leer = nicht übersprungen), `before_validation`, `outside_window` (`1`/`0`), `sleep_band` (`under5`, `from5to6`, `from6to7`, `from7to8`, `over8`; leer = nicht angegeben), `belt_packets` (Anzahl der gespeicherten Gurt-RR-Pakete dieses Morgens, `0` ohne Gurt), `raw_frames` (Anzahl der `raw_frame`-Zeilen, `0` ohne gespeichertes Rohsignal).

Nur mit gespeichertem Rohsignal (K70, K72) folgen weitere `meta`-Zeilen mit den Kamera-Angaben, leer = von der Kamera nicht geliefert: `exposure_time` (`ns`), `iso`, `timestamp_source` (`unknown`/`realtime`), `rolling_shutter_skew` (`ns`), `torch_strength` (Stufe der Kamera-API), `frame_gap_count`, `frame_gap_total` (`s`), `saturated_fraction` (0 bis 1).

**`camera`** (je eine Zeile): `resting_hr` (`bpm`, eine Nachkommastelle, leer bei `unusable`), `rmssd` (`ms`, leer wenn nicht verfügbar), `timing_noise` (`ms`, leer wenn nicht verfügbar).

**`camera_ibi`** (`key` = `ibi`, eine Zeile je Schlagabstand in zeitlicher Reihenfolge, `seq` ab 1, `ms` mit drei Nachkommastellen): **alle** Schlagabstände des Messfensters. **Markierung ungültig:** Ein gestörtes Intervall (im Speicher NaN, siehe [archive.md](archive.md) Morgenmessung) steht als Zeile mit **leerem** `value`; seine Position bleibt erhalten. Die Kamera-RMSSD ergibt sich aus den Differenzen **benachbarter** gültiger Werte, ein leeres Feld trennt Paare.

**`belt_rr`** (`key` = `rr`, eine Zeile je RR-Wert, nach Empfangszeit und Paketnummer, dann Position): die **rohen** RR-Werte der aktiven Pulsquelle von Beginn der Ruhephase bis zum Ende der Messung, nur wenn die Messung im Entwicklermodus lief und ein Gurt mit RR verbunden war. `value` ist die ganze Zahl in Einheiten von 1/1024 s (Millisekunden = Wert × 1000 / 1024), unverändert vom Gurt, ohne Artefaktfilter. Die Zeit des Werts ist die Empfangszeit seines Pakets (nicht die Schlagzeit): ein Paket enthält mehrere Schläge. Das Quellgerät steht nicht in der Datei; aufgenommen werden nur Pakete des **ersten** Quellgeräts (die Kennung des ersten Geräts dient zum Filtern und wird nicht exportiert), Pakete eines anderen Geräts nach einem Wechsel der aktiven Quelle (Failover) fehlen. Nach „Noch einmal messen“ (verworfene Messung) läuft das Fenster **ohne Lücke** weiter, von Beginn der Ruhephase bis zum Ende der Wiederholung.

**`raw_frame`** (`key` = `frame`, eine Zeile je Kamera-Bild in zeitlicher Reihenfolge, `seq` ab 1; nur mit gespeichertem Rohsignal, nur Entwicklermodus, K70): die Bildstatistik, keine Pixel. `value` enthält **genau 35 Zahlen, mit Semikolon getrennt, ohne Leerzeichen**, in dieser Reihenfolge: `t` (Sekunden seit Aufnahmebeginn), `r`, `g` (Mittel Rot und Grün), `r16[0]` bis `r16[15]`, `g16[0]` bis `g16[15]` (16 Teilbereiche, zeilenweise); `time` und `unit` leer. Das Feld braucht kein Anführungszeichen. **Verlustfrei:** Jede Zahl ist die kürzeste Dezimalform, die beim Lesen mit `float()`/`double.parse` wieder genau denselben 64-Bit-Wert ergibt (typisch 15 bis 17 Stellen), nie mit Exponent; Beträge unter 1e-6 stehen mit 20 Nachkommastellen (Rundung höchstens 5e-21, für Pixelmittel ohne Bedeutung). Ein Skript liest die Zeilen mit `row_type = raw_frame` und erhält dieselben Bilder wie im Speicher; die Auswertung auf diesen Bildern ergibt dieselben Schlagabstände und dasselbe Fenster wie in der App. Größe: etwa 650 Byte je Bild, bei 120 s und 30 Bildern/s (3600 Bilder) rund 2,3 MB.

## 5. Sortierung

Die Morgen aufsteigend nach `measured_at`, dann `morning_id`; innerhalb eines Morgens die Zeilenarten wie in Abschnitt 4 (`raw_frame` zuletzt). Die Reihenfolge ist wiederholbar.

## 6. Zeitfenster und Abgleich

Die Gurt-Pakete eines Morgens beginnen mit der Ruhephase und enden mit der Messung (nach „Noch einmal messen“ lückenlos bis zum Ende der Wiederholung, K65); sie stammen nur vom ersten Quellgerät der Messung, dessen Kennung nicht in der Datei steht; `measured_at` ist der Beginn der 60-s-Aufnahme, also etwa zwei Minuten nach dem ersten Paket. Kamera- und Gurtdaten liegen so im selben Zeitfenster; ein Abgleich der Uhren beider Quellen am Gerät ist Sache der Auswertung außerhalb der App.

## 7. Datenschutz

Die Datei ist unverschlüsselt und enthält Gesundheitsdaten. Sie wird nur auf Aktion des Nutzers über Teilen übergeben, nach einem Warnhinweis (K62 F4, FR-0201); der Abschnitt Entwickler mit dem Knopf erscheint nur im Entwicklermodus. Meldungen und Logs der App nennen weder Inhalt noch Pfad.
