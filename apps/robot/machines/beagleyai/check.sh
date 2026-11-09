#!/bin/sh

ssh -q beagleyai '
grep -q "pwm-epwm0-gpio12" /boot/firmware/extlinux/extlinux.conf || echo "extlinux: epwm0-gpio12 overlay missing (right drive PWM dead after reflash)"
grep -q "pwm-epwm1-gpio20" /boot/firmware/extlinux/extlinux.conf || echo "extlinux: epwm1-gpio20 overlay missing (left drive PWM dead after reflash)"
grep -q "uart-ttyama0" /boot/firmware/extlinux/extlinux.conf || echo "extlinux: uart-ttyama0 overlay missing (GPS HAT serial dead)"
grep -q "csi1-imx219" /boot/firmware/extlinux/extlinux.conf || echo "extlinux: csi1-imx219 overlay missing"
[ -e /etc/udev/rules.d/99-obsensor-libusb.rules ] || echo "udev: orbbec rules missing (camera needs vendor udev rules)"
grep -q BeagleY /proc/device-tree/model || echo "model: not a BeagleY-AI"
lsusb | grep -q 2bc5:0804 || echo "usb: Gemini 335L absent"
( for d in /sys/bus/usb/devices/*/; do [ "$(cat "$d/idVendor" 2>/dev/null)" = 2bc5 ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = 0804 ] && [ "$(cat "$d/speed" 2>/dev/null)" -ge 5000 ] && exit 0; done; exit 1 ) || echo "usb: Gemini 335L linked at USB2, not USB3 (5000M) — check the SuperSpeed cable"
lsusb | grep -q 03e7:2485 || echo "usb: OAK-D SR absent"
python3 -c "import fcntl,os; fd=os.open(\"/dev/i2c-1\",os.O_RDWR); fcntl.ioctl(fd,0x0703,0x3c); os.write(fd,bytes([0,0xe3]))" 2>/dev/null || echo "i2c: OLED not responding at 0x3c"
[ "$(systemctl is-enabled gpsd 2>/dev/null)" != enabled ] || echo "systemd: gpsd enabled (fights nmea_serial_driver for /dev/ttyAMA0)"
[ "$(systemctl is-enabled gpsd.socket 2>/dev/null)" != enabled ] || echo "systemd: gpsd.socket enabled (fights nmea_serial_driver for /dev/ttyAMA0)"
[ -e /dev/ttyAMA0 ] || echo "serial: /dev/ttyAMA0 missing (uart overlay)"
id -nG | grep -qw dialout || echo "groups: mfarabi not in dialout"
[ -x /usr/sbin/hostapd ] || echo "apt: hostapd missing"
[ -x ~/.pixi/bin/pixi ] || echo "pixi: not installed"
id -nG | grep -qw gpio || echo "groups: mfarabi not in gpio"
[ "$(systemctl is-enabled tailscaled 2>/dev/null)" = enabled ] || echo "systemd: tailscaled not enabled"
[ "$(systemctl is-enabled robot.service 2>/dev/null)" = enabled ] || echo "systemd: robot.service not enabled"
[ ! -f ~/MFarabi619/apps/robot/package.xml ] || echo "mirror: stale old-layout apps/robot/package.xml (git op resurrected it? colcon will skip all packages)"
'
