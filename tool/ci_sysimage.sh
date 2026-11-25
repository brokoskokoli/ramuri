#!/usr/bin/env bash
# Installiert vor dem Emulatorstart im Workflow e2e das Systemimage
# system-images;android-<api>;google_apis;x86_64 per sdkmanager (prüft den Download selbst per Prüfsumme),
# mit bis zu drei Versuchen und einer Pause dazwischen. Danach findet android-emulator-runner das Paket
# installiert und lädt es nicht selbst nach; ein einzelner abgebrochener Download macht den Lauf nicht rot.
# Scheitern alle Versuche, endet das Skript mit der Meldung „Systemimage nicht ladbar“ (Infrastrukturfehler,
# vor jedem Test).
#
# Aufruf: bash tool/ci_sysimage.sh <api>     z. B. bash tool/ci_sysimage.sh 36
# Umgebung: ANDROID_HOME bzw. ANDROID_SDK_ROOT (SDK), SYSIMAGE_PAUSE (Sekunden zwischen den Versuchen,
#           Standard 15).
set -uo pipefail

fehler() {
  echo "FEHLER (Systemimage): $*" >&2
  # Annotation im Lauf, damit der Grund ohne Log-Suche sichtbar ist.
  [[ -n ${GITHUB_ACTIONS:-} ]] && echo "::error title=Infrastruktur::$*"
  exit 1
}

api=${1:-}
[[ $api =~ ^[0-9]+$ ]] || fehler "ungültige API-Stufe '$api' (Aufruf: bash tool/ci_sysimage.sh <api>)"
pkg="system-images;android-$api;google_apis;x86_64"

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n $sdk && -d $sdk ]] || fehler "Android-SDK nicht gefunden (ANDROID_HOME/ANDROID_SDK_ROOT)"
sdkmanager=$(command -v sdkmanager || true)
[[ -n $sdkmanager ]] || sdkmanager=$sdk/cmdline-tools/latest/bin/sdkmanager
[[ -x $sdkmanager ]] || fehler "sdkmanager nicht gefunden unter $sdk/cmdline-tools/latest/bin"

dir=$sdk/system-images/android-$api/google_apis/x86_64
# Vollständig heißt: source.properties nennt genau diese API-Stufe, und das Systemabbild ist da.
vollstaendig() {
  [[ -f $dir/source.properties ]] \
    && grep -Eq "^AndroidVersion\.ApiLevel *= *$api *$" "$dir/source.properties" \
    && [[ -s $dir/system.img ]]
}

if vollstaendig; then echo "Systemimage $pkg ist bereits vollständig installiert ($dir)"; exit 0; fi

versuche=3 pause=${SYSIMAGE_PAUSE:-15}
for ((i = 1; i <= versuche; i++)); do
  echo "Systemimage $pkg installieren (Versuch $i von $versuche)"
  rm -rf "$dir"
  yes 2>/dev/null | "$sdkmanager" --sdk_root="$sdk" --install "$pkg"
  rc=${PIPESTATUS[1]}
  if [[ $rc -eq 0 ]] && vollstaendig; then echo "Systemimage $pkg installiert ($dir)"; exit 0; fi
  echo "Versuch $i gescheitert (sdkmanager Exit $rc, Paket vollständig: $(vollstaendig && echo ja || echo nein))" >&2
  ((i < versuche)) && sleep "$pause"
done
rm -rf "$dir"
fehler "Systemimage nicht ladbar: $pkg nach $versuche Versuchen nicht vollständig installiert (SDK $sdk)"
