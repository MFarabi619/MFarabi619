#!/bin/sh

ssh -q rpi5-16.local '
[ "$(nmcli -g connection.autoconnect-priority connection show openws-hotspot 2>/dev/null)" = 100 ] || echo "networkmanager: openws-hotspot autoconnect-priority is not 100 (field hotspot must beat openws)"
[ "$(nmcli -g connection.autoconnect-priority connection show openws 2>/dev/null)" = 50 ] || echo "networkmanager: openws autoconnect-priority is not 50"
[ "$(nmcli -g connection.autoconnect-retries connection show openws 2>/dev/null)" = 0 ] || echo "networkmanager: openws autoconnect-retries is not 0 (wifi parks itself after a few failures)"
[ "$(nmcli -g connection.autoconnect-retries connection show openws-hotspot 2>/dev/null)" = 0 ] || echo "networkmanager: openws-hotspot autoconnect-retries is not 0"
[ "$(nmcli -g 802-11-wireless.powersave connection show openws 2>/dev/null)" = disable ] || echo "networkmanager: openws wifi powersave not disabled (headless drop risk)"
[ "$(nmcli -g 802-11-wireless.powersave connection show openws-hotspot 2>/dev/null)" = disable ] || echo "networkmanager: openws-hotspot wifi powersave not disabled"
nmcli -g NAME connection show 2>/dev/null | grep -qx oak-poe || echo "networkmanager: oak-poe ethernet profile missing (camera link dead)"
[ -x ~/.pixi/bin/pixi ] || echo "pixi: not installed"
[ "$(systemctl is-enabled robot.service 2>/dev/null)" = enabled ] || echo "systemd: robot.service not enabled"
'
