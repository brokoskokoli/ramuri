# R005 – Durchstich der Aufzeichnung

**Status:** läuft · **Auftraggeber:** Project Supervisor (ADR-0005, ADR-0003) · **Datum:** 2026-11-04

## Frage
Trägt ADR-0005 Punkt 3 (ein FlutterEngine im Application-Objekt, dünner Kotlin-Foreground-Service, Logik in Dart) eine lückenlose Aufzeichnung bei gesperrtem Bildschirm? Daran hängen ADR-0005 Punkt 3 und Wake Lock, ADR-0003 Punkt 5 (WAL, Transaktionsgröße), ADR-0006 (Plugin) und die Pakete der Aufzeichnung in M1. Ergebnis ist eine Empfehlung für Host und Transaktionsgröße, **keine Produktgrenzwerte**.

**Kriterien:** keine Datenlücke im Emulator bei gesperrtem Bildschirm und Idle; gesicherte Daten überstehen den Kill; WAL nachweislich verschlüsselt; alle Abhängigkeiten GPL-3.0-verträglich, soweit ohne Rechtsprüfung einschätzbar.

## Hintergrund
ADR-0005 (Abschnitt „Vorschlag Research R005“), ADR-0003 (Punkte 1, 4, 5, Offene Punkte), ADR-0006 (Konsequenzen: Bau mit Target 36). R001 bis R004 sagen dazu nichts. Reihenfolge laut Auftrag: zuerst Bau, Lizenzen, WAL (günstig, kann alles kippen), dann Prototyp, dann lange Läufe.

