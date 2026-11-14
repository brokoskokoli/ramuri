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
| Wiederanlauf eines laufenden Laufs nach Prozessende | `e2e_recover_test.dart` | `recover-a`, `recover-b` / stufen |
| Speicher nach Prozessende (Schreiben, Lesen) | `e2e_storage_test.dart` | `storage-a`, `storage-b` / stufen |

`all_test.dart` bindet die Sammlung ein; eine neue `e2e_*_test.dart`, die weder dort noch als Stufe in `tool/ci_e2e.sh` steht, macht den Lauf rot (Wächter). Die Mehrphasen-Stufen brauchen ein Prozessende zwischen den Phasen und laufen darum einzeln.

## Bleibt lokal oder offen, und warum

- System-Dateidialog (SAF, Teilen): Systemoberfläche, im Emulator nicht stabil bedienbar; das Archiv wird ohne Dialog über die echte Export-/Restore-Fabrik getestet.
- Echtes Kamera-Recht und echte Kamera, weitere PPG-Szenarien: Hardware; CI nutzt die Fake-Kamera.
- Karte und Einwilligung: im Test nur weggeklickt.
- `storage` mit `PHASE=fill` (Speicher voll): langsam und gerätenah.
- Sichtprüfungen (Layout, Lesbarkeit): Sache des E2E-Agenten.
- Nur im Feld: Hintergrundbetrieb, Akku, echter Brustgurt.

Tests geben nur Zähler, Schlüssel und Längen aus, nie Werte (SEC-0001..0010); `ci_e2e.sh` filtert `E2E_`-Zeilen aus Log und Artefakt.
