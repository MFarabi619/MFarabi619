#!/usr/bin/env bash

host=${BEAGLEYAI_HOST:-10.0.0.222}

ssh "$host" true 2>/dev/null                                     || echo "ssh $host unreachable"
nc -z -G3 "$host" 8889 2>/dev/null                               || echo "rgpiod not reachable on :8889"
ssh "$host" grep -q BeagleY /proc/device-tree/model 2>/dev/null  || echo "not a BeagleY-AI"
ssh "$host" "python3 -c 'import fcntl,os; fd=os.open(\"/dev/i2c-1\",os.O_RDWR); fcntl.ioctl(fd,0x0703,0x3c); os.write(fd,bytes([0,0xe3]))'" 2>/dev/null || echo "OLED not responding at i2c-1 0x3c"
ssh "$host" 'lsusb | grep -q 2bc5:0804' 2>/dev/null              || echo "Gemini 335L not on USB"
ssh "$host" 'for d in /sys/bus/usb/devices/*/; do [ "$(cat "$d/idVendor" 2>/dev/null)" = 2bc5 ] && [ "$(cat "$d/idProduct" 2>/dev/null)" = 0804 ] && [ "$(cat "$d/speed" 2>/dev/null)" -ge 5000 ] && exit 0; done; exit 1' 2>/dev/null || echo "Gemini 335L linked at USB2, not USB3 (5000M) — check the SuperSpeed cable"
ssh "$host" 'lsusb | grep -q 03e7:2485' 2>/dev/null              || echo "OAK-D SR not on USB"
ssh "$host" test -f /boot/firmware/overlays/k3-am67a-beagley-ai-csi1-imx219.dtbo 2>/dev/null || echo "IMX219 csi1 overlay not installed"
ssh "$host" 'ls /dev | grep -q video-imx219-cam'                 || echo "IMX219 camera node absent"
