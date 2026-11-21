#!/bin/sh
# Selbsttest der Gate-Stufen (tool/gate.sh --list-stages, --stage, --dry-run), ohne einen Schritt auszuführen:
# - jeder Schritt des vollen Laufs steht in genau einer Stufe (Vereinigung aller Stufen = voller Lauf, keiner doppelt),
# - eine Stufe führt nur eigene Schritte aus und ist nicht leer, kein Stufenname doppelt,
# - --fast führt nur Schritte des vollen Laufs aus,
# - falsche Aufrufe (unbekannte Stufe, --stage ohne Namen, zwei Modi, --list-stages mit --dry-run) enden mit Exit 2.
# Gegenprobe: Kopien von gate.sh mit eingebautem Fehler (Schritt in keiner Stufe, Schritt in allen Stufen, Stufe
# fehlt in der Liste) müssen rot sein.
# Aufruf: sh tool/gate_stages_test.sh
unset GATE_LOCK_HELD   # läuft auch innerhalb des Gates; die Trockenläufe nehmen keinen Lock
gate=$(cd "$(dirname "$0")" && pwd)/gate.sh
cd "$(git rev-parse --show-toplevel)" || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
fails=0

# pruefe <gate-skript>: 0 = Stufen decken den vollen Lauf genau einmal ab; sonst je Abweichung eine Zeile "ABW ...".
pruefe() {
  g=$1; rc=0
  stufen=$(sh "$g" --list-stages 2>/dev/null) || { echo "ABW --list-stages endet nicht mit 0"; return 1; }
  [ -n "$stufen" ] || { echo "ABW --list-stages ist leer"; return 1; }
  d=$(echo "$stufen" | sort | uniq -d)
  [ -z "$d" ] || { echo "ABW Stufe doppelt in --list-stages: $d"; rc=1; }
  sh "$g" --dry-run 2>/dev/null > "$tmp/voll.out" || { echo "ABW --dry-run endet nicht mit 0"; return 1; }
  grep '^PLAN ' "$tmp/voll.out" | sort > "$tmp/voll"
  [ -s "$tmp/voll" ] || { echo "ABW voller Lauf ohne Schritt"; return 1; }
  : > "$tmp/stufen"
  for s in $stufen; do
    sh "$g" --dry-run --stage "$s" 2>/dev/null > "$tmp/s.out" || { echo "ABW Stufe $s: --dry-run endet nicht mit 0"; rc=1; continue; }
    grep '^PLAN ' "$tmp/s.out" > "$tmp/s"
    [ -s "$tmp/s" ] || { echo "ABW Stufe $s ohne Schritt"; rc=1; }
    awk -v s="$s" '$2 != s' "$tmp/s" > "$tmp/fremd"
    [ ! -s "$tmp/fremd" ] || { sed "s/^/ABW Stufe $s führt fremden Schritt aus: /" "$tmp/fremd"; rc=1; }
    cat "$tmp/s" >> "$tmp/stufen"
  done
  sort "$tmp/stufen" > "$tmp/stufen.s"
  # comm auf sortierten Listen zählt Wiederholungen: ein Schritt in zwei Stufen bleibt rechts übrig.
  comm -23 "$tmp/voll" "$tmp/stufen.s" > "$tmp/fehlt"
  comm -13 "$tmp/voll" "$tmp/stufen.s" > "$tmp/extra"
  [ ! -s "$tmp/fehlt" ] || { sed 's/^/ABW in keiner Stufe: /' "$tmp/fehlt"; rc=1; }
  [ ! -s "$tmp/extra" ] || { sed 's/^/ABW mehrfach oder nur in einer Stufe: /' "$tmp/extra"; rc=1; }
  sh "$g" --dry-run --fast 2>/dev/null | grep '^PLAN ' | sort > "$tmp/fast"
  [ -s "$tmp/fast" ] || { echo "ABW --fast ohne Schritt"; rc=1; }
  comm -23 "$tmp/fast" "$tmp/voll" > "$tmp/fast.extra"
  [ ! -s "$tmp/fast.extra" ] || { sed 's/^/ABW --fast führt Schritt aus, den der volle Lauf nicht kennt: /' "$tmp/fast.extra"; rc=1; }
  return $rc
}

if pruefe "$gate" > "$tmp/ergebnis"; then
  echo "OK   jeder Schritt in genau einer Stufe ($(wc -l < "$tmp/voll" | tr -d ' ') Schritte, $(sh "$gate" --list-stages | wc -l | tr -d ' ') Stufen)"
else
  cat "$tmp/ergebnis"; echo "FAIL Stufen decken den vollen Lauf nicht genau einmal ab"; fails=$((fails + 1))
fi

# aufruf_rc <Name> <erwarteter Exit> <Argumente...>
aufruf_rc() {
  n=$1 want=$2; shift 2
  sh "$gate" "$@" > "$tmp/aufruf" 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "OK   $n"; else echo "FAIL $n (Exit $got erwartet $want)"; cat "$tmp/aufruf"; fails=$((fails + 1)); fi
}
aufruf_rc "unbekannte Stufe -> Exit 2" 2 --dry-run --stage gibtsnicht
grep -q '^unbekannte Stufe: gibtsnicht' "$tmp/aufruf" || { echo "FAIL unbekannte Stufe: Meldung fehlt"; fails=$((fails + 1)); }
aufruf_rc "--stage ohne Namen -> Exit 2" 2 --stage
aufruf_rc "--stage mit leerem Namen -> Exit 2" 2 --stage ""
aufruf_rc "--fast und --stage -> Exit 2" 2 --fast --stage app
aufruf_rc "--changed und --fast -> Exit 2" 2 --changed --fast
aufruf_rc "--list-stages und --dry-run -> Exit 2" 2 --list-stages --dry-run
aufruf_rc "unbekannte Option -> Exit 2" 2 --coverage

# Gegenprobe: eingebaute Fehler müssen auffallen. mutante <Name> <sed-Ausdruck> <erwartete ABW-Zeile (grep)>
mutante() {
  sed "$2" "$gate" > "$tmp/gate_mut.sh"
  if cmp -s "$gate" "$tmp/gate_mut.sh"; then echo "FAIL Gegenprobe $1: Ersetzung greift nicht"; fails=$((fails + 1)); return; fi
  if pruefe "$tmp/gate_mut.sh" > "$tmp/mut"; then
    echo "FAIL Gegenprobe $1: Prüfung blieb grün"; fails=$((fails + 1))
  elif grep -q "$3" "$tmp/mut"; then echo "OK   Gegenprobe $1 rot"
  else cat "$tmp/mut"; echo "FAIL Gegenprobe $1: erwartete Meldung fehlt"; fails=$((fails + 1)); fi
}
mutante "Schritt in keiner Stufe" 's/^step tools "privat"/step keine "privat"/' '^ABW in keiner Stufe: PLAN keine privat$'
mutante "Schritt in allen Stufen" 's/^  \[ -z "\$only_stage" \] || \[ "\$stufe" = "\$only_stage" \] || return 0$/  [ -z "$only_stage" ] || [ "$stufe" = "$only_stage" ] || [ "$stufe" = tools ] || return 0/' 'führt fremden Schritt aus: PLAN tools privat$'
mutante "Stufe fehlt in der Liste" 's/^  echo zones drift android release /  echo zones drift android /' '^ABW in keiner Stufe: PLAN release '
mutante "Stufe doppelt" 's/^  echo analyze$/  echo analyze; echo analyze/' '^ABW Stufe doppelt'

[ $fails -eq 0 ] && echo "gate-Stufen-Test GRÜN" || { echo "gate-Stufen-Test ROT"; exit 1; }
