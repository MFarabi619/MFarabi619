#!/bin/sh
set -e

config="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
robot="$config/.."
beagle=beagleyai

ssh -q "$beagle" 'mkdir -p ~/robot_ws/units ~/robot_ws/config ~/.pixi/envs/robot/share/robot_description ~/.pixi/envs/robot/share/ament_index/resource_index/packages && touch ~/.pixi/envs/robot/share/ament_index/resource_index/packages/robot_description'

scp -q "$config"/robot.target \
  "$config"/zenoh-router.service \
  "$config"/rgpiod.service \
  "$config"/robot-state-publisher.service \
  "$config"/nmea-navsat-driver.service \
  "$config"/gpspipe.socket \
  "$config"/gpspipe@.service \
  "$config"/orbbec-gemini-335l.service \
  "$config"/foxglove-bridge.service \
  "$config"/controller-manager.service \
  "$config"/controller-spawner.service \
  "$config"/twist-mux.service \
  "$config"/bno085.service \
  "$config"/hostapd.conf \
  "$config"/gpsd.default \
  "$beagle":/home/mfarabi/robot_ws/units/

scp -q "$robot"/bringup/config/generated/nmea_navsat_driver.yaml \
  "$robot"/bringup/config/generated/imu_0.yaml \
  "$robot"/bringup/launch/generated/camera_0.launch.py \
  "$robot"/description/urdf/robot.urdf \
  "$robot"/control/config/control.yaml \
  "$robot"/control/config/drivetrain.generated.yaml \
  "$robot"/control/config/twist_mux.yaml \
  "$beagle":/home/mfarabi/robot_ws/config/

scp -q "$config"/pixi-global.toml "$beagle":/home/mfarabi/.pixi/manifests/pixi-global.toml

rsync -a -e "ssh -q" "$robot"/description/meshes/ \
  "$beagle":/home/mfarabi/.pixi/envs/robot/share/robot_description/meshes/

ssh -q "$beagle" '~/.pixi/bin/pixi global sync --quiet'

ssh -q -t "$beagle" 'sudo install -m 644 -o root -g root ~/robot_ws/units/*.service ~/robot_ws/units/*.socket ~/robot_ws/units/*.target /etc/systemd/system/ \
  && sudo install -m 644 -o root -g root ~/robot_ws/units/gpsd.default /etc/default/gpsd \
  && sudo install -m 600 -o root -g root ~/robot_ws/units/hostapd.conf /etc/hostapd/hostapd.conf \
  && sudo systemctl daemon-reload \
  && sudo systemctl try-restart gpsd hostapd robot.target'
