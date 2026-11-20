#!/bin/sh
# Test fuer tool/ci_e2e.sh mit Attrappen fuer adb und flutter (kein Emulator): Shard-Zuordnung,
# unbekannte Namen, Mindeststufen, Waechter ueber all_test.dart, Rot einer Stufe, NEED_KILL, kein E2E_ im Log,
# letzte Schrittmarke vor dem Fehler, Bildschirmfotos bei SHOT-Marken (E2E_SHOTS=1), Zeitlimit je Stufe
# (E2E_STUFE_LIMIT_S, haengende Attrappe), Zeitlimit je adb-Aufruf (E2E_ADB_LIMIT_S, haengende adb-Attrappe).
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
case "$*" in
  *"dumpsys package"*) echo 'android.permission.ACCESS_FINE_LOCATION: granted=true' ;;
  *"dumpsys window"*) [ -n "${FAKE_NOFOCUS:-}" ] || echo 'mCurrentFocus=Window{x u0 io.github.brokoskokoli.ramuri/.MainActivity}' ;;
  *screencap*) echo x >> "$FAKE_SHOTS"; echo PNG ;;
  *"am force-stop"*) echo x >> "$FAKE_STOPS" ;;
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
[ -z "${FAKE_SLEEP:-}" ] || sleep 6
# SHOT-Marken wie shot() in e2e_support.dart: Zeile E2E_, danach steht der Test (hier 1 s).
[ -z "${FAKE_SHOT_LINES:-}" ] || for n in s1_hell 'Gross' '../boese' 'a b' s1-dunkel_2; do
  echo "E2E_12:00:00.000 SHOT $n"; sleep 1; done
case "$*" in *PHASE=write* | *PHASE=a*) [ -n "${FAKE_NOKILL:-}" ] || { echo "E2E_X NEED_KILL"; sleep 3; } ;; esac
[ -z "${FAKE_STEPS:-}" ] || { echo "PUB_00 SCHRITT A1 start"; echo "PUB_01 SCHRITT A1 rot"; echo "00:02 +0 -1: A [E]"; echo "PUB_02 SCHRITT B1 start"; }
[ -z "${FAKE_FAIL:-}" ] || { echo "PUB_01 M2 form_error key=planFormErrorStand"; i=0; while [ $i -lt 60 ]; do echo "zeile $i"; i=$((i + 1)); done; echo "Expected: x"; exit 1; }
# Haengen (Aufruf enthaelt $FAKE_HANG): Kindprozess sleep, beide PIDs in $FAKE_PIDS; endet sonst nach 40 s gruen.
case "${FAKE_HANG:+$*}" in *"${FAKE_HANG:-}"*) [ -z "${FAKE_HANG:-}" ] || {
  echo "$$" >> "$FAKE_PIDS"; sleep 40 & echo "$!" >> "$FAKE_PIDS"; wait; } ;; esac
exit 0
X
chmod +x "$tmp/bin/adb" "$tmp/bin/flutter"
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/calls" FAKE_SHOTS="$tmp/shots" FAKE_ARGS="$tmp/args" FAKE_STOPS="$tmp/stops" \
  FAKE_PIDS="$tmp/pids" ANDROID_SERIAL=emulator-5554
unset E2E_SHARD E2E_STUFEN E2E_SHOTS E2E_STUFE_LIMIT_S E2E_ADB_LIMIT_S FAKE_ADB_HANG FAKE_ADB_HANG_EINMAL FAKE_NOKILL FAKE_FAIL FAKE_E FAKE_SLEEP FAKE_STEPS FAKE_SHOT_LINES \
  FAKE_NOFOCUS FAKE_HANG
