# R005 – Durchstich der Aufzeichnung

**Status:** abgeschlossen (beide Checkpoint-Serien ausgewertet, Research-Review Runde 3 steht aus), Ergebnis in [RESULTS.md](RESULTS.md) · **Auftraggeber:** Project Supervisor (ADR-0005, ADR-0003) · **Datum:** 2026-11-04

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

### Zwei Bedingungen
Goldfish hält den Kernel-Wake-Lock `emulator_wake_lock` ab etwa 13 s nach dem Boot, deshalb schläft der Emulator von selbst nie. Daher:
- **Standard:** Sperre bleibt, kein Suspend. Misst Host, Doze, Einfrieren.
- **natural** (`--natural 1`): `echo emulator_wake_lock > /sys/power/wake_unlock` per root. Das ist ein Eingriff in den Emulator, die Wake-Lock-Zählung bleibt in Kraft, kein `echo mem`. Ohne Wake Lock kommt der Emulator nicht zurück: Solche Läufe enden mit SIGKILL und Neustart, die Zeilen stammen aus der DB, der Schlafbeleg aus dem Kernel-Log (`kernel-pm.txt`, Emulator mit `-show-kernel`; Phase A lief ohne). `geo fix` weckt das System nicht.

### Gegenprobe Lücken (Pflicht)
1. **Negativkontrolle** `host=none`: gleicher Ablauf ohne Dienst. Bleibt sie lückenlos, ist „keine Lücke“ wertlos.
2. **Bekannte Lücke:** 30 s Pause der Einspeisung; die Auswertung muss sie finden. Der Emulator wiederholt die letzte Position, also zählt hier der Abstand der Positionswechsel (`poschg_*`), nicht der reine Abstand.
3. **Einfrieren:** SIGSTOP 30 s (`--stop-at`, `--stop-len`), muss als Abstand und im Herzschlag auftauchen.
4. **Schlaf-Beleg:** Kernelzähler `suspend_stats` vor und nach dem Lauf, `dmesg`, `kernel-pm.txt`. Die ursprünglich geplante Differenz `elapsedRealtime - uptimeMillis` taugt nicht: Sie bleibt auf diesem Kernel auch bei belegtem Suspend 0 (Probe `probe-suspend-api31`).
5. **Erzwungener Suspend** (`--force-at`): `echo mem`, nur Probe, kein Beleg zum Wake Lock.

### Abstände auf API 36
Probe `_abst_noinj`, `_abst_inj10`, `_abst_inj1` (je 240 s): ohne Einspeisung, alle 10 s, jede Sekunde, dazu `hal-log.txt` (Ausgaben des GNSS-HAL) und `location.txt`. Vergleicht Eingang, Verwerfung und Weitergabe im HAL mit den DB-Zeilen. Auswertung in `src/tables.py`, Tabelle 4.

### Langlauf
Ein Lauf, 60 min, API 36, `own`, Wake Lock, tx 1, `FULL`, natural; Zustand alle 60 s, Ressourcen alle 30 s (`resources.tsv`), Auswertung `src/longrun.py`.

### Kill
Commit-Bestätigung außerhalb der DB: Nach dem `await` der Transaktion schreibt die App `R005ACK seq=…` nach logcat, der Rechner schreibt mit. Bestätigungen in Flug können verloren gehen; sie verkleinern die geprüfte Menge, machen die Prüfung also schwächer (hier gering: Das bestätigte Ende lag in allen harten tx-1-Läufen mit `FULL` höchstens 1,1 s vor dem Kill). Danach wird der Prozess bzw. der Emulator getötet, nach einer zufälligen Laufzeit von 20 bis 40 s. Die DB wird gezogen und auf dem Rechner geöffnet; zusätzlich öffnet sie die App auf dem Gerät (`R005VERIFY`). Zählgrößen: `lost_acked` = bestätigte Sequenznummern, die in der DB fehlen (muss bei `FULL` 0 sein); `rcv_not_db` = zuletzt empfangene minus höchste gesicherte Nummer (der Preis der Transaktionsgröße); `holes`; `integrity_check`.

