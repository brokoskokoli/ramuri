#!/bin/bash
# R005: Wiederholung ungueltiger Laeufe (API 31) und Probe zu den Abstaenden (API 36). Marker: $R005_WORK/rerun.done
set -u
cd "$(dirname "$0")"; source emu-env.sh; export R005_EMU_EXTRA=-show-kernel
H="python3 harness.py"; set -x
$H kill-emu
$H boot --api 31
$H gap --api 31 --host own --wake 0 --dur 180 --tag _nat --natural 1 --quiet 1
for s in FULL NORMAL; do
  $H kill --api 31 --kind proc --tx 1 --sync $s --rep 3
  $H kill --api 31 --kind proc --tx 30 --sync $s --rep 3 --minrun 35 --maxrun 65
done
$H kill-emu
$H boot --api 36
$H gap --api 36 --host own --wake 0 --dur 240 --tag _abst_noinj --pause-at 0 --pause-len 400
$H gap --api 36 --host own --wake 0 --dur 240 --tag _abst_inj10 --inj-every 10
$H gap --api 36 --host own --wake 0 --dur 240 --tag _abst_inj1
$H kill-emu
touch "$R005_WORK/rerun.done"
