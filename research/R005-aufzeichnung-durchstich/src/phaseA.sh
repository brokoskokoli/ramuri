#!/bin/bash
# Phase A: Kontrollen und guenstige Messungen auf API 36, bevor die lange Matrix startet.
cd "$(dirname "$0")"; source emu-env.sh; H="python3 harness.py"; set -x
$H boot --api 36
$H wal --api 36 --dur 120
$H bench --api 36 --n 300
$H gap --api 36 --host none --wake 0 --dur 120 --tag _ctl
$H gap --api 36 --host own --wake 0 --dur 120 --tag _pausectl --pause-at 30 --pause-len 30
$H gap --api 36 --host own --wake 0 --dur 120 --tag _stopctl --stop-at 30 --stop-len 30
$H gap --api 36 --host own --wake 0 --dur 120 --tag _smoke
$H gap --api 36 --host ffgt --wake 0 --dur 120 --tag _smoke
$H swipe --api 36 --host own --tx 1 --dur 60 --rep 1
$H swipe --api 36 --host ffgt --tx 1 --dur 60 --rep 1
$H kill --api 36 --kind proc --tx 1 --sync FULL --rep 2 --tag _probe
$H kill --api 36 --kind emu --tx 1 --sync NORMAL --rep 5 --tag _probe
$H kill --api 36 --kind emu --tx 1 --sync FULL --rep 2 --tag _probe
$H kill --api 36 --kind sigkill --tx 1 --sync NORMAL --rep 5 --tag _probe
$H kill --api 36 --kind sigkill --tx 1 --sync FULL --rep 2 --tag _probe
touch "$R005_WORK/phaseA.done"