Emulator läuft immer mit `-no-snapshot-save -no-snapshot-load`. `NORMAL` ist die Kontrolle: Zeigt sie keinen Verlust, belegt der Aufbau auch für `FULL` nichts. Arten: `proc` (`kill -9`; die API-36-Läufe in RESULTS per `run-as`, die API-31-Läufe per root, weil `run-as` dort nicht wirkte, jeweils mit Prüfung, dass der PID weg ist. Der heutige Harness tötet immer per root, eine Wiederholung auf API 36 misst an dieser Stelle also anders), `emu` (`adb emu kill`), `sigkill` (SIGKILL auf den eigenen qemu-Prozess; zeigt den Verlust des Gast-Pagecaches, der Rechner läuft weiter, also kein Stromausfall). Gültig ist ein Lauf nur mit neuem oder fehlendem PID und ohne `R005RCV` nach dem Kill (Ausnahme `ffgt`-Neustart), und wenn der Abgleich unten besteht. Abweichung vom Auftrag: `adb emu kill` ist nur für tx 1 auf API 36 gemessen, `sigkill` ersetzt es je Transaktionsgröße; Begründung in RESULTS, „Kill“.

### Gültigkeit: Log gegen DB (gap und kill)
Jeder Lauf braucht mindestens ein `R005ACK`, darf kein `SqliteException` enthalten (bei kill nur bis zum Kill gezählt, `ffgt` nummeriert nach dem Neustart neu), und `trecv` muss für jede gemeinsame Sequenznummer in DB und Log gleich sein. Das erkennt eine DB aus einem abgebrochenen Vorversuch mit gleichem Laufnamen. Deshalb löscht der Harness außerdem vor jedem Lauf die DBs des Prototyps und bricht ab, wenn eine liegen bleibt. Tabelle 1, 2, 5, 8 und 8b in `tables.py` zählen nur gültige Läufe, die übrigen stehen oben in der Ausgabe. Tabelle 3 und 4 filtern nicht: Die Abstandsprobe (Tabelle 4) setzt die Einspeisung absichtlich aus und ist deshalb ungültig, das ist die gewollte Ausnahme.

### Kill nach dem ersten Checkpoint
Die 115 Läufe aus Tabelle 5 treffen nur Hauptdateien von 4096 Byte, weil der Standard `wal_autocheckpoint = 1000` bei tx 1 erst nach etwa 18 min greift. `./run.sh checkpoint` (`src/checkpoint.sh`) stellt den Zustand danach her: `sigkill`, tx 1, `own`, `wal_autocheckpoint` 10 (Parameter `--autock`), Kill nach 25 bis 45 s, also nach mindestens zwei Checkpoints. Sie trifft das wiederverwendete WAL, aber bei `FULL` keine Zeile nur in der Hauptdatei (vor der ersten Teilung schreibt jeder Commit die ganze Seite als einen Frame, siehe zweite Serie). Je API 36 und 31 7 × `FULL` und 3 × `NORMAL` als Kontrolle, 20 Läufe, Laufnamen `a<api>_sigkill_tx1_<sync>_ck10_r<n>`. Der jeweils erste Lauf ist die Vorprüfung: Zeigt er keinen Checkpoint, bricht die Serie ab, denn dass `autock` im Gerät wirkt, ist bisher nicht belegt (die WAL-Läufe mit `autock` 0 blieben unter 1000 Frames).

**Gültigkeit:** Hauptdatei über 4096 Byte, Kill-Wirkung belegt, Log gegen DB wie oben. **Ausschluss ist kein Freispruch:** Die Hauptdatei wird nach dem Kill gemessen, eine geschrumpfte Datei wäre gerade der gesuchte Schaden. `tables.py` weist ungültige Läufe deshalb samt ihrem `lost_acked` aus. Zusätzlich liest der Harness vor dem ersten Öffnen die Klartext-Köpfe des WAL (`src/walhdr.py`, Kontrolle an einer SQLite-Datei): `ckpt_seq` über 0 heißt, das WAL wurde wiederverwendet; `frames_old` sind liegen gebliebene Frames der Vorgeneration. **Grenzen:** 10 statt 1000 Frames je Checkpoint ändern dessen Größe und Häufigkeit; ein Treffer mitten im Checkpoint wird weder gesucht noch ausgeschlossen. `NORMAL` hat hier auch eine andere Erwartung als in Tabelle 5, denn der Checkpoint synchronisiert das WAL: Verlust höchstens seit dem letzten Checkpoint.

