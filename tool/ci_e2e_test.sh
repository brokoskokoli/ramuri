#!/bin/sh
# Test fuer tool/ci_e2e.sh mit Attrappen fuer adb und flutter (kein Emulator): Shard-Zuordnung,
# unbekannte Namen, Mindeststufen, Waechter ueber all_test.dart, Rot einer Stufe, NEED_KILL, kein E2E_ im Log,
# letzte Schrittmarke vor dem Fehler, Bildschirmfotos bei SHOT-Marken (E2E_SHOTS=1), Zeitlimit je Stufe
# (E2E_STUFE_LIMIT_S, haengende Attrappe), Zeitlimit je adb-Aufruf (E2E_ADB_LIMIT_S, haengende adb-Attrappe),
# Warten auf den Tageswechsel ausserhalb des Zeitlimits (Uhr der Attrappe per FAKE_UHR, Warteliste mit Waechter),
# Zeile "geo fix fehlgeschlagen: <n> von <m>" je Stufe (FAKE_GEO_FAIL).
# Takt der Warteschleife (E2E_TAKT_S) und Wartezeiten der Attrappen (FAKE_*_S) sind verkuerzt, damit der Test schnell bleibt.
# Aufruf: sh tool/ci_e2e_test.sh
script=$(cd "$(dirname "$0")" && pwd)/ci_e2e.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/w/app/integration_test"
cd "$tmp/w" || exit 1
for f in e2e_a_test.dart e2e_storage_test.dart e2e_recover_test.dart e2e_m2_flow_test.dart; do : > "app/integration_test/$f"; done
printf "import 'e2e_a_test.dart';\n" > app/integration_test/all_test.dart
# adb: Rechte gewaehrt, sonst leer. Haengen (Aufruf enthaelt $FAKE_ADB_HANG): PID in $FAKE_PIDS, 40 s schlafen;
# mit FAKE_ADB_HANG_EINMAL=<datei> nur beim ersten passenden Aufruf (Markerdatei).
cat > "$tmp/bin/adb" <<'X'
#!/bin/sh
case "${FAKE_ADB_HANG:+$*}" in *"${FAKE_ADB_HANG:-}"*) [ -z "${FAKE_ADB_HANG:-}" ] ||
  if [ -z "${FAKE_ADB_HANG_EINMAL:-}" ] || ! [ -e "$FAKE_ADB_HANG_EINMAL" ]; then
    [ -z "${FAKE_ADB_HANG_EINMAL:-}" ] || : > "$FAKE_ADB_HANG_EINMAL"
    echo "$$" >> "$FAKE_PIDS"; exec sleep 40
  fi ;;
esac
# Uhr: mit FAKE_UHR=<HH:MM:SS> antwortet "shell date" mit dieser Zeit und stellt sie je Aufruf um
# FAKE_UHR_SCHRITT_S vor (Zustand in $FAKE_UHR_DATEI); ohne FAKE_UHR keine Antwort (Uhr nicht lesbar).
case "$*" in *"shell date +%H:%M:%S"*)
  [ -n "${FAKE_UHR:-}" ] || exit 0
  [ -s "$FAKE_UHR_DATEI" ] || { IFS=: read -r h m s <<E
$FAKE_UHR
E
    echo $(((${h#0} * 3600 + ${m#0} * 60 + ${s#0}))) > "$FAKE_UHR_DATEI"; }
  t=$(cat "$FAKE_UHR_DATEI")
  echo $(((t + ${FAKE_UHR_SCHRITT_S:-0}) % 86400)) > "$FAKE_UHR_DATEI"
  printf '%02d:%02d:%02d\r\n' $((t / 3600)) $((t / 60 % 60)) $((t % 60))
  exit 0 ;;
esac
case "$*" in
  *"dumpsys package"*) echo 'android.permission.ACCESS_FINE_LOCATION: granted=true' ;;
  *"dumpsys window"*) [ -n "${FAKE_NOFOCUS:-}" ] || echo 'mCurrentFocus=Window{x u0 io.github.brokoskokoli.ramuri/.MainActivity}' ;;
  *screencap*) echo x >> "$FAKE_SHOTS"; echo PNG ;;
  *"am force-stop"*) echo x >> "$FAKE_STOPS" ;;
  # GPS-Zufuehrer: mit FAKE_GEO_FAIL schlaegt jeder Aufruf fehl.
  *"emu geo fix"*) [ -z "${FAKE_GEO_FAIL:-}" ] || exit 1 ;;
