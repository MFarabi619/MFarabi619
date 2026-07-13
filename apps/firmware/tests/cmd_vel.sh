#!/usr/bin/env bash
set -euo pipefail

echo "forward"
pixi run ros2 topic pub --times 10 --rate 10 -w 0 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 1.0}, angular: {z: 0.0}}"

echo "backward"
pixi run ros2 topic pub --times 10 --rate 10 -w 0 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: -1.0}, angular: {z: 0.0}}"

echo "left"
pixi run ros2 topic pub --times 10 --rate 10 -w 0 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.0}, angular: {z: 1.0}}"

echo "right"
pixi run ros2 topic pub --times 10 --rate 10 -w 0 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.0}, angular: {z: -1.0}}"