### Zweite Kill-Serie: Zeilen nur in der Hauptdatei
Die erste Serie endet bei höchstens 41 Zeilen. Bis zur ersten Seitenteilung schreibt jeder Commit die ganze Tabellenseite als einen Frame, also lagen dort bei `FULL` nie Zeilen nur in der Hauptdatei (Review Runde 2, Befund 1). Die Teilung kommt, wenn die Seite voll ist, und das hängt an der Zeilenlänge (Laufname in jeder Zeile, `tfix_ns` je API, Reserve der Verschlüsselung): Zeile 42 bis 44 in dieser Serie, 54 bis 56 in `wal-device` (`src/zeilen_je_seite.py`, RESULTS). `./run.sh checkpoint2` (`src/checkpoint2.sh`) tötet deshalb erst nach 90 bis 180 s, Laufnamen `a<api>_sigkill_tx1_<sync>_ck10b_r<n>`. Sonst wie die erste Serie: `sigkill`, tx 1, `own`, `--autock 10`, je API 7 × `FULL`, 3 × `NORMAL`.

**Gültigkeit, direkt belegt je Lauf (`analyze.py`, `main_only`):** Der Harness behält die Kopie von Hauptdatei und WAL vor dem ersten Öffnen (`before-open/`). Daraus:
1. Seitennummern der gültigen aktuellen WAL-Frames, Klartext im Frame-Kopf: Salt gleich Kopf, Prüfsummenkette stimmt, nur bis zum letzten Commit-Frame, wie die Wiederherstellung von SQLite (`src/walhdr.py`, `wal_frames`).
2. Blattseiten der Tabelle `fix` samt Zellenzahl über `dbstat` an einer frischen Kopie (`src/waltest/bin/pagestat.dart`).
3. Gezählt wird ein Lauf nur, wenn die Blattseite mit den ältesten Zeilen unter keiner WAL-Seite steht, die Hauptdatei über 8192 Byte groß ist und die Hauptdatei **allein, ohne WAL** gelesen diese Zeilen und alle übrigen außerhalb der WAL-Seiten unverändert liefert.

Ausgeschlossene Läufe stehen mit ihrem Verlust in Tabelle 8b, Ausschluss ist kein Freispruch. Kontrollen der Prüfung: am Gerät gezogenes verschlüsseltes WAL mit `autock` 0 ergibt „nicht belegt“, ebenso eine Klartext-Datei mit `autock` 0; eine Klartext-Datei mit `autock` 10 ergibt „belegt“; dieselbe Datei mit genullter Seite 3 in der Hauptdatei ergibt „nicht belegt“. Vorprüfung je API: Der erste Lauf muss den Zustand zeigen, sonst bricht die Serie mit Exit 3 ab.

**Erwartung, vor der Messung festgelegt:** `FULL` kein Verlust. `NORMAL`: Verlust nur unter den Commits seit dem letzten Checkpoint, also höchstens etwa 10 Zeilen, keine Zeile der ältesten Blattseite. **Grenze der Kontrolle:** `NORMAL` trennt nur die Synchronisation beim Commit. Beim Rückschreiben in die Hauptdatei synchronisieren `NORMAL` und `FULL` gleich, dafür gibt es keine Kontrolle. Das Rückschreiben der ältesten Blattseite liegt beim Kill außerdem mindestens etwa 20 s zurück (gemessen: mindestens 39,5 s, in Tabelle 8b gerundet 40). Die Serie schließt deshalb nicht aus, dass der Gastkern die Seite ohnehin schon geschrieben hatte (Frist in `checkpoint2-vm.txt`): **Sie belegt das Überstehen, nicht die Nötigkeit der Checkpoint-Synchronisation.** Weiter ungeprüft: Checkpoints von 1000 Frames, Kill mitten im Checkpoint.

### Verschlüsseltes WAL
Auf dem Rechner (`src/waltest`, gleiche Paketversion) und im Emulator. Bekannter Marker und bekannter Double, `wal_autocheckpoint = 0`, Kopie von Datei und WAL vor dem Checkpoint, Suche nach den Bytes, Byteverteilung der Seiteninhalte (χ², 255 Freiheitsgrade). Positivkontrolle unverschlüsselt. Beleg, dass das WAL Inhalt hatte: Die Kopie ohne WAL hat keine Tabelle, mit WAL alle Zeilen. Jede Öffnung auf frischer Kopie, denn das Schließen der letzten Verbindung checkpointet.