esac
exit 0
X
# flutter: schreibt die Testdatei in $FAKE_LOG; Stufen mit Prozessende melden NEED_KILL (E2E_-Zeile).
cat > "$tmp/bin/flutter" <<'X'
#!/bin/sh
for a in "$@"; do case "$a" in integration_test/*) echo "$a" >> "$FAKE_LOG" ;; esac; done
echo "$*" >> "$FAKE_ARGS"
echo "E2E_WERT=geheim123"
[ -z "${FAKE_E:-}" ] || echo "00:01 +0 -1: Archiv [E]"
[ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_LAUF_S"
# SHOT-Marken wie shot() in e2e_support.dart: Zeile E2E_, danach steht der Test (hier FAKE_SHOT_S).
[ -z "${FAKE_SHOT_LINES:-}" ] || for n in s1_hell 'Gross' '../boese' 'a b' s1-dunkel_2; do
  echo "E2E_12:00:00.000 SHOT $n"; sleep "$FAKE_SHOT_S"; done
# Warten auf den Tageswechsel im Test (waitPastLateEvening): Zeilen wie logPub, dazwischen FAKE_TW_S.
[ -z "${FAKE_TAGESWECHSEL:-}" ] || { echo "PUB_23:45:00.000 TAGESWECHSEL warten"; sleep "$FAKE_TW_S"; echo "PUB_00:00:00.000 TAGESWECHSEL ende"; }
case "$*" in *PHASE=write* | *PHASE=a*) [ -n "${FAKE_NOKILL:-}" ] || { echo "E2E_X NEED_KILL"; sleep "$FAKE_KILL_S"; } ;; esac
[ -z "${FAKE_STEPS:-}" ] || { echo "PUB_00 SCHRITT A1 start"; echo "PUB_01 SCHRITT A1 rot"; echo "00:02 +0 -1: A [E]"; echo "PUB_02 SCHRITT B1 start"; }
[ -z "${FAKE_FAIL:-}" ] || { echo "PUB_01 M2 form_error key=planFormErrorStand"; i=0; while [ $i -lt 60 ]; do echo "zeile $i"; i=$((i + 1)); done; echo "Expected: x"; exit 1; }
# Haengen (Aufruf enthaelt $FAKE_HANG): Kindprozess sleep, beide PIDs in $FAKE_PIDS; endet sonst nach 40 s gruen.
case "${FAKE_HANG:+$*}" in *"${FAKE_HANG:-}"*) [ -z "${FAKE_HANG:-}" ] || {
  echo "$$" >> "$FAKE_PIDS"; sleep 40 & echo "$!" >> "$FAKE_PIDS"; wait; } ;; esac
exit 0
X
chmod +x "$tmp/bin/adb" "$tmp/bin/flutter"
# Wartezeiten der Attrappen und Takt der Warteschleife in ci_e2e.sh (E2E_TAKT_S, sonst 2 s), auf einen Bruchteil
# verkuerzt; die Zeitlimits unten sind darauf abgestimmt. FAKE_LAUF_S: Lauf mit FAKE_SLEEP; FAKE_SHOT_S: Pause nach
# jeder SHOT-Zeile; FAKE_TW_S: Tageswechsel im Test; FAKE_KILL_S: Pause nach NEED_KILL (laenger als ein Takt, damit
# der Host die Marke vor dem Prozessende sieht).
export E2E_TAKT_S=0.1 FAKE_LAUF_S=1 FAKE_SHOT_S=0.3 FAKE_TW_S=3 FAKE_KILL_S=0.5
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/calls" FAKE_SHOTS="$tmp/shots" FAKE_ARGS="$tmp/args" FAKE_STOPS="$tmp/stops" \
  FAKE_PIDS="$tmp/pids" FAKE_UHR_DATEI="$tmp/uhr" ANDROID_SERIAL=emulator-5554
unset E2E_SHARD E2E_STUFEN E2E_SHOTS E2E_STUFE_LIMIT_S E2E_ADB_LIMIT_S FAKE_ADB_HANG FAKE_ADB_HANG_EINMAL FAKE_NOKILL FAKE_FAIL FAKE_E FAKE_SLEEP FAKE_STEPS FAKE_SHOT_LINES \
  FAKE_NOFOCUS FAKE_HANG FAKE_UHR FAKE_UHR_SCHRITT_S FAKE_TAGESWECHSEL E2E_UHR_VERSATZ_S FAKE_GEO_FAIL
fails=0
# run <Name> <rc> <Aufrufe-der-Testdateien (Anzahl)> [VAR=Wert ...]
run() {
  name=$1 want_rc=$2 want_calls=$3; shift 3
  : > "$FAKE_LOG"; : > "$FAKE_ARGS"; : > "$FAKE_STOPS"; : > "$FAKE_PIDS"; : > "$FAKE_UHR_DATEI"; rm -rf "$tmp/out"
  t_start=$(date +%s)
  env "$@" sh "$script" "$tmp/out" > "$tmp/stdout" 2>&1; rc=$?
  dauer=$(($(date +%s) - t_start))
  calls=$(wc -l < "$FAKE_LOG" | tr -d ' ')
  if [ "$rc" -eq "$want_rc" ] && [ "$calls" -eq "$want_calls" ]; then echo "OK   $name"; else
    echo "FAIL $name (rc=$rc erwartet $want_rc, Stufen $calls erwartet $want_calls)"; fails=$((fails + 1)); fi
}
run "Shard sammlung: all_test und treadmill-plan" 0 2 E2E_SHARD=sammlung
grep -qx 'integration_test/all_test.dart' "$FAKE_LOG" || { echo "FAIL Shard sammlung: all_test fehlt"; fails=$((fails + 1)); }
grep -qx 'integration_test/e2e_treadmill_test.dart' "$FAKE_LOG" || { echo "FAIL Shard sammlung: treadmill-plan fehlt"; fails=$((fails + 1)); }
run "Shard stufen: Mehrphasen-Stufen, m2-flow, readiness, plan-adapt, m3-flow und sport-plan" 0 9 E2E_SHARD=stufen
grep -qx 'integration_test/e2e_m3_flow_test.dart' "$FAKE_LOG" || { echo "FAIL Shard stufen: m3-flow fehlt"; fails=$((fails + 1)); }
grep -q all_test "$FAKE_LOG" && { echo "FAIL Shard stufen fuehrt all_test aus"; fails=$((fails + 1)); }
run "ohne Auswahl: alle elf Stufen"           0 11 X=1
run "Shard unbekannt (Tippfehler) -> Fehler"   1 0 E2E_SHARD=sammlungx
run "Stufe unbekannt -> Fehler"                1 0 E2E_STUFEN=recover-x
run "eine bekannte, eine unbekannte -> Fehler" 1 0 "E2E_STUFEN=sammlung recover-x"
run "Shard und Stufen zusammen -> Fehler"      1 0 E2E_SHARD=stufen E2E_STUFEN=sammlung
run "lokal einzelne Stufe"                     0 1 E2E_STUFEN=recover-a
# Gruener Lauf mit Standard-adb-Limit (60 s) wartet nicht auf das Limit.
[ "$dauer" -lt 30 ] && echo "OK   gruener Lauf ohne Warten auf das adb-Limit" || { echo "FAIL gruener Lauf dauerte $dauer s"; fails=$((fails + 1)); }
grep -q 'adb-Zeitlimit' "$tmp/stdout" && { echo "FAIL adb-Zeitlimit ohne Haengen gemeldet"; fails=$((fails + 1)); }
run "Stufe m2-flow: eigene Datei, nicht all_test" 0 1 E2E_STUFEN=m2-flow
grep -qx 'integration_test/e2e_m2_flow_test.dart' "$FAKE_LOG" || { echo "FAIL m2-flow: falsche Datei"; fails=$((fails + 1)); }
run "Stufe readiness: eigene Datei, nicht all_test" 0 1 E2E_STUFEN=readiness
grep -qx 'integration_test/e2e_readiness_test.dart' "$FAKE_LOG" || { echo "FAIL readiness: falsche Datei"; fails=$((fails + 1)); }
run "Stufe plan-adapt: eigene Datei, nicht all_test" 0 1 E2E_STUFEN=plan-adapt
grep -qx 'integration_test/e2e_plan_adapt_test.dart' "$FAKE_LOG" || { echo "FAIL plan-adapt: falsche Datei"; fails=$((fails + 1)); }
run "Stufe m3-flow: eigene Datei, nicht all_test" 0 1 E2E_STUFEN=m3-flow
grep -qx 'integration_test/e2e_m3_flow_test.dart' "$FAKE_LOG" || { echo "FAIL m3-flow: falsche Datei"; fails=$((fails + 1)); }
run "Stufe treadmill-plan: Laufband-Datei mit Schalter" 0 1 E2E_STUFEN=treadmill-plan
grep -qx 'integration_test/e2e_treadmill_test.dart' "$FAKE_LOG" || { echo "FAIL treadmill-plan: falsche Datei"; fails=$((fails + 1)); }
grep -q 'TREADMILL_PLAN=true' "$FAKE_ARGS" || { echo "FAIL treadmill-plan: Schalter fehlt"; fails=$((fails + 1)); }
run "Stufe sport-plan: Sport-Datei mit Schalter" 0 1 E2E_STUFEN=sport-plan
grep -qx 'integration_test/e2e_other_sport_test.dart' "$FAKE_LOG" || { echo "FAIL sport-plan: falsche Datei"; fails=$((fails + 1)); }
grep -q 'SPORT_PLAN=true' "$FAKE_ARGS" || { echo "FAIL sport-plan: Schalter fehlt"; fails=$((fails + 1)); }
run "leere Auswahl: keine Stufe gelaufen"      1 0 "E2E_STUFEN= "
# Waechter: eine Stufe in keinem Shard (Kopie des Skripts mit einer zusaetzlichen Stufe) ist ein Fehler vor dem ersten Lauf.
sed 's|^\[ "\$ran" -gt 0 \]|stufe neu 0 integration_test/e2e_a_test.dart\n&|' "$script" > "$tmp/ci_e2e_neu.sh"
grep -q '^stufe neu 0' "$tmp/ci_e2e_neu.sh" || { echo "FAIL Aufbau: Kopie ohne neue Stufe"; fails=$((fails + 1)); }
script_orig=$script; script="$tmp/ci_e2e_neu.sh"
run "Stufe ohne Shard -> Fehler vor dem Lauf" 1 0 X=1
grep -q 'Stufe neu steht in keinem Shard' "$tmp/stdout" || { echo "FAIL Waechter: Meldung fehlt"; fails=$((fails + 1)); }
script=$script_orig
run "Stufe rot -> Exit 1"                      1 1 E2E_STUFEN=sammlung FAKE_FAIL=1
grep -q 'E2E_\|geheim123' "$tmp/stdout" && { echo "FAIL E2E_-Zeile in der Ausgabe"; fails=$((fails + 1)); } || echo "OK   keine E2E_-Zeile in der Ausgabe"
grep -rq 'E2E_\|geheim123' "$tmp/out" && { echo "FAIL E2E_-Zeile im Artefakt"; fails=$((fails + 1)); } || echo "OK   keine E2E_-Zeile im Artefakt"
grep -q 'PUB_01 M2 form_error key=planFormErrorStand' "$tmp/stdout" && echo "OK   PUB_-Zeile (Marker ohne Werte) im Log trotz langer Ausgabe" || { echo "FAIL PUB_-Zeile fehlt im Log"; fails=$((fails + 1)); }
[ -f "$tmp/out/test-output-sammlung.txt" ] || { echo "FAIL kein Testlog im Artefakt"; fails=$((fails + 1)); }
# Letzte Schrittmarke vor dem ersten [E] im Fehlerabschnitt, nicht die eines spaeteren Tests der Sammlung.
run "Stufe rot mit Schrittmarken"              1 1 E2E_STUFEN=sammlung FAKE_FAIL=1 FAKE_STEPS=1
sed -n '/^--- Schritte Stufe sammlung ---$/,/^--- Fehlermeldung/p' "$tmp/stdout" | grep -c ' SCHRITT ' | grep -qx 3 && echo "OK   alle Schrittmarken der Stufe im Log" || { echo "FAIL Schrittmarken der Stufe fehlen im Log"; fails=$((fails + 1)); }
sed -n '/^--- Fehlermeldung Stufe sammlung ---$/,$p' "$tmp/stdout" | grep -qx 'letzter Schritt vor dem Fehler: PUB_01 SCHRITT A1 rot' && echo "OK   letzter Schritt vor dem Fehler im Fehlerabschnitt" || { echo "FAIL letzter Schritt vor dem Fehler fehlt"; fails=$((fails + 1)); }
run "Stufe rot ohne Schrittmarken"             1 1 E2E_STUFEN=sammlung FAKE_FAIL=1
grep -qx 'letzter Schritt vor dem Fehler: keiner' "$tmp/stdout" && echo "OK   ohne Marke: keiner" || { echo "FAIL ohne Marke: Meldung fehlt"; fails=$((fails + 1)); }
run "Prozessende ohne NEED_KILL -> Exit 1"     1 1 E2E_STUFEN=storage-a FAKE_NOKILL=1
# Foto: laeuft die Stufe weiter, kommen Fotos; nach dem ersten "[E]" kein neues mehr.
: > "$tmp/shots"; run "Foto: ohne Fehler laufend aktualisiert" 0 1 E2E_STUFEN=sammlung FAKE_SLEEP=1
[ "$(wc -l < "$tmp/shots" | tr -d ' ')" -ge 2 ] || { echo "FAIL Foto: keine laufenden Fotos"; fails=$((fails + 1)); }
: > "$tmp/shots"; run "Foto: nach [E] eingefroren" 1 1 E2E_STUFEN=sammlung FAKE_SLEEP=1 FAKE_E=1 FAKE_FAIL=1
[ "$(wc -l < "$tmp/shots" | tr -d ' ')" -le 1 ] || { echo "FAIL Foto: nach [E] weitere Fotos"; fails=$((fails + 1)); }
# Bildschirmfotos (E2E_SHOTS=1): je gueltige SHOT-Zeile genau ein screencap mit <stufe>-<name>.png, ungueltige Namen
# (Grossbuchstaben, Pfad, Leerzeichen) ohne Foto. FAKE_NOFOCUS: kein laufendes Fehlerfoto, jedes screencap ist ein SHOT-Foto.
: > "$tmp/shots"; run "Fotos: Schalter an, zwei Stufen" 0 2 "E2E_STUFEN=sammlung readiness" E2E_SHOTS=1 FAKE_SHOT_LINES=1 FAKE_NOFOCUS=1
[ "$(grep -c -- '--dart-define=E2E_SHOTS=true' "$FAKE_ARGS")" -eq 2 ] && echo "OK   Fotos: E2E_SHOTS an jede Stufe" || { echo "FAIL Fotos: E2E_SHOTS nicht an jede Stufe"; fails=$((fails + 1)); }
[ "$(wc -l < "$tmp/shots" | tr -d ' ')" -eq 4 ] && echo "OK   Fotos: je gueltige SHOT-Zeile ein screencap" || { echo "FAIL Fotos: $(wc -l < "$tmp/shots" | tr -d ' ') screencap statt 4"; fails=$((fails + 1)); }
want="readiness-s1-dunkel_2.png readiness-s1_hell.png sammlung-s1-dunkel_2.png sammlung-s1_hell.png"
got=$(cd "$tmp/out/shots" 2>/dev/null && ls | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$want" ] && echo "OK   Fotos: Dateinamen <stufe>-<name>.png, ungueltige verworfen" || { echo "FAIL Fotos: Dateien '$got' statt '$want'"; fails=$((fails + 1)); }
[ "$(cat "$tmp/out/shots/sammlung-s1_hell.png" 2>/dev/null)" = PNG ] || { echo "FAIL Fotos: Inhalt nicht von screencap"; fails=$((fails + 1)); }
[ "$(grep -c 'SHOT-Marke verworfen' "$tmp/stdout")" -eq 6 ] || { echo "FAIL Fotos: Meldung fuer verworfene Namen fehlt"; fails=$((fails + 1)); }
grep -qx 'FOTOS Stufe sammlung: 2' "$tmp/stdout" || { echo "FAIL Fotos: Anzahl je Stufe fehlt"; fails=$((fails + 1)); }
grep -v 'SHOT-Marke verworfen' "$tmp/stdout" | grep -q 'SHOT \|boese' && { echo "FAIL Fotos: SHOT-Zeile im Log"; fails=$((fails + 1)); }
: > "$tmp/shots"; run "Fotos: ohne Schalter" 0 2 "E2E_STUFEN=sammlung readiness" FAKE_SHOT_LINES=1 FAKE_NOFOCUS=1
grep -q 'E2E_SHOTS' "$FAKE_ARGS" && { echo "FAIL ohne Schalter: E2E_SHOTS weitergereicht"; fails=$((fails + 1)); } || echo "OK   ohne Schalter kein E2E_SHOTS"
[ -s "$tmp/shots" ] || [ -e "$tmp/out/shots" ] && { echo "FAIL ohne Schalter: Fotos"; fails=$((fails + 1)); } || echo "OK   ohne Schalter kein Foto"
run "Fotos: Schalter mit anderem Wert -> Fehler" 1 0 E2E_STUFEN=sammlung E2E_SHOTS=ja
# Zeitlimit je Stufe: haengende Attrappe (FAKE_HANG = Teil des Aufrufs), Grenze 2 s.
# zeitlimit_ok <stufe>: Meldung, Ende nach weniger als 30 s, kein Attrappen-Prozess mehr, kein E2E_ in Ausgabe und Artefakt.
zeitlimit_ok() {
  grep -q "^Zeitlimit in Stufe $1 nach [0-9]* s$" "$tmp/stdout" || { echo "FAIL Zeitlimit $1: Meldung fehlt"; fails=$((fails + 1)); }
  [ "$dauer" -lt 30 ] || { echo "FAIL Zeitlimit $1: Skript lief $dauer s"; fails=$((fails + 1)); }
  [ -s "$FAKE_PIDS" ] || { echo "FAIL Zeitlimit $1: Attrappe hing nicht"; fails=$((fails + 1)); }
  for p in $(cat "$FAKE_PIDS"); do kill -0 "$p" 2>/dev/null && { echo "FAIL Zeitlimit $1: Attrappen-Prozess $p laeuft noch"; fails=$((fails + 1)); kill -9 "$p"; }; done
  grep -q 'E2E_\|geheim123' "$tmp/stdout" && { echo "FAIL Zeitlimit $1: E2E_-Zeile in der Ausgabe"; fails=$((fails + 1)); }
  grep -rq 'E2E_\|geheim123' "$tmp/out" && { echo "FAIL Zeitlimit $1: E2E_-Zeile im Artefakt"; fails=$((fails + 1)); }
  [ -f "$tmp/out/test-output-$1.txt" ] || { echo "FAIL Zeitlimit $1: kein Testlog im Artefakt"; fails=$((fails + 1)); }
}
run "Zeitlimit: sammlung haengt -> Exit 1"     1 1 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=2 FAKE_HANG=all_test
zeitlimit_ok sammlung
grep -q '^STUFE sammlung rc=1 ' "$tmp/stdout" || { echo "FAIL Zeitlimit: STUFE-Zeile mit rc=1 fehlt"; fails=$((fails + 1)); }
[ -f "$tmp/out/screen-sammlung.png" ] || { echo "FAIL Zeitlimit: letztes Foto fehlt"; fails=$((fails + 1)); }
[ -f "$tmp/out/logcat-filtered.txt" ] || { echo "FAIL Zeitlimit: Logcat fehlt"; fails=$((fails + 1)); }
[ "$(wc -l < "$FAKE_STOPS" | tr -d ' ')" -eq 1 ] || { echo "FAIL Zeitlimit: kein am force-stop"; fails=$((fails + 1)); }
run "Zeitlimit: Kill-Stufe ohne NEED_KILL haengt" 1 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=2 FAKE_NOKILL=1 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
# Nach NEED_KILL haengt die Attrappe erst nach FAKE_KILL_S (0,5 s): Grenze 2 s (fruehestens nach 1 s Wanduhr), sonst
# greift sie mitunter vorher (Wettlauf, dann hing die Attrappe nie).
run "Zeitlimit: haengt nach NEED_KILL -> Exit 1" 1 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=2 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
grep -q '^STUFE recover-a rc=1 ' "$tmp/stdout" || { echo "FAIL Zeitlimit nach NEED_KILL: STUFE-Zeile mit rc=1 fehlt"; fails=$((fails + 1)); }
run "Zeitlimit: Folgestufe laeuft weiter"      1 2 "E2E_STUFEN=recover-a recover-b" E2E_STUFE_LIMIT_S=2 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
grep -q '^STUFE recover-b rc=0 ' "$tmp/stdout" || { echo "FAIL Zeitlimit: recover-b nicht gruen gelaufen"; fails=$((fails + 1)); }
run "Zeitlimit: Wert abc -> Fehler"            1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=abc
grep -q 'E2E_STUFE_LIMIT_S keine positive ganze Zahl' "$tmp/stdout" || { echo "FAIL Zeitlimit abc: Meldung fehlt"; fails=$((fails + 1)); }
run "Zeitlimit: Wert 0 -> Fehler"              1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=0
run "Zeitlimit: Wert -5 -> Fehler"             1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=-5
[ -s "$FAKE_ARGS" ] && { echo "FAIL Zeitlimit: flutter trotz ungueltigem Wert aufgerufen"; fails=$((fails + 1)); }
run "Zeitlimit: grosse Grenze, Stufe gruen"    0 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=600
grep -q 'Zeitlimit in Stufe' "$tmp/stdout" && { echo "FAIL Zeitlimit: Meldung ohne Ueberschreitung"; fails=$((fails + 1)); }
# Zeitlimit je adb-Aufruf: haengende adb-Attrappe (FAKE_ADB_HANG), adb-Limit 1 s; zeitlimit_ok prueft auch die
# adb-PIDs in $FAKE_PIDS. adb_ok <unterbefehl>: Meldung mit nur dem Unterbefehl, ohne weitere Argumente.
adb_ok() {
  grep -qx "adb-Zeitlimit nach 1 s: $1" "$tmp/stdout" || { echo "FAIL adb-Zeitlimit $1: Meldung fehlt"; fails=$((fails + 1)); }
}
run "adb-Zeitlimit: dumpsys window haengt"     1 1 E2E_STUFEN=sammlung "FAKE_ADB_HANG=dumpsys window" FAKE_HANG=all_test E2E_STUFE_LIMIT_S=2 E2E_ADB_LIMIT_S=1
zeitlimit_ok sammlung
adb_ok shell
run "adb-Zeitlimit: screencap haengt"          1 1 E2E_STUFEN=sammlung FAKE_ADB_HANG=screencap FAKE_HANG=all_test E2E_STUFE_LIMIT_S=2 E2E_ADB_LIMIT_S=1
zeitlimit_ok sammlung
adb_ok exec-out
run "adb-Zeitlimit: logcat -d im Rot-Zweig haengt" 1 1 E2E_STUFEN=sammlung "FAKE_ADB_HANG=logcat -d" FAKE_FAIL=1 E2E_ADB_LIMIT_S=1
adb_ok logcat
[ "$dauer" -lt 30 ] || { echo "FAIL adb-Zeitlimit logcat: Skript lief $dauer s"; fails=$((fails + 1)); }
[ -f "$tmp/out/test-output-sammlung.txt" ] || { echo "FAIL adb-Zeitlimit logcat: kein Testlog im Artefakt"; fails=$((fails + 1)); }
[ -s "$FAKE_PIDS" ] || { echo "FAIL adb-Zeitlimit logcat: Attrappe hing nicht"; fails=$((fails + 1)); }
for p in $(cat "$FAKE_PIDS"); do kill -0 "$p" 2>/dev/null && { echo "FAIL adb-Zeitlimit logcat: Prozess $p laeuft noch"; fails=$((fails + 1)); kill -9 "$p"; }; done
grep -q 'E2E_\|geheim123' "$tmp/stdout" && { echo "FAIL adb-Zeitlimit logcat: E2E_-Zeile in der Ausgabe"; fails=$((fails + 1)); }
grep -rq 'E2E_\|geheim123' "$tmp/out" && { echo "FAIL adb-Zeitlimit logcat: E2E_-Zeile im Artefakt"; fails=$((fails + 1)); }
rm -f "$tmp/hang-einmal"
run "adb-Zeitlimit: Folgestufe laeuft weiter"  1 2 "E2E_STUFEN=recover-a recover-b" "FAKE_ADB_HANG=dumpsys window" FAKE_ADB_HANG_EINMAL="$tmp/hang-einmal" FAKE_HANG=PHASE=a E2E_STUFE_LIMIT_S=2 E2E_ADB_LIMIT_S=1
zeitlimit_ok recover-a
adb_ok shell
grep -q '^STUFE recover-b rc=0 ' "$tmp/stdout" || { echo "FAIL adb-Zeitlimit: recover-b nicht gruen gelaufen"; fails=$((fails + 1)); }
: > "$FAKE_ARGS"
run "adb-Zeitlimit: Wert abc -> Fehler"        1 0 E2E_STUFEN=sammlung E2E_ADB_LIMIT_S=abc
grep -q 'E2E_ADB_LIMIT_S keine positive ganze Zahl' "$tmp/stdout" || { echo "FAIL adb-Zeitlimit abc: Meldung fehlt"; fails=$((fails + 1)); }
run "adb-Zeitlimit: Wert 0 -> Fehler"          1 0 E2E_STUFEN=sammlung E2E_ADB_LIMIT_S=0
run "adb-Zeitlimit: Wert -5 -> Fehler"         1 0 E2E_STUFEN=sammlung E2E_ADB_LIMIT_S=-5
[ -s "$FAKE_ARGS" ] && { echo "FAIL adb-Zeitlimit: flutter trotz ungueltigem Wert aufgerufen"; fails=$((fails + 1)); }
run "adb-Zeitlimit: leer wie nicht gesetzt"    0 1 E2E_STUFEN=recover-a E2E_ADB_LIMIT_S=
# Takt der Warteschleife (E2E_TAKT_S, oben 0.1): ungueltige Werte sind ein Fehler vor der ersten Stufe; leer = 2 s.
: > "$FAKE_ARGS"
run "Takt: Wert abc -> Fehler"                 1 0 E2E_STUFEN=sammlung E2E_TAKT_S=abc
grep -q 'E2E_TAKT_S keine positive Zahl' "$tmp/stdout" || { echo "FAIL Takt abc: Meldung fehlt"; fails=$((fails + 1)); }
run "Takt: Wert 0 -> Fehler"                   1 0 E2E_STUFEN=sammlung E2E_TAKT_S=0
run "Takt: Wert 0.0 -> Fehler"                 1 0 E2E_STUFEN=sammlung E2E_TAKT_S=0.0
run "Takt: Wert -1 -> Fehler"                  1 0 E2E_STUFEN=sammlung E2E_TAKT_S=-1
run "Takt: Wert 1. -> Fehler"                  1 0 E2E_STUFEN=sammlung E2E_TAKT_S=1.
[ -s "$FAKE_ARGS" ] && { echo "FAIL Takt: flutter trotz ungueltigem Wert aufgerufen"; fails=$((fails + 1)); }
# Vorgabe 2 s ohne Wanduhr: Lauf 1 s (FAKE_SLEEP), Fokus vorhanden -> bei 2 s Takt genau ein Foto, bei kuerzerem mehrere.
: > "$tmp/shots"; run "Takt: leer wie nicht gesetzt (2 s)" 0 1 E2E_STUFEN=sammlung E2E_TAKT_S= FAKE_SLEEP=1
n_takt=$(wc -l < "$tmp/shots" | tr -d ' ')
[ "$n_takt" -eq 1 ] && echo "OK   Takt leer: genau ein Foto (2 s)" || { echo "FAIL Takt leer: $n_takt Fotos statt 1 (Vorgabe nicht 2 s)"; fails=$((fails + 1)); }
# Waechter: eine Stufe im Shard ohne Zeitlimit in grenze_s ist ein Fehler vor dem ersten Lauf.
sed 's|^shard_sammlung="sammlung |&neu |; s|^\[ "\$ran" -gt 0 \]|stufe neu 0 integration_test/e2e_a_test.dart\n&|' "$script" > "$tmp/ci_e2e_neu.sh"
script="$tmp/ci_e2e_neu.sh"
run "Stufe ohne Zeitlimit -> Fehler vor dem Lauf" 1 0 X=1
grep -q 'Stufe neu hat kein Zeitlimit' "$tmp/stdout" || { echo "FAIL Waechter Zeitlimit: Meldung fehlt"; fails=$((fails + 1)); }
script=$script_orig
# Tageswechsel: Die Emulatoruhr der Attrappe laeuft je Abfrage 150 s vor (Abfragen 23:50, 23:52:30, 23:55, 23:57:30,
# 00:00, je 1 s Pause im Host, also ca. 3 s Warten); die Attrappe von flutter laeuft FAKE_LAUF_S (1 s, FAKE_SLEEP),
# Grenze 3 s. Zaehlte das Warten mit, laege die Stufe bei mindestens 4 s und waere rot.
run "Tageswechsel: Start 23:50, m2-flow wartet, Limit gehalten" 0 1 E2E_STUFEN=m2-flow FAKE_UHR=23:50:00 FAKE_UHR_SCHRITT_S=150 FAKE_SLEEP=1 E2E_STUFE_LIMIT_S=3
grep -q '^STUFE m2-flow wartet auf Tageswechsel [0-9]* s$' "$tmp/stdout" && echo "OK   Tageswechsel: Wartezeile ohne Werte" || { echo "FAIL Tageswechsel: Wartezeile fehlt"; fails=$((fails + 1)); }
gew=$(sed -n 's/^STUFE m2-flow wartet auf Tageswechsel \([0-9]*\) s$/\1/p' "$tmp/stdout")
[ "${gew:-0}" -ge 3 ] && [ "$dauer" -ge 4 ] && echo "OK   Tageswechsel: wirklich gewartet ($gew s)" || { echo "FAIL Tageswechsel: gewartet '${gew:-}' s, Lauf $dauer s"; fails=$((fails + 1)); }
grep -q 'Zeitlimit in Stufe' "$tmp/stdout" && { echo "FAIL Tageswechsel: Warten zaehlte gegen das Zeitlimit"; fails=$((fails + 1)); }
grep -q '^STUFE m2-flow rc=0 dauer=[0-2]s$' "$tmp/stdout" && echo "OK   Tageswechsel: Dauer der Stufe ohne Warten" || { echo "FAIL Tageswechsel: Dauer der Stufe enthaelt das Warten"; fails=$((fails + 1)); }
run "Tageswechsel: Start 23:50, treadmill-plan wartet" 0 1 E2E_STUFEN=treadmill-plan FAKE_UHR=23:50:00 FAKE_UHR_SCHRITT_S=300
grep -q '^STUFE treadmill-plan wartet auf Tageswechsel [0-9]* s$' "$tmp/stdout" || { echo "FAIL Tageswechsel: treadmill-plan wartet nicht"; fails=$((fails + 1)); }
run "Tageswechsel: Start 23:40, m2-flow wartet nicht" 0 1 E2E_STUFEN=m2-flow FAKE_UHR=23:40:00 FAKE_UHR_SCHRITT_S=60
grep -q 'wartet auf Tageswechsel' "$tmp/stdout" && { echo "FAIL Tageswechsel: Start 23:40 hat gewartet"; fails=$((fails + 1)); }
[ "$dauer" -lt 5 ] || { echo "FAIL Tageswechsel: Start 23:40 lief $dauer s"; fails=$((fails + 1)); }
run "Tageswechsel: Start 00:00, m2-flow wartet nicht" 0 1 E2E_STUFEN=m2-flow FAKE_UHR=00:00:00 FAKE_UHR_SCHRITT_S=60
grep -q 'wartet auf Tageswechsel' "$tmp/stdout" && { echo "FAIL Tageswechsel: Start 00:00 hat gewartet"; fails=$((fails + 1)); }
run "Tageswechsel: Start 23:44:59, m2-flow wartet nicht" 0 1 E2E_STUFEN=m2-flow FAKE_UHR=23:44:59 FAKE_UHR_SCHRITT_S=60
grep -q 'wartet auf Tageswechsel' "$tmp/stdout" && { echo "FAIL Tageswechsel: Start 23:44:59 hat gewartet"; fails=$((fails + 1)); }
run "Tageswechsel: Start 23:50, ungekennzeichnete Stufe wartet nie" 0 1 E2E_STUFEN=readiness FAKE_UHR=23:50:00 FAKE_UHR_SCHRITT_S=60
grep -q 'wartet auf Tageswechsel' "$tmp/stdout" && { echo "FAIL Tageswechsel: readiness hat gewartet"; fails=$((fails + 1)); }
[ "$dauer" -lt 5 ] || { echo "FAIL Tageswechsel: readiness lief $dauer s"; fails=$((fails + 1)); }
# Uhr nicht lesbar (keine Antwort): nicht warten.
run "Tageswechsel: Uhr nicht lesbar, kein Warten" 0 1 E2E_STUFEN=m2-flow
grep -q 'wartet auf Tageswechsel' "$tmp/stdout" && { echo "FAIL Tageswechsel: ohne Uhr gewartet"; fails=$((fails + 1)); }
# Versatz: Uhr 23:40 plus 600 s = 23:50, also Warten.
run "Tageswechsel: Versatz stellt die Uhr ins Fenster" 0 1 E2E_STUFEN=m2-flow FAKE_UHR=23:40:00 FAKE_UHR_SCHRITT_S=300 E2E_UHR_VERSATZ_S=600
grep -q '^STUFE m2-flow wartet auf Tageswechsel [0-9]* s$' "$tmp/stdout" || { echo "FAIL Tageswechsel: Versatz wirkt nicht"; fails=$((fails + 1)); }
run "Tageswechsel: Versatz abc -> Fehler" 1 0 E2E_STUFEN=m2-flow E2E_UHR_VERSATZ_S=abc
grep -q 'E2E_UHR_VERSATZ_S keine ganze Zahl' "$tmp/stdout" || { echo "FAIL Tageswechsel: Meldung Versatz fehlt"; fails=$((fails + 1)); }
# Warten im Test (Zeilen TAGESWECHSEL warten/ende, FAKE_TW_S = 3 s dazwischen), Grenze 2 s: gekennzeichnete Stufe gruen,
# ungekennzeichnete rot.
run "Tageswechsel im Test: m2-flow zieht das Warten ab" 0 1 E2E_STUFEN=m2-flow FAKE_TAGESWECHSEL=1 E2E_STUFE_LIMIT_S=2
grep -q '^STUFE m2-flow Tageswechsel im Test abgewartet [0-9]* s$' "$tmp/stdout" && echo "OK   Tageswechsel im Test: Zeile ohne Werte" || { echo "FAIL Tageswechsel im Test: Zeile fehlt"; fails=$((fails + 1)); }
grep -q 'Zeitlimit in Stufe' "$tmp/stdout" && { echo "FAIL Tageswechsel im Test: Warten zaehlte gegen das Zeitlimit"; fails=$((fails + 1)); }
run "Tageswechsel im Test: ungekennzeichnete Stufe zaehlt es" 1 1 E2E_STUFEN=readiness FAKE_TAGESWECHSEL=1 E2E_STUFE_LIMIT_S=2
grep -q '^Zeitlimit in Stufe readiness nach [0-9]* s$' "$tmp/stdout" || { echo "FAIL Tageswechsel im Test: readiness ohne Zeitlimit"; fails=$((fails + 1)); }
grep -q 'Tageswechsel im Test abgewartet' "$tmp/stdout" && { echo "FAIL Tageswechsel im Test: readiness zog Warten ab"; fails=$((fails + 1)); }
# Waechter: eine Stufe der Warteliste, die es nicht gibt, ist ein Fehler vor dem ersten Lauf.
sed 's|^tageswechsel_stufen="m2-flow |&m2-flwo |' "$script" > "$tmp/ci_e2e_neu.sh"
grep -q '^tageswechsel_stufen="m2-flow m2-flwo ' "$tmp/ci_e2e_neu.sh" || { echo "FAIL Aufbau: Kopie ohne falsche Stufe"; fails=$((fails + 1)); }
script="$tmp/ci_e2e_neu.sh"
run "Warteliste mit unbekannter Stufe -> Fehler vor dem Lauf" 1 0 E2E_STUFEN=m2-flow
grep -q 'Stufe m2-flwo in tageswechsel_stufen gibt es nicht' "$tmp/stdout" || { echo "FAIL Waechter Warteliste: Meldung fehlt"; fails=$((fails + 1)); }
script=$script_orig
# Waechter: Testdatei, die weder eingebunden noch Stufe ist, auch als Kommentar.
: > app/integration_test/e2e_neu_test.dart
run "Waechter: nicht eingebundene Datei"       1 0 E2E_STUFEN=sammlung
printf "import 'e2e_a_test.dart';\n// import 'e2e_neu_test.dart';\n" > app/integration_test/all_test.dart
run "Waechter: nur auskommentierter Import"    1 0 E2E_STUFEN=sammlung
printf "import 'e2e_a_test.dart';\nimport 'e2e_neu_test.dart';\n" > app/integration_test/all_test.dart
run "Waechter: eingebunden -> frei"            0 1 E2E_STUFEN=sammlung
# Eine Datei, die nur als Stufe (nicht in all_test.dart) steht, ist frei; ohne Stufenzeile rot.
rm -f app/integration_test/e2e_neu_test.dart
printf "import 'e2e_a_test.dart';\n" > app/integration_test/all_test.dart
run "Waechter: m2-flow als Stufe statt Import" 0 1 E2E_STUFEN=sammlung
# Lokale Mehrphasentests (Host-Schritte) sind vom Waechter ausgenommen, auch ohne Import in all_test.dart.
: > app/integration_test/e2e_health_real_test.dart; : > app/integration_test/e2e_health_revoke_test.dart
run "Waechter: lokale Health-Tests ausgenommen" 0 1 E2E_STUFEN=sammlung
# GPS-Zufuehrer: je Stufe eine Zeile "geo fix fehlgeschlagen: <n> von <m>" nur mit Zaehlern (keine Koordinaten),
# gezaehlt nur waehrend dieser Stufe. Der Zufuehrer ruft etwa einmal je Sekunde; die Stufen laufen je 3 s.
# geo_ok <fall> <stufe> <fehlgeschlagen:alle|keine>: Zeile der Stufe vorhanden, m >= 2, m <= Dauer der Stufe + 2.
geo_ok() {
  z=$(grep "^geo fix fehlgeschlagen: " "$tmp/stdout" | sed -n "$2p")
  echo "$z" | grep -qx 'geo fix fehlgeschlagen: [0-9]\{1,\} von [0-9]\{1,\}' || {
    echo "FAIL $1: Zeile '$z' fehlt oder hat falsches Format"; fails=$((fails + 1)); return; }
  gn=${z#geo fix fehlgeschlagen: }; gm=${gn#* von }; gn=${gn%% von *}
  gd=$(grep '^STUFE [^ ]* rc=' "$tmp/stdout" | sed -n "$2p" | sed 's/.*dauer=\([0-9]*\)s$/\1/')
  case "$3" in alle) gw=$gm ;; *) gw=0 ;; esac
  if [ "$gm" -ge 2 ] && [ "$gm" -le $((gd + 2)) ] && [ "$gn" -eq "$gw" ]; then echo "OK   $1: $gn von $gm"; else
    echo "FAIL $1: $gn von $gm (erwartet $3 fehlgeschlagen, 2 bis $((gd + 2)) Aufrufe)"; fails=$((fails + 1)); fi
}
run "geo fix: alle erfolgreich"                0 1 E2E_STUFEN=sammlung FAKE_SLEEP=1 FAKE_LAUF_S=3
geo_ok "geo fix erfolgreich" 1 keine
run "geo fix: alle fehlgeschlagen"             0 1 E2E_STUFEN=sammlung FAKE_SLEEP=1 FAKE_LAUF_S=3 FAKE_GEO_FAIL=1
geo_ok "geo fix fehlgeschlagen" 1 alle
run "geo fix: je Stufe eigene Zeile"           0 2 "E2E_STUFEN=storage-b recover-b" FAKE_SLEEP=1 FAKE_LAUF_S=3 FAKE_GEO_FAIL=1
[ "$(grep -c '^geo fix fehlgeschlagen: ' "$tmp/stdout")" -eq 2 ] || { echo "FAIL geo fix: nicht genau eine Zeile je Stufe"; fails=$((fails + 1)); }
geo_ok "geo fix Stufe 1" 1 alle
geo_ok "geo fix Stufe 2 (nur eigene Aufrufe)" 2 alle
run "geo fix: auch bei roter Stufe"            1 1 E2E_STUFEN=sammlung FAKE_FAIL=1
grep -q '^geo fix fehlgeschlagen: [0-9]* von [0-9]*$' "$tmp/stdout" && echo "OK   geo fix: Zeile bei roter Stufe" || { echo "FAIL geo fix: Zeile fehlt bei roter Stufe"; fails=$((fails + 1)); }
[ $fails -eq 0 ] && echo "ci_e2e-Test GRÜN" || { echo "ci_e2e-Test ROT"; exit 1; }
