#!/bin/sh

ssh -q pocketbeagle-2 '
grep -q "robot-dir-pins" /boot/firmware/extlinux/extlinux.conf || echo "extlinux: robot-dir-pins overlay missing (DIR pins dead after reflash, motors one-direction)"
[ -e /boot/firmware/overlays/k3-am62-pocketbeagle2-robot-dir-pins.dtbo ] || echo "overlays: robot-dir-pins.dtbo missing from /boot/firmware/overlays"
[ "$(systemctl is-enabled docker 2>/dev/null)" = disabled ] || echo "docker: not disabled (409MB RAM, docker costs ~50MB)"
[ "$(systemctl is-enabled containerd 2>/dev/null)" = disabled ] || echo "containerd: not disabled"
[ "$(systemctl is-enabled tailscaled 2>/dev/null)" = enabled ] || echo "tailscaled: not enabled (tailscale is the only network path to this robot)"
[ -x ~/.pixi/bin/pixi ] || echo "pixi: not installed"
id -nG | grep -qw gpio || echo "groups: mfarabi not in gpio"
swapon --noheadings 2>/dev/null | grep -q . || [ -e /proc/swaps ] && grep -q partition /proc/swaps || echo "swap: no swap active (colcon builds need it on 409MB)"
[ "$(systemctl is-enabled robot.service 2>/dev/null)" = enabled ] || echo "systemd: robot.service not enabled"
'
