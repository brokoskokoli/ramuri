# Vertrag: Messpaare-CSV (Kamera-Morgenmessung gegen Gurt-RR)

**Status:** Vorschlag des Pakets (WP33 Teil E, FR-0215). Die Eckpunkte hat der Maintainer entschieden (K62 F4: unverschlüsselte CSV über Teilen, nur im Entwicklermodus, mit Warnhinweis vor dem Teilen wie bei der Zusatzmetriken-CSV, K57; Übergabe aus `cacheDir/exports` wie K29); die Spalten und Einzelregeln sind Vorschläge und umkehrbar, solange keine Datei der Formatversion 1 ausgeliefert ist.
**Anforderungen:** FR-0215, FR-0201, SEC-0003.
**Code:** `app/packages/core/lib/src/export/morning_pairs_csv.dart`; Einstieg `app/lib/features/settings/morning_pairs_section.dart` (Seite „Über“, Abschnitt Entwickler).

Zweck: Der Maintainer vergleicht für die Validierung (K61) die Kamera-Werte einer Morgenmessung mit der Gurt-RR derselben Zeit. Die Datei liefert beide Seiten roh; **die App berechnet und zeigt weder eine Gurt-RMSSD noch Differenzen** (keine Zwischenauswertung). Das Dokument beschreibt das Format so, dass es ohne den Dart-Code gelesen werden kann.

## 1. Überblick

Eine Datei `running-morgenpaare-JJJJMMTT.csv` (MIME `text/csv`, Datum = heutiger UTC-Tag) enthält alle gespeicherten Morgenmessungen, auch ohne Gurt. Je Morgen stehen mehrere Zeilen, eine je Wert (lange Form mit Typspalte). Die Datei ist ein Export, kein Archiv (Reimport: [archive.md](archive.md)).

## 2. Kodierung und Aufbau (RFC 4180)

Wie [metrics-csv.md](metrics-csv.md) Abschnitt 2: UTF-8 **ohne** Byte-Order-Mark, Zeilenende CRLF auch nach der letzten Zeile, Trennzeichen Komma, Felder mit Komma, Anführungszeichen, CR oder LF in Anführungszeichen (`"` verdoppelt), Kopfzeile immer vorhanden, **Dezimaltrenner immer der Punkt**, **nie Exponentschreibweise** (sehr kleine Werte in fester Form, etwa `0.0000001`), keine Einheit im Wertfeld. Zeitpunkte sind ISO 8601 in UTC mit `Z`. Textfelder (`device_manufacturer`, `device_model`) werden unverändert geschrieben; ein Leser in einer Tabellenkalkulation behandelt Felder, die mit `=`, `+`, `-` oder `@` beginnen, selbst als Text.

## 3. Formatversion und Spalten

Kopfzeile (Formatversion 1, genau diese Namen und Reihenfolge); `format_version` steht in jeder Zeile, ein Leser lehnt eine unbekannte Version ab:

```
format_version,morning_id,row_type,key,seq,sub,time,value,unit
```

| Spalte | Inhalt |
|---|---|
| `format_version` | `1` |
| `morning_id` | Kennung der Morgenmessung im Speicher (ganze Zahl); gleich für alle Zeilen eines Morgens |
| `row_type` | `meta`, `camera`, `camera_ibi` oder `belt_rr` |
| `key` | Name des Werts (Abschnitt 4) |
| `seq` | laufende Nummer ab 1: bei `camera_ibi` das Intervall, bei `belt_rr` das BLE-Paket des Morgens; sonst leer |
| `sub` | bei `belt_rr` die Position des Werts im Paket ab 1; sonst leer |
| `time` | UTC-Zeitpunkt: bei `meta`/`measured_at` der Beginn der Aufnahme, bei `belt_rr` die **Empfangszeit des Pakets** (alle Werte eines Pakets tragen dieselbe); sonst leer |
| `value` | Wert (Punkt als Dezimaltrenner) oder Text; **leer = nicht verfügbar bzw. ungültig**, nie `0` und nie `NaN` (FR-0068) |
| `unit` | Einheit: `s`, `bpm`, `ms`, `1/1024 s`; leer bei Text- und Kennzahlen |

