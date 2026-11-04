#!/bin/bash
# Langlauf R005: ein Lauf, 60 min, API 36, eigener Host, Wake Lock, tx=1 FULL, Bedingung natural (emulator_wake_lock geloest), force-idle, gesperrt.
# Zustand alle 60 s, Ressourcen alle 30 s (resources.tsv, meminfo.txt). Marker: $R005_WORK/long.done
set -u
cd "$(dirname "$0")"; source emu-env.sh; export R005_EMU_EXTRA=-show-kernel
H="python3 harness.py"; set -x
$H kill-emu
$H boot --api 36
$H gap --api 36 --host own --wake 1 --tx 1 --sync FULL --dur ${R005_LONG_DUR:-3600} --tag _natlong --natural 1 --poll 60 --sample 30
$H kill-emu
touch "$R005_WORK/long.done"
