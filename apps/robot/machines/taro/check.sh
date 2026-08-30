#!/bin/sh

ssh -q rpi5-16-2.local '
[ "$(nmcli -g connection.autoconnect-priority connection show openws-hotspot 2>/dev/null)" = 100 ] || echo "networkmanager: openws-hotspot autoconnect-priority is not 100 (field hotspot must beat openws)"
[ "$(nmcli -g connection.autoconnect-priority connection show openws 2>/dev/null)" = 50 ] || echo "networkmanager: openws autoconnect-priority is not 50"
[ "$(nmcli -g connection.autoconnect-retries connection show openws 2>/dev/null)" = 0 ] || echo "networkmanager: openws autoconnect-retries is not 0 (wifi parks itself after a few failures)"
[ "$(nmcli -g connection.autoconnect-retries connection show openws-hotspot 2>/dev/null)" = 0 ] || echo "networkmanager: openws-hotspot autoconnect-retries is not 0"
[ "$(nmcli -g connection.autoconnect-retries connection show dlink-8499 2>/dev/null)" = 0 ] || echo "networkmanager: dlink-8499 autoconnect-retries is not 0"
[ "$(nmcli -g connection.autoconnect-retries connection show starlink 2>/dev/null)" = 0 ] || echo "networkmanager: starlink autoconnect-retries is not 0"
[ "$(nmcli -g 802-11-wireless.powersave connection show openws 2>/dev/null)" = disable ] || echo "networkmanager: openws wifi powersave not disabled (headless drop risk)"
[ "$(nmcli -g 802-11-wireless.powersave connection show openws-hotspot 2>/dev/null)" = disable ] || echo "networkmanager: openws-hotspot wifi powersave not disabled"
[ "$(nmcli -g 802-11-wireless.powersave connection show dlink-8499 2>/dev/null)" = disable ] || echo "networkmanager: dlink-8499 wifi powersave not disabled"
[ "$(nmcli -g 802-11-wireless.powersave connection show starlink 2>/dev/null)" = disable ] || echo "networkmanager: starlink wifi powersave not disabled"
[ -x ~/.pixi/bin/pixi ] || echo "pixi: not installed"
[ "$(systemctl is-enabled robot.service 2>/dev/null)" = enabled ] || echo "systemd: robot.service not enabled"
'