### Lizenzen
`src/licenses.py`: `flutter pub deps --json` plus Lizenzdatei im Pub-Cache, `gradlew :app:dependencies` plus Lizenzen im POM (mit Eltern-POMs), native `.so` aus der APK, Klassen der APK mit `dexdump` gegengeprüft. Einschätzung ohne Rechtsprüfung.

## Daten
| Was | Wo | Herkunft / Lizenz | Größe | Wiederherstellbar |
| --- | --- | --- | --- | --- |
| Synthetische GPS-Spuren | `research/data/work/R005/*/*/inject.tsv` | selbst erzeugt, fester Seed | klein | ja, `./run.sh` |
| Rohdaten der Läufe, Auswertung | `research/data/work/R005/`, siehe [DATA.md](../DATA.md) | Prototyp, nur synthetisch | etwa 152 MB | ja, `./run.sh` |
| System-Images `android-31`, `android-36` (`google_apis;arm64-v8a`) | Android SDK, nicht `research/data/` | Google, Android-SDK-Lizenz | etwa 6 GB | ja, `./init.sh` |

Keine Sammlung aus `input/`.

## Ausführung
**Voraussetzungen:** macOS auf Apple Silicon, Flutter 3.47.7, Android SDK unter `~/Library/Android/sdk`, JDK über `R005_JAVA_HOME` (Standard: JBR aus Android Studio), etwa 8 GB frei. `init.sh` holt die aktuelle Image-Revision, gemessen wurden Revision 7 (API 36) und 11 (API 31); sie sind nicht festgestellt, eine Wiederholung kann also auf einem anderen Image laufen. Gemessen wird nur auf dem eigenen Emulator `emulator-5600`, fremde Emulatoren bleiben unberührt. Gesamtdauer aller Läufe etwa 8 h 40 min, dazu `vorlaeufe` und `checkpoint`; lokal, kein Rechenserver, weil der Emulator hier läuft.

```bash
./init.sh                 # Images, AVDs, APK, Pub-Abhaengigkeiten; ./init.sh --help
./run.sh --help
./run.sh wal-host         # unter 1 min
./run.sh licenses
./run.sh phase-a          # etwa 35 min
./run.sh matrix           # etwa 5,5 h, fortsetzbar ueber .done
./run.sh long             # 60 min
./run.sh rerun            # etwa 35 min
./run.sh vorlaeufe        # etwa 25 min, Laeufe aus der Anfangsphase
./run.sh checkpoint       # etwa 45 min (gemessen 41 min)
./run.sh checkpoint2      # etwa 75 min (gemessen 71 min), zweite Serie, Zustand je Lauf belegt
./run.sh report           # Tabellen und Auswertungen nach work/R005/report, etwa 40 s
```

Kleines Beispiel (etwa 3 min, Ablage woanders):

```bash
RESEARCH_DATA=/tmp/r005-probe ./run.sh emu-start --api 36
RESEARCH_DATA=/tmp/r005-probe ./run.sh gap --api 36 --host own --wake 1 --dur 30 --tag _readme
RESEARCH_DATA=/tmp/r005-probe ./run.sh emu-stop
```

`./run.sh <schritt>`, Schritte:

