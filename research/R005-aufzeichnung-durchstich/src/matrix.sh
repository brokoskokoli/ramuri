#!/bin/bash
# Lange Matrix R005, siehe README, Abschnitt Ausfuehrung. Fortsetzbar: fertige Laeufe (.done) werden uebersprungen.
# Zwei Bedingungen: Standard (emulator_wake_lock gehalten, kein Suspend, misst Host, Doze, Einfrieren) und natural (Sperre geloest, echter Autosuspend).
set -u
cd "$(dirname "$0")"; source emu-env.sh; export R005_EMU_EXTRA=-show-kernel
H="python3 harness.py"; set -x
$H kill-emu
# ---- API 36
$H boot --api 36
$H wal --api 36 --dur 120 --tag _b
$H gap --api 36 --host own --wake 0 --dur 120 --tag _stopctl2 --stop-at 30 --stop-len 30
$H swipe --api 36 --host own --tx 1 --dur 60 --rep 2 --tag _b
$H swipe --api 36 --host ffgt --tx 1 --dur 60 --rep 2 --tag _b
for h in own ffgt; do $H gap --api 36 --host $h --wake 0 --dur 600 --rep 2; done
$H gap --api 36 --host none --wake 0 --dur 600
for h in own ffgt; do for w in 0 1; do $H gap --api 36 --host $h --wake $w --dur 180 --rep 2 --tag _nat --natural 1 --quiet 1; done; done
for s in FULL NORMAL; do
  $H kill --api 36 --kind proc --tx 1 --sync $s --rep 5
  $H kill --api 36 --kind proc --tx 5 --sync $s --rep 5
  $H kill --api 36 --kind proc --tx 30 --sync $s --rep 5 --minrun 35 --maxrun 65
done
for tx in 1 5 30; do
  r=""; [ $tx = 30 ] && r="--minrun 35 --maxrun 65"
  $H kill --api 36 --kind sigkill --tx $tx --sync FULL --rep 8 $r
  $H kill --api 36 --kind sigkill --tx $tx --sync NORMAL --rep 4 $r
done
$H kill --api 36 --host ffgt --kind proc --tx 1 --sync FULL --rep 3
$H kill --api 36 --host ffgt --kind sigkill --tx 1 --sync FULL --rep 3
# ---- API 31
$H kill-emu
$H boot --api 31
$H wal --api 31 --dur 120
$H bench --api 31 --n 300
$H gap --api 31 --host own --wake 0 --dur 120 --tag _stopctl2 --stop-at 30 --stop-len 30
$H swipe --api 31 --host own --tx 1 --dur 60 --rep 1
$H swipe --api 31 --host ffgt --tx 1 --dur 60 --rep 1
for h in own ffgt; do $H gap --api 31 --host $h --wake 0 --dur 600; done
$H gap --api 31 --host none --wake 0 --dur 300
$H gap --api 31 --host own --wake 0 --dur 180 --tag _nat --natural 1 --quiet 1
$H gap --api 31 --host own --wake 1 --dur 180 --tag _nat --natural 1 --quiet 1
$H gap --api 31 --host ffgt --wake 1 --dur 180 --tag _nat --natural 1 --quiet 1
for s in FULL NORMAL; do
  $H kill --api 31 --kind proc --tx 1 --sync $s --rep 3
  $H kill --api 31 --kind proc --tx 30 --sync $s --rep 3 --minrun 35 --maxrun 65
done
for tx in 1 30; do
  r=""; [ $tx = 30 ] && r="--minrun 35 --maxrun 65"
  $H kill --api 31 --kind sigkill --tx $tx --sync FULL --rep 5 $r
  $H kill --api 31 --kind sigkill --tx $tx --sync NORMAL --rep 3 $r
done
$H kill-emu
touch "$R005_WORK/matrix.done"
