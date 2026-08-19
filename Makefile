NUTTX := zephyrproject/nuttx
APPS  := zephyrproject/apps

VID_WCH       := 6790
VID_SILABS    := 4292
VID_FTDI      := 1027
VID_ESPRESSIF := 12346
ESP_BRIDGE_VIDS := $(VID_WCH) $(VID_SILABS) $(VID_FTDI) $(VID_ESPRESSIF)

PORT ?= $(shell ioreg -rc IOUSBHostDevice -l 2>/dev/null | \
	awk -v vids='$(ESP_BRIDGE_VIDS)' ' \
		BEGIN { split(vids, list); for (i in list) want[list[i]] = 1 } \
		/"idVendor" = [0-9]/    { vid = $$NF } \
		/"IOCalloutDevice" = "/ { if (want[vid]) { gsub(/"/, "", $$NF); print $$NF; exit } } \
	')

.DEFAULT_GOAL := build
.PHONY: build flash clean distclean menuconfig setup

build:
	$(MAKE) -C $(NUTTX)

clean distclean menuconfig:
	$(MAKE) -C $(NUTTX) $@

flash:
	$(MAKE) -C $(NUTTX) flash ESPTOOL_PORT=$(PORT)

setup:
	ln -sfn ../../apps/firmware/nuttx $(APPS)/nuttx-zig
