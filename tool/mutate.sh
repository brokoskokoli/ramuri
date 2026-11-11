#!/bin/sh
# Mutationsprobe: tool/mutate.sh <datei> <zeile> <ersetzung> -- <testbefehl ...>
#   Ersetzt genau die Zeile <zeile> (1-basiert, ganze Zeile) der getrackten, unveränderten Datei durch <ersetzung>,
#   führt den Testbefehl aus und stellt die Datei IMMER wieder her (trap auf EXIT, INT, TERM, HUP; byteweise per
#   Kopie, danach cmp und git diff --quiet). Der Testbefehl läuft im aktuellen Verzeichnis; <datei> ist dazu relativ.
#   Die Ersetzung geht über die Umgebung an awk, daher bleiben / & \ ' " $ unverändert (kein sed, keine Escapes).
# Ergebnis (letzte Zeile der Ausgabe):
#   erkannt   Test rot            Exit 0
#   überlebt  Test grün           Exit 1   (Prüfung fehlt oder ist zu schwach)
#   abgewiesen / Testbefehl nicht ausführbar / Wiederherstellung fehlgeschlagen: Exit 2 / 4 / 3
# Die Testausgabe steht in einer Logdatei (Pfad in der Ausgabe), gezeigt werden nur die letzten Zeilen.
# Ein roter Test durch Übersetzungsfehler des Mutanten zählt als "erkannt"; im Log nachsehen, ob es eine echte
# Prüfung war. Bei Abbruch wird auch der Prozessbaum des Tests beendet.
usage() { echo "Aufruf: tool/mutate.sh <datei> <zeile> <ersetzung> -- <testbefehl ...>" >&2; exit 2; }
[ $# -ge 5 ] || usage
file=$1; line=$2; repl=$3; shift 3
[ "$1" = "--" ] || usage
shift
[ $# -ge 1 ] || usage

reject() { echo "abgewiesen: $*" >&2; exit 2; }
[ -f "$file" ] || reject "$file ist keine Datei"
case $line in ''|*[!0-9]*) reject "Zeile '$line' ist keine positive Zahl";; esac
[ "$line" -ge 1 ] || reject "Zeile muss >= 1 sein"
git ls-files --error-unmatch -- "$file" >/dev/null 2>&1 || reject "$file ist nicht von git getrackt"
git diff --quiet HEAD -- "$file" || reject "$file hat uncommittete Änderungen (staged oder unstaged)"
total=$(awk 'END{print NR}' "$file")
[ "$line" -le "$total" ] || reject "$file hat nur $total Zeilen, Zeile $line existiert nicht"
orig=$(awk -v n="$line" 'NR==n{print; exit}' "$file")
[ "$orig" != "$repl" ] || reject "Ersetzung ist identisch mit der Zeile (kein Mutant)"

work=$(mktemp -d "${TMPDIR:-/tmp}/mutate.XXXXXX") || exit 2
bak=$work/orig
log=${TMPDIR:-/tmp}/mutate-$$.log
cp "$file" "$bak" || exit 2
mutated=0
child=

descendants() { # alle Nachfahren der PID $1 (ps-Tabelle, kein pkill)
  ps -A -o pid= -o ppid= | awk -v root="$1" '
    { kids[$2] = kids[$2] " " $1 }
    function walk(p, i, n, a) { n = split(kids[p], a, " "); for (i = 1; i <= n; i++) { print a[i]; walk(a[i]) } }
    END { walk(root) }'
}
stop_test() {
  [ -n "$child" ] || return 0
  pids="$(descendants "$child") $child"
  kill -TERM $pids 2>/dev/null
  wait "$child" 2>/dev/null
  child=
}
restore() {
  [ "$mutated" = 1 ] || return 0
  stop_test
  if cp "$bak" "$file" && cmp -s "$bak" "$file" && git diff --quiet -- "$file"; then
    mutated=0
  else
    echo "FEHLER: Wiederherstellung von $file fehlgeschlagen; Original liegt in $bak" >&2
    mutated=0
    exit 3
  fi
}
on_signal() { echo "abgebrochen (Signal), stelle $file wieder her" >&2; restore; rm -rf "$work"; exit 130; }
on_exit() { restore; rm -rf "$work" 2>/dev/null; }
trap on_exit EXIT
trap on_signal INT TERM HUP

mutated=1
if ! MUT_REPL=$repl awk -v n="$line" 'NR==n{print ENVIRON["MUT_REPL"]; next} {print}' "$bak" > "$file"; then
  echo "abgewiesen: Schreiben der Mutation fehlgeschlagen" >&2; exit 2
fi
echo "Mutant: $file:$line"
printf '  vorher:  %s\n' "$orig"
printf '  nachher: %s\n' "$repl"

"$@" > "$log" 2>&1 &
child=$!
wait "$child"
rc=$?
child=
restore
echo "Testausgabe (letzte 15 Zeilen, vollständig: $log):"
tail -n 15 "$log" | sed 's/^/  | /'
echo "Log: $log"
if [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
  echo "Testbefehl nicht ausführbar (Exit $rc), kein Ergebnis"; exit 4
elif [ "$rc" -ne 0 ]; then
  echo "erkannt (Test rot, Exit $rc), $file wiederhergestellt"; exit 0
else
  echo "überlebt (Test grün), $file wiederhergestellt"; exit 1
fi
