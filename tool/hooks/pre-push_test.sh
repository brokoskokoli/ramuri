#!/bin/sh
# Test für tool/hooks/pre-push: Tag-Regel (WP30) und Privat-Scan jedes Pushes (WP31): Aufruf: sh tool/hooks/pre-push_test.sh
# Legt ein temporäres Repo mit refs/remotes/origin/main an und ruft den Hook mit stdin wie Git auf.
hook=$(cd "$(dirname "$0")" && pwd)/pre-push
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q . || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git config commit.gpgsign false
git commit -q --allow-empty -m a && git commit -q --allow-empty -m b || exit 1
inmain=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$inmain"
git commit -q --allow-empty -m c || exit 1
outside=$(git rev-parse HEAD)
git tag -a -m ann v0.1.0-rc1 "$inmain"
git tag -a -m ann v9.9.9-ann "$outside"
git tag v9.9.9-light "$outside"
zero=0000000000000000000000000000000000000000
fails=0
# check <ok|rejected> <Name> <stdin-Zeile>
check() {
  want=$1 name=$2 line=$3
  printf '%s\n' "$line" | sh "$hook" origin url >/dev/null 2>&1; rc=$?
  if { [ "$want" = ok ] && [ $rc -eq 0 ]; } || { [ "$want" = rejected ] && [ $rc -ne 0 ]; }; then
    echo "OK   $name"
  else
    echo "FAIL $name (rc=$rc)"; fails=$((fails + 1))
  fi
}
check ok       "leichter Tag auf Commit in origin/main" "refs/tags/v0.1.0 $inmain refs/tags/v0.1.0 $zero"
check ok       "annotierter Tag auf Commit in origin/main" "refs/tags/v0.1.0-rc1 $(git rev-parse v0.1.0-rc1) refs/tags/v0.1.0-rc1 $zero"
check rejected "leichter Tag außerhalb origin/main" "refs/tags/v9.9.9-light $outside refs/tags/v9.9.9-light $zero"
check rejected "annotierter Tag außerhalb origin/main" "refs/tags/v9.9.9-ann $(git rev-parse v9.9.9-ann) refs/tags/v9.9.9-ann $zero"
check ok       "Tag-Löschung" "(delete) $zero refs/tags/v9.9.9-ann $outside"
check ok       "Nicht-Release-Tag außerhalb origin/main" "refs/tags/foo $outside refs/tags/foo $zero"
check ok       "wp-Branch unverändert frei" "refs/heads/wp/1-x $outside refs/heads/wp/1-x $zero"
git update-ref -d refs/remotes/origin/main
check rejected "Release-Tag ohne origin/main" "refs/tags/v0.1.0 $inmain refs/tags/v0.1.0 $zero"
# Privat-Scan (WP31): temporäre Termliste mit harmlosem Testbegriff, Hook-Scan auf die neuen Commits.
export RUNNING_APP_FORBIDDEN_TERMS="$tmp/terms"
printf 'zzgeheimzz\n' > "$tmp/terms"
git update-ref refs/remotes/origin/main "$inmain"
git checkout -q -b feat "$inmain"
base=$(git rev-parse HEAD)
echo "harmlos" > clean.txt && git add clean.txt && git commit -q -m clean || exit 1
cleanhead=$(git rev-parse HEAD)
check ok       "Scan: sauberer Push frei" "refs/heads/feat $cleanhead refs/heads/feat $zero"
echo "Text ZZGeheimZZ Text" > leak.txt && git add leak.txt && git commit -q -m leak || exit 1
leak=$(git rev-parse HEAD)
git rm -q leak.txt && git commit -q -m "kein Leck mehr" || exit 1
removed=$(git rev-parse HEAD)
check rejected "Scan: Begriff in älterem Commit des Ranges, später entfernt" "refs/heads/feat $removed refs/heads/feat $zero"
check rejected "Scan: Treffer, Remote-Stand bekannt" "refs/heads/feat $leak refs/heads/feat $cleanhead"
check ok       "Scan: Range ab dem Treffer (Leck liegt auf dem Remote) frei" "refs/heads/feat $removed refs/heads/feat $leak"
git reset -q --hard "$cleanhead"
echo "x" > zzgeheimzz.txt && git add zzgeheimzz.txt && git commit -q -m name || exit 1
check rejected "Scan: Begriff im Dateinamen" "refs/heads/feat $(git rev-parse HEAD) refs/heads/feat $zero"
git reset -q --hard "$cleanhead"
git commit -q --allow-empty -m "zzgeheimzz in Nachricht" || exit 1
check rejected "Scan: Begriff in Commit-Nachricht" "refs/heads/feat $(git rev-parse HEAD) refs/heads/feat $zero"
git reset -q --hard "$cleanhead"
echo "pfad /Users""/abc/x" > p.txt && git add p.txt && git commit -q -m pfad || exit 1
check rejected "Scan: Standardmuster (Nutzerpfad)" "refs/heads/feat $(git rev-parse HEAD) refs/heads/feat $zero"
git reset -q --hard "$cleanhead"
check ok       "Scan: Löschung einer Ref frei" "(delete) $zero refs/heads/feat $leak"
check rejected "Scan: Treffer trifft auch Tag-Push" "refs/tags/foo $leak refs/tags/foo $zero"
check rejected "Scan: main-Regel bleibt (sauber, ohne Freigabe)" "refs/heads/feat $cleanhead refs/heads/main $inmain"
# Ausnahmen (wie im Vollmodus): tool/check_private.sh und LICENSE werden nicht gescannt.
mkdir -p tool && echo "zzgeheimzz" > tool/check_private.sh && echo "zzgeheimzz" > LICENSE && git add tool LICENSE && git commit -q -m ausnahme || exit 1
check ok       "Scan: Ausnahmedateien (tool/check_private.sh, LICENSE) frei" "refs/heads/feat $(git rev-parse HEAD) refs/heads/feat $zero"
git reset -q --hard "$cleanhead"
# Merge: Term nur in der Konfliktauflösung (beide Seiten sauber).
git checkout -q -b sa "$cleanhead"; echo a > m.txt; git add m.txt; git commit -q -m sa
git checkout -q -b sb "$cleanhead"; echo b > m.txt; git add m.txt; git commit -q -m sb
git merge -q --no-commit sa >/dev/null 2>&1; echo "Aufloesung zzgeheimzz" > m.txt; git add m.txt; git commit -q -m merge-mit-term || exit 1
mergeleak=$(git rev-parse HEAD)
check rejected "Scan: Begriff nur in der Merge-Konfliktauflösung" "refs/heads/sb $mergeleak refs/heads/sb $zero"
git reset -q --hard "$mergeleak^1"
git merge -q --no-commit sa >/dev/null 2>&1; echo "Aufloesung sauber" > m.txt; git add m.txt; git commit -q -m merge-sauber || exit 1
check ok       "Scan: Merge mit sauberer Auflösung frei" "refs/heads/sb $(git rev-parse HEAD) refs/heads/sb $zero"
git checkout -q feat
# Tag-Annotation.
git tag -a -m "Notiz zzgeheimzz" foo-ann "$cleanhead"
check rejected "Scan: Begriff in Tag-Annotation" "refs/tags/foo-ann $(git rev-parse foo-ann) refs/tags/foo-ann $zero"
git tag -a -m "Notiz harmlos" foo-ok "$cleanhead"
check ok       "Scan: Tag-Annotation sauber frei" "refs/tags/foo-ok $(git rev-parse foo-ok) refs/tags/foo-ok $zero"
# Plausibilität: der Scan sieht einen nicht leeren Bereich (sonst wären die Treffer-Fälle oben wirkungslos).
[ "$(git rev-list "$leak" --not --remotes | wc -l | tr -d ' ')" -ge 2 ] && echo "OK   Scan-Bereich nicht leer" || { echo "FAIL Scan-Bereich leer"; fails=$((fails + 1)); }
[ $fails -eq 0 ] && echo "pre-push-Test GRÜN" || { echo "pre-push-Test ROT"; exit 1; }