| Schritt | Bedeutung |
| --- | --- |
| `licenses` | Lizenzbaum (Dart, Gradle) nach `work/R005/licenses` |
| `wal-host` | Verschluesseltes WAL am Rechner, mit Kontrollen, FAQ-Fall, Schluesselwechsel, nach `work/R005/wal-host` |
| `emu-start` | Eigenen Emulator (`emulator-5600`) fuer `--api` starten und einrichten |
| `emu-stop` | Eigenen Emulator beenden |
| `gap` | Luecken-Lauf bei Sperre und force-idle nach `work/R005/gap` |
| `kill` | Kill-Lauf nach `work/R005/kill` |
| `swipe` | Wischen aus den letzten Apps nach `work/R005/swipe` |
| `wal` | Verschluesseltes WAL im Emulator, mit Positivkontrolle, nach `work/R005/wal-device` |
| `bench` | Schreibkosten FULL gegen NORMAL, tx 1, 5, 30, nach `work/R005/bench` |
| `phase-a` | Kontrollen und Proben auf API 36 (`src/phaseA.sh`), etwa 35 min |
| `matrix` | Lange Matrix (`src/matrix.sh`), API 36 und 31, etwa 5,5 h, fortsetzbar |
| `long` | Langlauf 60 min (`src/long.sh`), Dauer ueber `R005_LONG_DUR` in Sekunden |
| `rerun` | Wiederholungen API 31 und Abstandsprobe API 36 (`src/rerun.sh`), etwa 35 min |
| `vorlaeufe` | Einzelne fruehere Laeufe, die in keinem anderen Skript stehen (`src/vorlaeufe.sh`), etwa 25 min |
| `checkpoint` | Kill-Serie nach dem ersten Checkpoint (`src/checkpoint.sh`): 20 `sigkill`-Laeufe, `wal_autocheckpoint` 10, API 36 und 31, FULL und NORMAL, unter 1 h, fortsetzbar |
| `checkpoint2` | Zweite Kill-Serie (`src/checkpoint2.sh`): 20 `sigkill`-Laeufe, `wal_autocheckpoint` 10, Kill nach 90 bis 180 s, API 36 und 31, FULL und NORMAL, Zustand je Lauf belegt, etwa 75 min, fortsetzbar |
| `report` | Alle Auswertungen und Tabellen aus den Rohdaten nach `work/R005/report` |

Parameter für `gap`, `kill`, `swipe`, `wal`, `bench`, `emu-start`:

| Parameter | Standard | Bedeutung |
| --- | --- | --- |
| `--api N` | 36 | API-Stufe des Emulators, 31 oder 36 |
| `--host own\|ffgt\|none` | own | Host, siehe README |
| `--wake 0\|1` | 0 | eigener Partial Wake Lock |
| `--tx N` | 1 | Zeilen je Transaktion |
| `--sync FULL\|NORMAL` | FULL | `PRAGMA synchronous` |
| `--dur S` | 600 | Dauer der Sperr- und Idle-Phase bei gap, Laufdauer bei swipe und wal |
| `--rep N` | 1 | Wiederholungen je Zelle |
| `--seed N` | 42 | Seed der Spur bei gap (Wiederholung r: Seed + r) |
| `--kind proc\|emu\|sigkill` | proc | Art des Kills |
| `--minrun S` | 20 | Kill: kuerzeste Laufzeit davor |
| `--maxrun S` | 40 | Kill: laengste Laufzeit davor (bei tx 30: 35 und 65 verwenden) |
| `--natural 0\|1` | 0 | gap: `emulator_wake_lock` loesen (Eingriff in den Emulator) |
| `--force-at S` | 0 | gap: nach S Sekunden Suspend erzwingen, 0 = nie |
| `--pause-at S` | 0 | gap: Einspeisung ab S Sekunden der Phase aussetzen |
| `--pause-len S` | 0 | gap: Laenge der Pause, 0 = keine |
| `--stop-at S` | 0 | gap: Prozess ab S Sekunden der Phase per SIGSTOP anhalten |
| `--stop-len S` | 0 | gap: Laenge des Anhaltens, 0 = keins |
| `--inj-every S` | 1 | gap: Einspeisung alle S Sekunden |
| `--idle 0\|1` | 1 | gap: force-idle setzen |
| `--post S` | 30 | gap mit natural: Nachphase |
| `--quiet 0\|1` | 0 | gap: keine Abfragen per adb in der Phase |
| `--poll S` | 15 | gap: Abstand der Zustandsabfragen |
| `--sample S` | 0 | gap: Abstand der Ressourcenproben, 0 = keine |
| `--autock N` | ungesetzt | kill: `wal_autocheckpoint` setzen, ungesetzt = SQLite-Standard 1000 |
| `--n N` | 300 | bench: Transaktionen je Zelle |
| `--tag _x` | leer | Zusatz im Laufnamen |

Läufe mit `.done` werden übersprungen. Ausgaben: `$RESEARCH_DATA/work/R005/<art>/<lauf>/`, Laufname aus API, Host, Wake Lock, Dauer und Tag. Fehlgeschlagene Läufe sind nach `invalid/` verschoben und in RESULTS erklärt. Die Vorläufe stehen in `src/vorlaeufe.sh`.
