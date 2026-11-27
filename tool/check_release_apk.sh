#!/bin/sh
# Prüfungen am gebauten Release-APK (aus tool/gate.sh release_rechte, WP30). Aufruf: tool/check_release_apk.sh <apk>
# Fail-closed; Exit 0 nur, wenn alle Prüfungen grün sind. Läuft von überall (wechselt in die Repo-Wurzel).
# WP14: Die Paket-ID des gebauten APK ist io.github.brokoskokoli.ramuri (aapt dump badging). Eine andere applicationId
# ändert nebenbei die FileProvider-Authority. Aufruf: paket_id_pruefen <aapt> <apk> [erwartete ID]; fail-closed.
paket_id_pruefen() {
  erwartet=${3:-io.github.brokoskokoli.ramuri}
  badging=$("$1" dump badging "$2") || { echo "aapt dump badging scheiterte"; return 1; }
  ist=$(echo "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  [ "$ist" = "$erwartet" ] || { echo "Paket-ID des APK ist '$ist', erwartet '$erwartet'"; return 1; }
}

# SEC-0008 (WP13): Das Release-APK fordert INTERNET (nur für Kartenkacheln, Einwilligung, Gate-Schritt "net"), aber keine
# Hintergrund-Standortberechtigung, keine exakten Wecker und BOOT_COMPLETED nur für den Erinnerungs-Empfänger. Geprüft am gebauten APK (aapt), nicht am Quell-Manifest,
# weil Plugins per Manifest-Merge Berechtigungen hinzufügen können. Fail-closed: fehlt aapt oder die Ausgabe, ist der
# Schritt rot. Auch Klartext-Verkehr (usesCleartextTraffic, Netzwerk-Sicherheitskonfiguration) wird am APK geprüft.
check_release_apk() {
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
  aapt=$(ls "$sdk"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -n "$aapt" ] || { echo "aapt nicht gefunden unter $sdk/build-tools"; return 1; }
  apk=$1
  [ -f "$apk" ] || { echo "$apk fehlt"; return 1; }
  paket_id_pruefen "$aapt" "$apk" || return 1
  perms=$("$aapt" dump permissions "$apk") || { echo "aapt dump permissions scheiterte"; return 1; }
  echo "$perms" | grep -q '^package: ' || { echo "aapt-Ausgabe unerwartet"; return 1; }
  echo "$perms"
  if ! echo "$perms" | grep -q 'android.permission.INTERNET'; then
    echo "Release-APK fordert android.permission.INTERNET nicht (WP13: Kartenkacheln)"; return 1
  fi
  tree=$("$aapt" dump xmltree "$apk" AndroidManifest.xml) || { echo "aapt dump xmltree scheiterte"; return 1; }
  echo "$tree" | grep -q 'networkSecurityConfig' || { echo "Release-APK: android:networkSecurityConfig fehlt"; return 1; }
  if echo "$tree" | grep 'usesCleartextTraffic' | grep -qv ')0x0$'; then
    echo "Release-APK erlaubt Klartext-Verkehr (usesCleartextTraffic)"; return 1
  fi
  # Die Konfiguration selbst (res/xml kann im APK umbenannt sein): cleartextTrafficPermitted muss false sein.
  nscfile=$(unzip -Z1 "$apk" | grep -E '^res/.*\.xml$' | while IFS= read -r f; do
    "$aapt" dump xmltree "$apk" "$f" 2>/dev/null | grep -q 'network-security-config' && { echo "$f"; break; }
  done)
  [ -n "$nscfile" ] || { echo "Release-APK: network-security-config nicht gefunden"; return 1; }
  nsc=$("$aapt" dump xmltree "$apk" "$nscfile")
  echo "$nsc" | grep -q 'cleartextTrafficPermitted' || { echo "Release-APK: cleartextTrafficPermitted fehlt"; return 1; }
  if echo "$nsc" | grep 'cleartextTrafficPermitted' | grep -qv ')0x0$'; then
    echo "Release-APK: Klartext-Verkehr in der Netzwerk-Sicherheitskonfiguration erlaubt"; return 1
  fi
  # WP08/WP22: keine Hintergrund-Standortberechtigung, keine exakten Wecker; RECEIVE_BOOT_COMPLETED nur mit genau einem
  # Empfänger TrainingReminderReceiver, exported=false, der nur Erinnerungs-Wecker neu plant (ADR-0005 Punkt 6 mit
  # Nachtrag, Maintainer 2026-11-10). Am gemergten Manifest des APK; Selbsttest tool/check_release_manifest_test.py.
  # Dazu (SEC-0009, SEC-0010): allowBackup=false, data-extraction-rules schließen alle Domänen aus, nur freigegebene
  # Komponenten exportiert, FileProvider nur cache-path exports/. Die Ressourcen (res/*.xml, im APK umbenannt) löst das
  # Skript über die Ressourcentabelle auf.
  rdir=$(mktemp -d) || return 1
  echo "$perms" >"$rdir/perms.txt"; echo "$tree" >"$rdir/tree.txt"
  "$aapt" dump --values resources "$apk" >"$rdir/resources.txt" || { echo "aapt dump resources scheiterte"; rm -rf "$rdir"; return 1; }
  mkdir "$rdir/xml"
  for f in $(unzip -Z1 "$apk" | grep -E '^res/[^ ]*\.xml$'); do
    "$aapt" dump xmltree "$apk" "$f" >"$rdir/xml/$(echo "$f" | tr / %)" 2>/dev/null || rm -f "$rdir/xml/$(echo "$f" | tr / %)"
  done
  python3 tool/check_release_manifest.py "$rdir/perms.txt" "$rdir/tree.txt" "$rdir/resources.txt" "$rdir/xml"; rc=$?
  rm -rf "$rdir"
  [ $rc -eq 0 ] || return 1
  # WP27 (ADR-0011 Punkt 5): CAMERA ist erlaubt und Pflicht (Kamera-PPG); Kamera und Blitz sind als uses-feature
  # vorhanden und required=false, sonst wäre die App ohne Kamera nicht installierbar. Kommt ein Feature mehrfach vor
  # (Manifest-Merge), zählt es als Pflicht, sobald ein Eintrag required=true hat.
  echo "$perms" | grep -q 'android.permission.CAMERA' || { echo "Release-APK fordert android.permission.CAMERA nicht (WP27)"; return 1; }
  # WP27: VIBRATE (normales Recht) für das Signal am Ende der Ruhephase; fehlt es, bleibt das Signal stumm.
  echo "$perms" | grep -q 'android.permission.VIBRATE' || { echo "Release-APK fordert android.permission.VIBRATE nicht (WP27)"; return 1; }
  for feature in android.hardware.camera android.hardware.camera.flash; do
    req=$(echo "$tree" | awk -v want="$feature" '
      function fin() { if (name == want) { found = 1; if (req != "0x0") anytrue = 1 } name = ""; req = "true" }
      /^ *E: / { fin() }
      /E: uses-feature/ { infeat = 1; next }
      /^ *E: / { infeat = 0 }
      infeat && /android:name\(/ { n = $0; sub(/^[^"]*"/, "", n); sub(/".*$/, "", n); name = n }
      infeat && /android:required\(/ { r = $0; sub(/^.*\)/, "", r); req = r }
      END { fin(); if (found) print (anytrue ? "true" : "false") }')
    case "$req" in
      false) ;;
      true) echo "Release-APK: uses-feature $feature ist Pflicht (required muss false sein)"; return 1 ;;
      *) echo "Release-APK: uses-feature $feature fehlt"; return 1 ;;
    esac
  done
  # WP07, WP27, WP32: Debug-Quellen (Test-Sensor, Fake-Kamera, Health-Connect-Fake, Debug-Panel) gehören nur in den
  # Debug-Einstieg. Jede Datei unter app/lib/debug/ trägt einen Marker; keiner darf in einer Datei des APK stehen
  # (tool/check_debug_code.py, Selbsttest tool/check_debug_code_test.py).
  python3 tool/check_debug_code.py artifact "$apk" || return 1
  echo "Keine Debug-Quelle im Release-APK; CAMERA und uses-feature required=false vorhanden"
}

[ $# -eq 1 ] || { echo "Aufruf: tool/check_release_apk.sh <apk>"; exit 2; }
[ -f "$1" ] || { echo "$1 fehlt"; exit 1; }
apk_abs=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/.." || exit 1
check_release_apk "$apk_abs"