Quellen der Vorrecherche (Abruf 2026-11-04): [FAQ von SQLite3MultipleCiphers](https://utelle.github.io/SQLite3MultipleCiphers/docs/faq/faq_overview/), [Pragma-Dokumentation](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/), [Changelog](https://github.com/utelle/SQLite3MultipleCiphers/blob/main/CHANGELOG.md), ADR-Belege.

## Methode

### Aufbau
Prototyp in `src/proto` (Flutter 3.47.7, minSdk 31, target 36, Profil-Build: AOT und `run-as` möglich; ein Release mit `isDebuggable` baut Flutter als Debug). `src/r005_host` ist der Adapter als lokales Plugin und damit in jedem Engine derselbe: `LocationManager`/`GPS_PROVIDER` mit 1 s, Partial Wake Lock, Gerätezustand, Schrittsensor. `src/proto/lib/recorder.dart` ist der gemeinsame Schreibcode: drift mit `NativeDatabase.createInBackground`, sqlite3mc, WAL, `secure_delete = ON`, Schlüssel über `flutter_secure_storage` (fester Testwert, damit der Rechner Kopien prüfen kann).

| Host | Was läuft | Engine |
| --- | --- | --- |
| `own` | ADR-0005 Punkt 3: Engine in `R005App`, `RecordService` mit Typ `location`, `START_NOT_STICKY` | ein Engine |
| `ffgt` | `flutter_foreground_task` 11.0.3, `allowAutoRestart: false` | UI-Engine plus Dienst-Engine, Schreibcode im Dienst-Engine |
| `none` | Negativkontrolle: wie `own`, aber ohne Dienst | ein Engine |

Eingabe: synthetische Spur mit festem Seed (Random Walk, etwa 3 m je Schritt), mit `adb emu geo fix` einmal je Sekunde vom Rechner eingespeist (`inject.tsv`).

### Messdefinition „Lücke“
Abstand zweier aufeinanderfolgender **in der Datenbank gesicherter** Punkte, gemessen an `trecv_ns`, also `SystemClock.elapsedRealtimeNanos()` beim Eingang im Adapter. `elapsedRealtime` läuft im Schlaf weiter, ein eingefrorener Prozess oder ein schlafendes System wird also sichtbar. `Location.getElapsedRealtimeNanos()` taugt dafür nicht: Der Emulator liefert dort Werte auf Epochenbasis (selbst gesehen in den Logs).

Berichtet wird die Verteilung (p50, p99, Maximum) und die Zahl der Abstände über 2 s, 5 s und 30 s. **Als Lücke gilt ein Abstand über 5 s**, dem Fünffachen der angeforderten Rate: deutlich über dem Eingangsjitter der Referenzphase (siehe RESULTS), aber klein genug, dass eingefrorene Prozesse und ein gedrosselter Standort sicher auffallen. Das ist eine Messdefinition, kein Produktgrenzwert. Zusätzlich die **Abdeckung**: Anteil der eingespeisten Spurpunkte, die in der DB ankamen (nächste Spurposition, Toleranz 1,2e-5 Grad wegen NMEA-Rundung).

### Lücken bei Sperre und Idle
Je Lauf: 60 s Referenz (sichtbar, entsperrt), dann Home, `input keyevent 223`, `dumpsys battery unplug`, `dumpsys deviceidle force-idle`. Alle 15 s protokolliert der Rechner `deviceidle get deep/light`, `mWakefulness`, Keyguard und Host-Last (`state.tsv`). Die App protokolliert jede Sekunde `R005HB` mit `elapsedRealtime`, `uptimeMillis`, `isDeviceLocked`, `isInteractive`, `isDeviceIdleMode`. Die Sperre ist echt (PIN gesetzt).

### Gegenprobe Lücken (Pflicht)
1. **Negativkontrolle** `host=none`: gleicher Ablauf ohne Dienst. Bleibt sie lückenlos, ist „keine Lücke“ wertlos.
2. **Bekannte Lücke:** 30 s Pause der Einspeisung; die Auswertung muss sie finden.
3. **Schlaf-Beleg:** `elapsedRealtime - uptimeMillis` über die Phase. Bleibt die Differenz 0, ist das System nie in den Suspend gegangen, und der Wake-Lock-Vergleich sagt nichts über den Suspend aus.

### Kill
Commit-Bestätigung außerhalb der DB: Nach dem `await` der Transaktion schreibt die App `R005ACK seq=…` nach logcat, der Rechner schreibt mit (Bestätigungen in Flug gehen höchstens verloren und machen die Prüfung nur strenger). Danach wird der Prozess bzw. der Emulator getötet, nach einer zufälligen Laufzeit von 20 bis 40 s. Die DB wird gezogen und auf dem Rechner geöffnet; zusätzlich öffnet sie die App auf dem Gerät (`R005VERIFY`). Zählgrößen: `lost_acked` = bestätigte Sequenznummern, die in der DB fehlen (muss bei `FULL` 0 sein); `rcv_not_db` = zuletzt empfangene minus höchste gesicherte Nummer (der Preis der Transaktionsgröße); `holes`; `integrity_check`.

Emulator läuft immer mit `-no-snapshot-save -no-snapshot-load`. `NORMAL` ist die Kontrolle: Zeigt sie keinen Verlust, belegt der Aufbau auch für `FULL` nichts. Arten: `proc` (`kill -9` per `run-as`), `emu` (`adb emu kill`), `sigkill` (SIGKILL auf den eigenen qemu-Prozess, falls `adb emu kill` zu sanft ist).

### Verschlüsseltes WAL
Auf dem Rechner (`src/waltest`, gleiche Paketversion) und im Emulator. Bekannter Marker und bekannter Double, `wal_autocheckpoint = 0`, Kopie von Datei und WAL vor dem Checkpoint, Suche nach den Bytes, Byteverteilung der Seiteninhalte (χ², 255 Freiheitsgrade). Positivkontrolle unverschlüsselt. Beleg, dass das WAL Inhalt hatte: Die Kopie ohne WAL hat keine Tabelle, mit WAL alle Zeilen. Jede Öffnung auf frischer Kopie, denn das Schließen der letzten Verbindung checkpointet.

### Lizenzen
`src/licenses.py`: `flutter pub deps --json` plus Lizenzdatei im Pub-Cache, `gradlew :app:dependencies` plus Lizenzen im POM (mit Eltern-POMs), native `.so` aus der APK, Klassen der APK mit `dexdump` gegengeprüft. Einschätzung ohne Rechtsprüfung.

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| Synthetische GPS-Spuren | `research/data/work/R005/*/*/inject.tsv` | selbst erzeugt, fester Seed | klein | ja, `./run.sh` |
| Rohdaten der Läufe | `research/data/work/R005/` | Prototyp, nur synthetisch | wenige 100 MB | ja, `./run.sh` |
| System-Images `android-31`, `android-36` (`google_apis;arm64-v8a`) | Android SDK, nicht `research/data/` | Google, Android-SDK-Lizenz | etwa 6 GB | ja, `./init.sh` |

Keine Sammlung aus `input/`.

## Ausführung
Wird nach den Läufen ergänzt (`./init.sh`, `./run.sh --help`).
