# Vertrag: Zusatzmetriken-CSV

**Status:** Vorschlag des Pakets (WP25 Teil D, FR-0184, OQ-0032). Die Eckpunkte (eine Datei über alle Läufe, alle berechneten Werte samt Stufe, Methode und Version, Punkt als Dezimaltrenner, UTF-8, unter „Daten“) hat der Maintainer bestätigt (K57); die Spalten und Einzelregeln sind Vorschläge und umkehrbar, solange keine Datei der Formatversion 1 ausgeliefert ist.
**Anforderungen:** FR-0184, FR-0053, FR-0201, SEC-0003.
**Code:** `app/packages/core/lib/src/export/metrics_csv.dart`; Einstieg `app/lib/features/export/metrics_csv_action.dart` (Bildschirm „Daten“).

Das Dokument beschreibt das Format so, dass es ohne den Dart-Code umgesetzt oder gelesen werden kann.

## 1. Überblick

Eine Datei `running-metriken-JJJJMMTT.csv` (MIME `text/csv`) enthält je berechnetem Wert eines Laufs und je Rolle (`original`, `current`; ADR-0004 Punkt 4) genau eine Zeile. Tageswerte (etwa ATL/CTL) gehören nicht dazu, nur Werte, die zu einem Lauf gehören. Die Datei ist ein Export, kein Archiv: Es gibt keinen Reimport (dafür gilt [archive.md](archive.md)).

## 2. Kodierung und Aufbau (RFC 4180)

- UTF-8, **ohne** Byte-Order-Mark.
- Zeilenende CRLF (`\r\n`), auch nach der letzten Zeile.
- Trennzeichen Komma. Ein Feld wird in Anführungszeichen gesetzt, wenn es Komma, Anführungszeichen, CR oder LF enthält; ein Anführungszeichen im Feld wird verdoppelt (`""`). Andere Felder stehen ohne Anführungszeichen.
- Die erste Zeile ist die Kopfzeile aus Abschnitt 3. Sie steht immer, auch ohne Daten (dann besteht die Datei nur aus ihr).
- **Dezimaltrenner ist immer der Punkt**, unabhängig von der Sprache und Region des Geräts. Kein Tausendertrenner, keine Einheit im Feld.
- Zahlen sind die kürzeste Darstellung, die den Wert wieder genau ergibt (Dart `double.toString`, z. B. `52.3`, `0.0`; sehr kleine oder große Werte KÖNNEN die Exponentenschreibweise `1e-7` tragen).
- Zeitpunkte sind ISO 8601 in UTC mit `Z` (z. B. `2030-01-01T08:00:00.000Z`).
- Die Felder werden unverändert geschrieben; ein Leser, der die Datei in einer Tabellenkalkulation öffnet, muss Felder, die mit `=`, `+`, `-` oder `@` beginnen (Freitext in `sources`), selbst als Text behandeln.

## 3. Formatversion und Spalten

Die Formatversion steht in der ersten Spalte `format_version` jeder Zeile (Formatversion 1: `1`). Eine neue Version ändert die Spalten und erhöht diese Zahl; ein Leser lehnt eine ihm unbekannte Version ab. Eine Datei ohne Daten trägt nur die Kopfzeile, deren Spaltenfolge die Version festlegt.

Kopfzeile (Formatversion 1, genau diese Namen und Reihenfolge):

```
format_version,run_id,run_started_at,run_mode,role,value_key,value,unit,quality,unavailable_reason,method,method_version,parameter_version,computed_at,data_from,data_to,measurement_count,sources
```

| Spalte | Inhalt | Einheit / Wertebereich | Leer, wenn |
|---|---|---|---|
| `format_version` | Formatversion | ganze Zahl, `1` | nie |
| `run_id` | Kennung des Laufs im Speicher | ganze Zahl | nie |
| `run_started_at` | Start des Laufs | UTC-Zeitpunkt | nie |
| `run_mode` | Art des Laufs | `gps` oder `treadmill` | nie |
| `role` | Rolle des Werts | `original` oder `current` | nie |
| `value_key` | Schlüssel des Werts | Text | nie |
| `value` | Wert | Zahl in der Einheit der Spalte `unit` | der Wert nicht bestimmbar ist (dann steht `unavailable_reason`) |
| `unit` | Einheit des Werts | Text, wie gespeichert | nie |
| `quality` | Stufe | `provisional`, `sufficient`, `good`, `undeterminable` | nie |
| `unavailable_reason` | Grund, warum der Wert fehlt | stabiler Code (Name des Enum) | der Wert vorhanden ist |
| `method` | Methode | Text | nie |
| `method_version` | Version der Methode | ganze Zahl | nie |
| `parameter_version` | Version der Parameter | ganze Zahl | nie |
| `computed_at` | Zeitpunkt der Berechnung | UTC-Zeitpunkt | nie |
| `data_from`, `data_to` | Zeitraum der Daten | UTC-Zeitpunkt | der Zeitraum nicht gespeichert ist |
| `measurement_count` | Anzahl der Messungen | ganze Zahl | nie |
| `sources` | Quellgeräte und Quellen | JSON-Array von Texten (`["a","b"]`, leer `[]`), als Feld mit verdoppelten Anführungszeichen | nie |

Ein fehlender Wert ist ein **leeres** Feld, nie `0` und nie `NaN` (FR-0068).

## 4. Sortierung

Aufsteigend nach `run_id`, dann `value_key` (Unicode-Codepunkte), dann `role` mit `original` vor `current`. Die Reihenfolge ist damit unabhängig von der Speicherreihenfolge und wiederholbar.

## 5. Datenschutz

Die Datei enthält Gesundheitsdaten und wird nur auf Aktion des Nutzers über Teilen oder Speichern übergeben (FR-0201). Meldungen und Logs der App nennen weder Inhalt noch Pfad.
