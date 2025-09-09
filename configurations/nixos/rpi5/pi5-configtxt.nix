{ ... }:
{
  hardware = {
    i2c={
      enable = true;
      group = "i2c";
      };

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
}
