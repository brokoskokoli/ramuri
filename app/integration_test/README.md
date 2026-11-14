# E2E-Regressionssammlung

Läuft auf GitHub im Workflow `e2e` (je API 31 und 36, zwei Shards) über `tool/ci_e2e.sh`; die Stufen-Zuordnung steht nur dort. Lokal, ohne GitHub, nur der E2E-Agent mit Emulator (`tool/ci_e2e.sh` mit `E2E_STUFEN="..."`).

| Ablauf | Datei | Stufe / Shard |
|---|---|---|
| Neuberechnung (recalc) | `e2e_recalc_test.dart` | `sammlung` / Shard sammlung |
| Lauf aufzeichnen | `e2e_run_test.dart` | `sammlung` / sammlung |
| Plan anlegen, anpassen, neu berechnen, Warnsignal | `e2e_plan_test.dart` | `sammlung` / sammlung |
| Archiv-Export und Reimport (ohne Dateidialog) | `e2e_archive_test.dart` | `sammlung` / sammlung |
| Laufband | `e2e_treadmill_test.dart` | `sammlung` / sammlung |
| Kamera-Ruhepuls (Fake-Kamera, guter Puls und kein Finger) | `e2e_resting_test.dart` | `sammlung` / sammlung |
| Health-Connect-Import (Debug-Quelle: Rechte, Abruf, Verlauf, Übernehmen, Widerruf mit Löschfrage, Installieren); echter Dialog nur lokal mit `--dart-define=HC_REAL=true` | `e2e_health_test.dart` | `sammlung` / sammlung |
| Wiederanlauf eines laufenden Laufs nach Prozessende | `e2e_recover_test.dart` | `recover-a`, `recover-b` / stufen |
| Plan, geführte Einheit in Echtzeit (~5,5 min), „Aus dem Plan“, Rückmeldung, Zieländerung, Planverlauf; Karten-Frage nur in der Zusammenfassung | `e2e_m2_flow_test.dart` | `m2-flow` / stufen |
| Speicher nach Prozessende (Schreiben, Lesen) | `e2e_storage_test.dart` | `storage-a`, `storage-b` / stufen |

`all_test.dart` bindet die Sammlung ein (`e2e_m2_flow_test.dart` läuft wegen der Dauer als eigene Stufe); eine neue `e2e_*_test.dart`, die weder dort noch als Stufe in `tool/ci_e2e.sh` steht, macht den Lauf rot (Wächter). Die Mehrphasen-Stufen brauchen ein Prozessende zwischen den Phasen und laufen darum einzeln.

## Lokale Mehrphasentests (Health Connect, nicht in der CI)

Nur der E2E-Agent mit Emulator, je Phase ein Lauf `flutter test integration_test/<datei> -d <serial> --dart-define=...`; die Wächter in `tool/ci_e2e.sh` nehmen beide Dateien aus. Marker im Testlog: `SHOT <name>` (Bildschirmfoto), `HOSTACT <aktion>` (Host-Schritt, der Test wartet 6 s). Außer der ersten Phase immer mit `--no-uninstall`, damit Daten und Schlüssel bleiben. Paket `io.github.brokoskokoli.ramuri`.

- `e2e_health_real_test.dart`: echter Adapter, echter Berechtigungsdialog von Health Connect (API 34+). `--dart-define=HC_MODE=cancel` (Dialog abbrechen) oder `HC_MODE=grant` (Dialog bestätigen); der Host beantwortet den Systemdialog per `adb shell input` nach dem Marker `SHOT`.
- `e2e_health_revoke_test.dart`: Löschfrage beim Öffnen von „Heute“ nach Entzug des Rechts (SEC-0007), mit `--dart-define=HC_PHASE=...`:
  1. `HC_PHASE=1`: Debug-Quelle, Schlaf einwilligen und importieren (erste Phase, mit Neuinstallation ist ok).
  2. Host: `adb shell pm grant io.github.brokoskokoli.ramuri android.permission.health.READ_SLEEP`, dann `HC_PHASE=2 --no-uninstall` (echter Adapter, Recht erteilt: keine Frage).
  3. Host: `adb shell pm revoke io.github.brokoskokoli.ramuri android.permission.health.READ_SLEEP` (beendet den App-Prozess, daher eigene Phase), dann `HC_PHASE=3 --no-uninstall HC_ANSWER=delete|keep` (Frage erscheint; Abbrechen lässt sie offen; Löschen entfernt die Daten, Behalten lässt sie und beendet die Einwilligung).
  4. `HC_PHASE=B`: Debug-Quelle, Zähler je Art im Speicher (Ruhepuls, HRV, VO2max, Schlaf; nicht eingewilligte Art 0). Die Zahl hängt von der UTC-Tageszeit ab (siehe unten).

Die Debug-Quelle liefert je Nacht einen HRV-Wert 20 min nach dem Ende der Schlafphase (06:30 UTC); vor 06:50 UTC liegt der der letzten Nacht in der Zukunft und wird nicht gelesen: HRV 11 statt 12 gespeicherter Werte.

## Bleibt lokal oder offen, und warum

- System-Dateidialog (SAF, Teilen): Systemoberfläche, im Emulator nicht stabil bedienbar; das Archiv wird ohne Dialog über die echte Export-/Restore-Fabrik getestet.
- Echtes Kamera-Recht und echte Kamera, weitere PPG-Szenarien: Hardware; CI nutzt die Fake-Kamera.
- Karte und Einwilligung: im Test nur weggeklickt.
- `storage` mit `PHASE=fill` (Speicher voll): langsam und gerätenah.
- Sichtprüfungen (Layout, Lesbarkeit): Sache des E2E-Agenten.
- Nur im Feld: Hintergrundbetrieb, Akku, echter Brustgurt.

Tests geben nur Zähler, Schlüssel und Längen aus, nie Werte (SEC-0001..0010); `ci_e2e.sh` filtert `E2E_`-Zeilen aus Log und Artefakt.