## 4. Zeilenarten je Morgen (in dieser Reihenfolge)

**`meta`** (je eine Zeile, `value` wie angegeben): `measured_at` (nur `time`), `utc_offset` (Versatz des Ortes zu UTC in ganzen Sekunden, Einheit `s`), `posture` (`lying`/`sitting`), `device_manufacturer`, `device_model` (Telefon, keine Seriennummer), `method`, `method_version`, `quality` (`good`/`limited`), `before_validation`, `outside_window` (`1`/`0`), `sleep_band` (`under5`, `from5to6`, `from6to7`, `from7to8`, `over8`; leer = nicht angegeben), `belt_packets` (Anzahl der gespeicherten Gurt-RR-Pakete dieses Morgens, `0` ohne Gurt).

**`camera`** (je eine Zeile): `resting_hr` (`bpm`, eine Nachkommastelle), `rmssd` (`ms`, leer wenn nicht verfügbar), `timing_noise` (`ms`, leer wenn nicht verfügbar).

**`camera_ibi`** (`key` = `ibi`, eine Zeile je Schlagabstand in zeitlicher Reihenfolge, `seq` ab 1, `ms` mit drei Nachkommastellen): **alle** Schlagabstände des Messfensters. **Markierung ungültig:** Ein gestörtes Intervall (im Speicher NaN, siehe [archive.md](archive.md) Morgenmessung) steht als Zeile mit **leerem** `value`; seine Position bleibt erhalten. Die Kamera-RMSSD ergibt sich aus den Differenzen **benachbarter** gültiger Werte, ein leeres Feld trennt Paare.

**`belt_rr`** (`key` = `rr`, eine Zeile je RR-Wert, nach Empfangszeit und Paketnummer, dann Position): die **rohen** RR-Werte der aktiven Pulsquelle von Beginn der Ruhephase bis zum Ende der Messung, nur wenn die Messung im Entwicklermodus lief und ein Gurt mit RR verbunden war. `value` ist die ganze Zahl in Einheiten von 1/1024 s (Millisekunden = Wert × 1000 / 1024), unverändert vom Gurt, ohne Artefaktfilter. Die Zeit des Werts ist die Empfangszeit seines Pakets (nicht die Schlagzeit): ein Paket enthält mehrere Schläge. Das Quellgerät steht nicht in der Datei; aufgenommen werden nur Pakete des **ersten** Quellgeräts (die Kennung des ersten Geräts dient zum Filtern und wird nicht exportiert), Pakete eines anderen Geräts nach einem Wechsel der aktiven Quelle (Failover) fehlen. Nach „Noch einmal messen“ (verworfene Messung) läuft das Fenster **ohne Lücke** weiter, von Beginn der Ruhephase bis zum Ende der Wiederholung.

## 5. Sortierung

Die Morgen aufsteigend nach `measured_at`, dann `morning_id`; innerhalb eines Morgens die Zeilenarten wie in Abschnitt 4. Die Reihenfolge ist wiederholbar.

## 6. Zeitfenster und Abgleich

Die Gurt-Pakete eines Morgens beginnen mit der Ruhephase und enden mit der Messung; `measured_at` ist der Beginn der 60-s-Aufnahme, also etwa zwei Minuten nach dem ersten Paket. Kamera- und Gurtdaten liegen so im selben Zeitfenster; ein Abgleich der Uhren beider Quellen am Gerät ist Sache der Auswertung außerhalb der App.

## 7. Datenschutz

Die Datei ist unverschlüsselt und enthält Gesundheitsdaten. Sie wird nur auf Aktion des Nutzers über Teilen übergeben, nach einem Warnhinweis (K62 F4, FR-0201); der Abschnitt Entwickler mit dem Knopf erscheint nur im Entwicklermodus. Meldungen und Logs der App nennen weder Inhalt noch Pfad.
