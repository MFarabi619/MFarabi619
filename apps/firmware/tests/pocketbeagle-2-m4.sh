#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

sudo scp -q build/zephyr/zephyr.elf pocketbeagle-2:/lib/firmware/am62-mcu-m4f0_0-fw

ssh -t pocketbeagle-2 "sudo sh -c '
  echo stop > /sys/class/remoteproc/remoteproc0/state
  echo start > /sys/class/remoteproc/remoteproc0/state
  sleep 1
  cat /sys/kernel/debug/remoteproc/remoteproc0/trace0
'"
