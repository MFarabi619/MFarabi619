include $(APPDIR)/Make.defs

PROGNAME  = $(CONFIG_APPS_NUTTX_ZIG_PROGNAME)
PRIORITY  = $(CONFIG_APPS_NUTTX_ZIG_PRIORITY)
STACKSIZE = $(CONFIG_APPS_NUTTX_ZIG_STACKSIZE)
MODULE    = $(CONFIG_APPS_NUTTX_ZIG)

ZIG_CACHE ?= $(HOME)/.cache/zephyr-lang-zig
ZIG_HOST_ARCH := $(patsubst arm64,aarch64,$(shell uname -m))
ZIG_HOST_OS := $(if $(filter Darwin,$(shell uname -s)),macos,linux-musl)
ZIG := $(ZIG_CACHE)/zig-relsafe-$(ZIG_HOST_ARCH)-$(ZIG_HOST_OS)-baseline/zig

NUTTX_ZIG_OBJ = nuttx_zig$(OBJEXT)
EXTOBJS += $(NUTTX_ZIG_OBJ)

$(NUTTX_ZIG_OBJ): $(wildcard $(CURDIR)/src/*.zig) $(CURDIR)/build.zig $(CURDIR)/build.zig.zon
	$(Q) $(ZIG) build --build-file $(CURDIR)/build.zig \
		--cache-dir $(CURDIR)/.zig-cache --prefix $(CURDIR)/zig-out \
		-Dtarget=xtensa-freestanding-none -Dcpu=esp32s3 -Doptimize=ReleaseSafe \
		-Dnuttx-include=$(TOPDIR)/include
	$(Q) cp $(CURDIR)/zig-out/obj/nuttx_zig$(OBJEXT) $@

clean::
	$(Q) rm -rf $(CURDIR)/zig-out $(CURDIR)/.zig-cache $(NUTTX_ZIG_OBJ)

include $(APPDIR)/Application.mk
