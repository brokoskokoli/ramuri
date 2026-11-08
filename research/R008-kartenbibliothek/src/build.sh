#!/bin/bash
# Baut die Mini-Apps (Release) und misst die APK-Groessen. Usage: build.sh <out> <apps...>
set -euo pipefail
OUT=$1; shift; HERE="$(cd "$(dirname "$0")" && pwd)"
APPS="$(dirname "$OUT")/apps"   # gemeinsame Build-Ordner unter work/R008/apps
VMT=~/.pub-cache/hosted/pub.dev/vector_map_tiles-9.0.0-beta.13
[ -d "$VMT" ] || dart pub cache add vector_map_tiles --version 9.0.0-beta.13
python3 "$HERE/patch_vmt.py" "$VMT" "$APPS/vmt_patched"
printf 'app\tvariante\tdatei\tbytes\n' > "$OUT/apk_sizes.tsv"
for a in "$@"; do
  APP=$("$HERE/mkapp.sh" "$a" "$APPS")
  ( cd "$APP"
    flutter pub get >/dev/null
    cp pubspec.lock "$OUT/pubspec.lock.$a"
    flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 > "$OUT/build_$a.log" 2>&1
    for f in build/app/outputs/flutter-apk/app-*-release.apk; do
      cp "$f" "$OUT/$a-$(basename "$f")"; printf '%s\tsplit\t%s\t%s\n' "$a" "$(basename "$f")" "$(stat -f %z "$f")" >> "$OUT/apk_sizes.tsv"; done
    flutter build apk --release >> "$OUT/build_$a.log" 2>&1
    f=build/app/outputs/flutter-apk/app-release.apk
    cp "$f" "$OUT/$a-app-release-universal.apk"; printf '%s\tuniversal\t%s\t%s\n' "$a" app-release.apk "$(stat -f %z "$f")" >> "$OUT/apk_sizes.tsv"
    # Inhalt: native Bibliotheken je ABI
    unzip -l "$OUT/$a-app-release-universal.apk" | awk '$4 ~ /^lib\//{print $1"\t"$4}' > "$OUT/native_$a.tsv"
  )
  echo "gebaut: $a"
done
cat "$OUT/apk_sizes.tsv"