fails=0
# run <Name> <rc> <Aufrufe-der-Testdateien (Anzahl)> [VAR=Wert ...]
run() {
  name=$1 want_rc=$2 want_calls=$3; shift 3
  : > "$FAKE_LOG"; : > "$FAKE_ARGS"; : > "$FAKE_STOPS"; : > "$FAKE_PIDS"; rm -rf "$tmp/out"
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
run "Shard stufen: Mehrphasen-Stufen, m2-flow und readiness" 0 6 E2E_SHARD=stufen
grep -q all_test "$FAKE_LOG" && { echo "FAIL Shard stufen fuehrt all_test aus"; fails=$((fails + 1)); }
run "ohne Auswahl: alle acht Stufen"          0 8 X=1
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
run "Stufe treadmill-plan: Laufband-Datei mit Schalter" 0 1 E2E_STUFEN=treadmill-plan
grep -qx 'integration_test/e2e_treadmill_test.dart' "$FAKE_LOG" || { echo "FAIL treadmill-plan: falsche Datei"; fails=$((fails + 1)); }
grep -q 'TREADMILL_PLAN=true' "$FAKE_ARGS" || { echo "FAIL treadmill-plan: Schalter fehlt"; fails=$((fails + 1)); }
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
# Zeitlimit je Stufe: haengende Attrappe (FAKE_HANG = Teil des Aufrufs), Grenze 3 s.
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
run "Zeitlimit: sammlung haengt -> Exit 1"     1 1 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=3 FAKE_HANG=all_test
zeitlimit_ok sammlung
grep -q '^STUFE sammlung rc=1 ' "$tmp/stdout" || { echo "FAIL Zeitlimit: STUFE-Zeile mit rc=1 fehlt"; fails=$((fails + 1)); }
[ -f "$tmp/out/screen-sammlung.png" ] || { echo "FAIL Zeitlimit: letztes Foto fehlt"; fails=$((fails + 1)); }
[ -f "$tmp/out/logcat-filtered.txt" ] || { echo "FAIL Zeitlimit: Logcat fehlt"; fails=$((fails + 1)); }
[ "$(wc -l < "$FAKE_STOPS" | tr -d ' ')" -eq 1 ] || { echo "FAIL Zeitlimit: kein am force-stop"; fails=$((fails + 1)); }
run "Zeitlimit: Kill-Stufe ohne NEED_KILL haengt" 1 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=3 FAKE_NOKILL=1 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
# Nach NEED_KILL haengt die Attrappe erst nach 3 s (sleep 3 oben): Grenze 6 s, sonst greift sie mitunter vorher
# (Wettlauf, dann hing die Attrappe nie).
run "Zeitlimit: haengt nach NEED_KILL -> Exit 1" 1 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=6 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
grep -q '^STUFE recover-a rc=1 ' "$tmp/stdout" || { echo "FAIL Zeitlimit nach NEED_KILL: STUFE-Zeile mit rc=1 fehlt"; fails=$((fails + 1)); }
run "Zeitlimit: Folgestufe laeuft weiter"      1 2 "E2E_STUFEN=recover-a recover-b" E2E_STUFE_LIMIT_S=6 FAKE_HANG=PHASE=a
zeitlimit_ok recover-a
grep -q '^STUFE recover-b rc=0 ' "$tmp/stdout" || { echo "FAIL Zeitlimit: recover-b nicht gruen gelaufen"; fails=$((fails + 1)); }
run "Zeitlimit: Wert abc -> Fehler"            1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=abc
grep -q 'E2E_STUFE_LIMIT_S keine positive ganze Zahl' "$tmp/stdout" || { echo "FAIL Zeitlimit abc: Meldung fehlt"; fails=$((fails + 1)); }
run "Zeitlimit: Wert 0 -> Fehler"              1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=0
run "Zeitlimit: Wert -5 -> Fehler"             1 0 E2E_STUFEN=sammlung E2E_STUFE_LIMIT_S=-5
[ -s "$FAKE_ARGS" ] && { echo "FAIL Zeitlimit: flutter trotz ungueltigem Wert aufgerufen"; fails=$((fails + 1)); }
run "Zeitlimit: grosse Grenze, Stufe gruen"    0 1 E2E_STUFEN=recover-a E2E_STUFE_LIMIT_S=600
grep -q 'Zeitlimit in Stufe' "$tmp/stdout" && { echo "FAIL Zeitlimit: Meldung ohne Ueberschreitung"; fails=$((fails + 1)); }
# Zeitlimit je adb-Aufruf: haengende adb-Attrappe (FAKE_ADB_HANG), adb-Limit 2 s; zeitlimit_ok prueft auch die
# adb-PIDs in $FAKE_PIDS. adb_ok <unterbefehl>: Meldung mit nur dem Unterbefehl, ohne weitere Argumente.
adb_ok() {
  grep -qx "adb-Zeitlimit nach 2 s: $1" "$tmp/stdout" || { echo "FAIL adb-Zeitlimit $1: Meldung fehlt"; fails=$((fails + 1)); }
}
run "adb-Zeitlimit: dumpsys window haengt"     1 1 E2E_STUFEN=sammlung "FAKE_ADB_HANG=dumpsys window" FAKE_HANG=all_test E2E_STUFE_LIMIT_S=3 E2E_ADB_LIMIT_S=2
zeitlimit_ok sammlung
adb_ok shell
run "adb-Zeitlimit: screencap haengt"          1 1 E2E_STUFEN=sammlung FAKE_ADB_HANG=screencap FAKE_HANG=all_test E2E_STUFE_LIMIT_S=3 E2E_ADB_LIMIT_S=2
zeitlimit_ok sammlung
adb_ok exec-out
run "adb-Zeitlimit: logcat -d im Rot-Zweig haengt" 1 1 E2E_STUFEN=sammlung "FAKE_ADB_HANG=logcat -d" FAKE_FAIL=1 E2E_ADB_LIMIT_S=2
adb_ok logcat
[ "$dauer" -lt 30 ] || { echo "FAIL adb-Zeitlimit logcat: Skript lief $dauer s"; fails=$((fails + 1)); }
[ -f "$tmp/out/test-output-sammlung.txt" ] || { echo "FAIL adb-Zeitlimit logcat: kein Testlog im Artefakt"; fails=$((fails + 1)); }
[ -s "$FAKE_PIDS" ] || { echo "FAIL adb-Zeitlimit logcat: Attrappe hing nicht"; fails=$((fails + 1)); }
for p in $(cat "$FAKE_PIDS"); do kill -0 "$p" 2>/dev/null && { echo "FAIL adb-Zeitlimit logcat: Prozess $p laeuft noch"; fails=$((fails + 1)); kill -9 "$p"; }; done
grep -q 'E2E_\|geheim123' "$tmp/stdout" && { echo "FAIL adb-Zeitlimit logcat: E2E_-Zeile in der Ausgabe"; fails=$((fails + 1)); }
grep -rq 'E2E_\|geheim123' "$tmp/out" && { echo "FAIL adb-Zeitlimit logcat: E2E_-Zeile im Artefakt"; fails=$((fails + 1)); }
rm -f "$tmp/hang-einmal"
run "adb-Zeitlimit: Folgestufe laeuft weiter"  1 2 "E2E_STUFEN=recover-a recover-b" "FAKE_ADB_HANG=dumpsys window" FAKE_ADB_HANG_EINMAL="$tmp/hang-einmal" FAKE_HANG=PHASE=a E2E_STUFE_LIMIT_S=6 E2E_ADB_LIMIT_S=2
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
# Waechter: eine Stufe im Shard ohne Zeitlimit in grenze_s ist ein Fehler vor dem ersten Lauf.
sed 's|^shard_sammlung="sammlung |&neu |; s|^\[ "\$ran" -gt 0 \]|stufe neu 0 integration_test/e2e_a_test.dart\n&|' "$script" > "$tmp/ci_e2e_neu.sh"
script="$tmp/ci_e2e_neu.sh"
run "Stufe ohne Zeitlimit -> Fehler vor dem Lauf" 1 0 X=1
grep -q 'Stufe neu hat kein Zeitlimit' "$tmp/stdout" || { echo "FAIL Waechter Zeitlimit: Meldung fehlt"; fails=$((fails + 1)); }
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
[ $fails -eq 0 ] && echo "ci_e2e-Test GRÜN" || { echo "ci_e2e-Test ROT"; exit 1; }
