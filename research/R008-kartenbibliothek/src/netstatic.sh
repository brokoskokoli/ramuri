#!/bin/bash
# Statische Suche nach Netz-APIs und fest eingebauten Hosts. Usage: netstatic.sh <apps-ordner> <out>
set -uo pipefail
APPS=$1; OUT=$2; PUB=~/.pub-cache/hosted/pub.dev
NETRE='HttpClient\(|Socket\.connect|RawSocket|WebSocket|RawDatagramSocket|package:http/|package:dio/|HttpURLConnection|OkHttpClient|java\.net\.URL\(|URL\(|Socket\('
for app in fm ml; do
  [ -f "$APPS/$app/pubspec.lock" ] || continue
  echo "== $app: Dart-Pakete mit Netz-APIs (lib/, ohne Tests und Beispiele)"
  python3 - "$APPS/$app/pubspec.lock" <<'PY' | while read -r name ver; do
import re,sys
for m in re.finditer(r'\n  (\S+):\n    dependency: "[^"]+"\n    description:.*?\n    source: hosted\n    version: "([^"]+)"', open(sys.argv[1]).read(), re.S): print(m.group(1), m.group(2))
PY
    d="$PUB/$name-$ver"
    hits=$(grep -rElI "$NETRE" "$d/lib" "$d/android/src/main" 2>/dev/null | sed "s#$d/##" | tr '\n' ' ')
    [ -n "$hits" ] && echo "  $name $ver: $hits"
  done
done > "$OUT/net_dart.txt"
cat "$OUT/net_dart.txt"
echo "== Hosts in nativen Bibliotheken und Dart-AOT der Release-APKs (strings, https?://)"
for apk in "$(ls -d "$(dirname "$OUT")"/build-*/ 2>/dev/null | tail -1)"*-universal.apk; do
  [ -f "$apk" ] || continue
  t=$(mktemp -d); unzip -q -o "$apk" 'lib/arm64-v8a/*' 'classes*.dex' -d "$t" 2>/dev/null
  for f in "$t"/lib/arm64-v8a/*.so "$t"/classes*.dex; do
    [ -f "$f" ] || continue
    hosts=$(strings -n 8 "$f" | grep -Eo 'https?://[A-Za-z0-9.-]+' | sort -u | tr '\n' ' ')
    echo "$(basename "$apk") $(basename "$f"): $hosts"
  done
done | tee "$OUT/net_hosts.txt"
