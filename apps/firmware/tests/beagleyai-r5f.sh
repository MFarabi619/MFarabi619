#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

sudo scp build/zephyr/zephyr.elf beagleyai:/lib/firmware/

ssh -t beagleyai "
  echo stop       | sudo tee /dev/remoteproc/j7-mcu-r5f0_0/state >/dev/null 2>&1
  echo zephyr.elf | sudo tee /dev/remoteproc/j7-mcu-r5f0_0/firmware >/dev/null
  echo start      | sudo tee /dev/remoteproc/j7-mcu-r5f0_0/state >/dev/null
  sleep 1
  sudo cat /sys/kernel/debug/remoteproc/remoteproc2/trace0
"
