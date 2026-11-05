#!/bin/bash
# Stellt her, was R005 braucht. Idempotent: Vorhandenes wird nicht neu geladen oder gebaut. Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source src/emu-env.sh
if [ "${1:-}" = "--help" ]; then cat <<HELP
Stellt fuer R005 her:
  System-Images android-31 und android-36 (google_apis;arm64-v8a)  -> Android SDK, zusammen etwa 6 GB, nur falls sie fehlen
  AVDs running_app_r005_api31 und running_app_r005_api36            -> ~/.android/avd, nur falls sie fehlen
  APK des Prototyps (Profil-Build, minSdk 31, target 36)            -> src/proto/build/, etwa 41 MB, nur falls sie fehlt
  Abhaengigkeiten von src/waltest                                   -> Pub-Cache
  Arbeitsordner work/R005 samt Eintrag in research/data/INDEX.md    -> research/data/work/R005/
Voraussetzungen: Flutter 3.47.7, Android SDK unter ~/Library/Android/sdk. JDK nur per Umgebung
(Standard: JBR aus Android Studio, ueberschreibbar mit R005_JAVA_HOME); keine globale Aenderung.
Laeuft in einem Worktree, Daten liegen trotzdem im Haupt-Checkout. Keine Sammlung aus research/input/.
HELP
exit 0; fi
SDK="$HOME/Library/Android/sdk"; mkdir -p "$R005_WORK"
for api in 31 36; do
  img="system-images;android-$api;google_apis;arm64-v8a"
  [ -d "$SDK/system-images/android-$api/google_apis/arm64-v8a" ] || yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "$img"
  avd="running_app_r005_api$api"
  if [ ! -d "$HOME/.android/avd/$avd.avd" ]; then
    echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n "$avd" -k "$img" -d pixel_6
    cfg="$HOME/.android/avd/$avd.avd/config.ini"
    for kv in hw.ramSize=3072 hw.gps=yes hw.cpu.ncore=4 disk.dataPartition.size=4G; do
      grep -v "^${kv%%=*}=" "$cfg" > "$cfg.tmp"; mv "$cfg.tmp" "$cfg"; echo "$kv" >> "$cfg"
    done
  fi
done
[ -f "$R005_APK" ] || (cd src/proto && flutter pub get >/dev/null && flutter build apk --profile --target-platform android-arm64)
(cd src/waltest && dart pub get >/dev/null)
research_register "work/R005" R005 "Rohdaten R005 (Logs, DB-Kopien, Auswertung, nur synthetisch)"
echo "R005 initialisiert (Daten: $RESEARCH_DATA)"
