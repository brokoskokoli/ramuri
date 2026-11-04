# Umgebung fuer harness.py: JDK nur im Lauf, Pfade aus _shared/paths.sh
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
export JAVA_HOME="${R005_JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_AVD_HOME="$HOME/.android/avd"
_R005="$(git rev-parse --show-toplevel)/research/R005-aufzeichnung-durchstich"
export R005_WORK="$(research_work R005)"
export R005_APK="$_R005/src/proto/build/app/outputs/flutter-apk/app-profile.apk"
export R005_WALTEST="$_R005/src/waltest"
