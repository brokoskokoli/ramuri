#!/bin/bash
# Fuehrt R005 aus. Alle Schritte und Parameter: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source src/emu-env.sh
usage() { cat <<'HELP'
Usage: ./run.sh <schritt> [Parameter]
Schritte:
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
Parameter fuer gap, kill, swipe, wal, bench, emu-start:
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
Laeufe mit .done werden uebersprungen. Ausgaben: $RESEARCH_DATA/work/R005/ . Andere Ablage: RESEARCH_DATA=<ordner> ./run.sh ...
HELP
}
STEP="${1:-}"; [ -n "$STEP" ] || { usage >&2; exit 2; }; shift || true
case " $* " in *" --help "*) usage; exit 0;; esac
[ "$STEP" = "--help" ] && { usage; exit 0; }
H="python3 src/harness.py"; [ -f "$R005_APK" ] || { echo "APK fehlt: erst ./init.sh" >&2; exit 2; }
case "$STEP" in phase-a|vorlaeufe) ;; *) export R005_EMU_EXTRA=-show-kernel;; esac   # Phase A und die Vorlaeufe auf API 31 liefen ohne -show-kernel, alles Weitere mit
mkdir -p "$R005_WORK"; (git rev-parse --short HEAD; flutter --version | head -1; uname -m; sysctl -n hw.ncpu; "$HOME/Library/Android/sdk/emulator/emulator" -version | head -1) > "$R005_WORK/run.info" 2>/dev/null || true
case "$STEP" in
  licenses) mkdir -p "$R005_WORK/licenses"; python3 src/licenses.py src/proto "$R005_WORK/licenses";;
  wal-host) mkdir -p "$R005_WORK/wal-host"; d="$R005_WORK/wal-host/$(date +%Y%m%d-%H%M%S)"; (cd src/waltest; dart run bin/waltest.dart "$d") | tee "$d.log";;
  emu-start) $H boot "$@";;
  emu-stop)  $H kill-emu;;
  gap|kill|swipe|wal|bench) $H "$STEP" "$@";;
  phase-a) src/phaseA.sh;;
  matrix) src/matrix.sh;;
  long) src/long.sh;;
  rerun) src/rerun.sh;;
  vorlaeufe) src/vorlaeufe.sh;;
  checkpoint) src/checkpoint.sh;;
  checkpoint2) src/checkpoint2.sh;;
  report)
    r="$R005_WORK/report"; mkdir -p "$r"
    for k in gap kill swipe wal bench; do python3 src/analyze.py $k "$R005_WORK" > "$r/analyze-$k.out"; done
    python3 src/longrun.py "$R005_WORK/gap/a36_own_w1_i1_3600s_natlong_r0" > "$r/longrun.out"
    python3 src/abstand.py "$R005_WORK"/gap/a36_own_w0_i1_240s_abst_*_r0 "$R005_WORK"/gap/a36_own_w0_i1_600s_r0 "$R005_WORK"/gap/a31_own_w0_i1_600s_r0 "$R005_WORK"/gap/a36_none_w0_i1_600s_r0 "$R005_WORK"/gap/a36_none_w0_i1_120s_ctl_r0 > "$r/abstand.out"
    python3 src/tables.py "$R005_WORK" | tee "$r/tables.md";;
  *) usage >&2; exit 2;;
esac
