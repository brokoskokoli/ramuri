# R008 – Kartenbibliothek und Kachelanbieter

**Status:** läuft · **Auftraggeber:** Project Supervisor für ADR-0009 Punkt 6, vor WP13 · **Datum:** 2026-11-07

## Frage
Welche Flutter-Bibliothek und welcher Kachelanbieter tragen FR-0204 (Karte auf der Live-Seite, in Zusammenfassung und Detailansicht, Miniaturen in einer Historie mit 50 und mehr Läufen) unter den Randbedingungen von ADR-0009 Punkt 1 bis 5 (Netz nur im Kartenadapter und nur nach Einwilligung, verschlüsselter Kachel- und Miniaturspeicher, Karte nur in der Oberfläche)? Ist OpenFreeMap für eine verteilte App zulässig und tragfähig (Nutzungsbedingungen, Verfügbarkeit, Alternativen; die Server der OSMF sind ausgeschlossen)?

Daran hängt ADR-0009 Punkt 6 (Bibliothek und Darstellung) und damit der Zuschnitt von WP13.

## Hintergrund
- Konzept: FR-0204, FR-0027, FR-0037, FR-0040, FR-0041, SEC-0002, SEC-0007, SEC-0008, SEC-0009; OQ-0074; ADR-0009 (Punkte 1 bis 5 sind Randbedingung, nicht Gegenstand), ADR-0003 (Schlüssel und Verschlüsselung), ADR-0005 (Aufzeichnungsdienst kennt die Karte nicht); WP13.
- Kandidaten laut ADR-0009: `flutter_map` mit `vector_map_tiles` und `maplibre_gl`. Weitere Kandidaten, wo sinnvoll (z. B. `maplibre` von josxha, Rasterkacheln eines freien Anbieters).
- Frühere Analysen: R005 (Emulator-Aufbau, Lizenzbaum-Werkzeug), keine zur Karte.
- Quellen der Vorrecherche stehen in [RESULTS.md](RESULTS.md) unter „Quellen“.

## Methode
1. **Vorrecherche (Web):** Nutzungsbedingungen und Betriebsmodell von OpenFreeMap, Namensnennung, Verfügbarkeit; Alternativen ohne Schlüssel und Konto (z. B. VersaTiles, selbst gehostete PMTiles, freie Rasterdienste), die OSMF-Server ausgeschlossen. Reife und Pflege der Bibliotheken (Versionen, Beta-Status, Kompatibilität mit Flutter 3.47.7).
2. **Mini-Apps** (Quellen in `src/apps/`, gebaut unter `research/data/work/R008/`), alle mit Flutter 3.47.7, minSdk 31, targetSdk 36, Release-Build:
   - `base`: leere Flutter-App (Vergleichsbasis für die APK-Größe).
   - `fm`: `flutter_map` + `vector_map_tiles` mit OpenFreeMap-Stil, eigene Kachelquelle über einen Hook (verschlüsselter Speicher statt Klartext-Cache), Live-Seite mit wandernder Position, Miniatur als einmaliger Snapshot.
   - `ml`: `maplibre_gl` mit OpenFreeMap-Stil, Live-Seite, Miniatur über die Snapshot-Funktion der Bibliothek, sofern vorhanden.
   - weitere nur, wenn die Vorrecherche es nahelegt.
3. **Kennzahlen:**
   - **APK-Zuwachs:** Release-APK je ABI (`--split-per-abi`, arm64-v8a und x86_64) und universal, Differenz zu `base` in MB.
   - **Lizenzbaum:** vollständiger Abhängigkeitsbaum (Dart über `pubspec.lock` und die LICENSE-Dateien im Pub-Cache, Android/Gradle über `releaseRuntimeClasspath` und die POM-Lizenzen), jede Lizenz gegen GPL-3.0 eingeordnet.
   - **Netz und Telemetrie:** statisch (Netz-APIs und fest eingebaute Hosts in den Quellen und Bibliotheken), dynamisch per Netzwerkmitschnitt im Emulator (`-tcpdump`): ohne Einwilligung keine Verbindung, mit Einwilligung nur die Hosts des Anbieters.
   - **Speicher-Hook:** Host-Test, dass Kacheln nur über den eigenen Hook gelesen und geschrieben werden und im App-Verzeichnis keine Kachel- oder Bildsignaturen im Klartext liegen (Suche nach `\x1a`-PBF-Kopf, gzip, PNG, SQLite-Kopf).
   - **Miniaturen:** Snapshot einmal erzeugen, verschlüsselt ablegen, danach nur das Bild anzeigen; Zeit je Snapshot und Größe je Miniatur.
   - **Live-Seite:** Bildrate und CPU-Zeit (`dumpsys gfxinfo`, `/proc/<pid>/stat`) während einer eingespeisten Fahrt im Emulator; Akku nur als Stellvertreter (CPU-Zeit), keine Aussage über echte Geräte.
   - **Aufwand:** Umfang der Hooks, nötige native Eingriffe, Testbarkeit am Host (Gate).
4. **Emulator:** nur wenn kein anderer Emulator läuft. Erst API 36 voll, dann API 31 nur Start-Smoke. Höchstens ein Emulator, explizites Serial, `-no-audio`, Ende per PID.

Warum aussagekräftig: Die Kriterien aus ADR-0009 Punkt 6 werden je Kandidat am gebauten Release-APK gemessen, nicht nur aus der Dokumentation übernommen. Grenzen: Emulator statt Gerät (Akku, GPU), wenige Kachelanfragen.

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| Synthetische Route | `src/route.dart` bzw. erzeugt | selbst erzeugt, öffentlicher Park ohne Personenbezug | < 10 kB | ja |
| Wenige Kacheln, Stil, Sprites als Testvorlage | `research/data/work/R008/fixtures/` | OpenFreeMap, Daten © OpenStreetMap-Mitwirkende (ODbL), OpenMapTiles | < 5 MB | ja, `./init.sh` |
| Mini-App-Builds, APKs, Mitschnitte | `research/data/work/R008/` | selbst erzeugt | ~2 GB (Build-Ordner) | ja, `./run.sh` |

Keine Sammlung aus `research/input/`.

## Ausführung
Voraussetzungen: Flutter 3.47.7 (global), Android-SDK mit AVDs `running_app_api36` und `running_app_api31`, Netz für `pub get`, Gradle und wenige Kacheln.

```bash
./init.sh            # Fixture-Kacheln laden (idempotent, wenige Anfragen)
./run.sh <schritt>   # siehe Tabelle
```

Die Schritte und Parameter stehen gleichlautend in `./run.sh --help` (wird mit den Skripten ergänzt).

Ausgaben: `research/data/work/R008/<schritt>/` (wegwerfbar).
