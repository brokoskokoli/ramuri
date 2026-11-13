#!/usr/bin/env bash
# Signierter Release-Build (WP30), lokal und in CI gleich. Aufruf:
#   tool/build_signed.sh <tag>              baut APK und AAB nach dist/ (Tag vX.Y.Z oder vX.Y.Z-rcN, N 1..98)
#   tool/build_signed.sh --print-version <tag>   gibt "<versionName> <versionCode>" aus, ohne Build
# Geheimnisse aus der Umgebung (SIGNING_KEYSTORE_BASE64, SIGNING_STORE_PASSWORD, optional SIGNING_KEY_PASSWORD und
# SIGNING_KEY_ALIAS), sonst lokal aus dem macOS-Schlüsselbund (Dienst ramuri-release-signing). Sie werden nie
# ausgegeben und nie als Kommandozeilenargument übergeben; der Keystore liegt nur in einer temporären Datei.
set -euo pipefail

# SHA-256 des Release-Zertifikats (steht auch im README).
RELEASE_CERT_SHA256=1c7e8472f5e705814fe65808ad7f506f903e198f4ba8543a97bbb0f4d4b602c5

fehler() { echo "FEHLER: $*" >&2; exit 1; }

# version_aus_tag <tag>: setzt VERSION_NAME und VERSION_CODE oder bricht ab.
# versionCode = MAJOR*1000000 + MINOR*10000 + PATCH*100 + (N beim RC, 99 bei der Version); jeder RC liegt unter seiner
# Version, jede neue Version über allen RCs der vorigen. MINOR und PATCH über 99 liefen in die Nachbarstelle über.
version_aus_tag() {
  local tag=$1 re='^v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc([1-9][0-9]?))?$'
  [[ $tag =~ $re ]] || fehler "Tag '$tag' passt nicht zu vX.Y.Z oder vX.Y.Z-rcN (N 1..98, keine führenden Nullen)"
  local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]} rc=${BASH_REMATCH[5]}
  [[ ${#minor} -le 2 && ${#patch} -le 2 ]] || fehler "MINOR und PATCH dürfen höchstens 99 sein ($tag)"
  [[ $major -le 2000 ]] || fehler "MAJOR darf höchstens 2000 sein ($tag), sonst läuft versionCode über"
  if [[ -n $rc ]]; then
    [[ $rc -le 98 ]] || fehler "RC-Nummer muss 1..98 sein ($tag)"
    VERSION_CODE=$((major * 1000000 + minor * 10000 + patch * 100 + rc))
  else
    VERSION_CODE=$((major * 1000000 + minor * 10000 + patch * 100 + 99))
  fi
  VERSION_NAME=${tag#v}
}

if [[ ${1:-} == --print-version ]]; then
  [[ $# -eq 2 ]] || fehler "Aufruf: tool/build_signed.sh --print-version <tag>"
  version_aus_tag "$2"
  echo "$VERSION_NAME $VERSION_CODE"
  exit 0
fi
[[ $# -eq 1 ]] || fehler "Aufruf: tool/build_signed.sh <tag>  (z. B. v0.1.0 oder v0.1.0-rc1)"
version_aus_tag "$1"

cd "$(dirname "$0")/.."

# --- Geheimnisse (nur Namen in Meldungen) ---
keychain() { security find-generic-password -s ramuri-release-signing -a "$1" -w 2>/dev/null; }
if [[ -z ${SIGNING_STORE_PASSWORD:-} ]]; then
  command -v security >/dev/null || fehler "SIGNING_STORE_PASSWORD fehlt (und kein macOS-Schlüsselbund)"
  SIGNING_STORE_PASSWORD=$(keychain store-password) || fehler "SIGNING_STORE_PASSWORD fehlt (Umgebung und Schlüsselbund Konto store-password)"
  [[ -n $SIGNING_STORE_PASSWORD ]] || fehler "SIGNING_STORE_PASSWORD ist leer"
fi
SIGNING_KEY_PASSWORD=${SIGNING_KEY_PASSWORD:-$SIGNING_STORE_PASSWORD}
SIGNING_KEY_ALIAS=${SIGNING_KEY_ALIAS:-ramuri}

umask 077
keystore=$(mktemp "${TMPDIR:-/tmp}/ramuri-release.XXXXXX")
trap 'rm -f "$keystore"' EXIT
if [[ -n ${SIGNING_KEYSTORE_BASE64:-} ]]; then
  printf '%s' "$SIGNING_KEYSTORE_BASE64" | base64 -d >"$keystore" || fehler "SIGNING_KEYSTORE_BASE64 ist kein gültiges Base64"
else
  command -v security >/dev/null || fehler "SIGNING_KEYSTORE_BASE64 fehlt (und kein macOS-Schlüsselbund)"
  keychain keystore-base64 | base64 -d >"$keystore" || fehler "SIGNING_KEYSTORE_BASE64 fehlt (Umgebung und Schlüsselbund Konto keystore-base64)"
fi
[[ -s $keystore ]] || fehler "Keystore ist leer"
unset SIGNING_KEYSTORE_BASE64
export SIGNING_STORE_FILE=$keystore SIGNING_STORE_PASSWORD SIGNING_KEY_PASSWORD SIGNING_KEY_ALIAS

# --- Build ---
# Gradle ohne Daemon: ein Daemon bliebe stundenlang mit den Signatur-Passwörtern in seiner Umgebung am Leben. Dasselbe gilt
# für den Kotlin-Compile-Daemon (erbt die Umgebung des Starters), daher Kotlin im Gradle-Prozess übersetzen.
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.daemon=false -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process"
apk=app/build/app/outputs/flutter-apk/app-release.apk
aab=app/build/app/outputs/bundle/release/app-release.aab
rm -f "$apk" "$aab"
echo "Baue ramuri $VERSION_NAME (versionCode $VERSION_CODE)"
( cd app && flutter build apk --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE" )
( cd app && flutter build appbundle --release --build-name "$VERSION_NAME" --build-number "$VERSION_CODE" )
[[ -f $apk ]] || fehler "$apk fehlt"
[[ -f $aab ]] || fehler "$aab fehlt"

# --- Signatur gegen das feste Zertifikat prüfen ---
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
apksigner=$(for d in $(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V); do [[ -x $d/apksigner ]] && echo "$d/apksigner"; done | tail -1)
[[ -n $apksigner ]] || fehler "apksigner nicht gefunden unter $sdk/build-tools"
certs=$("$apksigner" verify --print-certs "$apk") || fehler "apksigner verify scheiterte"
echo "$certs" | grep -i 'SHA-256 digest' || true
if ! grep -qi "SHA-256 digest: $RELEASE_CERT_SHA256" <<<"$certs"; then
  fehler "APK ist nicht mit dem Release-Zertifikat $RELEASE_CERT_SHA256 signiert"
fi

# --- Release-Prüfung des Gates auf genau diese APK ---
tool/check_release_apk.sh "$apk" || fehler "Release-Prüfung der APK ist rot"

# --- dist/ ---
rm -rf dist
mkdir -p dist
cp "$apk" "dist/ramuri-$VERSION_NAME.apk"
cp "$aab" "dist/ramuri-$VERSION_NAME.aab"
if command -v sha256sum >/dev/null; then sum="sha256sum"; else sum="shasum -a 256"; fi
( cd dist && $sum "ramuri-$VERSION_NAME.apk" "ramuri-$VERSION_NAME.aab" >SHA256SUMS.txt && cat SHA256SUMS.txt )
echo "Fertig: dist/ramuri-$VERSION_NAME.apk und .aab"
