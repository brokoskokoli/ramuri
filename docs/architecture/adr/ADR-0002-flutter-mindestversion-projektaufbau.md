# ADR-0002 — Flutter, Android-Mindestversion und Projektaufbau

- **Status:** Accepted (Maintainer, 2026-11-04)
- **Datum:** 2026-11-04
- **Quellen:** Entscheidung des Maintainers vom 2026-11-04 (Flutter, siehe PROJECT.md); SRC-003 (OQ-0035)
- **Betroffene Anforderungen:** CON-0001, CON-0002, NFR-0006, FR-0200, OQ-0035

## Kontext
Zielplattform ist Android, später optional iOS (CON-0001). Flutter ist vom Maintainer gesetzt und steht hier nicht zur Wahl. Offen sind Mindestversion (OQ-0035), Aufbau von `app/` und wie iOS offen bleibt. Die Agenten testen vorerst nur im Emulator, jede unterstützte Android-Generation kostet also Verzweigungen, die niemand im Feld prüft.

## Entscheidung
**Gesetzt (Maintainer):** Flutter, aktuell stable 3.47.9 mit Dart 3.13.7 [1].

**1. Versionen:** `minSdk` 31 (Android 12), `targetSdk` 36, `compileSdk` mindestens 36.

| minSdk | Anteil Geräte [2] | Was dadurch nötig bliebe |
|---|---|---|
| 26 | 99,2 % | Wie 28; Health Connect ist erst ab API 28 nutzbar [3] |
| 28 | 98,2 % | Wie 30, mit zwei Android-Generationen mehr im Testumfang |
| 30 | 93,5 % | Alte Bluetooth-Rechte, `ACCESS_FINE_LOCATION` fürs Scannen und `ACCESS_BACKGROUND_LOCATION` für eine Suche aus einem Dienst [4]; zweiter Satz Backup-Regeln [5] |
| **31** | **87,4 %** | Nichts davon; einheitliche Startregeln für Foreground Services [6] |

Flutter unterstützt API 24 bis 37 und testet in CI 24 bis 36 [7]. Target 36 ist seit 31.08.2026 Pflicht für neue Apps bei Google Play [8] und liegt im CI-getesteten Bereich. `connect-client` ab 1.1.0 verlangt `compileSdk` 36 [3].

**2. Aufbau von `app/`** als Pub-Workspace [9], ohne Abhängigkeit von außen nach innen:
- `app/packages/core`: reines Dart ohne Flutter im `pubspec`. Fachlogik, Modelle, Planung, Ports und deren Fakes. Läuft mit `dart test`; ein Flutter-Import scheitert schon am Auflösen.
- `app/packages/adapters`: Umsetzung der Ports mit Plugins und eigenem Plattformcode.
- `app/lib` und `app/android`: Oberfläche, Zusammenbau der Abhängigkeiten, Kotlin-Anteile.

Ports mindestens für Standort, Herzfrequenzsensor, Schrittfrequenz, Aufzeichnungsdienst, Speicher, Schlüsselablage, Health Connect und Uhr.

**3. iOS:** `flutter create --platforms=android`, also kein `ios/`, keine iOS-Tests und keine Zusage. Offen bleibt iOS allein durch die Ports und dadurch, dass die Plugins aus ADR-0003 und ADR-0006 iOS mitbringen. Eigener Kotlin-Code (ADR-0005, ADR-0007) und HealthKit bräuchten später Swift und eine eigene ADR.

## Erwogene Alternativen
- **minSdk 28:** Rund 11 Prozentpunkte mehr Geräte, aber Verzweigungen für Berechtigungen und Backup, die sich nur im Emulator prüfen ließen. Ablehnung nur empfohlen, die Abwägung gehört dem Maintainer.
- **minSdk 24 (Flutter-Untergrenze):** Unter API 28 kein Health Connect [3], keine Verbesserung für die Kernfunktion.
- **Ein Paket mit Importregel statt Workspace:** Einfacher, aber die Flutter-Freiheit der Fachlogik hinge an einer Lint-Regel statt am Paketgraph.
- **Mehrere feine Pakete je Baustein:** Mehraufwand ohne Nutzen, solange ein Coder-Team alles pflegt.

## Konsequenzen
- Rund 12,6 % der aktiven Geräte fallen weg. Die Zahl stammt aus einer Drittquelle (Statcounter über apilevels.com) und sagt nichts über Läufer.
- `tool/gate.sh` prüft bisher nur `lib` und `test` in `app/`. Das erste Paket muss das Gate um `app/packages/*` erweitern, sonst laufen Fachtests nicht mit.
- Das Gate nutzt in CI `channel: stable` ungepinnt; die Flutter-Version sollte im ersten Paket festgelegt werden.
- Target 37 ändert Regeln (etwa die Standortschaltfläche für sitzungsbezogenen Zugriff [10]) und ist beim Wechsel neu zu prüfen.

## Im Emulator nicht belegbar
Verhalten auf Herstellergeräten unter Android 12 bis 16. Geprüft wird nur auf Images von Google, sinnvoll an beiden Rändern (API 31 und 36).

## Offene Punkte
Build mit diesen Versionen und der vollständige Lizenzbaum aller Abhängigkeiten sind unbelegt, solange kein Projekt existiert; Prüfung in Research-Auftrag R005 (siehe ADR-0005). Der Vertriebsweg ist nicht festgelegt und bestimmt, ob die Play-Vorgaben überhaupt gelten.

## Belege (Abruf 2026-11-04)
[1] https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json ·
[2] https://apilevels.com/ (Statcounter, Oktober 2026) ·
[3] https://developer.android.com/health-and-fitness/guides/health-connect/develop/get-started ·
[4] https://developer.android.com/develop/connectivity/bluetooth/bt-permissions ·
[5] https://developer.android.com/guide/topics/data/autobackup ·
[6] https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start ·
[7] https://docs.flutter.dev/reference/supported-platforms ·
[8] https://developer.android.com/google/play/requirements/target-sdk ·
[9] https://dart.dev/tools/pub/workspaces ·
[10] https://developer.android.com/develop/sensors-and-location/location/permissions
