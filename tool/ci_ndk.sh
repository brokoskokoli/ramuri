#!/usr/bin/env bash
# Installiert vor dem ersten Gradle-Build genau die NDK-Version, die der Build verlangt
# (app/android/app/build.gradle.kts: ndkVersion = flutter.ndkVersion). Die Version wird aus der
# eingesetzten Flutter-Version gelesen (FlutterExtension.kt), es gibt also keinen zweiten Wert, der
# veralten kann. Ohne Vorab-Installation lädt Gradle das NDK im Build selbst nach; ein beschädigter
# Download bricht dann die Konfiguration von :app ab.
#
# Aufruf: bash tool/ci_ndk.sh            installiert (bis zu zwei Wiederholungen) und prüft das Paket
#         bash tool/ci_ndk.sh --version  gibt nur die verlangte Version aus
# Umgebung: ANDROID_HOME bzw. ANDROID_SDK_ROOT (SDK), GITHUB_OUTPUT (falls gesetzt: version=<v>),
#           NDK_VERSION (nur zur Probe des Fehlerwegs: überschreibt die abgeleitete Version),
#           NDK_PAUSE (Sekunden zwischen den Versuchen, Standard 10).
set -uo pipefail

fehler() { echo "FEHLER (NDK): $*" >&2; exit 1; }

flutter_version_ndk() {
  local bin root kt v
  bin=$(command -v flutter) || fehler "flutter nicht im PATH"
  root=$(cd "$(dirname "$(readlink -f "$bin")")/.." && pwd)
  kt=$root/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt
  [[ -f $kt ]] || fehler "$kt fehlt; die NDK-Version der Flutter-Version ist nicht lesbar"
  v=$(sed -n 's/^[[:space:]]*val ndkVersion: String = "\([0-9][0-9.]*\)".*/\1/p' "$kt" | head -1)
  [[ -n $v ]] || fehler "ndkVersion in $kt nicht gefunden"
  echo "$v"
}

version=${NDK_VERSION:-$(flutter_version_ndk)} || exit 1
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || fehler "ungültige NDK-Version '$version'"
if [[ ${1:-} == --version ]]; then echo "$version"; exit 0; fi

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n $sdk && -d $sdk ]] || fehler "Android-SDK nicht gefunden (ANDROID_HOME/ANDROID_SDK_ROOT)"
sdkmanager=$(command -v sdkmanager || true)
[[ -n $sdkmanager ]] || sdkmanager=$sdk/cmdline-tools/latest/bin/sdkmanager
[[ -x $sdkmanager ]] || fehler "sdkmanager nicht gefunden unter $sdk/cmdline-tools/latest/bin"
[[ -n ${GITHUB_OUTPUT:-} ]] && echo "version=$version" >> "$GITHUB_OUTPUT"

dir=$sdk/ndk/$version
# Vollständig heißt: source.properties nennt genau diese Version, und Toolchain und ndk-build sind da.
vollstaendig() {
  [[ -f $dir/source.properties ]] \
    && grep -Eq "^Pkg\.Revision *= *$version([^0-9.]|$)" "$dir/source.properties" \
    && [[ -x $dir/ndk-build && -d $dir/toolchains/llvm/prebuilt ]]
}

if vollstaendig; then echo "NDK $version ist bereits vollständig installiert ($dir)"; exit 0; fi

versuche=3 pause=${NDK_PAUSE:-10}
for ((i = 1; i <= versuche; i++)); do
  echo "NDK $version installieren (Versuch $i von $versuche)"
  rm -rf "$dir"
  yes 2>/dev/null | "$sdkmanager" --sdk_root="$sdk" --install "ndk;$version"
  rc=${PIPESTATUS[1]}
  if [[ $rc -eq 0 ]] && vollstaendig; then echo "NDK $version installiert ($dir)"; exit 0; fi
  echo "Versuch $i gescheitert (sdkmanager Exit $rc, Paket vollständig: $(vollstaendig && echo ja || echo nein))" >&2
  ((i < versuche)) && sleep "$pause"
done
rm -rf "$dir"
fehler "NDK $version ließ sich nach $versuche Versuchen nicht vollständig installieren (Paket ndk;$version, SDK $sdk)"
