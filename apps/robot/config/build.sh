#!/bin/sh
set -e

config="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
robot="$config/.."
beagle=mfarabi@10.0.0.222

ssh -q "$beagle" 'mkdir -p ~/robot_ws/src ~/robot_ws/config'
scp -q "$config"/robot_ws.pixi.toml "$beagle":/home/mfarabi/robot_ws/pixi.toml
rsync -a --delete -e "ssh -q" "$robot"/hardware_interfaces/ \
    "$beagle":robot_ws/src/robot_hardware_interfaces/
scp -q "$robot"/imu/imu_driver.py "$beagle":robot_ws/src/
ssh -q "$beagle" '~/.pixi/bin/pixi run --manifest-path ~/robot_ws/pixi.toml build'
