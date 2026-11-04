#!/bin/bash
# R005: Laeufe, die anfangs von Hand bzw. ueber Hilfsskripte liefen und in keinem anderen Skript stehen (Tabelle 1 bis 3). Befehle laut meta.json und den Protokollen.
# Die drei API-31-Laeufe tragen Tabelle 1 (API 31 own: n = 2) und Tabelle 3, darunter die einzige Pausen-Kontrolle auf API 31. Sie liefen ohne -show-kernel.
# a36_own_w0_i1_120s_nat_r0 ist als veraltete DB verworfen (RESULTS, Eigene Aufbaufehler); der Befehl bleibt, damit er sich mit dem korrigierten Harness wiederholen laesst.
set -u
cd "$(dirname "$0")"; source emu-env.sh
H="python3 harness.py"; set -x
$H kill-emu
$H boot --api 31
$H gap --api 31 --host own --wake 0 --dur 120 --tag _smoke
$H gap --api 31 --host none --wake 0 --dur 120 --tag _smoke
$H gap --api 31 --host own --wake 0 --dur 120 --tag _pausectl --pause-at 30 --pause-len 30
$H kill-emu
export R005_EMU_EXTRA=-show-kernel
$H boot --api 36
$H gap --api 36 --host own --wake 0 --dur 120 --tag _nat --natural 1 --quiet 1
$H gap --api 36 --host own --wake 1 --dur 120 --tag _nat --natural 1 --quiet 1
$H gap --api 36 --host own --wake 0 --dur 120 --tag _forced --force-at 30 --quiet 1
$H kill-emu
touch "$R005_WORK/vorlaeufe.done"
