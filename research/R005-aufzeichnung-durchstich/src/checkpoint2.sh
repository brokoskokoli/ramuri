#!/bin/bash
# Zweite Checkpoint-Serie R005 (Review Runde 2, Befund 1, Fix B, Entscheidung des Maintainers): sigkill, wenn die ersten Zeilen nur noch in der Hauptdatei liegen.
# tx 1, wal_autocheckpoint 10, Kill erst nach 90 bis 180 s: Die erste Blattseite ist nach Zeile 54 voll und danach nach dem naechsten Checkpoint nur noch in der Hauptdatei.
# Je API 7 x FULL, 3 x NORMAL, zusammen 20 Laeufe, etwa 75 min. Fortsetzbar ueber .done. Marker: $R005_WORK/checkpoint2.done
# Der Harness behaelt die Kopie vor dem Oeffnen (before-open). Vorpruefung je API: Der erste Lauf muss den Zustand direkt zeigen (analyze.py main_only), sonst Abbruch, Exit 3.
set -euo pipefail
cd "$(dirname "$0")"; source emu-env.sh; export R005_EMU_EXTRA=-show-kernel
H="python3 harness.py"; A="--kind sigkill --tx 1 --autock 10 --tag _ck10b --minrun 90 --maxrun 180"; set -x
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$H kill-emu
for api in 36 31; do
  $H boot --api $api
  # Rueckschreib-Frist des Gastkerns, noetig zur Einordnung der aeltesten Blattseite (siehe RESULTS)
  for f in dirty_expire_centisecs dirty_writeback_centisecs; do echo "$api $f $("$ADB" -s emulator-5600 shell cat /proc/sys/vm/$f 2>&1)"; done | tee -a "$R005_WORK/checkpoint2-vm.txt"
  $H kill --api $api $A --sync FULL --rep 1
  python3 analyze.py ckgate "$R005_WORK" a${api}_sigkill_tx1_FULL_ck10b_r0 || { $H kill-emu; echo "Vorpruefung API $api: Zustand nicht belegt, Serie abgebrochen" >&2; exit 3; }
  $H kill --api $api $A --sync FULL --rep 7
  $H kill --api $api $A --sync NORMAL --rep 3
  $H kill-emu
done
touch "$R005_WORK/checkpoint2.done"
