{
  config,
  pkgs,
  lib,
  ...
}:

{
  boot = {
    consoleLogLevel = 7;
    # https://github.com/raspberrypi/firmware/issues/1539#issuecomment-784498108
    # https://github.com/RPi-Distro/pi-gen/blob/master/stage1/00-boot-files/files/cmdline.txt
    kernelParams = [
      "console=tty1"
      "console=serial0,115200n8"
    ];

    initrd.availableKernelModules = [
      "vc4"
      "usbhid" # https://github.com/NixOS/nixos-hardware/issues/631#issuecomment-1584100732
      "xhci_pci"
      "usb_storage"
      "pcie_brcmstb" # required for the pcie bus to work
      "reset-raspberrypi" # required for vl805 firmware to load
    ];
  };

  environment.systemPackages = with pkgs; [
    raspberrypi-utils
  ];

  hardware = {
    enableRedistributableFirmware = true;
    raspberry-pi.config = {
        # [all] conditional filter, https://www.raspberrypi.com/documentation/computers/config_txt.html#conditional-filters
      all = {
        options = {
          avoid_warnings = {
            enable = true;
            value = true;
          };

          camera_auto_detect = {
            enable = true;
            value = true;
          };

          display_auto_detect = {
            enable = true;
            value = true;
          };

          auto_initramfs = {
            enable = true;
            value = 1;
          };

          arm_64bit = {
            enable = true;
            value = true;
          };

          arm_boost = {
            enable = true;
            value = true;
          };

          # https://www.raspberrypi.com/documentation/computers/config_txt.html#enable_uart
          # in conjunction with `console=serial0,115200` in kernel command line (`cmdline.txt`)
          # creates a serial console, accessible using GPIOs 14 and 15 (pins
          #  8 and 10 on the 40-pin header)
          enable_uart = {
            enable = true;
            value = true;
          };
          # https://www.raspberrypi.com/documentation/computers/config_txt.html#uart_2ndstage
          # enable debug logging to the UART, also automatically enables
          # UART logging in `start.elf`
          uart_2ndstage = {
            enable = true;
            value = true;
          };
        };

        # Base DTB parameters
        # https://github.com/raspberrypi/linux/blob/a1d3defcca200077e1e382fe049ca613d16efd2b/arch/arm/boot/dts/overlays/README#L132
        base-dt-params = {
          i2c_arm = {
            enable = true;
            value = "on";
          };
          i2s = {
            enable = true;
            value = "on";
          };
          spi = {
            enable = true;
            value = "on";
          };
          audio = {
            enable = true;
            value = "on";
          };
          # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#enable-pcie
          pciex1 = {
            enable = true;
            value = "on";
          };
          # PCIe Gen 3.0
          # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#pcie-gen-3-0
          pciex1_gen = {
            enable = true;
            value = "3";
          };
        };
      };
    };
  };
  # workaround for "modprobe: FATAL: Module <module name> not found"
  # see https://github.com/NixOS/nixpkgs/issues/154163,
  #     https://github.com/NixOS/nixpkgs/issues/154163#issuecomment-1350599022
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
    })
  ];
}
