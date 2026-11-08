#!/bin/bash
# Legt eine Mini-App unter $2 an: flutter create (Android), dann pubspec, lib, test aus src/apps/<name> und
# src/apps/common, minSdk 31, targetSdk 36. Usage: mkapp.sh <name> <zielordner>
set -euo pipefail
NAME=$1; DEST=$2; SRC="$(cd "$(dirname "$0")" && pwd)/apps"
mkdir -p "$DEST"
if [ ! -f "$DEST/$NAME/android/app/build.gradle.kts" ]; then
  ( cd "$DEST" && flutter create --platforms android --org io.github.r008 --project-name "r008_$NAME" "$NAME" >/dev/null )
fi
APP="$DEST/$NAME"
cp "$SRC/$NAME/pubspec.yaml" "$APP/pubspec.yaml"
rm -rf "$APP/lib" "$APP/test"; mkdir -p "$APP/lib" "$APP/test"
cp "$SRC/$NAME"/lib/*.dart "$APP/lib/"
[ "$NAME" = base ] || cp "$SRC"/common/*.dart "$APP/lib/"
[ -d "$SRC/$NAME/test" ] && cp "$SRC/$NAME"/test/*.dart "$APP/test/" 2>/dev/null || true
echo "# R008: keine Lints (Research-Code)" > "$APP/analysis_options.yaml"
G="$APP/android/app/build.gradle.kts"
sed -i '' -E 's/minSdk = .*/minSdk = 31/; s/targetSdk = .*/targetSdk = 36/' "$G"
# Netz nur fuer die Karten-Apps (wie ADR-0009); base bekommt kein INTERNET im Release
M="$APP/android/app/src/main/AndroidManifest.xml"
if [ "$NAME" != base ] && ! grep -q android.permission.INTERNET "$M"; then
  sed -i '' 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <application#' "$M"
fi
[ -f "$SRC/$NAME/gradle.properties.add" ] && { grep -q R008 "$APP/android/gradle.properties" || cat "$SRC/$NAME/gradle.properties.add" >> "$APP/android/gradle.properties"; }
echo "$APP"
