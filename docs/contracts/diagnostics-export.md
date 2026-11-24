# Vertrag: Diagnose-Export

**Status:** Formatversion 1. Inhalt und Weg (nur Fehlertyp, Ortskennung, Anzahl, App-Version und Zeitraum; Weitergabe nur über das Teilen-Menü) hat der Maintainer festgelegt (Entscheidung 2026-11-20); Dateiformat JSON und Feldnamen sind die Festlegung der Umsetzung.
**Anforderungen:** FR-0223, FR-0217, FR-0201, SEC-0004, SEC-0008, SEC-0009.
**Code:** `app/lib/features/export/diagnostics_export_action.dart` (Inhalt, Dateiname, Schaltfläche); Zähler `app/lib/error_counter.dart`; Abschnitt „Fehler“ `app/lib/features/settings/error_counts_section.dart`.

## 1. Überblick

Eine Datei `ramuri-diagnose-JJJJMMTT.json` (MIME `application/json`; `JJJJMMTT` ist der lokale Kalendertag des Exports) enthält die lokal gezählten Fehler der App. Gezählt wird je Paar (Fehlertyp, Ortskennung); die Zähler liegen in den Einstellungen der verschlüsselten Datenbank (Schlüssel `diagnostics.error_counts`, nicht im Archiv, [archive.md](archive.md)).

Die Datei entsteht nur in den Entwicklereinstellungen (Entwicklermodus, FR-0217) nach „Diagnose teilen“ und dem Bestätigen im Dialog, der den Inhalt zeigt. Sie geht nur an das Teilen-Menü des Systems ([file-export.md](file-export.md), Weg „Teilen“ mit Inhalt im Speicher); die App öffnet dafür keine Netzverbindung und überträgt nichts von selbst. Die Plattform legt die Datei im Export-Cache ab, der beim Start, vor jedem Teilen und bei „Alles löschen“ geleert wird.

## 2. Kodierung

- UTF-8 ohne Byte-Order-Mark, JSON-Objekt, eingerückt mit zwei Leerzeichen.
- Tage als `JJJJ-MM-TT` (lokaler Kalendertag des Geräts beim Speichern des Zählers).

## 3. Felder

| Feld | Typ | Bedeutung |
|---|---|---|
| `format` | Zeichenkette | immer `ramuri-diagnose` |
| `formatVersion` | Ganzzahl | `1` |
| `appVersion` | Zeichenkette oder `null` | Version der installierten App (`versionName (versionCode)`); `null`, wenn sie nicht lesbar ist |
| `from` | Tag oder `null` | frühester Tag des ersten Auftretens aller Einträge; `null`, wenn kein Eintrag einen Tag trägt |
| `to` | Tag oder `null` | spätester Tag des letzten Auftretens aller Einträge; `null` wie bei `from` |
| `errors` | Liste | je Eintrag ein Objekt mit genau `type`, `place`, `count`; sortiert nach `count` absteigend, bei Gleichstand nach `type`, dann `place` (Zeichenfolge) |
| `errors[].type` | Zeichenkette | Fehlertyp (Laufzeittyp, z. B. `StateError`) |
| `errors[].place` | Zeichenkette | Ortskennung: erste Datei der App im Stack als `package:<paket>/<pfad>.dart` ohne Zeile und Spalte, sonst `unknown`; nie ein Pfad des Geräts |
| `errors[].count` | Ganzzahl ≥ 1 | Anzahl seit dem letzten Zurücksetzen |

Weitere Felder gibt es nicht. Die Datei enthält **keine** Gerätekennung, keinen Gerätenamen, keine Läufe, keine Gesundheitswerte, keine Fehlernachricht, kein `toString` eines Fehlers und keinen Stack (SEC-0008, SEC-0009). Die Liste hat höchstens 50 Einträge (Obergrenze des Zählers). Einträge ohne Tage (gezählt vor dieser Formatversion) tragen nur zu `from`/`to` nichts bei.

## 4. Beispiel (synthetisch)

```json
{
  "format": "ramuri-diagnose",
  "formatVersion": 1,
  "appVersion": "0.1.0 (12)",
  "from": "2026-11-03",
  "to": "2026-11-10",
  "errors": [
    {
      "type": "StateError",
      "place": "package:running_app/features/measure/x.dart",
      "count": 2
    }
  ]
}
```

## 5. Zurücksetzen und Löschen

„Zähler zurücksetzen“ (nach Rückfrage) leert gespeicherte und noch nicht gespeicherte Zähler. „Alles löschen“ leert sie mit der Datenbank; noch nicht gespeicherte Zähler werden verworfen (SEC-0004).
