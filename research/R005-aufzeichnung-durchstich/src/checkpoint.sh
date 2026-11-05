#!/bin/bash
# Checkpoint-Serie R005 (Review Runde 1, Befund 3): sigkill, nachdem die Hauptdatei Daten hat und das WAL wiederverwendet wurde.
# tx 1, wal_autocheckpoint 10 (etwa ein Checkpoint je 10 s statt je 18 min), Kill nach 25 bis 45 s, also nach mindestens zwei Checkpoints.
# Je API 7 x FULL, 3 x NORMAL (Kontrolle), zusammen 20 Laeufe, Dauer etwa 50 min. Fortsetzbar ueber .done. Marker: $R005_WORK/checkpoint.done
# Der jeweils erste Lauf ist die Vorpruefung: Zeigt er keinen Checkpoint (Hauptdatei 4096 Byte), bricht die Serie ab, Exit 3.
set -euo pipefail
cd "$(dirname "$0")"; source emu-env.sh; export R005_EMU_EXTRA=-show-kernel
H="python3 harness.py"; A="--kind sigkill --tx 1 --autock 10 --tag _ck10 --minrun 25 --maxrun 45"; set -x
$H kill-emu
for api in 36 31; do
  $H boot --api $api
  $H kill --api $api $A --sync FULL --rep 1
  python3 analyze.py ckgate "$R005_WORK" a${api}_sigkill_tx1_FULL_ck10_r0 || { $H kill-emu; echo "Vorpruefung API $api: kein Checkpoint, Serie abgebrochen" >&2; exit 3; }
  $H kill --api $api $A --sync FULL --rep 7
  $H kill --api $api $A --sync NORMAL --rep 3
  $H kill-emu
done
touch "$R005_WORK/checkpoint.done"
